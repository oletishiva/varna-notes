import 'reminder_service.dart';

/// Web / fallback: reminders are not available.
ReminderService createReminderService() => const NoopReminderService();
