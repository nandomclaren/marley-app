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
    };
  }
}
