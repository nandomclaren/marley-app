import 'goal.dart';
import 'transaction.dart';

class Balances {
  final double rev;
  final double wise;
  final double swile;

  const Balances({this.rev = 0, this.wise = 0, this.swile = 0});

  Balances copyWith({double? rev, double? wise, double? swile}) {
    return Balances(
      rev: rev ?? this.rev,
      wise: wise ?? this.wise,
      swile: swile ?? this.swile,
    );
  }

  factory Balances.fromJson(Map<String, dynamic> j) {
    return Balances(
      rev: ((j['rev'] as num?) ?? 0).toDouble(),
      wise: ((j['wise'] as num?) ?? 0).toDouble(),
      swile: ((j['swile'] as num?) ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'rev': rev, 'wise': wise, 'swile': swile};
}

/// The full app data blob, persisted locally and synced via Gist as a single
/// JSON document. Structure must stay byte-compatible with the web app.
class AppData {
  final int lastModified;
  final List<String> months; // 'YYYY-MM', ascending
  final Balances balances;
  final List<Txn> txns;
  final Map<String, Map<String, double>> budgets; // month -> cat -> amount
  final Map<String, Goal> goals; // cat -> goal

  // month -> list of transaction descriptions the user explicitly deleted
  // from that month, so `autoGenerateRecurringTxns` doesn't keep bringing
  // them back. Mirrors the web app's `data.skipRecurring` (added lazily
  // there too — absent entirely on data predating this feature).
  final Map<String, List<String>> skipRecurring;

  const AppData({
    required this.lastModified,
    required this.months,
    required this.balances,
    required this.txns,
    required this.budgets,
    required this.goals,
    this.skipRecurring = const {},
  });

  factory AppData.empty() {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    return AppData(
      lastModified: 0,
      months: [month],
      balances: const Balances(),
      txns: const [],
      budgets: {month: {}},
      goals: const {},
    );
  }

  AppData copyWith({
    int? lastModified,
    List<String>? months,
    Balances? balances,
    List<Txn>? txns,
    Map<String, Map<String, double>>? budgets,
    Map<String, Goal>? goals,
    Map<String, List<String>>? skipRecurring,
  }) {
    return AppData(
      lastModified: lastModified ?? this.lastModified,
      months: months ?? this.months,
      balances: balances ?? this.balances,
      txns: txns ?? this.txns,
      budgets: budgets ?? this.budgets,
      goals: goals ?? this.goals,
      skipRecurring: skipRecurring ?? this.skipRecurring,
    );
  }

  factory AppData.fromJson(Map<String, dynamic> j) {
    final budgetsRaw = (j['budgets'] as Map<String, dynamic>? ?? {});
    final budgets = <String, Map<String, double>>{};
    budgetsRaw.forEach((month, catsRaw) {
      final cats = <String, double>{};
      (catsRaw as Map<String, dynamic>? ?? {}).forEach((cat, v) {
        cats[cat] = ((v as num?) ?? 0).toDouble();
      });
      budgets[month] = cats;
    });

    final goalsRaw = (j['goals'] as Map<String, dynamic>? ?? {});
    final goals = <String, Goal>{};
    goalsRaw.forEach((cat, v) {
      goals[cat] = Goal.fromJson(v as Map<String, dynamic>);
    });

    final skipRaw = (j['skipRecurring'] as Map<String, dynamic>? ?? {});
    final skipRecurring = <String, List<String>>{};
    skipRaw.forEach((month, descs) {
      skipRecurring[month] =
          ((descs as List<dynamic>?) ?? []).map((e) => e as String).toList();
    });

    return AppData(
      lastModified: (j['_lastModified'] as num?)?.toInt() ?? 0,
      months: ((j['months'] as List<dynamic>?) ?? [])
          .map((e) => e as String)
          .toList(),
      balances: Balances.fromJson(j['balances'] as Map<String, dynamic>? ?? {}),
      txns: ((j['txns'] as List<dynamic>?) ?? [])
          .map((e) => Txn.fromJson(e as Map<String, dynamic>))
          .toList(),
      budgets: budgets,
      goals: goals,
      skipRecurring: skipRecurring,
    );
  }

  Map<String, dynamic> toJson() {
    final budgetsJson = <String, dynamic>{};
    budgets.forEach((month, cats) => budgetsJson[month] = cats);

    final goalsJson = <String, dynamic>{};
    goals.forEach((cat, g) => goalsJson[cat] = g.toJson());

    final skipRecurringJson = <String, dynamic>{};
    skipRecurring.forEach((month, descs) => skipRecurringJson[month] = descs);

    return {
      '_lastModified': lastModified,
      'months': months,
      'balances': balances.toJson(),
      'txns': txns.map((t) => t.toJson()).toList(),
      'budgets': budgetsJson,
      'goals': goalsJson,
      'skipRecurring': skipRecurringJson,
    };
  }
}
