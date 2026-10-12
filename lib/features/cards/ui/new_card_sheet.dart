import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/usage_limits.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../core/theme/varna_theme.dart';
import '../../../shared/app_state.dart';
import '../../../shared/auth_gate.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_bottom_sheet.dart';
import '../../notebooks/ui/notebook_dialogs.dart';
import '../../plus/ui/upsell_sheet.dart';

/// Shows the "New card" sheet for [notebookId].
Future<void> showNewCardSheet(
  BuildContext context, {
  required String notebookId,
}) async {
  await showVarnaSheet<void>(
    context,
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    builder: (BuildContext sheetContext) => NewCardContent(notebookId: notebookId),
  );
}

/// The centre "+" button: opens the sheet for the notebook used last, or
/// asks the user to create a notebook first.
Future<void> startNewCardFlow(BuildContext context, WidgetRef ref) async {
  List<Notebook> notebooks = ref.read(notebooksProvider).valueOrNull ??
      await ref.read(notesRepositoryProvider).listNotebooks();
  if (!context.mounted) {
    return;
  }
  if (notebooks.isEmpty) {
    final bool? create = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final VarnaColors c = VarnaColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Create a notebook first', style: displayStyle(dialogContext, 22)),
          content: Text(
            'Cards live inside notebooks. Make your first notebook, then add '
            'a card to it.',
            style: bodyStyle(dialogContext, 15),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Create notebook'),
            ),
          ],
        );
      },
    );
    if (create != true || !context.mounted) {
      return;
    }
    final Notebook? created = await createNotebookFlow(context, ref);
    if (created == null || !context.mounted) {
      return;
    }
    notebooks = <Notebook>[created];
  }
  final String? last = ref.read(lastNotebookIdProvider);
  final Notebook target = notebooks.firstWhere(
    (Notebook n) => n.id == last,
    orElse: () => notebooks.first,
  );
  if (target.locked && !ref.read(unlockedNotebooksProvider).contains(target.id)) {
    final bool ok = await authenticateUser(reason: 'Unlock ${target.title}');
    if (!ok || !context.mounted) {
      return;
    }
    ref.read(unlockedNotebooksProvider.notifier).update(
          (Set<String> s) => <String>{...s, target.id},
        );
  }
  if (!context.mounted) {
    return;
  }
  await showNewCardSheet(context, notebookId: target.id);
}

/// `/new-card/:notebookId` as a full page (dark backdrop, sheet at the
/// bottom). Tapping the backdrop closes it.
class NewCardScreen extends StatelessWidget {
  const NewCardScreen({super.key, required this.notebookId});

  final String notebookId;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Scaffold(
      backgroundColor: c.ink,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox.expand(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: VarnaExtras.maxContentWidth),
              child: Material(
                color: c.ground,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(VarnaMetrics.sheetRadius),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: VarnaExtras.handle,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        NewCardContent(notebookId: notebookId),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The body of the new-card sheet: six card types and "Draft with AI".
class NewCardContent extends ConsumerStatefulWidget {
  const NewCardContent({super.key, required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<NewCardContent> createState() => _NewCardContentState();
}

class _NewCardContentState extends ConsumerState<NewCardContent> {
  bool _busy = false;

  /// Closes the sheet/page and opens [location].
  void _finish(NavigatorState nav, GoRouter router, String location) {
    nav.pop();
    unawaited(router.push<void>(location));
  }

  void _fail(ScaffoldMessengerState messenger, String text) {
    messenger.showSnackBar(SnackBar(content: Text(text)));
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _create(CardType type, int colorIndex) async {
    if (_busy) {
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    final GoRouter router = GoRouter.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final NoteCard card = await ref.read(notesRepositoryProvider).createCard(
            notebookId: widget.notebookId,
            type: type,
            colorIndex: colorIndex,
          );
      _finish(nav, router, '/card/${card.id}');
    } catch (_) {
      _fail(messenger, 'Could not create the card. Please try again.');
    }
  }

  void _voice() {
    if (_busy) {
      return;
    }
    _finish(
      Navigator.of(context),
      GoRouter.of(context),
      '/record/${widget.notebookId}',
    );
  }

  Future<void> _scan() async {
    if (_busy) {
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    final GoRouter router = GoRouter.of(context);
    final LimitCheck check = await ref.read(usageLimitsProvider).canScan();
    if (!mounted) {
      return;
    }
    if (!check.allowed) {
      await showUpsellSheet(context, reason: UpsellReason.scanLimit);
      return;
    }
    _finish(nav, router, '/scan/${widget.notebookId}');
  }

  Future<ImageSource?> _chooseSource() {
    return showVarnaSheet<ImageSource>(
      context,
      builder: (BuildContext sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SheetTitle('Add a photo'),
          SheetAction(
            icon: Icons.photo_camera_outlined,
            label: 'Take a photo',
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          SheetAction(
            icon: Icons.photo_library_outlined,
            label: 'Choose from gallery',
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
  }

  Future<void> _photo() async {
    if (_busy) {
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    final GoRouter router = GoRouter.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ImageSource? source =
        kIsWeb ? ImageSource.gallery : await _chooseSource();
    if (source == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (file == null) {
        if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }
      final Uint8List bytes = await file.readAsBytes();
      final String attachmentId = Uuid().v4();
      await ref.read(attachmentStoreProvider).save(attachmentId, bytes);
      final Attachment attachment = Attachment(
        id: attachmentId,
        kind: AttachmentKind.image,
        fileName: file.name.isEmpty ? 'photo.jpg' : file.name,
        byteLength: bytes.length,
      );
      final NoteCard card = await ref.read(notesRepositoryProvider).createCard(
            notebookId: widget.notebookId,
            type: CardType.photo,
            colorIndex: 1,
            attachments: <Attachment>[attachment],
          );
      _finish(nav, router, '/card/${card.id}');
    } catch (_) {
      _fail(messenger, 'Could not add the photo. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final Notebook? notebook = ref.watch(notebookProvider(widget.notebookId)).valueOrNull;
    final bool aiReady = ref.watch(aiServiceProvider).isConfigured;

    Widget row(List<Widget> tiles) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < tiles.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: tiles[i]),
            ],
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text('New card', style: displayStyle(context, 26)),
        ),
        const SizedBox(height: 2),
        Text(
          notebook == null || notebook.title.trim().isEmpty
              ? 'Pick a card type'
              : 'Goes into ${notebook.title}',
          style: bodyStyle(context, 14, color: c.muted),
        ),
        const SizedBox(height: 18),
        row(<Widget>[
          _TypeTile(
            label: 'Text',
            icon: Icons.notes_rounded,
            color: c.cardColor(0),
            onTap: () => unawaited(_create(CardType.text, 0)),
          ),
          _TypeTile(
            label: 'Checklist',
            icon: Icons.checklist_rounded,
            color: c.cardColor(2),
            onTap: () => unawaited(_create(CardType.checklist, 2)),
          ),
          _TypeTile(
            label: 'Voice',
            icon: Icons.mic_none_rounded,
            color: c.cardColor(4),
            onTap: _voice,
          ),
        ]),
        const SizedBox(height: 12),
        row(<Widget>[
          _TypeTile(
            label: 'Photo',
            icon: Icons.photo_camera_outlined,
            color: c.cardColor(1),
            onTap: () => unawaited(_photo()),
          ),
          _TypeTile(
            label: 'Scan',
            icon: Icons.document_scanner_outlined,
            color: c.cardColor(3),
            onTap: () => unawaited(_scan()),
          ),
          _TypeTile(
            label: 'Sketch',
            icon: Icons.draw_outlined,
            color: c.surface,
            badge: 'Soon',
            onTap: null,
          ),
        ]),
        const SizedBox(height: 14),
        _AiTile(
          enabled: aiReady,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('AI drafting arrives in a later update.')),
            );
          },
        ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      hint: badge == null ? null : 'Coming soon',
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(VarnaMetrics.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 104),
              child: Stack(
                fit: StackFit.passthrough,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(icon, size: 28, color: c.ink),
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: bodyStyle(context, 15, weight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (badge != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.ink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge!,
                          style: bodyStyle(
                            context,
                            11,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiTile extends StatelessWidget {
  const _AiTile({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Material(
          color: c.ink,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.auto_awesome_outlined, size: 24, color: c.cardColor(0)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Draft with AI',
                            style: bodyStyle(
                              context,
                              16,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            enabled
                                ? 'Describe it, get a card you can edit'
                                : 'Plus, coming soon',
                            style: bodyStyle(
                              context,
                              13,
                              color: VarnaExtras.onDarkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
