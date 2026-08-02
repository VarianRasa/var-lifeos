import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../mindmap/application/focus_timer_provider.dart';

class PomodoroTimerDial extends StatelessWidget {
  const PomodoroTimerDial({
    required this.timerState,
    required this.onStartPause,
    required this.onSkip,
    required this.onReset,
    super.key,
  });

  final FocusTimerState timerState;
  final VoidCallback onStartPause;
  final VoidCallback onSkip;
  final VoidCallback onReset;

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isFocusPhase = timerState.phase == FocusTimerPhase.focus;
    final phaseColor = isFocusPhase
        ? semantic.accent
        : (timerState.phase == FocusTimerPhase.shortBreak
              ? semantic.info
              : semantic.warning);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(240, 240),
                painter: _TimerDialPainter(
                  progress: timerState.progress,
                  color: phaseColor,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: phaseColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      timerState.phase.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: phaseColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatTime(timerState.remainingSeconds),
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sesi ${timerState.completedSessionsCount + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              iconSize: 24,
              tooltip: 'Reset',
              icon: const Icon(Icons.replay),
              onPressed: onReset,
            ),
            const SizedBox(width: 16),
            IconButton.filled(
              iconSize: 36,
              tooltip: timerState.isRunning ? 'Pause' : 'Start',
              icon: Icon(timerState.isRunning ? Icons.pause : Icons.play_arrow),
              onPressed: onStartPause,
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              iconSize: 24,
              tooltip: 'Skip',
              icon: const Icon(Icons.skip_next),
              onPressed: onSkip,
            ),
          ],
        ),
      ],
    );
  }
}

class _TimerDialPainter extends CustomPainter {
  _TimerDialPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TimerDialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
