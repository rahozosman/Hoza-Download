/// Static product facts used by the UI.
abstract final class AppInfo {
  static const String name = 'Hoza Download';
  static const String tagline = 'Download what you are allowed to save.';

  /// Shown on the About row and in the licence page.
  ///
  /// Keep in step with `version:` in pubspec.yaml — that is what the APK's
  /// versionName comes from, and the two disagreeing would misreport the build
  /// a user is running.
  static const String version = '1.0.0';

  static const String packageId = 'com.hoza.download';

  /// Where the app fetches its remote configuration — platform kill switches,
  /// extractor patterns, probe and telemetry addresses. Must be https. Leave
  /// empty to run entirely on the built-in defaults (no network request is
  /// made). See `server/README.md` for the file's shape and hosting options.
  static const String remoteConfigUrl =
      'https://raw.githubusercontent.com/rahozosman/Hoza-Download/main/server/config/extractors.json';

  /// Where finished downloads are written, in the user's shared storage. The
  /// platform reports the same path back for the Settings row; this constant is
  /// what the UI shows alongside a finished file.
  static const String downloadFolder = 'Download/Hoza Download';

  /// The person behind the app — the only identity Hoza Download claims.
  static const String developer = 'Rahoz Osman Salim';

  /// Short form for the Home signature, where the line has to stay one row.
  static const String developerShort = 'Rahoz Osman';

  static const String developerEmail = 'hozahoza2001@gmail.com';

  /// Fixed, not derived from the clock: a device with the wrong date would
  /// otherwise rewrite the notice every time the app opened.
  static const String copyright = '© 2026 Rahoz Osman. All rights reserved.';
}
