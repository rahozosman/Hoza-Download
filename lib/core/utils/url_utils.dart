/// Why a link was rejected. Each case maps to one plain-language message.
enum UrlRejection { empty, noUrlFound, unsupportedScheme, malformed }

/// Result of validating user- or share-supplied text.
class UrlValidation {
  const UrlValidation._(this.url, this.rejection);

  const UrlValidation.valid(Uri url) : this._(url, null);
  const UrlValidation.rejected(UrlRejection reason) : this._(null, reason);

  /// The normalised link, present only when valid.
  final Uri? url;

  final UrlRejection? rejection;

  bool get isValid => url != null;

  /// Message shown under the input. Deliberately non-technical.
  String get message => switch (rejection) {
    null => '',
    UrlRejection.empty => 'Paste a link to continue.',
    UrlRejection.noUrlFound => 'No link found in that text.',
    UrlRejection.unsupportedScheme =>
      'Only http and https links are supported.',
    UrlRejection.malformed => 'That does not look like a valid link.',
  };
}

/// Parsing and validation for every link that enters the app, whether typed,
/// pasted or received from an Android share.
///
/// All input is treated as untrusted: nothing is fetched, opened or written
/// from a link that has not passed through here.
abstract final class UrlUtils {
  static final RegExp _urlPattern = RegExp(
    r'(https?://[^\s<>"'
    r"'"
    r']+)',
    caseSensitive: false,
  );

  /// Longest length a link may have before it is treated as malformed. Guards
  /// against pathological input from a share payload.
  static const int maxLength = 2048;

  /// Pulls the first http(s) link out of arbitrary text.
  ///
  /// Shared text often looks like `Check this out https://… via App`, so the
  /// URL has to be extracted rather than assumed to be the whole string.
  static String? extractFirstUrl(String? text) {
    if (text == null) return null;
    final match = _urlPattern.firstMatch(text);
    if (match == null) return null;
    return _trimTrailingPunctuation(match.group(0)!);
  }

  /// Validates raw text and returns the normalised link.
  static UrlValidation validate(String? rawText) {
    final text = rawText?.trim() ?? '';
    if (text.isEmpty) return const UrlValidation.rejected(UrlRejection.empty);
    if (text.length > maxLength) {
      return const UrlValidation.rejected(UrlRejection.malformed);
    }

    final candidate = extractFirstUrl(text) ?? text;
    final uri = Uri.tryParse(candidate);

    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      // No scheme at all is the common "user typed a bare domain" case.
      return UrlValidation.rejected(
        candidate.contains(' ')
            ? UrlRejection.noUrlFound
            : UrlRejection.malformed,
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const UrlValidation.rejected(UrlRejection.unsupportedScheme);
    }

    return UrlValidation.valid(uri);
  }

  /// Strips punctuation a messaging app may have appended to a link.
  static String _trimTrailingPunctuation(String url) {
    var result = url;
    const trailing = {'.', ',', ')', ']', '}', '!', '?', ';', ':', '>'};
    while (result.isNotEmpty && trailing.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
