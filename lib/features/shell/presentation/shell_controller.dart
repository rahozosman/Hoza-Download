import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The three top-level destinations. Kept deliberately small — extra tabs are
/// out of scope for this product.
enum ShellTab { home, downloads, settings }

/// Which destination the shell is showing.
///
/// Exposed as a provider so any screen (for example Home's "See all") can move
/// the user without passing callbacks down the tree.
class ShellTabController extends Notifier<ShellTab> {
  @override
  ShellTab build() => ShellTab.home;

  void select(ShellTab tab) {
    if (state == tab) return;
    state = tab;
  }
}

final shellTabProvider = NotifierProvider<ShellTabController, ShellTab>(
  ShellTabController.new,
);

/// Ticks every time something lands in the Downloads tab, so its badge can
/// bump even when the count did not change (a second photo of the same set).
class DownloadBadgeBump extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final downloadBadgeBumpProvider = NotifierProvider<DownloadBadgeBump, int>(
  DownloadBadgeBump.new,
);
