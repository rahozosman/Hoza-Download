import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoza_download/app/router.dart';

Route<void> _route(String? name) => PageRouteBuilder<void>(
  settings: RouteSettings(name: name),
  pageBuilder: (_, _, _) => const SizedBox.shrink(),
);

void main() {
  group('RouteStack', () {
    test('a share landing in the app waits until the shell is up', () {
      final stack = RouteStack.instance;
      final splash = _route(Routes.splash);
      final shell = _route(Routes.shell);
      final sheet = _route(null);

      stack.didPush(splash, null);
      expect(RouteStack.hasShell, isFalse);

      // The splash leaves by replacing itself with the shell.
      stack.didReplace(newRoute: shell, oldRoute: splash);
      expect(RouteStack.hasShell, isTrue);

      // A sheet over the shell does not hide it from the check.
      stack.didPush(sheet, shell);
      expect(RouteStack.hasShell, isTrue);

      stack.didPop(sheet, shell);
      stack.didRemove(shell, null);
      expect(RouteStack.hasShell, isFalse);
    });
  });
}
