/// A single ledger entry. Mirrors the JSON shape used by the web app
/// (`data.txns`) byte-for-byte so both apps can share the same Gist.
class Txn {
  final int id;
  final String date; // 'YYYY-MM-DD'
  final String desc;
  final String acct; // 'Revolut' | 'Wise' | 'Swile' | '—'
  final double out;
  final double in_;
  final String notes;
  final String style; // normal|opening|salary|critical|fixed|warning|adjustment
  final bool recurring;
  final bool warning;
  final bool cleared;
  final bool locked;
  final String cat;

  // Flutter-only fields (not part of the web app's schema — harmlessly
  // ignored there, same as `skipRecurring`). Both drive Fluxo's day-level
  // attention ordering: a transaction the user typed in through "+" sorts
  // ahead of one that showed up some other way (recurring generation,
  // import, ...) among still-pending rows; `settledAt` is when it was last
  // marked cleared or locked, so the most recently resolved row floats to
  // the top of the settled ones instead of them all looking equally old.
  final bool addedManually;
  final int? settledAt;

  const Txn({
    required this.id,
    required this.date,
    required this.desc,
    required this.acct,
    required this.out,
    required this.in_,
    this.notes = '',
    this.style = 'normal',
    this.recurring = false,
    this.warning = false,
    this.cleared = false,
    this.locked = false,
    this.cat = '',
    this.addedManually = false,
    this.settledAt,
  });

  double get net => in_ - out;

  Txn copyWith({
    int? id,
    String? date,
    String? desc,
    String? acct,
    double? out,
    double? in_,
    String? notes,
    String? style,
    bool? recurring,
    bool? warning,
    bool? cleared,
    bool? locked,
    String? cat,
    bool? addedManually,
    int? settledAt,
    // `settledAt` is nullable, so the usual `param ?? this.field` pattern
    // can't express "clear it back to null" (toggling a txn back to
    // uncleared). Pass this instead of `settledAt` to force it to null.
    bool clearSettledAt = false,
  }) {
    return Txn(
      id: id ?? this.id,
      date: date ?? this.date,
      desc: desc ?? this.desc,
      acct: acct ?? this.acct,
      out: out ?? this.out,
      in_: in_ ?? this.in_,
      notes: notes ?? this.notes,
      style: style ?? this.style,
      recurring: recurring ?? this.recurring,
      warning: warning ?? this.warning,
      cleared: cleared ?? this.cleared,
      locked: locked ?? this.locked,
      cat: cat ?? this.cat,
      addedManually: addedManually ?? this.addedManually,
      settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
    );
  }

  factory Txn.fromJson(Map<String, dynamic> j) {
    return Txn(
      id: (j['id'] as num).toInt(),
      date: j['date'] as String? ?? '',
      desc: j['desc'] as String? ?? '',
      acct: j['acct'] as String? ?? '—',
      out: ((j['out'] as num?) ?? 0).toDouble(),
      // The web app's field is literally named `in_` (with the trailing
      // underscore) in its own JS objects — `in` is a reserved word there,
      // so that's what actually gets serialized to the Gist. Do not
      // "clean this up" to 'in': that would desync from the real data.
      in_: ((j['in_'] as num?) ?? 0).toDouble(),
      notes: j['notes'] as String? ?? '',
      style: j['style'] as String? ?? 'normal',
      recurring: j['recurring'] as bool? ?? false,
      warning: j['warning'] as bool? ?? false,
      cleared: j['cleared'] as bool? ?? false,
      locked: j['locked'] as bool? ?? false,
      cat: j['cat'] as String? ?? '',
      addedManually: j['addedManually'] as bool? ?? false,
      settledAt: (j['settledAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'desc': desc,
      'acct': acct,
      'out': out,
      'in_': in_,
      'notes': notes,
      'style': style,
      'recurring': recurring,
      'warning': warning,
      'cleared': cleared,
      'locked': locked,
      'cat': cat,
      'addedManually': addedManually,
      'settledAt': settledAt,
    };
  }
}
