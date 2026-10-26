import 'package:flutter/material.dart';

/// Five tappable stars (1–5). [value] 0 means nothing chosen yet.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 44,
    this.semanticLabel,
  });

  final int value;

  /// Null makes the stars read-only.
  final ValueChanged<int>? onChanged;
  final double size;

  /// Builds the accessibility label for star [n], e.g. `(n) => '$n stars'`.
  final String Function(int n)? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var n = 1; n <= 5; n++)
          Semantics(
            button: onChanged != null,
            selected: n <= value,
            label: semanticLabel?.call(n),
            child: IconButton(
              key: Key('star-$n'),
              iconSize: size,
              onPressed: onChanged == null ? null : () => onChanged!(n),
              icon: Icon(
                n <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                color: n <= value ? Colors.amber.shade600 : scheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

/// One line of a fare breakdown: label left, amount right.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasis = false,
    this.muted = false,
  });

  final String label;
  final String amount;

  /// Bold total line.
  final bool emphasis;

  /// Secondary (e.g. "incl. GST") line.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = emphasis
        ? text.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : muted
            ? text.bodySmall
            : text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(amount, style: style),
        ],
      ),
    );
  }
}
