import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'database_helper.dart' as db;
import 'dart:async';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  NotificationService._init();

  Future<void> init() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleForDeadline(db.Deadline deadline) async {
    await cancelForDeadline(deadline);
    if (deadline.isDone) return;

    final now = DateTime.now();
    final due = deadline.dueDate;

    // Уведомление в момент дедлайна
    if (due.isAfter(now)) {
      await _scheduleIfFuture(
        id: _notificationId(deadline.id!, 0),
        title: _titleByPriority(deadline.priority),
        body: deadline.title, // только название
        scheduledTime: due,
        priority: deadline.priority,
      );
    }

    switch (deadline.priority) {
      case db.Priority.high:
        await _scheduleIfFuture(
          id: _notificationId(deadline.id!, 1),
          title: '🔴 Срочно! Завтра дедлайн',
          body: deadline.title,
          scheduledTime: due.subtract(const Duration(days: 1)),
          priority: deadline.priority,
        );
        await _scheduleIfFuture(
          id: _notificationId(deadline.id!, 2),
          title: '🔴 Срочно! Через 3 часа',
          body: deadline.title,
          scheduledTime: due.subtract(const Duration(hours: 3)),
          priority: deadline.priority,
        );
        await _scheduleIfFuture(
          id: _notificationId(deadline.id!, 3),
          title: '🔴 Срочно! Через 30 минут',
          body: deadline.title,
          scheduledTime: due.subtract(const Duration(minutes: 30)),
          priority: deadline.priority,
        );

      case db.Priority.medium:
        await _scheduleIfFuture(
          id: _notificationId(deadline.id!, 1),
          title: '🟠 Напоминание: завтра дедлайн',
          body: deadline.title,
          scheduledTime: due.subtract(const Duration(days: 1)),
          priority: deadline.priority,
        );
        await _scheduleIfFuture(
          id: _notificationId(deadline.id!, 2),
          title: '🟠 Напоминание: через 3 часа',
          body: deadline.title,
          scheduledTime: due.subtract(const Duration(hours: 3)),
          priority: deadline.priority,
        );

      case db.Priority.low:
        await _scheduleIfFuture(
          id: _notificationId(deadline.id!, 1),
          title: '🟢 Не забудь: завтра дедлайн',
          body: deadline.title,
          scheduledTime: due.subtract(const Duration(days: 1)),
          priority: deadline.priority,
        );
    }
  }

  // Уведомление о просрочке — только один раз
  Future<void> showOverdueNotification(db.Deadline deadline) async {
    final androidDetails = AndroidNotificationDetails(
      'overdue_channel',
      'Просроченные задачи',
      channelDescription: 'Уведомления о просроченных дедлайнах',
      importance: Importance.max,
      priority: Priority.high,
      color: const Color(0xFFFF5C5C),
    );

    await _plugin.show(
      _notificationId(deadline.id!, 99),
      '⚠️ Просрочено!',
      deadline.title,
      NotificationDetails(android: androidDetails),
    );

    // Отмечаем что уведомление уже отправлено
    deadline.isOverdueNotified = true;
    unawaited(db.DatabaseHelper.instance.update(deadline));
  }

  Future<void> cancelForDeadline(db.Deadline deadline) async {
    for (int i = 0; i <= 99; i++) {
      await _plugin.cancel(_notificationId(deadline.id!, i));
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<void> rescheduleAll() async {
    await cancelAll();
    final deadlines = await db.DatabaseHelper.instance.readAll();
    for (final deadline in deadlines) {
      if (!deadline.isDone) await scheduleForDeadline(deadline);
    }
  }

  Future<void> checkOverdue() async {
    final deadlines = await db.DatabaseHelper.instance.readAll();
    for (final deadline in deadlines) {
      if (!deadline.isDone &&
          deadline.dueDate.isBefore(DateTime.now()) &&
          !deadline.isOverdueNotified) {
        await showOverdueNotification(deadline);
      }
    }
  }

  Future<void> _scheduleIfFuture({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required db.Priority priority,
  }) async {
    if (scheduledTime.isAfter(DateTime.now())) {
      await _schedule(
        id: id, title: title, body: body,
        scheduledTime: scheduledTime, priority: priority,
      );
    }
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required db.Priority priority,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId(priority),
      _channelName(priority),
      channelDescription: 'Уведомления DeadlineFlow',
      importance: _importance(priority),
      priority: _androidPriority(priority),
      color: _color(priority),
      enableVibration: priority == db.Priority.high,
    );

    await _plugin.zonedSchedule(
      id, title, body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  int _notificationId(int deadlineId, int offset) => deadlineId * 100 + offset;

  String _titleByPriority(db.Priority priority) => switch (priority) {
    db.Priority.high   => '🔴 Дедлайн сейчас!',
    db.Priority.medium => '🟠 Дедлайн сейчас',
    db.Priority.low    => '🟢 Дедлайн сейчас',
  };

  String _channelId(db.Priority p) => switch (p) {
    db.Priority.high   => 'high_channel',
    db.Priority.medium => 'medium_channel',
    db.Priority.low    => 'low_channel',
  };

  String _channelName(db.Priority p) => switch (p) {
    db.Priority.high   => 'Высокий приоритет',
    db.Priority.medium => 'Средний приоритет',
    db.Priority.low    => 'Низкий приоритет',
  };

  Importance _importance(db.Priority p) => switch (p) {
    db.Priority.high   => Importance.max,
    db.Priority.medium => Importance.high,
    db.Priority.low    => Importance.defaultImportance,
  };

  Priority _androidPriority(db.Priority p) => switch (p) {
    db.Priority.high   => Priority.max,
    db.Priority.medium => Priority.high,
    db.Priority.low    => Priority.defaultPriority,
  };

  Color _color(db.Priority p) => switch (p) {
    db.Priority.high   => const Color(0xFFFF5C5C),
    db.Priority.medium => const Color(0xFFFFAB2E),
    db.Priority.low    => const Color(0xFF4CD97B),
  };
}