// Chooses the reminder implementation at compile time.
// Exposes: `ReminderService createReminderService()`.
export 'reminder_service_stub.dart'
    if (dart.library.io) 'reminder_service_io.dart';
