import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The link the floating share sheet is currently showing.
///
/// One place holds it, so a share can never be opened twice or dropped because
/// a screen was still building, and a second share arriving while the sheet is
/// up simply replaces the value the sheet is watching.
class OverlayShareController extends Notifier<Uri?> {
  @override
  Uri? build() => null;

  void present(Uri url) => state = url;

  void clear() => state = null;
}

final overlayShareProvider = NotifierProvider<OverlayShareController, Uri?>(
  OverlayShareController.new,
);
