/// User Gamification domain model for Life OS (XP, Leveling, Streaks & Badges).
library;

import 'dart:math' as math;

/// Available badge achievements.
enum LifeOsBadge {
  firstStep('first_step', 'First Step', 'Completed 1st task', '🎯'),
  taskMaster('task_master', 'Task Master', 'Completed 25 tasks', '⚔️'),
  streakMaster('streak_master', 'Streak Master', '7-day habit streak', '🔥'),
  focusHero('focus_hero', 'Focus Hero', 'Accumulated 5 hours focus', '⏱️'),
  cardScholar('card_scholar', 'Card Scholar', 'Reviewed 30 flashcards', '🧠'),
  lifePlanner('life_planner', 'Life Planner', 'Used auto time-blocking', '⚡');

  const LifeOsBadge(this.id, this.title, this.description, this.emoji);
  final String id;
  final String title;
  final String description;
  final String emoji;

  static LifeOsBadge? fromId(String id) {
    for (final b in values) {
      if (b.id == id) return b;
    }
    return null;
  }
}

/// XP rewards config for actions.
class XpRewards {
  const XpRewards._();

  static const int taskCompleted = 10;
  static const int habitCompleted = 15;
  static const int flashcardReviewed = 5;
  static const int focusMinuteCompleted = 1;
  static const int dailyReviewDone = 30;
  static const int autoTimeBlockUsed = 20;
}

/// Immutable user gamification stats.
final class UserGamificationStats {
  const UserGamificationStats({
    required this.totalXp,
    required this.unlockedBadgeIds,
    required this.tasksCompletedCount,
    required this.habitsCompletedCount,
    required this.flashcardsReviewedCount,
    required this.focusMinutesCount,
    required this.lastXpEarnedAt,
  });

  factory UserGamificationStats.initial() {
    return const UserGamificationStats(
      totalXp: 0,
      unlockedBadgeIds: [],
      tasksCompletedCount: 0,
      habitsCompletedCount: 0,
      flashcardsReviewedCount: 0,
      focusMinutesCount: 0,
      lastXpEarnedAt: null,
    );
  }

  factory UserGamificationStats.fromJson(Map<String, Object?> json) {
    return UserGamificationStats(
      totalXp: (json['totalXp'] as num?)?.toInt() ?? 0,
      unlockedBadgeIds: [
        if (json['unlockedBadgeIds'] is List)
          for (final id in json['unlockedBadgeIds'] as List)
            if (id is String) id,
      ],
      tasksCompletedCount: (json['tasksCompletedCount'] as num?)?.toInt() ?? 0,
      habitsCompletedCount:
          (json['habitsCompletedCount'] as num?)?.toInt() ?? 0,
      flashcardsReviewedCount:
          (json['flashcardsReviewedCount'] as num?)?.toInt() ?? 0,
      focusMinutesCount: (json['focusMinutesCount'] as num?)?.toInt() ?? 0,
      lastXpEarnedAt: DateTime.tryParse(
        json['lastXpEarnedAt'] as String? ?? '',
      ),
    );
  }

  final int totalXp;
  final List<String> unlockedBadgeIds;
  final int tasksCompletedCount;
  final int habitsCompletedCount;
  final int flashcardsReviewedCount;
  final int focusMinutesCount;
  final DateTime? lastXpEarnedAt;

  Map<String, Object?> toJson() {
    return {
      'totalXp': totalXp,
      'unlockedBadgeIds': unlockedBadgeIds,
      'tasksCompletedCount': tasksCompletedCount,
      'habitsCompletedCount': habitsCompletedCount,
      'flashcardsReviewedCount': flashcardsReviewedCount,
      'focusMinutesCount': focusMinutesCount,
      if (lastXpEarnedAt != null)
        'lastXpEarnedAt': lastXpEarnedAt!.toIso8601String(),
    };
  }

  /// Calculates user level: Level = floor(sqrt(XP / 50)) + 1
  int get level => math.max(1, (math.sqrt(totalXp / 50.0)).floor() + 1);

  /// XP required to reach start of current level.
  int get currentLevelBaseXp {
    final lvl = level;
    return (lvl - 1) * (lvl - 1) * 50;
  }

  /// XP required to reach next level.
  int get nextLevelTargetXp {
    final lvl = level;
    return lvl * lvl * 50;
  }

  /// Level progress ratio (0.0 to 1.0).
  double get levelProgress {
    final base = currentLevelBaseXp;
    final target = nextLevelTargetXp;
    if (target == base) return 1.0;
    return ((totalXp - base) / (target - base)).clamp(0.0, 1.0);
  }

  List<LifeOsBadge> get unlockedBadges {
    return unlockedBadgeIds
        .map(LifeOsBadge.fromId)
        .whereType<LifeOsBadge>()
        .toList();
  }

  UserGamificationStats addXp(int xpGained, {DateTime? now}) {
    if (xpGained <= 0) return this;
    final nextStats = copyWith(
      totalXp: totalXp + xpGained,
      lastXpEarnedAt: now ?? DateTime.now(),
    );
    return nextStats._checkBadges();
  }

  UserGamificationStats recordTaskCompletion({DateTime? now}) {
    final nextTasks = tasksCompletedCount + 1;
    final next = copyWith(
      totalXp: totalXp + XpRewards.taskCompleted,
      tasksCompletedCount: nextTasks,
      lastXpEarnedAt: now ?? DateTime.now(),
    );
    return next._checkBadges();
  }

  UserGamificationStats recordHabitCompletion({DateTime? now}) {
    final nextHabits = habitsCompletedCount + 1;
    final next = copyWith(
      totalXp: totalXp + XpRewards.habitCompleted,
      habitsCompletedCount: nextHabits,
      lastXpEarnedAt: now ?? DateTime.now(),
    );
    return next._checkBadges();
  }

  UserGamificationStats recordFlashcardReview({DateTime? now}) {
    final nextCards = flashcardsReviewedCount + 1;
    final next = copyWith(
      totalXp: totalXp + XpRewards.flashcardReviewed,
      flashcardsReviewedCount: nextCards,
      lastXpEarnedAt: now ?? DateTime.now(),
    );
    return next._checkBadges();
  }

  UserGamificationStats recordFocusMinutes(int minutes, {DateTime? now}) {
    if (minutes <= 0) {
      return this;
    }
    final nextMins = focusMinutesCount + minutes;
    final next = copyWith(
      totalXp: totalXp + (minutes * XpRewards.focusMinuteCompleted),
      focusMinutesCount: nextMins,
      lastXpEarnedAt: now ?? DateTime.now(),
    );
    return next._checkBadges();
  }

  UserGamificationStats _checkBadges() {
    final newBadgeIds = {...unlockedBadgeIds};

    if (tasksCompletedCount >= 1) newBadgeIds.add(LifeOsBadge.firstStep.id);
    if (tasksCompletedCount >= 25) newBadgeIds.add(LifeOsBadge.taskMaster.id);
    if (habitsCompletedCount >= 7) newBadgeIds.add(LifeOsBadge.streakMaster.id);
    if (focusMinutesCount >= 300) newBadgeIds.add(LifeOsBadge.focusHero.id);
    if (flashcardsReviewedCount >= 30) {
      newBadgeIds.add(LifeOsBadge.cardScholar.id);
    }

    return copyWith(unlockedBadgeIds: newBadgeIds.toList());
  }

  UserGamificationStats copyWith({
    int? totalXp,
    List<String>? unlockedBadgeIds,
    int? tasksCompletedCount,
    int? habitsCompletedCount,
    int? flashcardsReviewedCount,
    int? focusMinutesCount,
    DateTime? lastXpEarnedAt,
  }) {
    return UserGamificationStats(
      totalXp: totalXp ?? this.totalXp,
      unlockedBadgeIds: unlockedBadgeIds ?? this.unlockedBadgeIds,
      tasksCompletedCount: tasksCompletedCount ?? this.tasksCompletedCount,
      habitsCompletedCount: habitsCompletedCount ?? this.habitsCompletedCount,
      flashcardsReviewedCount:
          flashcardsReviewedCount ?? this.flashcardsReviewedCount,
      focusMinutesCount: focusMinutesCount ?? this.focusMinutesCount,
      lastXpEarnedAt: lastXpEarnedAt ?? this.lastXpEarnedAt,
    );
  }
}
