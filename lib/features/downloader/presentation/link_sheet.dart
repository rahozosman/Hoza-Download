import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/media_option.dart';
import '../../../data/providers/downloads_provider.dart';
import '../../../data/providers/settings_provider.dart';
import '../../../services/platform/share_surface.dart';
import '../../../shared/widgets/hoza_bottom_sheet.dart';
import '../../../shared/widgets/hoza_button.dart';
import '../../../shared/widgets/hoza_card.dart';
import '../../../shared/widgets/flight_overlay.dart';
import '../../../shared/widgets/media_thumbnail.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_art.dart';
import '../../../shared/widgets/state_views.dart';
import '../../shell/presentation/shell_controller.dart';
import '../data/source_registry.dart';
import '../domain/source_provider.dart';
import '../domain/variant_selection.dart';
import 'download_sheet.dart';
import 'widgets/duplicate_sheet.dart';
import 'widgets/media_header.dart';
import 'widgets/variant_picker.dart';

/// Whether a link sheet is on screen right now, anywhere in the app.
///
/// A share can reach the sheet by more than one path at once — the floating
/// window's own show loop, the share listener, a pasted link — and two of
/// them firing for the same share would stack a second sheet on the first.
/// One sheet at a time is the rule, enforced here rather than trusted to
/// every caller.
bool _linkSheetVisible = false;

/// Opens the compact link sheet for [url].
///
/// This is the surface an Android share lands on, so it is a sheet rather than
/// a full screen — the user stays in context and dismisses with one gesture.
/// A second call while one is already open is ignored: the sheet that is up
/// already carries the share.
Future<void> showLinkSheet(
  BuildContext context,
  Uri url, {
  bool overlay = false,
}) async {
  if (_linkSheetVisible) return;
  _linkSheetVisible = true;
  try {
    await showHozaSheet<void>(
      context: context,
      // A half sheet the user can pull to full height when the list of
      // qualities or photos runs long.
      expandable: true,
      initialFraction: 0.5,
      // A share is a detour from whatever the user was watching; the sheet
      // gets up quicker than the app's own sheets so the detour stays short.
      entrance: Motion.fast,
      // The sheet wears the app's own theme — dark when the app is dark — so
      // what slides up over another app is recognisably Hoza, in the mode the
      // user chose for it.
      builder: (_) => LinkSheet(url: url, overlay: overlay),
    );
  } finally {
    _linkSheetVisible = false;
  }
}

class LinkSheet extends ConsumerStatefulWidget {
  const LinkSheet({super.key, required this.url, this.overlay = false});

  final Uri url;

  /// True when this sheet is the whole floating share window rather than a
  /// modal inside the running app: leaving for the Downloads tab then has to
  /// bring the app forward first.
  final bool overlay;

  @override
  ConsumerState<LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<LinkSheet> {
  /// How much of the screen the sheet may take: enough for the options, never
  /// so much that it reads as a screen of its own.
  static const double _maxHeightFraction = 0.65;

  late Future<SourceResolution> _resolution;

  /// Stops the lookup once the sheet is gone: nobody is waiting for it, and
  /// the pages it would still read cost the user data.
  LookupCancel _cancel = LookupCancel();

  MediaType? _selectedType;

  /// Everything ticked, by variant id. One id for a video or a soundtrack,
  /// any number of them for a post's photos.
  Set<String> _selectedIds = <String>{};

  /// Guards the Download button while the duplicate check and enqueue run.
  bool _starting = false;

  /// Set once the user confirms; from then on the sheet mirrors that record.
  String? _downloadId;

  @override
  void initState() {
    super.initState();
    _resolution = _resolve();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<SourceResolution> _resolve({bool fresh = false}) => ref
      .read(sourceRegistryProvider)
      .resolve(widget.url, fresh: fresh, cancel: _cancel);

  void _retryLookup() {
    _cancel.cancel();
    _cancel = LookupCancel();
    setState(() {
      _selectedType = null;
      _selectedIds = <String>{};
      // "Try again" means ask the source again, not repeat the cached answer.
      _resolution = _resolve(fresh: true);
    });
  }

  /// Applies the user's defaults the first time metadata arrives.
  void _applyDefaults(MediaMetadata metadata) {
    if (_selectedType != null) return;
    final settings = ref.read(settingsProvider);

    final type = VariantSelection.openingType(
      metadata,
      settings.defaultMediaType,
    );

    _selectedType = type;
    _selectedIds = _defaultSelection(metadata, type);
  }

  void _selectType(MediaMetadata metadata, MediaType type) {
    setState(() {
      _selectedType = type;
      _selectedIds = _defaultSelection(metadata, type);
    });
  }

  /// What a type opens on.
  ///
  /// Every photo of a post: sharing one is nearly always about the post, and
  /// any of them can be unticked in a tap. A video or a soundtrack has one
  /// answer instead — the rendition closest to the user's quality preference.
  Set<String> _defaultSelection(MediaMetadata metadata, MediaType type) {
    final variants = VariantSelection.ranked(metadata.variantsFor(type));
    if (_picksSeveral(type, variants)) {
      return {for (final variant in variants) variant.id};
    }
    final preferred = VariantSelection.preferred(
      variants,
      ref.read(settingsProvider).qualityPreference,
    );
    return preferred == null ? <String>{} : {preferred.id};
  }

  /// Whether this type is one where several files may be saved at once.
  ///
  /// Only a post with more than one photo in it: a video's resolutions are
  /// renditions of one file, and ticking two of those would mean saving the
  /// same video twice.
  static bool _picksSeveral(MediaType type, List<MediaVariant> variants) =>
      type == MediaType.image && variants.length > 1;

  /// A tap on a tile: one more picture, one fewer, or a different rendition.
  void _toggle(_Choice choice, MediaVariant variant) {
    setState(() {
      if (!choice.picksSeveral) {
        _selectedIds = {variant.id};
        return;
      }
      final next = {..._selectedIds};
      if (!next.remove(variant.id)) next.add(variant.id);
      _selectedIds = next;
    });
  }

  /// Ticks every photo, or clears them when they are all already ticked.
  void _toggleAll(_Choice choice) {
    setState(() {
      _selectedIds = choice.selection.length == choice.variants.length
          ? <String>{}
          : {for (final variant in choice.variants) variant.id};
    });
  }

  Future<void> _startDownload(
    MediaMetadata metadata,
    MediaVariant variant,
  ) async {
    if (_starting) return;
    setState(() => _starting = true);
    HapticFeedback.mediumImpact();

    try {
      final controller = ref.read(downloadsProvider.notifier);

      // Never overwrite silently: if the file is already on the device, the
      // user decides what happens next.
      final existing = await controller.findDuplicate(
        metadata: metadata,
        variant: variant,
      );
      if (!mounted) return;

      if (existing != null) {
        final choice = await showDuplicateSheet(context, existing);
        if (!mounted) return;

        switch (choice) {
          case DuplicateChoice.cancel:
            return;
          case DuplicateChoice.openExisting:
            final opened = await controller.openFile(existing.id);
            if (!mounted) return;
            if (!opened) {
              _notify('No app on this device can open that file.');
            } else {
              _close();
            }
            return;
          case DuplicateChoice.downloadAgain:
            break;
        }
      }

      final outcome = await controller.enqueue(
        metadata: metadata,
        variant: variant,
      );
      if (!mounted) return;

      if (!outcome.isStarted) {
        _notify(outcome.blockedReason ?? 'The download could not be started.');
        return;
      }
      // Measured before the stage swaps, while the poster is still where the
      // user saw it.
      final from = Flight.rectOf(_headerPoster);
      setState(() => _downloadId = outcome.id);
      unawaited(_flyToTray(metadata, from));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _close() => Navigator.of(context).maybePop();

  /// The poster on the sheet's header, so it can be sent flying.
  final GlobalKey _headerPoster = GlobalKey(debugLabel: 'linkSheetPoster');

  /// Sends the poster to the Downloads tab and bumps its badge — the answer
  /// to "where did it go?", given before the question is asked.
  ///
  /// In the floating share window there is no tab bar; the poster sinks to
  /// the bottom edge and fades, which still says "it went to Hoza".
  Future<void> _flyToTray(MediaMetadata metadata, Rect? from) async {
    if (from == null || !mounted) return;
    final tab = Flight.rectOf(FlightTargets.downloadsTab);
    final screen = MediaQuery.sizeOf(context);
    final to = tab != null
        ? Rect.fromCenter(center: tab.center, width: 28, height: 18)
        : Rect.fromCenter(
            center: Offset(screen.width / 2, screen.height - 28),
            width: 28,
            height: 18,
          );

    await Flight.run(
      context,
      from: from,
      to: to,
      lift: 56,
      endOpacity: tab != null ? 0.85 : 0,
      child: MediaThumbnail(
        mediaType: _selectedType ?? MediaType.video,
        imageUrl: metadata.thumbnailUrl,
        width: from.width,
        aspectRatio: from.width / from.height,
      ),
    );
    if (!mounted) return;
    ref.read(downloadBadgeBumpProvider.notifier).bump();
  }

  void _viewDownloads() {
    ref.read(shellTabProvider.notifier).select(ShellTab.downloads);
    if (widget.overlay) unawaited(ref.read(shareSurfaceProvider).openApp());
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final host = Formatters.hostOf(widget.url.toString()) ?? widget.url.host;

    return FutureBuilder<SourceResolution>(
      future: _resolution,
      builder: (context, snapshot) {
        final choice = _choiceFor(snapshot);

        return HozaSheet(
          title: host,
          // A half-sheet: the app the link came from stays in view above it,
          // and a long quality list scrolls inside rather than growing over it.
          maxHeightFraction: _maxHeightFraction,
          // Glass only inside the app: over another app there is nothing of
          // ours behind the sheet to show through, and text over a playing
          // video needs a solid ground.
          frosted: !widget.overlay,
          trailing: IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
          // What the user came here to press is held out of the scroll, so a
          // source with a dozen qualities cannot bury it. It is there from the
          // first frame, greyed while the link is still being read, and it
          // does not move when the answer arrives.
          footer: _confirmBar(snapshot, choice),
          // Checking, choosing and downloading are three states of one
          // surface, not three screens. The sheet grows to each in turn while
          // the old state fades out under the new one, so nothing ever cuts.
          //
          // Once a download is running the switcher is left behind entirely:
          // the download stage is rendered on its own. A cross-fade would
          // otherwise keep the frame it swapped in — a progress block frozen
          // at its first percent — alive underneath the live one, which read
          // as a second, stuck download.
          child: _downloadId != null
              ? AnimatedSize(
                  duration: context.motion(Motion.slow),
                  curve: Motion.emphasized,
                  alignment: Alignment.topCenter,
                  child: _stage(snapshot, choice),
                )
              : AnimatedSize(
                  duration: context.motion(Motion.slow),
                  curve: Motion.emphasized,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: context.motion(Motion.base),
                    switchInCurve: Motion.emphasized,
                    switchOutCurve: Motion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    // Both states hang from the top while the sheet resizes
                    // under them; centred, the outgoing one would drift as it
                    // faded.
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, ?current],
                    ),
                    child: _stage(snapshot, choice),
                  ),
                ),
        );
      },
    );
  }

  /// What the sheet would download if the button were pressed right now, or
  /// null whenever there is nothing to choose from — still checking, refused,
  /// or already downloading.
  ///
  /// Worked out once per build because the body and the pinned bar below it
  /// both need it, and they must never disagree about which variant is
  /// selected.
  _Choice? _choiceFor(AsyncSnapshot<SourceResolution> snapshot) {
    if (_downloadId != null) return null;
    if (snapshot.data case ResolvedMedia(:final metadata)) {
      _applyDefaults(metadata);

      final availableTypes = MediaType.values
          .where(metadata.hasVariantsFor)
          .toList();
      // A resolved link with no variants is a refusal, not a choice.
      if (availableTypes.isEmpty) return null;

      final type = _selectedType ?? availableTypes.first;
      final variants = VariantSelection.ranked(metadata.variantsFor(type));

      // Kept in the order the list is drawn in, so the photos are queued the
      // way the post shows them however they were ticked.
      var selection = variants
          .where((variant) => _selectedIds.contains(variant.id))
          .toList();
      // A single-pick type always has something picked; an empty set only
      // means the user has cleared a photo post, which is allowed.
      if (selection.isEmpty && !_picksSeveral(type, variants)) {
        selection = [variants.first];
      }

      return _Choice(
        metadata: metadata,
        availableTypes: availableTypes,
        type: type,
        variants: variants,
        selection: selection,
      );
    }
    return null;
  }

  /// Whichever of the three states the sheet is in, keyed so the switcher
  /// above can tell one from the next.
  Widget _stage(AsyncSnapshot<SourceResolution> snapshot, _Choice? choice) {
    final downloadId = _downloadId;
    if (downloadId != null) {
      return KeyedSubtree(
        key: const ValueKey<String>('download'),
        child: DownloadStage(
          downloadId: downloadId,
          onClose: _close,
          onViewDownloads: _viewDownloads,
        ),
      );
    }

    if (choice != null) {
      return KeyedSubtree(
        key: const ValueKey<String>('ready'),
        child: _chooser(choice),
      );
    }

    // The registry converts failures into an UnsupportedSource, so an error
    // here would be a bug — it is still handled rather than left to render an
    // empty sheet.
    final result = snapshot.hasError
        ? const UnsupportedSource(UnsupportedReason.lookupFailed)
        : snapshot.data;

    if (result == null) {
      return const _ResolvingView(key: ValueKey<String>('resolving'));
    }

    // Anything that got here and is not a refusal is a resolved link with
    // nothing downloadable in it, which comes to the same thing.
    final refusal = result is UnsupportedSource
        ? result
        : const UnsupportedSource(UnsupportedReason.noDownloadableVariant);

    return KeyedSubtree(
      key: const ValueKey<String>('unsupported'),
      child: _UnsupportedView(
        result: refusal,
        onRetry: refusal.canRetry ? _retryLookup : null,
        onClose: _close,
      ),
    );
  }

  /// The scrolling half: what the link is, and everything there is to pick.
  Widget _chooser(_Choice choice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HozaCard(
          padding: const EdgeInsets.all(Gap.sm),
          child: MediaHeader(
            posterKey: _headerPoster,
            // The sheet's own title already names the site, so the card does
            // not repeat it.
            showSource: false,
            source: choice.metadata.source,
            title:
                choice.metadata.title ?? choice.metadata.sourceUrl.toString(),
            mediaType: choice.type,
            thumbnailUrl: choice.metadata.thumbnailUrl,
            durationSeconds: choice.metadata.durationSeconds,
          ),
        ),
        const SizedBox(height: Gap.md),
        VariantPicker(
          availableTypes: choice.availableTypes,
          selectedType: choice.type,
          onTypeSelected: (next) => _selectType(choice.metadata, next),
          variants: choice.variants,
          selectedIds: choice.selectedIds,
          onVariantSelected: (variant) => _toggle(choice, variant),
          multiSelect: choice.picksSeveral,
          onToggleAll: choice.picksSeveral ? () => _toggleAll(choice) : null,
        ),
      ],
    );
  }

  /// The pinned half: what will be saved, and the button that saves it.
  ///
  /// Null once the download has started — that stage carries its own controls
  /// — and null on a refusal, which carries Close and Try again instead.
  Widget? _confirmBar(
    AsyncSnapshot<SourceResolution> snapshot,
    _Choice? choice,
  ) {
    if (_downloadId != null) return null;

    final checking = !snapshot.hasData && !snapshot.hasError;
    if (choice == null && !checking) return null;

    final selection = choice?.selection ?? const <MediaVariant>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EstimatedSizeRow(selection: choice == null ? null : selection),
        const SizedBox(height: Gap.sm),
        HozaButton(
          // The button says how many files it is about to save, so a set is
          // never a surprise — and says what to do first when none are ticked.
          label: choice != null && choice.picksSeveral
              ? _photoLabel(selection.length)
              : 'Download',
          icon: selection.length > 1
              ? Icons.collections_rounded
              : Icons.arrow_downward_rounded,
          state: _starting ? HozaButtonState.loading : HozaButtonState.idle,
          onPressed: choice == null || selection.isEmpty
              ? null
              : () => _start(choice.metadata, selection),
        ),
      ],
    );
  }

  static String _photoLabel(int count) => switch (count) {
    0 => 'Pick a photo to save',
    1 => 'Download 1 photo',
    _ => 'Download $count photos',
  };

  /// Saves what is ticked.
  ///
  /// One file still goes through the duplicate check, which is a question
  /// about a name already on the device and only answerable one file at a
  /// time; a set is queued as a set, and the numbered names keep it apart
  /// from anything already saved.
  Future<void> _start(MediaMetadata metadata, List<MediaVariant> selection) {
    return selection.length == 1
        ? _startDownload(metadata, selection.first)
        : _startAll(metadata, selection);
  }

  /// Queues every photo of the post as one set and follows the first.
  Future<void> _startAll(
    MediaMetadata metadata,
    List<MediaVariant> variants,
  ) async {
    if (_starting) return;
    setState(() => _starting = true);
    HapticFeedback.mediumImpact();

    try {
      final outcome = await ref
          .read(downloadsProvider.notifier)
          .enqueueAll(metadata: metadata, variants: variants);
      if (!mounted) return;

      if (!outcome.isStarted) {
        _notify(outcome.blockedReason ?? 'The downloads could not be started.');
        return;
      }
      // Measured before the stage swaps, while the poster is still where the
      // user saw it.
      final from = Flight.rectOf(_headerPoster);
      setState(() => _downloadId = outcome.id);
      unawaited(_flyToTray(metadata, from));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}

/// Skeleton shown while the source is being checked. Mirrors the shape of the
/// resolved layout so the swap does not shift the sheet.
class _ResolvingView extends StatelessWidget {
  const _ResolvingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Checking link',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HozaCard(
            padding: const EdgeInsets.all(Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(
                  width: 104,
                  height: 65,
                  borderRadius: Radii.tileRadius,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Skeleton.line(),
                      SizedBox(height: Gap.xs),
                      Skeleton.line(width: 160),
                      SizedBox(height: Gap.xs),
                      Skeleton.line(width: 90),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // Every block stands where its real counterpart will, so the sheet
          // settles into the resolved layout instead of reflowing it. The size
          // line and the button are not here: they are already on screen, in
          // the bar pinned below.
          const Skeleton(
            width: double.infinity,
            height: 52,
            borderRadius: Radii.pillRadius,
          ),
          const SizedBox(height: Gap.md),
          const Skeleton.line(width: 96),
          const SizedBox(height: Gap.sm),
          const _SkeletonTileRow(),
          const SizedBox(height: Gap.xs),
          const _SkeletonTileRow(),
        ],
      ),
    );
  }
}

/// One row of the quality grid, waiting to be filled in.
class _SkeletonTileRow extends StatelessWidget {
  const _SkeletonTileRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Skeleton(height: 62, borderRadius: Radii.tileRadius)),
        SizedBox(width: Gap.xs),
        Expanded(child: Skeleton(height: 62, borderRadius: Radii.tileRadius)),
      ],
    );
  }
}

/// The refusal path: clear, final, and with a way back.
class _UnsupportedView extends StatelessWidget {
  const _UnsupportedView({
    required this.result,
    required this.onClose,
    this.onRetry,
  });

  final UnsupportedSource result;
  final VoidCallback onClose;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      children: [
        StateView(
          icon: result.reason == UnsupportedReason.lookupFailed
              ? Icons.wifi_off_rounded
              : Icons.block_rounded,
          art: result.reason == UnsupportedReason.lookupFailed
              ? StateArt.offline
              : StateArt.brokenLink,
          title: result.title,
          message: result.message,
          tone: StateTone.error,
          compact: true,
        ),
        if (result.detail != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Text(
              result.detail!,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: palette.textTertiary,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: HozaButton(
                label: 'Close',
                variant: onRetry == null
                    ? HozaButtonVariant.primary
                    : HozaButtonVariant.secondary,
                onPressed: onClose,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: Gap.sm),
              Expanded(
                child: HozaButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One resolved link, reduced to exactly what the sheet is about to act on.
///
/// The body and the pinned bar are built from the same instance, so the size
/// shown and the file fetched can never come from different variants.
class _Choice {
  const _Choice({
    required this.metadata,
    required this.availableTypes,
    required this.type,
    required this.variants,
    required this.selection,
  });

  final MediaMetadata metadata;

  /// The types this source genuinely offers — never padded.
  final List<MediaType> availableTypes;

  final MediaType type;

  /// Every variant of [type], highest quality first.
  final List<MediaVariant> variants;

  /// What is ticked, in the order [variants] lists it. Empty only when the
  /// user has cleared a photo post.
  final List<MediaVariant> selection;

  /// Whether several of these may be saved at once — a post's photos, and
  /// nothing else. See `_picksSeveral`.
  bool get picksSeveral => type == MediaType.image && variants.length > 1;

  Set<String> get selectedIds => {for (final variant in selection) variant.id};
}
