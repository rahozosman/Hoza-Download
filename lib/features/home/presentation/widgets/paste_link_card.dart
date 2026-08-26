import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/url_utils.dart';
import '../../../../shared/widgets/hoza_button.dart';
import '../../../../shared/widgets/hoza_card.dart';
import '../../../downloader/presentation/link_sheet.dart';

/// The Home entry point: paste or type a link, then continue.
///
/// Validation runs on the raw text so the user is told what is wrong before
/// anything is fetched.
class PasteLinkCard extends StatefulWidget {
  const PasteLinkCard({super.key});

  @override
  State<PasteLinkCard> createState() => _PasteLinkCardState();
}

class _PasteLinkCardState extends State<PasteLinkCard> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Only shown after the user has tried to continue or paste, so the field
  /// does not scold them mid-typing.
  String? _error;

  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      // Typing clears a stale error; it is re-evaluated on the next attempt.
      if (_error != null) _error = null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;

    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _error = 'Your clipboard is empty.');
      return;
    }

    final extracted = UrlUtils.extractFirstUrl(text) ?? text;
    _controller.text = extracted;
    _controller.selection = TextSelection.collapsed(offset: extracted.length);
    setState(() => _error = null);
    HapticFeedback.selectionClick();
  }

  void _continue() {
    final validation = UrlUtils.validate(_controller.text);
    if (!validation.isValid) {
      setState(() => _error = validation.message);
      return;
    }

    setState(() => _error = null);
    _focusNode.unfocus();
    showLinkSheet(context, validation.url!);
  }

  void _clear() {
    _controller.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    // Shown back as soon as the text resolves to somewhere real, so the field
    // confirms what it understood before anything is fetched.
    final host = _error != null ? null : Formatters.hostOf(_controller.text);

    return HozaCard(
      // The light runs whether or not the field is focused: this is the one
      // thing Home is for, so the card is lit the whole time it is on screen
      // rather than only once the user has already committed to it.
      glow: true,
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HozaIconTile(icon: Icons.link_rounded, size: 30),
              const SizedBox(width: Gap.xs),
              Text(
                'Paste a link',
                style: AppTypography.sectionTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 1,
            maxLength: UrlUtils.maxLength,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
            onSubmitted: (_) => _continue(),
            style: AppTypography.body.copyWith(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'https://…',
              // The head of the field answers what is in it: a globe while
              // it is waiting, a tick the moment the text resolves to a real
              // address, a warning when it does not. Colour and glyph change
              // together, so the state is never carried by hue alone.
              prefixIcon: _FieldMark(
                icon: _error != null
                    ? Icons.error_outline_rounded
                    : host != null
                    ? Icons.check_circle_rounded
                    : Icons.public_rounded,
                color: _error != null
                    ? palette.danger
                    : host != null
                    ? palette.accent
                    : palette.textTertiary,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 42,
                minHeight: 42,
              ),
              suffixIcon: _hasText
                  ? IconButton(
                      onPressed: _clear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear link',
                    )
                  : IconButton(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      tooltip: 'Paste from clipboard',
                    ),
              errorText: null,
            ),
          ),
          // One line under the field, carrying whichever of the two things
          // is worth saying: what went wrong, or where the link points.
          AnimatedSize(
            duration: context.motion(Motion.fast),
            curve: Motion.standard,
            alignment: AlignmentDirectional.topStart,
            child: _error != null
                ? _Note(
                    icon: Icons.error_outline_rounded,
                    text: _error!,
                    color: palette.danger,
                  )
                : host != null
                ? _Note(
                    icon: Icons.check_circle_outline_rounded,
                    text: host,
                    color: palette.accent,
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: Gap.md),
          HozaButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _hasText ? _continue : null,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            'Or share a link to Hoza Download from any app.',
            style: AppTypography.caption.copyWith(color: palette.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The glyph at the head of the link field.
///
/// It swaps rather than recolouring in place: the field is the one control on
/// Home, and a mark that lands as the address becomes valid is what tells the
/// user the app understood them before anything is fetched.
class _FieldMark extends StatelessWidget {
  const _FieldMark({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(Motion.fast),
      switchInCurve: Motion.springy,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(icon, key: ValueKey<IconData>(icon), size: 18, color: color),
    );
  }
}

/// The single line under the field: an icon, a colour, and one short message.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: Gap.xxs),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
