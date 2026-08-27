// The player endpoints are asked through the package's own request layer,
// which it marks internal. Hoza reads the answer itself because the package's
// public path HEADs the first stream without a byte range — a request YouTube
// refuses for anything but a short clip — and so declares working endpoints
// dead. The package is pinned in pubspec.lock; revisit this when it moves.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/src/reverse_engineering/models/stream_info_provider.dart';
import 'package:youtube_explode_dart/src/reverse_engineering/player/player_response.dart';
import 'package:youtube_explode_dart/src/videos/video_controller.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../../../core/constants/app_info.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../data/models/media_option.dart';
import '../../domain/source_provider.dart';
import '../request_race.dart';
import '../resolvers/endpoint_health.dart';

/// Reads what YouTube serves for a watch link.
///
/// YouTube publishes each quality as its own file and keeps the picture and
/// the sound apart above 360p, so the high qualities are offered as a pair of
/// tracks that the download engine merges on the device. Only H.264 in an MP4
/// container is offered for the picture: that is what Android's own muxer can
/// merge without re-encoding, on every phone the app runs on.
///
/// The sound is taken wherever it is found. AAC is preferred — it merges
/// untouched — but most videos are published with Opus and no AAC at all, and
/// those are re-encoded on the device on the way in rather than left out. That
/// is the difference between a 1080p download with sound and a 360p one.
///
/// The manifest is not asked for once. YouTube answers its phone app, its
/// iPhone app and its headset app from separate player endpoints, and on any
/// given day some of them are refusing while others serve normally — depending
/// on one of them is why a downloader suddenly "stops working". Hoza asks a
/// fleet of them, three at a time, and keeps the first answer that names
/// streams a server will hand over. See [_fleet].
///
/// Naming a stream is not the same as serving it. YouTube's media servers
/// refuse most of what some endpoints name — everything past the first minute
/// of a stream, for clients without an attestation token — with a 403. So
/// every quality the picker would show is asked for first, its last byte, and
/// only the ones the server actually answers are offered. See [_verify].
class YoutubeProvider implements SourceProvider {
  YoutubeProvider(HttpClient client, EndpointHealth health)
    : this._(client, health, yt.YoutubeHttpClient());

  YoutubeProvider._(this._client, this._health, this._youtube)
    : _controller = VideoController(_youtube);

  /// The app's own client, used to ask the media servers what they serve.
  final HttpClient _client;

  final EndpointHealth _health;

  /// The package's request layer: cookies, consent and the headers YouTube's
  /// pages expect. Shared by the player lookups and the visitor id fetch.
  final yt.YoutubeHttpClient _youtube;

  /// Asks a player endpoint directly. Long-lived on purpose: it remembers the
  /// visitor id the iPhone endpoint wants, which saves a round trip per link.
  final VideoController _controller;

  /// The visitor id YouTube issued this device, sent with the headset
  /// endpoint's requests. Fetched once and kept; dropped if YouTube stops
  /// honouring it, so the next lookup asks for a fresh one.
  String? _visitor;

  @override
  String get name => 'YouTube';

  /// Domains YouTube serves watch pages on. Matched by suffix so `m.`,
  /// `music.` and `www.` all resolve to the same provider.
  static const Set<String> _domains = {
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
  };

  /// Qualities offered, best first. More than this is noise in a picker.
  static const int _maxVideoVariants = 6;

  /// How many endpoints are asked at once.
  ///
  /// Enough that one refusing endpoint costs nothing, few enough that the
  /// whole fleet is never woken for a video the first three can serve.
  static const int _waveSize = 3;

  /// Longest one endpoint may take to answer. A player lookup is one small
  /// request; one that takes longer than this is not going to answer usefully,
  /// and the wave should move on without it.
  static const Duration _endpointTimeout = Duration(seconds: 12);

  /// The YouTube player endpoints Hoza knows how to ask, best first.
  ///
  /// These are YouTube's own servers — one per client it publishes — not
  /// third-party mirrors. Only clients that hand over playable addresses
  /// outright are listed: the website and TV clients scramble theirs, and
  /// unscrambling them needs a JavaScript engine the app does not carry.
  ///
  /// Verified 2026-08-26: the Apple headset endpoint is the one whose streams
  /// YouTube's media servers hand over whole. The Android and iPhone endpoints
  /// answer with complete manifests, but their servers refuse every byte past
  /// roughly the first minute of a stream unless the client presents an
  /// attestation token the app does not have — so they only ever win for a
  /// clip shorter than that, and [_verify] keeps them from winning otherwise.
  static final List<_Endpoint> _fleet = [
    _Endpoint('visionos', _visionOs, needsVisitor: true),
    _Endpoint('android', yt.YoutubeApiClient.androidSdkless),
    _Endpoint('ios', yt.YoutubeApiClient.ios),
    _Endpoint('android-vr', yt.YoutubeApiClient.androidVr),
    _Endpoint('media-connect', yt.YoutubeApiClient.mediaConnect),
    _Endpoint('android-music', yt.YoutubeApiClient.androidMusic),
  ];

  /// YouTube's Apple Vision Pro app, as it introduces itself to the player
  /// endpoint. Its streams come with plain addresses — no scrambling — and
  /// are served in full. It is only answered when the request carries a
  /// visitor id, see [_visitorData]; without one it gets a sign-in wall.
  static const String _visionOsUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  static const yt.YoutubeApiClient _visionOs = yt.YoutubeApiClient(
    {
      'context': {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': '1.02',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
          'userAgent': _visionOsUserAgent,
          'osName': 'visionOS',
          'osVersion': '26.5.23O471',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
        },
      },
    },
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
    headers: {
      'X-Youtube-Client-Name': '101',
      'X-Youtube-Client-Version': '1.02',
    },
  );

  /// [client] with the visitor id YouTube issued this device, in the body and
  /// the header, which is how YouTube's own apps send it.
  static yt.YoutubeApiClient _withVisitor(
    yt.YoutubeApiClient client,
    String visitor,
  ) {
    final context = Map<String, dynamic>.from(
      client.payload['context'] as Map<String, dynamic>,
    );
    context['client'] = <String, dynamic>{
      ...context['client'] as Map<String, dynamic>,
      'visitorData': visitor,
    };
    return yt.YoutubeApiClient(
      {...client.payload, 'context': context},
      client.apiUrl,
      headers: {...client.headers, 'X-Goog-Visitor-Id': visitor},
    );
  }

  /// The visitor id YouTube hands any new browser, read from the same place
  /// the package reads it for the iPhone endpoint.
  Future<String> _visitorData(Duration timeout) async {
    final cached = _visitor;
    if (cached != null) return cached;

    var raw = await _youtube
        .getString(
          'https://www.youtube.com/sw.js_data',
          headers: const {
            'User-Agent': _visionOsUserAgent,
            'Content-Type': 'application/json',
          },
        )
        .timeout(timeout);
    if (raw.startsWith(")]}'")) raw = raw.substring(4);

    final data = json.decode(raw) as List<dynamic>;
    final visitor = data[0][2][0][0][13] as String;
    return _visitor = visitor;
  }

  @override
  bool canHandle(Uri url) =>
      _isYoutube(url) && yt.VideoId.parseVideoId(url.toString()) != null;

  static bool _isYoutube(Uri url) {
    final parts = url.host.toLowerCase().split('.');
    for (var i = 0; i < parts.length - 1; i++) {
      if (_domains.contains(parts.sublist(i).join('.'))) return true;
    }
    return false;
  }

  @override
  Future<SourceResolution> resolve(Uri url, {required Duration timeout}) async {
    final id = yt.VideoId.parseVideoId(url.toString());
    if (id == null) {
      return const UnsupportedSource(
        UnsupportedReason.noDownloadableVariant,
        detail: 'That YouTube link does not point at a single video.',
      );
    }

    final videoId = yt.VideoId(id);
    final deadline = DateTime.now().add(timeout);
    final answer = await _askFleet(videoId, deadline);

    final tracks = answer.tracks;
    if (tracks == null) {
      return answer.refusal ??
          const UnsupportedSource(
            UnsupportedReason.lookupFailed,
            detail:
                'None of the YouTube servers Hoza asked would hand this '
                'video over. Try again in a moment.',
          );
    }

    return _fold(url, videoId, tracks, answer.details);
  }

  /// Asks the fleet, a wave at a time, and keeps the first answer that names
  /// streams this device can save.
  ///
  /// Endpoints are ordered by how they have been answering, so the one that
  /// worked a minute ago leads and one that is refusing is left out of the
  /// early waves. Only when every endpoint has been tried does the package's
  /// own default path get a last word.
  Future<_Answer> _askFleet(yt.VideoId videoId, DateTime deadline) async {
    final ordered = _health.order(_fleet, (endpoint) => endpoint.key);
    _Answer? refusal;

    for (var start = 0; start < ordered.length; start += _waveSize) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;

      final wave = ordered.skip(start).take(_waveSize).toList();
      final answer = await _firstToAnswer(wave, videoId, remaining);
      if (answer.tracks != null) return answer;
      refusal = _clearer(refusal, answer);
    }

    final remaining = deadline.difference(DateTime.now());
    if (remaining > Duration.zero) {
      final last = await _lastResort(videoId, remaining);
      if (last.tracks != null) return last;
      refusal = _clearer(refusal, last);
    }

    return refusal ?? const _Answer.none();
  }

  /// Runs one wave and completes as soon as any endpoint in it succeeds.
  ///
  /// The endpoints that lose are not cancelled — a player lookup is one small
  /// request with nothing meaningful to abort — but their answers are dropped,
  /// and what they taught us about the server is kept.
  Future<_Answer> _firstToAnswer(
    List<_Endpoint> wave,
    yt.VideoId videoId,
    Duration remaining,
  ) {
    final settled = Completer<_Answer>();
    _Answer? refusal;
    var pending = wave.length;

    final budget = remaining < _endpointTimeout ? remaining : _endpointTimeout;
    for (final endpoint in wave) {
      unawaited(
        _ask(endpoint, videoId, budget).then((answer) {
          if (settled.isCompleted) return;
          if (answer.tracks != null) {
            settled.complete(answer);
            return;
          }
          refusal = _clearer(refusal, answer);
          pending--;
          if (pending == 0) settled.complete(refusal ?? const _Answer.none());
        }),
      );
    }

    return settled.future;
  }

  /// One endpoint, asked once. Never throws: a failure here is that server's,
  /// not YouTube's, and the wave carries on without it.
  Future<_Answer> _ask(
    _Endpoint endpoint,
    yt.VideoId videoId,
    Duration timeout,
  ) async {
    final startedAt = DateTime.now();
    try {
      final client = endpoint.needsVisitor
          ? _withVisitor(endpoint.client, await _visitorData(timeout))
          : endpoint.client;

      final response = await _controller
          .getPlayerResponse(videoId, client)
          .timeout(timeout);

      final answer = _read(response, endpoint.key);
      final named = answer.tracks;
      if (named == null) {
        if (answer.endpointFault) {
          _health.recordFailure(endpoint.key);
          // A visitor id YouTube has stopped honouring is worth replacing
          // before this endpoint is asked again.
          if (endpoint.needsVisitor) _visitor = null;
        }
        return answer;
      }

      final left = timeout - DateTime.now().difference(startedAt);
      final served = await _verify(named, left);
      if (served.isEmpty) {
        // The endpoint named streams its servers will not hand over: as
        // useless as no answer, and worth leaving this endpoint alone for.
        AppLog.warn('YouTube endpoint ${endpoint.key}', 'no stream served');
        _health.recordFailure(endpoint.key);
        return const _Answer.fault();
      }

      _health.recordSuccess(endpoint.key, DateTime.now().difference(startedAt));
      return _Answer.tracks(served, answer.details);
    } catch (error) {
      AppLog.warn('YouTube endpoint ${endpoint.key}', error.runtimeType);
      _health.recordFailure(endpoint.key);
      return _Answer.failed(_refusalFor(error));
    }
  }

  /// Turns one endpoint's answer into tracks, or into the reason it gave.
  _Answer _read(PlayerResponse response, String endpoint) {
    final status = response.playabilityStatus.toUpperCase();
    final reason = (response.videoPlayabilityError ?? '').toLowerCase();

    if (!response.previewVideoId.isNullOrEmpty || reason.contains('payment')) {
      return const _Answer.refused(
        UnsupportedSource(
          UnsupportedReason.restricted,
          detail: 'This video has to be bought or rented before it can play.',
        ),
      );
    }

    if (status != 'OK') {
      AppLog.warn('YouTube endpoint $endpoint', '$status: $reason');

      // A sign-in wall is the endpoint turning this network away, not a
      // fact about the video: another endpoint may well serve it.
      if (status == 'LOGIN_REQUIRED' && reason.contains('bot')) {
        return const _Answer.fault();
      }
      if (reason.contains('age') || status == 'LOGIN_REQUIRED') {
        return const _Answer.refused(
          UnsupportedSource(
            UnsupportedReason.restricted,
            detail: 'YouTube will not play this video without an account.',
          ),
        );
      }
      if (status == 'ERROR' || reason.contains('unavailable')) {
        return const _Answer.refused(
          UnsupportedSource(
            UnsupportedReason.noDownloadableVariant,
            detail: 'This video is private, deleted, or not available here.',
          ),
        );
      }
      return const _Answer.fault();
    }

    if (response.isLive) {
      return const _Answer.refused(
        UnsupportedSource(
          UnsupportedReason.noDownloadableVariant,
          detail:
              'This is a live stream. Hoza can only save a video that has '
              'finished.',
        ),
      );
    }

    final tracks = [
      for (final stream in response.streams) ?_Track.fromProvider(stream),
    ];
    if (tracks.isEmpty) {
      // Answered, but with nothing this device can fetch outright: scrambled
      // addresses, or a manifest with no lengths. Treat it as this endpoint
      // being unhelpful rather than the video being unavailable.
      AppLog.warn('YouTube endpoint $endpoint', 'no usable streams');
      return const _Answer.fault();
    }

    final title = response.videoTitle.trim();
    final duration = response.videoDuration.inSeconds;
    return _Answer.tracks(
      tracks,
      _Details(
        title: title.isEmpty ? null : title,
        durationSeconds: duration > 0 ? duration : null,
      ),
    );
  }

  /// The package's own client sequence, tried once the fleet has nothing left.
  Future<_Answer> _lastResort(yt.VideoId videoId, Duration timeout) async {
    final client = yt.YoutubeExplode();
    try {
      final manifest = await client.videos.streamsClient
          .getManifest(videoId)
          .timeout(timeout);
      final tracks = [
        for (final stream in manifest.streams) ?_Track.fromStream(stream),
      ];
      if (tracks.isEmpty) return const _Answer.none();
      final served = await _verify(tracks, timeout);
      if (served.isEmpty) return const _Answer.none();
      return _Answer.tracks(served, const _Details());
    } catch (error) {
      AppLog.warn('YouTube last-resort lookup', error.runtimeType);
      return _Answer.failed(_refusalFor(error));
    }
  }

  /// Keeps only the tracks the media servers will actually hand over.
  ///
  /// Every track the picker could end up offering — the best H.264 rendition
  /// of each height, the soundtracks from [_audioCandidates], and the
  /// ready-mixed files if no soundtrack is served — is asked for one byte of
  /// itself. A track the server refuses is dropped, so a quality is never
  /// shown that would fail the moment the user chose it. The probes run
  /// together and cost one small round trip each.
  Future<List<_Track>> _verify(List<_Track> tracks, Duration budget) async {
    final videos = _bestPerHeight(tracks);
    final heights = videos.keys.toList()..sort((a, b) => b.compareTo(a));
    final audios = _audioCandidates(tracks);

    final candidates = <_Track>[
      for (final height in heights.take(_maxVideoVariants)) videos[height]!,
      ...audios,
    ];

    final timeout = budget < _probeTimeout ? budget : _probeTimeout;
    if (timeout <= Duration.zero) return const <_Track>[];

    final served = await _servedOf(candidates, timeout);

    // Nothing to pair the pictures with: the ready-mixed files are the
    // fallback, and they have to be checked the same way.
    if (!served.any((t) => t.isAudioOnly)) {
      final muxed = tracks
          .where((t) => t.isMuxed && t.container == _mp4)
          .toList();
      served.addAll(await _servedOf(muxed, timeout));
    }
    return served;
  }

  /// The soundtracks worth probing: every AAC one, and the best of whatever
  /// else the video carries its sound in.
  ///
  /// Only AAC used to be probed, and most videos are published with Opus and
  /// no AAC at all — which left a 1080p picture with nothing to merge into it
  /// and dropped the whole video to the 360p ready-mixed file. The engine
  /// re-encodes an Opus track on the way in, so it belongs in the pool.
  ///
  /// Only the video's own language is considered here and in [_bestAudio]: a
  /// dubbed track would otherwise be merged in silently.
  List<_Track> _audioCandidates(List<_Track> tracks) {
    final own = tracks.where((t) => t.isAudioOnly && t.isDefaultAudio).toList();
    final aac = own.where((t) => t.container == _mp4).toList();
    final others = own.where((t) => t.container != _mp4).toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    // Every AAC track, but only the best of the rest: YouTube's media servers
    // answer for a video's Opus renditions as a set, so probing the others
    // would buy nothing for the round trips it costs.
    return [...aac, if (others.isNotEmpty) others.first];
  }

  Future<List<_Track>> _servedOf(List<_Track> tracks, Duration timeout) async {
    if (tracks.isEmpty) return <_Track>[];
    final answers = await Future.wait([
      for (final track in tracks) _serves(track.url, track.bytes, timeout),
    ]);
    return [
      for (var i = 0; i < tracks.length; i++)
        if (answers[i]) tracks[i],
    ];
  }

  /// Whether the media server answers a request for the *last* byte of the
  /// [bytes]-long file at [url].
  ///
  /// The last byte, not the first: a server that limits a client to the
  /// opening minute of a stream serves the first byte happily and refuses the
  /// rest, and the picker must not offer a download that would stop a minute
  /// in. A refusal is logged with its status so a change in what YouTube
  /// serves shows up in the log rather than as a silently shorter picker.
  Future<bool> _serves(Uri url, int bytes, Duration timeout) async {
    try {
      final last = bytes > 0 ? bytes - 1 : 0;
      final request = await _client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, _probeAgent);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$last-$last');

      final response = await request.close().timeout(timeout);
      final status = response.statusCode;
      await RequestRace.discard(response);

      final served =
          status == HttpStatus.partialContent || status == HttpStatus.ok;
      if (!served) {
        AppLog.warn(
          'YouTube stream probe',
          'HTTP $status for itag ${url.queryParameters['itag'] ?? '?'}',
        );
      }
      return served;
    } catch (error) {
      AppLog.warn('YouTube stream probe', error.runtimeType);
      return false;
    }
  }

  /// Longest a stream probe may take. It is one byte from a CDN; a server
  /// that takes longer than this is not one to download from.
  static const Duration _probeTimeout = Duration(seconds: 10);

  static String get _probeAgent =>
      '${AppInfo.name.replaceAll(' ', '')}/${AppInfo.version}';

  /// Of two answers that both said no, the one that explains more.
  static _Answer? _clearer(_Answer? current, _Answer next) {
    if (next.refusal == null) return current;
    if (current?.refusal == null) return next;
    return _rank(next.refusal!) > _rank(current!.refusal!) ? next : current;
  }

  static int _rank(UnsupportedSource refusal) => switch (refusal.reason) {
    UnsupportedReason.restricted => 3,
    UnsupportedReason.noDownloadableVariant => 2,
    UnsupportedReason.noProvider => 1,
    UnsupportedReason.lookupFailed => 0,
  };

  /// The refusal that best explains an exception from an endpoint.
  static UnsupportedSource _refusalFor(Object error) => switch (error) {
    yt.VideoRequiresPurchaseException() => const UnsupportedSource(
      UnsupportedReason.restricted,
      detail: 'This video has to be bought or rented before it can play.',
    ),
    yt.VideoUnavailableException() => const UnsupportedSource(
      UnsupportedReason.noDownloadableVariant,
      detail: 'This video is private, deleted, or not available here.',
    ),
    yt.VideoUnplayableException() => const UnsupportedSource(
      UnsupportedReason.restricted,
      detail: 'YouTube will not play this video without an account.',
    ),
    _ => const UnsupportedSource(UnsupportedReason.lookupFailed),
  };

  SourceResolution _fold(
    Uri url,
    yt.VideoId videoId,
    List<_Track> tracks,
    _Details details,
  ) {
    final audio = _bestAudio(tracks);
    final variants = <MediaVariant>[
      ..._videoVariants(tracks, audio),
      // A ready-mixed file carries the same soundtrack, and the encoder throws
      // its picture away — so an audio download is still on offer for a video
      // YouTube publishes no separate audio track for.
      ..._audioVariants(audio ?? _bestMuxed(tracks), details.durationSeconds),
    ];

    if (variants.isEmpty) {
      return const UnsupportedSource(
        UnsupportedReason.noDownloadableVariant,
        detail: 'YouTube offered no format this device can save.',
      );
    }

    return ResolvedMedia(
      MediaMetadata(
        sourceUrl: url,
        source: 'YouTube',
        title: details.title,
        // Derived from the id, so it costs no request and cannot fail.
        thumbnailUrl: yt.ThumbnailSet(videoId.value).highResUrl,
        durationSeconds: details.durationSeconds,
        variants: variants,
      ),
    );
  }

  /// The soundtrack merged into every paired video, and the source of every
  /// audio download.
  ///
  /// AAC first, because Android's muxer copies it into the video untouched and
  /// the download costs nothing but the transfer. Anything else — Opus, in
  /// practice — is taken only when no AAC track is served, and is re-encoded
  /// on the device; slower, but it is what most videos are published with, and
  /// taking it is what keeps them from being offered without their sound.
  _Track? _bestAudio(List<_Track> tracks) {
    final own = tracks.where((t) => t.isAudioOnly && t.isDefaultAudio).toList();
    if (own.isEmpty) return null;
    final aac = own.where((t) => t.container == _mp4).toList();
    final candidates = aac.isNotEmpty ? aac : own;
    candidates.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return candidates.first;
  }

  /// The best of the ready-mixed files, whose sound stands in when YouTube
  /// serves no separate audio track for this video. Its bitrate covers both
  /// tracks, so this is the whole file: the sheet shows what that costs to
  /// fetch before anything is downloaded.
  _Track? _bestMuxed(List<_Track> tracks) {
    final muxed = tracks
        .where((t) => t.isMuxed && t.container == _mp4)
        .toList();
    if (muxed.isEmpty) return null;
    muxed.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return muxed.first;
  }

  List<MediaVariant> _videoVariants(List<_Track> tracks, _Track? audio) {
    if (audio != null) {
      final best = _bestPerHeight(tracks);
      if (best.isNotEmpty) {
        final heights = best.keys.toList()..sort((a, b) => b.compareTo(a));
        return [
          for (final height in heights.take(_maxVideoVariants))
            _pairedVariant(best[height]!, audio),
        ];
      }
    }

    // Nothing to merge: fall back to the streams that already carry sound.
    final muxed = tracks.where((t) => t.isMuxed && t.container == _mp4).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    return muxed.map(_muxedVariant).toList();
  }

  /// One stream per resolution — the highest-bitrate H.264 rendition of each.
  Map<int, _Track> _bestPerHeight(List<_Track> tracks) {
    final best = <int, _Track>{};
    for (final track in tracks) {
      if (!track.isVideoOnly || track.container != _mp4) continue;
      if (!track.videoCodec.startsWith('avc')) continue;
      if (track.height <= 0) continue;

      final current = best[track.height];
      if (current == null || track.bitrate > current.bitrate) {
        best[track.height] = track;
      }
    }
    return best;
  }

  MediaVariant _pairedVariant(_Track video, _Track audio) {
    return MediaVariant(
      id: 'yt-${video.tag}',
      label: _labelFor(video.qualityLabel, video.height),
      format: MediaFormat.mp4,
      url: video.url,
      heightPx: video.height,
      estimatedBytes: video.bytes,
      audioUrl: audio.url,
      audioBytes: audio.bytes,
      // YouTube's media hosts serve byte ranges, which is what lets a paused
      // download pick up where it stopped — and what lets the engine pull the
      // file down several segments at a time.
      supportsResume: true,
    );
  }

  MediaVariant _muxedVariant(_Track stream) {
    return MediaVariant(
      id: 'yt-${stream.tag}',
      label: _labelFor(stream.qualityLabel, stream.height),
      format: MediaFormat.mp4,
      url: stream.url,
      heightPx: stream.height,
      estimatedBytes: stream.bytes,
      supportsResume: true,
    );
  }

  /// The audio downloads on offer, best first.
  ///
  /// YouTube does not let a caller pick a bitrate. It publishes one soundtrack
  /// per video — usually ~160 kbps Opus or 128 kbps AAC, and for some videos a
  /// 256 kbps AAC track — and that is the whole choice. So both of these are
  /// written on the device from whatever came down, unless YouTube already
  /// serves the one that was asked for, in which case the file is saved
  /// exactly as it arrived.
  ///
  /// Encoding at a higher bitrate than the source cannot put back detail the
  /// download never carried; it makes a larger file of the same sound, in the
  /// format that was asked for.
  static const List<int> _audioBitrates = [320, 256];

  /// How far under a target YouTube's own bitrate may sit and still count as
  /// meeting it. Its 256 kbps track is reported a hair under often enough that
  /// an exact test would re-encode it for no gain at all.
  static const int _bitrateSlack = 8;

  List<MediaVariant> _audioVariants(_Track? audio, int? durationSeconds) {
    if (audio == null) return const <MediaVariant>[];
    return [
      for (final kbps in _audioBitrates)
        _audioVariant(audio, kbps, durationSeconds),
    ];
  }

  MediaVariant _audioVariant(_Track audio, int kbps, int? durationSeconds) {
    final served = (audio.bitrate / 1000).round();
    // A ready-mixed file is never saved as it stands, whatever its bitrate
    // says: that number covers a picture the audio download does not want.
    final asIs =
        audio.isAudioOnly &&
        audio.container == _mp4 &&
        served + _bitrateSlack >= kbps;

    return MediaVariant(
      id: 'yt-audio-${audio.tag}-$kbps',
      label: 'M4A $kbps kbps',
      format: MediaFormat.m4a,
      url: audio.url,
      bitrateKbps: kbps,
      // What comes down the wire either way — the source track, whole.
      estimatedBytes: audio.bytes,
      reencodeKbps: asIs ? null : kbps,
      outputBytes: asIs ? audio.bytes : _weightAt(kbps, durationSeconds),
      supportsResume: true,
    );
  }

  /// What [kbps] of sound weighs over [durationSeconds], or null when the
  /// lookup reported no duration — the sheet then says the size is unknown
  /// rather than inventing one.
  static int? _weightAt(int kbps, int? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return null;
    return durationSeconds * kbps * 1000 ~/ 8;
  }

  /// YouTube's own label, but only when it agrees with the resolution the
  /// stream actually carries. It mislabels the odd rendition, and two chips
  /// both reading `144p` for different files would be worse than plain heights.
  static String _labelFor(String published, int heightPx) {
    final height = '${heightPx}p';
    return published.startsWith(height) ? published : height;
  }

  static const String _mp4 = 'mp4';
}

/// One YouTube player endpoint.
class _Endpoint {
  const _Endpoint(this.key, this.client, {this.needsVisitor = false});

  /// Name used by the health registry and the log. Never shown to the user.
  final String key;

  final yt.YoutubeApiClient client;

  /// Whether YouTube only answers this endpoint when the request carries the
  /// visitor id it issued the device.
  final bool needsVisitor;
}

/// What one lookup came back with: tracks, or the reason there are none.
class _Answer {
  const _Answer.tracks(List<_Track> this.tracks, this.details)
    : refusal = null,
      endpointFault = false;

  /// The video cannot be had, for a reason worth telling the user.
  const _Answer.refused(UnsupportedSource this.refusal)
    : tracks = null,
      details = const _Details(),
      endpointFault = false;

  /// The endpoint, not the video, is the problem.
  const _Answer.fault()
    : tracks = null,
      refusal = null,
      details = const _Details(),
      endpointFault = true;

  /// The request itself failed; [refusal] says how that reads to the user.
  const _Answer.failed(UnsupportedSource this.refusal)
    : tracks = null,
      details = const _Details(),
      endpointFault = true;

  const _Answer.none()
    : tracks = null,
      refusal = null,
      details = const _Details(),
      endpointFault = false;

  final List<_Track>? tracks;
  final UnsupportedSource? refusal;
  final _Details details;
  final bool endpointFault;
}

class _Details {
  const _Details({this.title, this.durationSeconds});

  final String? title;
  final int? durationSeconds;
}

/// One stream as YouTube describes it, from whichever path read it.
class _Track {
  const _Track({
    required this.tag,
    required this.url,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.bitrate,
    required this.bytes,
    required this.height,
    required this.qualityLabel,
    required this.isDefaultAudio,
  });

  /// A stream from a player endpoint's answer, or null when it cannot be
  /// fetched as-is: no address, a scrambled address, or no length.
  static _Track? fromProvider(StreamInfoProvider stream) {
    if (stream.url.isEmpty || stream.signatureParameter != null) return null;
    final url = Uri.tryParse(stream.url);
    if (url == null || !url.hasAuthority) return null;

    final bytes = stream.contentLength ?? 0;
    if (bytes <= 0) return null;

    final label = stream.qualityLabel ?? '';
    return _Track(
      tag: stream.tag,
      url: url,
      container: (stream.container ?? '').toLowerCase(),
      videoCodec: (stream.videoCodec ?? '').toLowerCase(),
      audioCodec: (stream.audioCodec ?? '').toLowerCase(),
      bitrate: stream.bitrate ?? 0,
      bytes: bytes,
      height: stream.videoHeight ?? _heightOf(label),
      qualityLabel: label,
      isDefaultAudio: stream.audioTrack?.audioIsDefault ?? true,
    );
  }

  /// A stream from the package's own manifest.
  static _Track? fromStream(yt.StreamInfo stream) {
    final bytes = stream.size.totalBytes;
    if (bytes <= 0) return null;

    return switch (stream) {
      yt.MuxedStreamInfo() => _Track(
        tag: stream.tag,
        url: stream.url,
        container: stream.container.name,
        videoCodec: stream.videoCodec.toLowerCase(),
        audioCodec: stream.audioCodec.toLowerCase(),
        bitrate: stream.bitrate.bitsPerSecond,
        bytes: bytes,
        height: stream.videoResolution.height,
        qualityLabel: stream.qualityLabel,
        isDefaultAudio: true,
      ),
      yt.VideoOnlyStreamInfo() => _Track(
        tag: stream.tag,
        url: stream.url,
        container: stream.container.name,
        videoCodec: stream.videoCodec.toLowerCase(),
        audioCodec: '',
        bitrate: stream.bitrate.bitsPerSecond,
        bytes: bytes,
        height: stream.videoResolution.height,
        qualityLabel: stream.qualityLabel,
        isDefaultAudio: true,
      ),
      yt.AudioOnlyStreamInfo() => _Track(
        tag: stream.tag,
        url: stream.url,
        container: stream.container.name,
        videoCodec: '',
        audioCodec: stream.audioCodec.toLowerCase(),
        bitrate: stream.bitrate.bitsPerSecond,
        bytes: bytes,
        height: 0,
        qualityLabel: '',
        isDefaultAudio: stream.audioTrack?.audioIsDefault ?? true,
      ),
      _ => null,
    };
  }

  final int tag;
  final Uri url;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int bitrate;
  final int bytes;
  final int height;
  final String qualityLabel;

  /// Whether this is the video's own soundtrack rather than a dub.
  final bool isDefaultAudio;

  bool get isAudioOnly => videoCodec.isEmpty && audioCodec.isNotEmpty;
  bool get isVideoOnly => videoCodec.isNotEmpty && audioCodec.isEmpty;
  bool get isMuxed => videoCodec.isNotEmpty && audioCodec.isNotEmpty;

  /// `1080p60` -> 1080. Zero when the label names no resolution.
  static int _heightOf(String label) {
    final match = RegExp(r'^(\d{2,5})p').firstMatch(label.trim());
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }
}

extension on String? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}
