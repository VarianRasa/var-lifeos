/// Flashcard Deck Review Dialog with 3D Flip Card animation and SM-2 feedback buttons.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/mindmap_mutation_controller.dart';
import '../domain/mindmap_node.dart';
import '../domain/spaced_repetition.dart';

class FlashcardReviewDialog extends ConsumerStatefulWidget {
  const FlashcardReviewDialog({super.key, required this.cards});

  final List<MindmapNode> cards;

  static Future<void> show(BuildContext context, List<MindmapNode> cards) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => FlashcardReviewDialog(cards: cards),
    );
  }

  @override
  ConsumerState<FlashcardReviewDialog> createState() =>
      _FlashcardReviewDialogState();
}

class _FlashcardReviewDialogState extends ConsumerState<FlashcardReviewDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  int _currentIndex = 0;
  bool _isFlipped = false;
  int _reviewedCount = 0;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  Future<void> _answerCard(FlashcardRating rating) async {
    if (_currentIndex >= widget.cards.length) return;

    final currentCard = widget.cards[_currentIndex];
    final currentState = getFlashcardState(currentCard);
    final nextState = currentState.answer(rating);
    final updatedNode = updateFlashcardState(currentCard, nextState);

    await ref.read(mindmapMutationControllerProvider).saveNode(updatedNode);

    setState(() {
      _reviewedCount++;
      if (_isFlipped) {
        _isFlipped = false;
        _flipController.reset();
      }
      _currentIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = _currentIndex >= widget.cards.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: isDone
            ? _buildCompletionView(context)
            : _buildReviewView(context),
      ),
    );
  }

  Widget _buildReviewView(BuildContext context) {
    final theme = Theme.of(context);
    final card = widget.cards[_currentIndex];
    final cardState = getFlashcardState(card);

    final frontText = card.title.isNotEmpty
        ? card.title
        : 'Flashcard #${_currentIndex + 1}';
    final rawBack = card.data['answer'] ?? card.data['back'];
    final backText = rawBack is String && rawBack.isNotEmpty
        ? rawBack
        : (card.tags.isNotEmpty
              ? 'Tags: ${card.tags.join(', ')}'
              : 'No detailed answer provided.');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Spaced Repetition Deck',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (_currentIndex + 1) / widget.cards.length,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Card ${_currentIndex + 1} of ${widget.cards.length}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Interval: ${cardState.intervalDays}d | Ease: ${cardState.easeFactor.toStringAsFixed(2)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GestureDetector(
            onTap: _flipCard,
            child: AnimatedBuilder(
              animation: _flipAnimation,
              builder: (context, child) {
                final angle = _flipAnimation.value * math.pi;
                final isBackVisible = angle >= math.pi / 2;

                return Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(angle),
                  alignment: Alignment.center,
                  child: isBackVisible
                      ? Transform(
                          transform: Matrix4.identity()..rotateY(math.pi),
                          alignment: Alignment.center,
                          child: _buildCardFace(
                            context,
                            title: 'ANSWER',
                            content: backText,
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.3),
                            badgeColor: theme.colorScheme.primary,
                          ),
                        )
                      : _buildCardFace(
                          context,
                          title: 'QUESTION',
                          content: frontText,
                          color: theme.colorScheme.surfaceContainerHigh,
                          badgeColor: theme.colorScheme.tertiary,
                        ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_isFlipped)
          ElevatedButton.icon(
            onPressed: _flipCard,
            icon: const Icon(Icons.flip),
            label: const Text('Show Answer'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: _buildRatingButton(
                  context,
                  rating: FlashcardRating.blackout,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRatingButton(
                  context,
                  rating: FlashcardRating.incorrect,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRatingButton(
                  context,
                  rating: FlashcardRating.correctDifficult,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRatingButton(
                  context,
                  rating: FlashcardRating.perfect,
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCardFace(
    BuildContext context, {
    required String title,
    required String content,
    required Color color,
    required Color badgeColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  content,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
                ),
              ),
            ),
          ),
          Text(
            'Tap card to flip',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingButton(
    BuildContext context, {
    required FlashcardRating rating,
    required Color color,
  }) {
    return InkWell(
      onTap: () => _answerCard(rating),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(
              rating.label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${rating.score}',
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
        const SizedBox(height: 16),
        Text(
          'Deck Review Complete!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You reviewed $_reviewedCount flashcards and earned +${_reviewedCount * 5} XP!',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Life OS'),
        ),
      ],
    );
  }
}
