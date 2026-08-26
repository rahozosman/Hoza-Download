import '../../../data/models/app_settings.dart';
import '../../../data/models/media_option.dart';
import 'source_provider.dart';

/// Picks which variant a sheet opens on.
///
/// The preference only ever chooses among variants the source actually offers;
/// an unavailable quality falls back to the nearest real one rather than being
/// shown and then failing.
abstract final class VariantSelection {
  /// Highest quality first.
  ///
  /// A post's photos are the one exception: they are numbered in the order
  /// the post shows them, and re-sorting them by size would scramble that.
  static List<MediaVariant> ranked(List<MediaVariant> variants) {
    if (variants.every((variant) => variant.mediaType == MediaType.image)) {
      return [...variants];
    }
    final sorted = [...variants];
    sorted.sort((a, b) {
      final byHeight = (b.heightPx ?? 0).compareTo(a.heightPx ?? 0);
      if (byHeight != 0) return byHeight;
      final byBitrate = (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0);
      if (byBitrate != 0) return byBitrate;
      return (b.totalEstimatedBytes ?? 0).compareTo(a.totalEstimatedBytes ?? 0);
    });
    return sorted;
  }

  static MediaVariant? preferred(
    List<MediaVariant> variants,
    QualityPreference preference,
  ) {
    if (variants.isEmpty) return null;
    final sorted = ranked(variants);

    final target = preference.targetHeight;
    if (target == null) return sorted.first;

    // Best variant at or below the target, otherwise the smallest above it.
    for (final variant in sorted) {
      if ((variant.heightPx ?? 0) <= target) return variant;
    }
    return sorted.last;
  }

  /// The media type a sheet should open on: the preferred one when the source
  /// offers it, otherwise the first type that is available.
  static MediaType openingType(MediaMetadata metadata, MediaType preference) {
    if (metadata.hasVariantsFor(preference)) return preference;
    return MediaType.values.firstWhere(
      metadata.hasVariantsFor,
      orElse: () => preference,
    );
  }
}
