import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class SummaryCardData {
  final String label;
  final double value;
  final String? subtitle;

  /// Always tints the card container red (e.g. "Mínimo do mês" — a
  /// standing warning card, independent of the actual value).
  final bool dangerCard;

  /// Threshold below which the value text itself turns red (matches the
  /// web app's `minVal < 800 ? red : accent` rule); null means no
  /// value-based coloring.
  final double? redBelowThreshold;

  /// Colors the value green when positive, red when negative, and leaves
  /// it neutral near zero — matches the web app's `.pos`/`.neg` classes on
  /// header cards like "A Alocar" and "Total Disponível". Ignored when
  /// [redBelowThreshold] is also set (that takes priority).
  final bool signedColor;

  const SummaryCardData({
    required this.label,
    required this.value,
    this.subtitle,
    this.dangerCard = false,
    this.redBelowThreshold,
    this.signedColor = false,
  });
}

/// A 2x2 grid of stat cards (Início do mês / Saldo Hoje / Projetado fim do
/// mês / Mínimo do mês on Fluxo). Two columns — rather than four crammed
/// into one row — give each amount enough width that real numbers
/// (thousands, negatives) don't get clipped; [FittedBox] is still there as
/// a safety net for anything wider than that.
class SummaryCards extends StatelessWidget {
  final List<SummaryCardData> cards;

  const SummaryCards({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < cards.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: i + 2 < cards.length ? 8 : 0),
              child: Row(
                children: [
                  Expanded(child: StatCard(data: cards[i])),
                  if (i + 1 < cards.length) ...[
                    const SizedBox(width: 8),
                    Expanded(child: StatCard(data: cards[i + 1])),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration(Brightness brightness, {bool dangerCard = false}) {
  return BoxDecoration(
    color: dangerCard
        ? MarleyColors.red(brightness)
            .withValues(alpha: brightness == Brightness.dark ? 0.16 : 0.08)
        : MarleyColors.bgCard(brightness),
    borderRadius: BorderRadius.circular(14),
    border: dangerCard
        ? Border.all(color: MarleyColors.red(brightness).withValues(alpha: 0.4))
        : null,
  );
}

/// A single stat card: label + big value (+ optional subtitle). Used both
/// standalone (e.g. Contas' "Working Balance") and laid out in
/// [SummaryCards]' 2-per-row grid.
class StatCard extends StatelessWidget {
  final SummaryCardData data;
  const StatCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: _cardDecoration(brightness, dangerCard: data.dangerCard),
      child: _CardContent(data: data),
    );
  }
}

/// Same chrome as [StatCard], but swipeable between several
/// [SummaryCardData] "pages" sharing one card slot — e.g. Contas' Cleared
/// and Uncleared, which used to each get their own card (the second one
/// stretching awkwardly across the full row). A small dot indicator at the
/// bottom shows which page is active, Instagram-carousel style.
class SwipeableStatCard extends StatefulWidget {
  final List<SummaryCardData> pages;
  const SwipeableStatCard({super.key, required this.pages});

  @override
  State<SwipeableStatCard> createState() => _SwipeableStatCardState();
}

class _SwipeableStatCardState extends State<SwipeableStatCard> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration:
          _cardDecoration(brightness, dangerCard: widget.pages[_page].dangerCard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 58,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _CardContent(data: widget.pages[i]),
              ),
            ),
          ),
          if (widget.pages.length > 1) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? MarleyColors.accent
                          : MarleyColors.accent.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  final SummaryCardData data;
  const _CardContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final valueColor = data.redBelowThreshold != null
        ? (data.value < data.redBelowThreshold!
            ? MarleyColors.red(brightness)
            : MarleyColors.accent)
        : data.signedColor
            ? (data.value < -0.005
                ? MarleyColors.red(brightness)
                : data.value > 0.005
                    ? MarleyColors.green(brightness)
                    : null)
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.7),
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatEur(data.value),
            maxLines: 1,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: valueColor),
          ),
        ),
        if (data.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            data.subtitle!,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
