import 'package:flutter/material.dart';

class CategoryGroup {
  final String group;
  final List<String> cats;
  final Color color;

  const CategoryGroup(
      {required this.group, required this.cats, required this.color});
}

/// Category taxonomy + per-group accent colors. Order matters: colors are
/// matched to groups by index, same as the web app.
const List<CategoryGroup> kCategoryGroups = [
  CategoryGroup(
    group: 'Personal Budgets',
    cats: ['💁🏻‍♂️ Nando', '💁🏼‍♀️ Thati'],
    color: Color(0xFF5B6DCD),
  ),
  CategoryGroup(
    group: 'Alimentation',
    cats: ['🍕 Uber Eats & Restos', '🛒 Courses & Marché', '🥐 Boulangerie'],
    color: Color(0xFF56C05A),
  ),
  CategoryGroup(
    group: 'Dépenses fixes',
    cats: [
      '💸 Bail',
      '🎒 Open Sky',
      '🏫 École Thiers',
      '💡 Électricité',
      '📱 Forfaits Mobile',
      '💻 Abonnements',
      '🙏 Dons',
    ],
    color: Color(0xFFF5B731),
  ),
  CategoryGroup(
    group: 'Mobilité',
    cats: ['🚇 RATP', '🚖 Uber'],
    color: Color(0xFFCF5E59),
  ),
  CategoryGroup(
    group: 'Santé',
    cats: ['🩺 Médecins & Pharmacie', '💈 Auto soin'],
    color: Color(0xFF8E93D6),
  ),
  CategoryGroup(
    group: 'Maison',
    cats: ['🪛 Entretien & Fournitures', '🏦 Frais & Admin'],
    color: Color(0xFF26C6DA),
  ),
  CategoryGroup(
    group: 'Enfants',
    cats: ['👭 Sá & Sô', '🧣 Vêtements'],
    color: Color(0xFFFF7043),
  ),
  CategoryGroup(
    group: 'Qualité de Vie',
    cats: [
      '🧑‍🧑‍🧒‍🧒 Sortie Famille',
      '👩🏼‍❤️‍💋‍👨🏻 Dates',
      '🥳 Fêtes & Cadeaux'
    ],
    color: Color(0xFF78909C),
  ),
  CategoryGroup(
    group: 'Prévoyance',
    cats: [
      '🏝️ Vacances',
      '🛋️ Équipement Maison',
      '💼 Voyage Travail',
      '🔄 Transfert de Devises'
    ],
    color: Color(0xFF8D6E63),
  ),
];

/// Flat list of all category names, in group order.
List<String> get kAllCategories =>
    kCategoryGroups.expand((g) => g.cats).toList(growable: false);

Color colorForCategory(String cat) {
  for (final g in kCategoryGroups) {
    if (g.cats.contains(cat)) return g.color;
  }
  return const Color(0xFF9E9E9E);
}

String? groupForCategory(String cat) {
  for (final g in kCategoryGroups) {
    if (g.cats.contains(cat)) return g.group;
  }
  return null;
}

const List<String> kAccounts = ['Revolut', 'Wise', 'Swile'];
const String kNoAccount = '—';
