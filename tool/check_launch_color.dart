// ignore_for_file: avoid_print

import 'dart:io';

/// Fails when a native launch colour and the Flutter palette background it
/// hands over to drift apart.
///
/// Android paints the launch window before Flutter has drawn anything:
/// `hozaMidnight` when the system is in its night scheme, `hozaDawn` by day.
/// Each must equal the matching `HozaPalette` background, or every cold start
/// shows a visible step from one colour to another — small, and exactly the
/// kind of seam that makes an app read as cheap.
///
/// A comment in colors.xml used to be the only thing holding the pairs
/// together. It did not hold: the palette was retuned and the launch colour
/// was left behind. This checks it instead.
///
///     dart run tool/check_launch_color.dart
///
/// Exits 0 when both pairs match, 1 when any does not.
void main() {
  final xml = File('android/app/src/main/res/values/colors.xml');
  final dart = File('lib/app/theme/app_colors.dart');

  var ok = true;
  for (final (name, palette) in [
    ('hozaMidnight', 'dark'),
    ('hozaDawn', 'light'),
  ]) {
    final native = _nativeLaunchColour(xml, name);
    final flutter = _paletteBackground(dart, palette);

    if (native == null) {
      _fail('Could not find <color name="$name"> in ${xml.path}');
      ok = false;
      continue;
    }
    if (flutter == null) {
      _fail('Could not find the $palette palette background in ${dart.path}');
      ok = false;
      continue;
    }

    if (native != flutter) {
      _fail(
        'Launch colour drift.\n'
        '  native  (colors.xml, $name): #$native\n'
        '  flutter (HozaPalette.$palette.background): #$flutter\n'
        'These paint one after the other on every cold start, so they have '
        'to be the same colour.',
      );
      ok = false;
      continue;
    }

    print('Launch colour matches on both sides ($palette): #$native');
  }

  if (!ok) exitCode = 1;
}

/// `<color name="hozaMidnight">#FF080E1C</color>` → `FF080E1C`
String? _nativeLaunchColour(File file, String name) {
  if (!file.existsSync()) return null;
  final match = RegExp(
    '<color\\s+name="$name"\\s*>\\s*#([0-9a-fA-F]{6,8})\\s*</color>',
  ).firstMatch(file.readAsStringSync());
  return match == null ? null : _normalise(match.group(1)!);
}

/// The `background:` of the named palette — the one the launch window in the
/// matching system scheme stands in for.
String? _paletteBackground(File file, String palette) {
  if (!file.existsSync()) return null;
  final source = file.readAsStringSync();

  final start = source.indexOf('HozaPalette $palette = HozaPalette(');
  if (start < 0) return null;

  final match = RegExp(
    r'background:\s*Color\(0x([0-9a-fA-F]{6,8})\)',
  ).firstMatch(source.substring(start));
  return match == null ? null : _normalise(match.group(1)!);
}

/// Both sides written the same way, so `FF080E1C` and `ff080e1c` compare equal
/// and a 6-digit value is treated as fully opaque.
String _normalise(String hex) {
  final value = hex.toUpperCase();
  return value.length == 6 ? 'FF$value' : value;
}

void _fail(String message) {
  stderr.writeln(message);
  exitCode = 1;
}
