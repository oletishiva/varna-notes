import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Goes back, or to [fallback] when there is nothing to go back to (for
/// example after opening a deep link).
void goBackOr(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
