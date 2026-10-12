import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/varna_colors.dart';
import '../../../sync/logic/sync_status.dart';
import 'card_saver.dart';
import 'ui_kit.dart';

/// Leaves the current screen: pops it, or goes to the notebooks home when
/// there is nothing to pop (for example after a deep link).
void leaveScreen(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

/// Leaves through a [router] that was captured *before* an await, so it also
/// works when the screen itself is already gone (for example after the card
/// it showed was deleted).
void leaveWithRouter(GoRouter router) {
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/');
  }
}

/// One entry of the card "..." menu.
class CardMenuAction {
  const CardMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

/// Page frame for card editors: full-screen background tinted with the card
/// colour, a header (back button, save status, options menu), scrollable
/// [content] and an optional [footer] pinned to the bottom. Everything is
/// centred in a column of at most [kContentMaxWidth]. On very short viewports
/// (for example landscape with the keyboard open) the footer scrolls with the
/// content instead of being pinned, so nothing overflows.
///
/// The widget tree above [content] is the same at every height: only the
/// footer moves. That keeps the text fields (and their focus) alive while the
/// keyboard opens and closes.
class TintedCardScaffold extends StatelessWidget {
  const TintedCardScaffold({
    super.key,
    required this.tint,
    required this.onBack,
    required this.content,
    this.footer,
    this.status,
    this.destinationLabel,
    this.updatedAt,
    this.favourite = false,
    this.onToggleFavourite,
    this.onDelete,
    this.extraActions = const <CardMenuAction>[],
    this.backIcon = Icons.arrow_back,
    this.backTooltip = 'Back',
  });

  final Color tint;
  final VoidCallback onBack;
  final Widget content;
  final Widget? footer;

  /// Save progress; null hides the indicator.
  final ValueNotifier<SaveStatus>? status;

  /// Where the card is kept, for the status text ("Google Drive"); null means
  /// only on this phone.
  final String? destinationLabel;

  /// When the card was last changed; used to tell whether the last
  /// successful sync already includes it.
  final DateTime? updatedAt;
  final bool favourite;
  final VoidCallback? onToggleFavourite;
  final VoidCallback? onDelete;
  final List<CardMenuAction> extraActions;
  final IconData backIcon;
  final String backTooltip;

  static const double _gutter = 20;

  @override
  Widget build(BuildContext context) {
    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 0),
      child: Row(
        children: <Widget>[
          RoundIconButton(
            icon: backIcon,
            tooltip: backTooltip,
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: status == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerRight,
                    child: SaveIndicator(
                      status: status!,
                      destinationLabel: destinationLabel,
                      cardUpdatedAt: updatedAt,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          CardOptionsMenu(
            favourite: favourite,
            onToggleFavourite: onToggleFavourite,
            onDelete: onDelete,
            extraActions: extraActions,
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: tint,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                // Only the footer's place depends on the height.
                final bool footerInline = box.maxHeight < 440;
                final Widget? footerWidget = footer;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    header,
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(
                          _gutter,
                          0,
                          _gutter,
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            content,
                            if (footerInline && footerWidget != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: footerWidget,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (!footerInline && footerWidget != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _gutter,
                          0,
                          _gutter,
                          16,
                        ),
                        child: footerWidget,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// "Saved" / "Saving..." / "Not saved" next to a small cloud icon.
///
/// A saved card says "Saved on this device" until the last successful sync
/// (when a cloud is connected) is newer than the card; only then does it say
/// "Saved to" plus the cloud name.
class SaveIndicator extends ConsumerWidget {
  const SaveIndicator({
    super.key,
    required this.status,
    this.destinationLabel,
    this.cardUpdatedAt,
  });

  final ValueListenable<SaveStatus> status;
  final String? destinationLabel;
  final DateTime? cardUpdatedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? destination = destinationLabel;
    final DateTime? edited = cardUpdatedAt;
    bool inCloud = false;
    if (destination != null && edited != null) {
      final SyncStatus? sync = ref.watch(syncStatusProvider).valueOrNull;
      inCloud = sync is SyncSynced && !sync.at.isBefore(edited);
    }
    return ValueListenableBuilder<SaveStatus>(
      valueListenable: status,
      builder: (BuildContext context, SaveStatus value, Widget? _) {
        final String text;
        final IconData icon;
        switch (value) {
          case SaveStatus.saved:
            text = inCloud ? 'Saved to $destination' : 'Saved on this device';
            icon = inCloud ? Icons.cloud_done_outlined : Icons.check_circle_outline;
          case SaveStatus.saving:
            text = 'Saving...';
            icon = Icons.cloud_upload_outlined;
          case SaveStatus.failed:
            text = 'Not saved';
            icon = Icons.error_outline;
        }
        return Semantics(
          liveRegion: true,
          label: text,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(context, 13, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The round "..." button and its menu: card specific [extraActions] first,
/// then favourite and delete.
class CardOptionsMenu extends StatelessWidget {
  const CardOptionsMenu({
    super.key,
    required this.favourite,
    this.onToggleFavourite,
    this.onDelete,
    this.extraActions = const <CardMenuAction>[],
  });

  final bool favourite;
  final VoidCallback? onToggleFavourite;
  final VoidCallback? onDelete;
  final List<CardMenuAction> extraActions;

  static const int _favouriteValue = -1;
  static const int _deleteValue = -2;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    PopupMenuItem<int> item(int value, IconData icon, String label,
        {Color? color}) {
      return PopupMenuItem<int>(
        value: value,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: color ?? colors.ink),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: bodyStyle(context, 15,
                    weight: FontWeight.w600, color: color ?? colors.ink),
              ),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<int>(
      tooltip: 'Card options',
      position: PopupMenuPosition.under,
      onSelected: (int value) {
        if (value == _favouriteValue) {
          onToggleFavourite?.call();
        } else if (value == _deleteValue) {
          onDelete?.call();
        } else if (value >= 0 && value < extraActions.length) {
          extraActions[value].onSelected();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        for (int i = 0; i < extraActions.length; i++)
          item(i, extraActions[i].icon, extraActions[i].label),
        if (onToggleFavourite != null)
          item(
            _favouriteValue,
            favourite ? Icons.star : Icons.star_border,
            favourite ? 'Remove from favourites' : 'Add to favourites',
          ),
        if (onDelete != null)
          item(
            _deleteValue,
            Icons.delete_outline,
            'Delete card',
            color: colors.danger,
          ),
      ],
      child: SizedBox(
        width: 44,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: frostedWhite(),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.more_horiz, color: colors.ink),
        ),
      ),
    );
  }
}
