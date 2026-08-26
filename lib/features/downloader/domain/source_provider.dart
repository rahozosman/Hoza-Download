import '../../../data/models/media_option.dart';

/// What a source told us about a link.
class MediaMetadata {
  const MediaMetadata({
    required this.sourceUrl,
    required this.source,
    required this.variants,
    this.title,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  final Uri sourceUrl;

  /// Display name of the site the media came from.
  final String source;

  /// Every variant the source genuinely offers. Never padded with qualities
  /// the source does not provide.
  final List<MediaVariant> variants;

  final String? title;
  final String? thumbnailUrl;
  final int? durationSeconds;

  List<MediaVariant> variantsFor(MediaType type) =>
      variants.where((variant) => variant.mediaType == type).toList();

  bool hasVariantsFor(MediaType type) =>
      variants.any((variant) => variant.mediaType == type);
}

/// Why a link cannot be downloaded.
///
/// Every case is a *refusal to proceed*, never a hint at a workaround: Hoza
/// does not circumvent DRM, authentication, paywalls or platform restrictions.
enum UnsupportedReason {
  /// No registered provider recognises this site.
  noProvider,

  /// The site is recognised but offers no downloadable version of this link.
  noDownloadableVariant,

  /// The content is protected or requires an account the app will not bypass.
  restricted,

  /// The lookup itself failed — network, timeout or an unusable response.
  lookupFailed,
}

/// Outcome of resolving a link.
sealed class SourceResolution {
  const SourceResolution();
}

class ResolvedMedia extends SourceResolution {
  const ResolvedMedia(this.metadata);

  final MediaMetadata metadata;
}

class UnsupportedSource extends SourceResolution {
  const UnsupportedSource(this.reason, {this.detail});

  final UnsupportedReason reason;

  /// Optional extra line shown under the standard message.
  final String? detail;

  String get title => switch (reason) {
    UnsupportedReason.lookupFailed => 'Could not read this link',
    _ => 'Download unavailable',
  };

  String get message => switch (reason) {
    UnsupportedReason.noProvider =>
      'This source does not provide a supported downloadable version.',
    UnsupportedReason.noDownloadableVariant =>
      'This link has no downloadable video, photo or audio version.',
    UnsupportedReason.restricted =>
      'This content is protected by its source and cannot be downloaded.',
    UnsupportedReason.lookupFailed =>
      'The link could not be checked. Check your connection and try again.',
  };

  /// Only a failed lookup is worth retrying; the rest are permanent.
  bool get canRetry => reason == UnsupportedReason.lookupFailed;
}

/// A way to stop a lookup that nobody is waiting for any more.
///
/// The sheet that asked for a link may close while providers are still being
/// asked; the chain checks this between providers and stops rather than
/// spending the user's data on an answer that will be thrown away.
class LookupCancel {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Contract every download source implements.
///
/// Providers only expose media their source publishes as downloadable. A
/// provider that would need to defeat a protection simply does not claim the
/// link.
abstract interface class SourceProvider {
  /// Display name used in the UI.
  String get name;

  /// Whether this provider claims the link.
  bool canHandle(Uri url);

  /// Reads what the source publishes for [url].
  ///
  /// Implementations must respect [timeout] and surface failures as an
  /// [UnsupportedSource] rather than throwing raw network errors.
  Future<SourceResolution> resolve(Uri url, {required Duration timeout});
}
