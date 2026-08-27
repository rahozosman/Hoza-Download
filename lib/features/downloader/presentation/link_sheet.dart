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

/// Opens the compact link sheet for [url].
///
/// This is the surface an Android share lands on, so it is a sheet rather than
/// a full screen — the user stays in context and dismisses with one gesture.
Future<void> showLinkSheet(
  BuildContext context,
  Uri url, {
  bool overlay = false,
}) {
  return showHozaSheet<void>(
    context: context,
    // A half sheet the user can pull to full height when the list of
    // qualities or photos runs long.
    expandable: true,
    initialFraction: 0.65,
    // The sheet wears the app's own theme — dark when the app is dark — so
    // what slides up over another app is recognisably Hoza, in the mode the
    // user chose for it.
    builder: (_) => LinkSheet(url: url, overlay: overlay),
  );
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
  String? _selectedVariantId;

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
      _selectedVariantId = null;
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
    final preferred = VariantSelection.preferred(
      metadata.variantsFor(type),
      settings.qualityPreference,
    );

    _selectedType = type;
    _selectedVariantId = preferred?.id;
  }

  void _selectType(MediaMetadata metadata, MediaType type) {
    final preferred = VariantSelection.preferred(
      metadata.variantsFor(type),
      ref.read(settingsProvider).qualityPreference,
    );
    setState(() {
      _selectedType = type;
      _selectedVariantId = preferred?.id;
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
          child: AnimatedSize(
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
              // Both states hang from the top while the sheet resizes under
              // them; centred, the outgoing one would drift as it faded.
              // Once a download is running, only the download stage is laid
              // out: the chooser it replaced must never linger underneath it
              // as a second set of tiles and buttons.
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [if (_downloadId == null) ...previous, ?current],
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

      return _Choice(
        metadata: metadata,
        availableTypes: availableTypes,
        type: type,
        variants: variants,
        selected:
            variants.where((v) => v.id == _selectedVariantId).firstOrNull ??
            variants.first,
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
          selectedVariantId: choice.selected.id,
          onVariantSelected: (variant) =>
              setState(() => _selectedVariantId = variant.id),
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

    // A post with several photos can be saved as one set. The button says
    // how many, so "all" is never a surprise.
    final photos = choice != null && choice.type == MediaType.image
        ? choice.variants
        : const <MediaVariant>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EstimatedSizeRow(variant: choice?.selected),
        const SizedBox(height: Gap.sm),
        HozaButton(
          label: 'Download',
          icon: Icons.arrow_downward_rounded,
          state: _starting ? HozaButtonState.loading : HozaButtonState.idle,
          onPressed: choice == null
              ? null
              : () => _startDownload(choice.metadata, choice.selected),
        ),
        if (photos.length > 1) ...[
          const SizedBox(height: Gap.xs),
          HozaButton(
            label: 'Save all ${photos.length} photos',
            icon: Icons.collections_rounded,
            variant: HozaButtonVariant.secondary,
            state: _starting ? HozaButtonState.loading : HozaButtonState.idle,
            onPressed: () => _startAll(choice!.metadata, photos),
          ),
        ],
      ],
    );
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
    required this.selected,
  });

  final MediaMetadata metadata;

  /// The types this source genuinely offers — never padded.
  final List<MediaType> availableTypes;

  final MediaType type;

  /// Every variant of [type], highest quality first.
  final List<MediaVariant> variants;

  final MediaVariant selected;
}
