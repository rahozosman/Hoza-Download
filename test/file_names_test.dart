import 'package:flutter_test/flutter_test.dart';
import 'package:hoza_download/core/utils/file_names.dart';

void main() {
  group('FileNames.sanitize', () {
    test('strips path traversal down to the last segment', () {
      expect(FileNames.sanitize('../../etc/passwd'), 'passwd');
      expect(FileNames.sanitize(r'C:\Users\me\clip.mp4'), 'clip.mp4');
    });

    test('replaces characters Android and Windows refuse', () {
      expect(FileNames.sanitize('a<b>c:d"e|f?g*h'), 'a b c d e f g h');
    });

    test('drops leading dots and trailing dots or spaces', () {
      expect(FileNames.sanitize('...hidden'), 'hidden');
      expect(FileNames.sanitize('name... '), 'name');
    });

    test('falls back when nothing usable is left', () {
      expect(FileNames.sanitize('   '), FileNames.fallbackStem);
      expect(FileNames.sanitize('???'), FileNames.fallbackStem);
    });

    test('avoids reserved device names', () {
      expect(FileNames.sanitize('CON'), 'CON file');
    });
  });

  group('FileNames.sanitizeWithExtension', () {
    test('keeps the stem within the filesystem limit', () {
      final name = FileNames.sanitizeWithExtension('x' * 500, 'mp4');
      expect(name.endsWith('.mp4'), isTrue);
      expect(
        name.length,
        lessThanOrEqualTo(FileNames.maxStemLength + '.mp4'.length),
      );
    });

    test('a caption becomes a readable file name', () {
      expect(
        FileNames.sanitizeWithExtension('my cat is funny #fyp', 'mp4'),
        'my cat is funny #fyp.mp4',
      );
    });
  });

  group('FileNames.uniqueName', () {
    test('returns the name itself when it is free', () {
      expect(FileNames.uniqueName('clip.mp4', (_) => false), 'clip.mp4');
    });

    test('numbers a taken name and skips taken numbers', () {
      final taken = {'clip.mp4', 'clip (1).mp4'};
      expect(FileNames.uniqueName('clip.mp4', taken.contains), 'clip (2).mp4');
    });

    test('handles names without an extension', () {
      expect(FileNames.uniqueName('clip', (n) => n == 'clip'), 'clip (1)');
    });
  });
}
