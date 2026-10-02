import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'open'),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> schedule({
    required String id,
    required String title,
    required DateTime remindAt,
  }) async {
    final scheduled = tz.TZDateTime.from(remindAt, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id.hashCode,
      'Echo Codex reminder',
      title,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'action_reminders',
          'Action reminders',
          channelDescription: 'Reminders for Echo Codex action items.',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: id,
    );
  }

  Future<void> scheduleRecording({
    required String id,
    required DateTime startsAt,
  }) async {
    final scheduled = tz.TZDateTime.from(startsAt, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id.hashCode,
      'Echo Codex recording',
      'Scheduled recording starts now.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'scheduled_recordings',
          'Scheduled recordings',
          channelDescription: 'Scheduled Echo Codex recordings.',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'record:$id',
    );
  }

  /// Says the notes for a recording are written, now, rather than at a scheduled time.
  ///
  /// The other half of "record now, notes later": deferring the work is only an
  /// improvement if the person does not have to keep checking. [title] is the note's own
  /// title, so the notification says which recording finished — someone who queued three
  /// in a morning should not have to open the app to find out.
  Future<void> notesReady({required String id, required String title}) =>
      _plugin.show(
        'notes:$id'.hashCode,
        'Your notes are ready',
        title,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'notes_ready',
            'Finished notes',
            channelDescription:
                'Tells you when the notes for a recording have been written.',
            importance: Importance.defaultImportance,
          ),
          iOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        payload: 'note:$id',
      );

  Future<void> cancel(String id) => _plugin.cancel(id.hashCode);
}
