import 'download_record.dart';
import 'media_option.dart';

/// Filter chips on the Downloads screen.
///
/// Media type only. Status is not a filter any more: the list is grouped by it,
/// so a "Completed" chip would have been a second, competing way to say the
/// same thing — and one that hid everything else while it was on.
enum DownloadFilter {
  all('All'),
  video('Video'),
  audio('Audio'),
  image('Images');

  const DownloadFilter(this.label);

  final String label;

  bool matches(DownloadRecord record) => switch (this) {
    DownloadFilter.all => true,
    DownloadFilter.video => record.mediaType == MediaType.video,
    DownloadFilter.audio => record.mediaType == MediaType.audio,
    DownloadFilter.image => record.mediaType == MediaType.image,
  };
}
