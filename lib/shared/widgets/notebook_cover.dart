import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/varna_colors.dart';
import '../format.dart';
import 'tokens.dart';

const BorderRadius _coverRadius = BorderRadius.only(
  topLeft: Radius.circular(8),
  bottomLeft: Radius.circular(8),
  topRight: Radius.circular(20),
  bottomRight: Radius.circular(20),
);

/// A notebook as a book cover: coloured, with a darker spine on the left.
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.notebook,
    required this.cardCount,
    this.onTap,
    this.onLongPress,
    this.minHeight = 150,
  });

  final Notebook notebook;
  final int cardCount;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final String title = notebook.title.trim().isEmpty ? 'Untitled' : notebook.title;
    return Semantics(
      button: true,
      label: notebook.locked ? 'Locked notebook' : 'Notebook',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: _coverRadius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: c.ink.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: c.cardColor(notebook.colorIndex),
          borderRadius: _coverRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.passthrough,
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: ColoredBox(color: c.ink.withValues(alpha: 0.14)),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (notebook.locked) ...<Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.lock_outline_rounded, size: 14, color: c.ink),
                              const SizedBox(width: 6),
                              Text(
                                'Locked',
                                style: bodyStyle(context, 12, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                        Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: displayStyle(context, 21, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pluralize(cardCount, 'card'),
                          style: bodyStyle(context, 13, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
