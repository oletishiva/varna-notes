import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';

const List<String> _colorNames = <String>['Sun', 'Sky', 'Mint', 'Coral', 'Lilac'];

/// Row of the five card colours; the selected one shows a tick.
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (int i = 0; i < c.cardColors.length; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: '${_colorNames[i % _colorNames.length]} colour',
            child: Material(
              color: c.cardColors[i],
              shape: CircleBorder(
                side: BorderSide(
                  color: i == selected ? c.ink : c.hairline,
                  width: i == selected ? 2.5 : 1,
                ),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onChanged(i),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: i == selected
                      ? Icon(Icons.check_rounded, color: c.ink, size: 22)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
