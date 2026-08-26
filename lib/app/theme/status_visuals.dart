import 'package:flutter/material.dart';

import '../../data/models/download_status.dart';
import '../../data/models/media_option.dart';
import 'app_colors.dart';

/// How a [DownloadStatus] is drawn.
///
/// Status is always carried by an icon *and* a word, never by colour alone, so
/// the state stays readable for colour-blind users and in greyscale.
@immutable
class StatusVisuals {
  const StatusVisuals({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  static StatusVisuals of(DownloadStatus status, HozaPalette p) {
    switch (status) {
      case DownloadStatus.queued:
        return StatusVisuals(
          label: 'Queued',
          icon: Icons.schedule_rounded,
          foreground: p.textSecondary,
          background: p.surfaceMuted,
        );
      case DownloadStatus.downloading:
        return StatusVisuals(
          label: 'Downloading',
          icon: Icons.arrow_downward_rounded,
          foreground: p.accent,
          background: p.accentSoft,
        );
      case DownloadStatus.paused:
        return StatusVisuals(
          label: 'Paused',
          icon: Icons.pause_rounded,
          foreground: p.warning,
          background: p.warningSoft,
        );
      case DownloadStatus.completed:
        return StatusVisuals(
          label: 'Completed',
          icon: Icons.check_rounded,
          foreground: p.success,
          background: p.successSoft,
        );
      case DownloadStatus.failed:
        return StatusVisuals(
          label: 'Failed',
          icon: Icons.error_outline_rounded,
          foreground: p.danger,
          background: p.dangerSoft,
        );
      case DownloadStatus.cancelled:
        return StatusVisuals(
          label: 'Cancelled',
          icon: Icons.block_rounded,
          foreground: p.textTertiary,
          background: p.surfaceMuted,
        );
    }
  }
}

/// How a [MediaType] is drawn wherever video and audio sit side by side.
///
/// The two are told apart by glyph and word first, and by hue second — the
/// fallback artwork already marks audio green, so the picker, the poster badge
/// and the summary strip follow that rather than inventing a second
/// convention. Nothing in the sheet relies on the hue alone.
@immutable
class MediaVisuals {
  const MediaVisuals({
    required this.label,
    required this.icon,
    required this.tint,
    required this.tintSoft,
    required this.tintDeep,
  });

  final String label;
  final IconData icon;

  /// The hue this type carries: selected tiles, the switch thumb, badges.
  final Color tint;

  /// The same hue at wash strength, for a selected surface behind text.
  final Color tintSoft;

  /// Where a surface of this type ramps to. Both types end on a brand hue, so
  /// the sheet never leaves the palette however the user switches.
  final Color tintDeep;

  static MediaVisuals of(MediaType type, HozaPalette p) => switch (type) {
    MediaType.video => MediaVisuals(
      label: 'Video',
      icon: Icons.play_circle_fill_rounded,
      tint: p.accent,
      tintSoft: p.accentSoft,
      tintDeep: p.accentAlt,
    ),
    MediaType.audio => MediaVisuals(
      label: 'Audio',
      icon: Icons.music_note_rounded,
      tint: p.success,
      tintSoft: p.successSoft,
      tintDeep: p.accent,
    ),
    MediaType.image => MediaVisuals(
      label: 'Image',
      icon: Icons.photo_rounded,
      tint: p.warning,
      tintSoft: p.warningSoft,
      tintDeep: p.accent,
    ),
  };

  /// The ramp a filled surface of this type is painted with.
  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tint, tintDeep],
  );

  /// The halo a filled surface of this type casts.
  BoxShadow get halo => BoxShadow(
    color: tint.withValues(alpha: 0.28),
    blurRadius: 14,
    offset: const Offset(0, 4),
  );
}
