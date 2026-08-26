import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../data/reset/reset_service.dart';
import '../../../../shared/widgets/hoza_bottom_sheet.dart';
import '../../../../shared/widgets/hoza_button.dart';
import '../../../shell/presentation/shell_controller.dart';

/// Two confirmations, then the reset itself.
///
/// The first asks, the second makes sure. Neither dialog puts the destructive
/// answer where the thumb already rests: Cancel is the filled button in both,
/// so continuing always costs a deliberate reach, and a double-tap on the row
/// cannot carry someone through to a wipe.
Future<void> showResetFlow(BuildContext context, WidgetRef ref) async {
  final agreed = await _confirmScope(context);
  if (!agreed || !context.mounted) return;

  final certain = await _confirmFinal(context);
  if (!certain || !context.mounted) return;

  HapticFeedback.heavyImpact();

  await showHozaSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _ResetSheet(),
  );
}

/// Step one: exactly what goes, and — just as important — what stays.
Future<bool> _confirmScope(BuildContext context) async {
  final palette = context.colors;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.dangerSoft,
        ),
        child: Icon(Icons.restart_alt_rounded, size: 24, color: palette.danger),
      ),
      title: const Text('Reset all data?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently removes everything Hoza Download keeps on '
              'this device:',
              style: AppTypography.body.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: Gap.sm),
            _Point(
              icon: Icons.remove_circle_outline_rounded,
              tint: palette.danger,
              text:
                  'Download history, the queue, and every completed or '
                  'failed record',
            ),
            _Point(
              icon: Icons.remove_circle_outline_rounded,
              tint: palette.danger,
              text: 'Every setting, back to its default',
            ),
            _Point(
              icon: Icons.remove_circle_outline_rounded,
              tint: palette.danger,
              text: 'Cached details and unfinished download chunks',
            ),
            const SizedBox(height: Gap.xs),
            Divider(color: palette.border, height: Gap.md),
            _Point(
              icon: Icons.check_circle_outline_rounded,
              tint: palette.success,
              text: 'Files you have already saved stay exactly where they are',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.danger),
          child: const Text('Reset everything'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  return result ?? false;
}

/// Step two: short, and about consequence rather than contents.
Future<bool> _confirmFinal(BuildContext context) async {
  final palette = context.colors;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('This cannot be undone'),
      content: Text(
        'Hoza Download will start again as if it had just been installed, '
        'including the welcome tour. There is no way back from this.',
        style: AppTypography.body.copyWith(color: palette.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.danger),
          child: const Text('Yes, reset everything'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep my data'),
        ),
      ],
    ),
  );

  return result ?? false;
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.tint, required this.text});

  final IconData icon;
  final Color tint;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { pending, running, done }

/// The reset itself, shown as the four stages it really moves through.
class _ResetSheet extends ConsumerStatefulWidget {
  const _ResetSheet();

  @override
  ConsumerState<_ResetSheet> createState() => _ResetSheetState();
}

class _ResetSheetState extends ConsumerState<_ResetSheet>
    with SingleTickerProviderStateMixin {
  /// How long each stage is held on screen. The work itself is close to
  /// instant, and progress nobody can read is not progress — but the pacing
  /// belongs here, in the display, not in the service doing the work.
  static const Duration _dwell = Duration(milliseconds: 280);

  late final AnimationController _success = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );

  // Built once, not per build: a CurvedAnimation subscribes to its parent.
  late final CurvedAnimation _pop = CurvedAnimation(
    parent: _success,
    curve: Motion.springy,
  );

  ResetStage _stage = ResetStage.stopping;
  ResetReport? _report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  @override
  void dispose() {
    _pop.dispose();
    _success.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final report = await ref
        .read(resetServiceProvider)
        .run(
          onStage: (stage) async {
            if (!mounted) return;
            setState(() => _stage = stage);
            if (stage == ResetStage.done || context.reduceMotion) return;
            await Future<void>.delayed(_dwell);
          },
        );

    if (!mounted) return;
    setState(() => _report = report);
    HapticFeedback.mediumImpact();

    if (context.reduceMotion) {
      _success.value = 1;
    } else {
      _success.forward();
    }
  }

  void _finish() {
    // Back to the top of the app, which is where a fresh install would open.
    ref.read(shellTabProvider.notifier).select(ShellTab.home);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return PopScope(
      // There is nothing to go back to mid-wipe; the stores are already
      // changing underneath the screen that opened this.
      canPop: report != null,
      child: HozaSheet(
        title: report == null ? 'Resetting' : null,
        child: AnimatedSize(
          duration: context.motion(Motion.base),
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: context.motion(Motion.base),
            switchInCurve: Motion.standard,
            switchOutCurve: Motion.exit,
            child: report == null
                ? _progress(context)
                : _outcome(context, report),
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final palette = context.colors;
    final steps = ResetStage.steps;
    final reached = _stage == ResetStage.done
        ? steps.length
        : steps.indexOf(_stage);

    return Column(
      key: const ValueKey<String>('progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: Gap.sm),
          _StageRow(
            label: steps[i].label,
            state: i < reached
                ? _StepState.done
                : i == reached
                ? _StepState.running
                : _StepState.pending,
          ),
        ],
        const SizedBox(height: Gap.lg),
        Text(
          'Files you have already saved are not affected.',
          style: AppTypography.caption.copyWith(color: palette.textTertiary),
        ),
      ],
    );
  }

  Widget _outcome(BuildContext context, ResetReport report) {
    final palette = context.colors;

    return Column(
      key: const ValueKey<String>('outcome'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _pop,
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.successSoft,
            ),
            child: Icon(Icons.check_rounded, size: 32, color: palette.success),
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Everything has been reset.',
          textAlign: TextAlign.center,
          style: AppTypography.title.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          _summarise(report),
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: Gap.lg),
        HozaButton(
          label: 'Done',
          icon: Icons.arrow_forward_rounded,
          onPressed: _finish,
        ),
      ],
    );
  }

  /// Says what was actually removed. A reset that only claims to have worked
  /// is the thing this feature exists not to be.
  static String _summarise(ResetReport report) {
    const tail =
        'Hoza Download will start again as if it were new, and the files you '
        'had already saved are untouched.';

    if (report.records == 0 &&
        report.preferences == 0 &&
        report.partials == 0) {
      return 'There was nothing left to remove. $tail';
    }

    final parts = [
      _count(report.records, 'download', 'downloads'),
      _count(report.preferences, 'preference', 'preferences'),
      _count(report.partials, 'cached chunk', 'cached chunks'),
    ];
    return '${parts.join(', ')} removed. $tail';
  }

  static String _count(int value, String one, String many) =>
      '$value ${value == 1 ? one : many}';
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Row(
      children: [
        SizedBox.square(
          dimension: 20,
          child: Center(
            child: AnimatedSwitcher(
              duration: context.motion(Motion.fast),
              switchInCurve: Motion.springy,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: switch (state) {
                _StepState.pending => Icon(
                  Icons.circle_outlined,
                  key: const ValueKey<String>('pending'),
                  size: 15,
                  color: palette.borderStrong,
                ),
                _StepState.running => SizedBox.square(
                  key: const ValueKey<String>('running'),
                  dimension: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
                _StepState.done => Icon(
                  Icons.check_circle_rounded,
                  key: const ValueKey<String>('done'),
                  size: 18,
                  color: palette.success,
                ),
              },
            ),
          ),
        ),
        const SizedBox(width: Gap.sm),
        AnimatedDefaultTextStyle(
          duration: context.motion(Motion.base),
          curve: Motion.standard,
          style: AppTypography.body.copyWith(
            color: state == _StepState.pending
                ? palette.textTertiary
                : palette.textPrimary,
          ),
          child: Text(label),
        ),
      ],
    );
  }
}
