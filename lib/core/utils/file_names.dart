/// Filename hygiene for anything that reaches the filesystem.
///
/// Titles, server-supplied names and user renames are all untrusted input: they
/// may contain path separators, traversal sequences, reserved names or control
/// characters. Nothing is written to disk without passing through here.
abstract final class FileNames {
  /// Windows/Android-unsafe characters plus control codes.
  static final RegExp _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
  static final RegExp _collapseSpaces = RegExp(r'\s+');

  /// Names Windows refuses; harmless to avoid on Android too.
  static const Set<String> _reserved = {
    'con',
    'prn',
    'aux',
    'nul',
    'com1',
    'com2',
    'com3',
    'com4',
    'com5',
    'com6',
    'com7',
    'com8',
    'com9',
    'lpt1',
    'lpt2',
    'lpt3',
    'lpt4',
    'lpt5',
    'lpt6',
    'lpt7',
    'lpt8',
    'lpt9',
  };

  /// Keeps the stem short enough that stem + extension stays well inside the
  /// 255-byte limit common to Android filesystems.
  static const int maxStemLength = 120;

  static const String fallbackStem = 'download';

  /// Reduces [input] to a safe single path segment.
  ///
  /// Strips directory components entirely, so `../../etc/passwd` becomes
  /// `passwd` and can never escape the target folder.
  static String sanitize(String input, {String fallback = fallbackStem}) {
    var name = input.trim();

    // Drop any path structure: only the last segment can be a file name.
    name = name.split(RegExp(r'[/\\]')).last;

    name = name.replaceAll(_illegal, ' ');
    name = name.replaceAll(_collapseSpaces, ' ').trim();

    // Leading dots hide files; trailing dots and spaces are stripped by some
    // filesystems, which would silently change the name.
    while (name.startsWith('.')) {
      name = name.substring(1).trimLeft();
    }
    while (name.isNotEmpty && (name.endsWith('.') || name.endsWith(' '))) {
      name = name.substring(0, name.length - 1);
    }

    if (name.isEmpty) return fallback;
    if (_reserved.contains(name.toLowerCase())) return '$name file';
    return name;
  }

  /// Sanitises a full name and re-attaches [extension].
  static String sanitizeWithExtension(
    String input,
    String extension, {
    String fallback = fallbackStem,
  }) {
    final safe = sanitize(input, fallback: fallback);
    final stem = stemOf(safe);
    final trimmed = stem.length > maxStemLength
        ? stem.substring(0, maxStemLength).trimRight()
        : stem;
    final finalStem = trimmed.isEmpty ? fallback : trimmed;
    return '$finalStem.$extension';
  }

  /// `clip.final.mp4` -> `clip.final`.
  static String stemOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return fileName;
    return fileName.substring(0, dot);
  }

  /// `clip.final.mp4` -> `mp4`, or an empty string when there is none.
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }

  /// Produces the next non-colliding name: `clip.mp4`, `clip (1).mp4`, …
  ///
  /// [exists] reports whether a candidate is already taken, so the same logic
  /// works against a directory listing or a database.
  static String uniqueName(
    String fileName,
    bool Function(String candidate) exists, {
    int maxAttempts = 999,
  }) {
    if (!exists(fileName)) return fileName;

    final stem = stemOf(fileName);
    final extension = extensionOf(fileName);
    final suffix = extension.isEmpty ? '' : '.$extension';

    for (var i = 1; i <= maxAttempts; i++) {
      final candidate = '$stem ($i)$suffix';
      if (!exists(candidate)) return candidate;
    }

    // Give up on the numbered scheme rather than looping forever; the caller
    // still gets a name that does not collide with the ones tried above.
    return '$stem (${DateTime.now().millisecondsSinceEpoch})$suffix';
  }
}
