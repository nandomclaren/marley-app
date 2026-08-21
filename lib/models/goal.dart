/// A savings/budget goal attached to a category. Mirrors `data.goals[catName]`.
class Goal {
  final String type; // 'target_date' | 'monthly'
  final double target;
  final String? targetDate; // 'YYYY-MM-DD', only for target_date goals
  final double? monthlyContrib; // only for target_date goals

  const Goal({
    required this.type,
    required this.target,
    this.targetDate,
    this.monthlyContrib,
  });

  factory Goal.fromJson(Map<String, dynamic> j) {
    return Goal(
      type: j['type'] as String? ?? 'monthly',
      target: ((j['target'] as num?) ?? 0).toDouble(),
      targetDate: j['targetDate'] as String?,
      monthlyContrib: (j['monthlyContrib'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'target': target,
      if (targetDate != null) 'targetDate': targetDate,
      if (monthlyContrib != null) 'monthlyContrib': monthlyContrib,
    };
  }
}
