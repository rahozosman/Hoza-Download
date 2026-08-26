import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/file_names.dart';

/// Confirms a destructive action. Returns true only on an explicit yes.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final palette = context.colors;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.danger),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return result ?? false;
}

/// What the user chose in the delete dialog.
class DeleteChoice {
  const DeleteChoice({required this.confirmed, required this.deleteFile});

  static const DeleteChoice cancelled = DeleteChoice(
    confirmed: false,
    deleteFile: false,
  );

  final bool confirmed;

  /// True only when the user explicitly ticked the box.
  final bool deleteFile;
}

/// Confirms removing a download, and asks separately about the saved file.
///
/// The two are deliberately different decisions: tidying the list is cheap and
/// reversible, deleting media is not, so the file is only touched on an
/// explicit opt-in that starts unticked.
Future<DeleteChoice> promptDelete(
  BuildContext context, {
  required String fileName,
  required bool unfinished,
  required bool hasFile,
}) async {
  var deleteFile = false;

  final result = await showDialog<DeleteChoice>(
    context: context,
    builder: (context) {
      final palette = context.colors;

      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(unfinished ? 'Stop and remove?' : 'Remove from history?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unfinished
                    ? 'This cancels "$fileName" and discards the part that has '
                          'downloaded so far.'
                    : 'This removes "$fileName" from your Hoza Download '
                          'history.',
              ),
              if (hasFile && !unfinished) ...[
                const SizedBox(height: Gap.xs),
                CheckboxListTile(
                  value: deleteFile,
                  onChanged: (value) =>
                      setState(() => deleteFile = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: palette.danger,
                  title: Text(
                    'Also delete the saved file',
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(DeleteChoice.cancelled),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(DeleteChoice(confirmed: true, deleteFile: deleteFile)),
              style: TextButton.styleFrom(foregroundColor: palette.danger),
              child: Text(unfinished ? 'Stop and remove' : 'Remove'),
            ),
          ],
        ),
      );
    },
  );

  return result ?? DeleteChoice.cancelled;
}

/// Asks for a new file name.
///
/// The extension is fixed and shown but not editable — changing it would
/// misrepresent the file's contents. The returned name is already sanitised.
Future<String?> promptRename(
  BuildContext context, {
  required String currentFileName,
}) async {
  final extension = FileNames.extensionOf(currentFileName);
  final controller = TextEditingController(
    text: FileNames.stemOf(currentFileName),
  );

  try {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        final palette = context.colors;

        return AlertDialog(
          title: const Text('Rename file'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: FileNames.maxStemLength,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'File name',
                  suffixText: extension.isEmpty ? null : '.$extension',
                  suffixStyle: AppTypography.caption.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
                onSubmitted: (value) =>
                    Navigator.of(context).pop(_normalise(value, extension)),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'Unsupported characters are replaced automatically.',
                style: AppTypography.caption.copyWith(
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(_normalise(controller.text, extension)),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

String? _normalise(String value, String extension) {
  if (value.trim().isEmpty) return null;
  return extension.isEmpty
      ? FileNames.sanitize(value)
      : FileNames.sanitizeWithExtension(value, extension);
}
