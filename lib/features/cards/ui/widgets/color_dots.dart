import 'package:flutter/material.dart';

import '../../../../core/theme/varna_colors.dart';

const List<String> _colourNames = <String>[
  'Yellow',
  'Blue',
  'Green',
  'Coral',
  'Lilac',
];

/// The row of five card-colour dots from the design (44dp touch targets).
String _nameOf(int i) =>
    i < _colourNames.length ? _colourNames[i] : 'Colour ${i + 1}';

class CardColorDots extends StatelessWidget {
  const CardColorDots({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final int count = colors.cardColors.length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: '${_nameOf(i)} colour',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onSelected(i),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.cardColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: i == selected ? colors.ink : Colors.white,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
