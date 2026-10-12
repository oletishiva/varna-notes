import 'package:flutter/material.dart';

import '../../../../core/theme/varna_colors.dart';
import 'ui_kit.dart';

/// The big editable card title (Bricolage Grotesque 32).
class CardTitleField extends StatelessWidget {
  const CardTitleField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.hintText = 'Title',
    this.onSubmitted,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final TextStyle style = displayStyle(context, 32).copyWith(
      color: colors.ink,
      height: 1.08,
    );
    return Semantics(
      textField: true,
      label: 'Title',
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        style: style,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        cursorColor: colors.ink,
        decoration: InputDecoration.collapsed(
          hintText: hintText,
          hintStyle: style.copyWith(color: colors.ink.withValues(alpha: 0.35)),
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}
