import 'package:flutter/material.dart';

import '../data/categories.dart';

/// Bottom sheet listing every category grouped by section. Returns the
/// selected category name (with emoji) via [Navigator.pop], or null if
/// dismissed.
class CategoryPickerSheet extends StatelessWidget {
  const CategoryPickerSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CategoryPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final group in kCategoryGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  group.group,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: group.color,
                    fontSize: 13,
                  ),
                ),
              ),
              for (final cat in group.cats)
                ListTile(
                  title: Text(cat),
                  onTap: () => Navigator.of(context).pop(cat),
                ),
            ],
          ],
        );
      },
    );
  }
}
