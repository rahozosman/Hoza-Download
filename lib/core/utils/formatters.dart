import 'package:intl/intl.dart';

/// Display formatting shared by every screen.
///
/// Kept pure and widget-free so the same rules apply in lists, sheets and
/// notifications.
abstract final class Formatters {
  static final DateFormat _timeOfDay = DateFormat.jm();
  static final DateFormat _weekday = DateFormat('EEEE');
  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');

  /// `18.5 MB`. Returns a dash when the size is unknown so the UI never
  /// invents a number.
  static String bytes(int? value, {String unknown = '—'}) {
    if (value == null || value < 0) return unknown;
    if (value < 1000) return '$value B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = value / 1000;
    var unit = 0;
    while (size >= 1000 && unit < units.length - 1) {
      size /= 1000;
      unit++;
    }
    final decimals = size >= 100 ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[unit]}';
  }

  /// `4.2 MB/s`.
  static String speed(double? bytesPerSecond, {String unknown = '—'}) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) return unknown;
    return '${bytes(bytesPerSecond.round())}/s';
  }

  /// `12.4 MB / 18.5 MB`, degrading gracefully when the total is unknown.
  static String transferred(int downloaded, int? total) {
    if (total == null || total <= 0) return bytes(downloaded);
    return '${bytes(downloaded)} / ${bytes(total)}';
  }

  /// `00:42`, `01:20:05`. Returns a dash when no honest estimate exists.
  static String duration(int? seconds, {String unknown = '—'}) {
    if (seconds == null || seconds < 0) return unknown;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    if (hours > 0) return '${two(hours)}:${two(minutes)}:${two(secs)}';
    return '${two(minutes)}:${two(secs)}';
  }

  /// `67%`.
  static String percent(double? progress) {
    if (progress == null) return '—';
    return '${(progress.clamp(0.0, 1.0) * 100).round()}%';
  }

  /// `Today, 1:42 PM` / `Yesterday, 9:05 AM` / `Tue, 8:12 PM` / `4 Mar 2025`.
  static String timestamp(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final day = DateTime(value.year, value.month, value.day);
    final today = DateTime(reference.year, reference.month, reference.day);
    final difference = today.difference(day).inDays;

    if (difference == 0) return 'Today, ${_timeOfDay.format(value)}';
    if (difference == 1) return 'Yesterday, ${_timeOfDay.format(value)}';
    if (difference < 7) {
      return '${_weekday.format(value)}, ${_timeOfDay.format(value)}';
    }
    if (value.year == reference.year) return _dayMonth.format(value);
    return _dayMonthYear.format(value);
  }

  /// Time-of-day greeting for the Home header.
  static String greeting({DateTime? now}) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// Host of a URL without the `www.` prefix, for the source label.
  /// Returns null for anything that is not a parseable http(s) URL.
  static String? hostOf(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasAuthority) return null;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
