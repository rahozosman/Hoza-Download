// Build-time tool: turns the source artwork into the app's icon asset.
//
// The artwork is an app-tile: a dark rounded square drawn edge to edge on an
// opaque white ground. Android's adaptive icon draws the foreground inset
// inside its mask, which would leave four white corner blobs floating inside
// the icon — so the corners are cut to transparent here, once, and every
// consumer (launcher icon, in-app mark, iOS) gets a clean tile.
//
// Run with:  dart run tool/make_icon.dart <source.png>
//
// Then regenerate the launcher icons:  dart run flutter_launcher_icons
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Where the app reads its mark from. Overwritten in place.
const String output = 'assets/icon/hoza_icon.png';

/// Icon assets never need more than this; anything larger is dead weight in
/// the APK, since the launcher mipmaps are generated separately.
const int outputSize = 1024;

/// A pixel this bright on all three channels is the white ground, not art.
const int whiteThreshold = 245;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/make_icon.dart <source.png>');
    exitCode = 64;
    return;
  }

  final source = File(args.first);
  if (!source.existsSync()) {
    stderr.writeln('No such file: ${source.path}');
    exitCode = 66;
    return;
  }

  final decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode ${source.path}');
    exitCode = 65;
    return;
  }

  final art = decoded.numChannels == 4
      ? decoded
      : decoded.convert(numChannels: 4);

  final radius = _cornerRadius(art);
  stdout.writeln(
    'source ${art.width}x${art.height}, corner radius ${radius.round()}px '
    '(${(radius / art.width * 100).toStringAsFixed(1)}%)',
  );
  // Sampled mid-left edge: inside the tile, clear of the ring, so it reports
  // the ground colour the adaptive background has to match.
  stdout.writeln('tile colour ${_hex(art, art.width ~/ 40, art.height ~/ 2)}');

  _roundCorners(art, radius);

  final resized = img.copyResize(
    art,
    width: outputSize,
    height: outputSize,
    interpolation: img.Interpolation.cubic,
  );

  File(output)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(resized));

  stdout.writeln('wrote $output at ${outputSize}px with transparent corners');
}

/// Measures the artwork's own corner radius.
///
/// On a rounded tile drawn to the edge, the top row is white until the curve
/// ends — so the first non-white pixel along it is the radius. Falls back to a
/// sane share of the width if the art turns out to be a full-bleed square.
double _cornerRadius(img.Image art) {
  final probeRow = math.max(1, art.height ~/ 500);
  for (var x = 0; x < art.width ~/ 2; x++) {
    if (!_isWhite(art, x, probeRow)) return x.toDouble();
  }
  return art.width * 0.2;
}

/// Clears everything outside a rounded rectangle to transparent, with one
/// pixel of feathering so the cut does not read as a staircase.
void _roundCorners(img.Image art, double radius) {
  final w = art.width.toDouble();
  final h = art.height.toDouble();
  final r = radius.clamp(1.0, math.min(w, h) / 2);

  for (var y = 0; y < art.height; y++) {
    for (var x = 0; x < art.width; x++) {
      final coverage = _coverage(x + 0.5, y + 0.5, w, h, r);
      if (coverage >= 1) continue;

      final pixel = art.getPixel(x, y);
      art.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        (pixel.a * coverage).round(),
      );
    }
  }
}

/// How much of the pixel at ([x], [y]) falls inside the rounded rectangle.
double _coverage(double x, double y, double w, double h, double r) {
  // Distance from the corner circle's centre, measured only in the corner
  // quadrants; anywhere else the pixel is fully inside.
  final dx = math.max(math.max(r - x, x - (w - r)), 0.0);
  final dy = math.max(math.max(r - y, y - (h - r)), 0.0);
  if (dx == 0 || dy == 0) return 1;

  final distance = math.sqrt(dx * dx + dy * dy);
  return (r + 0.5 - distance).clamp(0.0, 1.0);
}

bool _isWhite(img.Image art, int x, int y) {
  final pixel = art.getPixel(x, y);
  return pixel.r >= whiteThreshold &&
      pixel.g >= whiteThreshold &&
      pixel.b >= whiteThreshold;
}

String _hex(img.Image art, int x, int y) {
  final pixel = art.getPixel(x, y);
  String part(num value) =>
      value.toInt().toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${part(pixel.r)}${part(pixel.g)}${part(pixel.b)}';
}
