import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../app_config.dart';
import '../../../../core/data/attachment_store.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/reminder_service.dart';
import '../../../../core/theme/varna_colors.dart';
import 'card_saver.dart';
import 'format_utils.dart';
import 'ui_kit.dart';

/// Shows a short message at the bottom of the screen.
void showInfo(BuildContext context, String message) {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Rect? _anchorOf(BuildContext context) {
  final RenderObject? box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return null;
}

/// Opens the system share sheet with plain [text]. [context] should belong to
/// the button that was tapped (iPad anchors the share popover to it).
Future<void> shareText(
  BuildContext context, {
  required String text,
  String? subject,
}) async {
  final Rect? anchor = _anchorOf(context);
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: (subject == null || subject.isEmpty) ? null : subject,
        sharePositionOrigin: anchor,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showInfo(context, 'Sharing is not available here.');
    }
  }
}

/// Shares one image (kept in memory, so it works on web too).
Future<void> shareImageBytes(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
}) async {
  final Rect? anchor = _anchorOf(context);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(bytes, mimeType: imageMimeType(fileName)),
        ],
        fileNameOverrides: <String>[fileName],
        sharePositionOrigin: anchor,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showInfo(context, 'Sharing is not available here.');
    }
  }
}

/// Asks where a photo should come from. On web there is only the file
/// chooser, so it answers right away.
Future<ImageSource?> chooseImageSource(BuildContext context) async {
  if (kIsWeb) {
    return ImageSource.gallery;
  }
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              minTileHeight: 56,
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              minTileHeight: 56,
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Picks a photo, stores its bytes in [store] and returns the attachment that
/// describes it (or null when cancelled or when it failed; failures show a
/// message).
Future<Attachment?> pickAndStoreImage(
  BuildContext context,
  AttachmentStore store,
) async {
  final ImageSource? source = await chooseImageSource(context);
  if (source == null || !context.mounted) {
    return null;
  }
  try {
    final XFile? file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      imageQuality: 85,
    );
    if (file == null) {
      return null;
    }
    final Uint8List bytes = await file.readAsBytes();
    final String id = const Uuid().v4();
    await store.save(id, bytes);
    final String name = file.name.isEmpty ? 'photo.jpg' : file.name;
    return Attachment(
      id: id,
      kind: AttachmentKind.image,
      fileName: name,
      byteLength: bytes.length,
    );
  } catch (_) {
    if (context.mounted) {
      showInfo(
        context,
        'Could not get the photo. Check that Varna may use the camera and '
        'photos in your phone settings.',
      );
    }
    return null;
  }
}

/// Asks "really delete?" and answers true when confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  String title = 'Delete this card?',
  String message = 'It is removed from all your devices the next time you '
      'sync. This cannot be undone.',
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final VarnaColors colors = VarnaColors.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

enum _ReminderChoice { change, remove }

/// Lets the user set, change or remove the reminder of a card: date picker,
/// then time picker, then the notification is scheduled and `reminderAt`
/// saved. Plain reminders do not need Plus.
///
/// [title] is the notification title (usually the card title).
Future<void> editCardReminder({
  required BuildContext context,
  required ReminderService reminders,
  required CardSaver saver,
  required NoteCard card,
  required String title,
}) async {
  if (!reminders.isSupported) {
    showInfo(context, 'Reminders work in the ${AppConfig.appName} mobile app.');
    return;
  }
  final DateTime now = DateTime.now();
  final DateTime? existing = card.reminderAt?.toLocal();
  if (existing != null && existing.isAfter(now)) {
    final _ReminderChoice? choice = await showModalBottomSheet<_ReminderChoice>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  'Reminder set for ${formatDateTime(existing)}',
                  style: bodyStyle(sheetContext, 16, weight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('Change time'),
                minTileHeight: 56,
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ReminderChoice.change),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('Remove reminder'),
                minTileHeight: 56,
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ReminderChoice.remove),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (choice == null || !context.mounted) {
      return;
    }
    if (choice == _ReminderChoice.remove) {
      await reminders.cancel(card.id);
      await saver.update((NoteCard c) => c.copyWith(reminderAt: null));
      if (context.mounted) {
        showInfo(context, 'Reminder removed.');
      }
      return;
    }
  }

  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime? date = await showDatePicker(
    context: context,
    initialDate: (existing != null && existing.isAfter(now))
        ? existing
        : today.add(const Duration(days: 1)),
    firstDate: today,
    lastDate: DateTime(today.year + 5, today.month, today.day),
    helpText: 'Remind me on',
  );
  if (date == null || !context.mounted) {
    return;
  }
  final TimeOfDay? time = await showTimePicker(
    context: context,
    initialTime: existing != null
        ? TimeOfDay(hour: existing.hour, minute: existing.minute)
        : const TimeOfDay(hour: 9, minute: 0),
    helpText: 'Remind me at',
  );
  if (time == null || !context.mounted) {
    return;
  }
  final DateTime when =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!when.isAfter(DateTime.now())) {
    showInfo(context, 'Pick a time in the future.');
    return;
  }
  final bool allowed = await reminders.requestPermission();
  if (!context.mounted) {
    return;
  }
  if (!allowed) {
    showInfo(
      context,
      'Notifications are off for ${AppConfig.appName}. Turn them on in your '
      'phone settings to get reminders.',
    );
    return;
  }
  await reminders.schedule(
    cardId: card.id,
    title: title.trim().isEmpty ? 'Reminder' : title.trim(),
    body: 'Open ${AppConfig.appName} to see your card.',
    when: when,
  );
  await saver.update((NoteCard c) => c.copyWith(reminderAt: when.toUtc()));
  if (context.mounted) {
    showInfo(context, 'Reminder set for ${formatDateTime(when)}.');
  }
}

/// A pill showing the reminder time of a card; tap to change it.
class ReminderChip extends StatelessWidget {
  const ReminderChip({super.key, required this.reminderAt, required this.onTap});

  final DateTime reminderAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: frostedWhite(),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.notifications_active_outlined,
                      size: 18, color: colors.ink),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Reminder: ${formatDateTime(reminderAt)}',
                      style: bodyStyle(context, 14, weight: FontWeight.w600),
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
