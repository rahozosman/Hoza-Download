import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoza_download/services/platform/share_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.hoza.download/surface');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late String? hostAnswer;

  setUp(() {
    calls = [];
    hostAnswer = 'share';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'host' ? hostAnswer : true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('ShareSurface', () {
    test('asks the platform which window holds the engine', () async {
      final surface = ShareSurface(channel: channel);

      expect(await surface.currentHost(), ShareHost.share);
      hostAnswer = 'app';
      expect(await surface.currentHost(), ShareHost.app);
      hostAnswer = null;
      expect(await surface.currentHost(), isNull);
    });

    test('reveals, closes and opens the app through the channel', () async {
      final surface = ShareSurface(channel: channel);
      await surface.ready();
      await surface.close();
      await surface.openApp();
      expect(calls, ['ready', 'close', 'openApp']);
    });

    test('a platform error never throws into the caller', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'no_window');
      });
      final surface = ShareSurface(channel: channel);
      await expectLater(surface.ready(), completes);
      expect(await surface.currentHost(), isNull);
    });

    test('window events from the platform reach the streams', () async {
      final surface = ShareSurface(channel: channel);
      final dismissed = expectLater(surface.dismissals, emits(anything));
      final hosts = expectLater(
        surface.hosts,
        emitsInOrder([ShareHost.share, ShareHost.app]),
      );

      Future<void> send(String method, [Object? args]) =>
          messenger.handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );

      await send('overlayDismissed');
      await send('hostChanged', 'share');
      await send('hostChanged', 'app');

      await dismissed;
      await hosts;
    });
  });
}
