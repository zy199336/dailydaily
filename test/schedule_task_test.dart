import 'package:daily_schedule/models/schedule_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes multi-day timed tasks', () {
    final task = ScheduleTask(
      id: 'task-1',
      title: '论文',
      description: '跨天任务',
      startDate: DateTime(2026, 6, 18),
      endDate: DateTime(2026, 6, 20),
      startTime: const TimeValue(9, 0),
      endTime: const TimeValue(17, 0),
      isAllDay: false,
      isCompleted: false,
      createdAt: DateTime(2026, 6, 14),
      updatedAt: DateTime(2026, 6, 14, 10),
    );

    final json = task.toSupabase();

    expect(json['start_date'], '2026-06-18');
    expect(json['end_date'], '2026-06-20');
    expect(json['start_time'], '09:00:00');
    expect(json['end_time'], '17:00:00');
    expect(task.spansMultipleDays, isTrue);
  });

  test('copyWith can assign owner id for sync isolation', () {
    final task = ScheduleTask(
      id: 'task-1',
      title: '同步空间任务',
      startDate: DateTime(2026, 6, 18),
      endDate: DateTime(2026, 6, 18),
      isAllDay: true,
      isCompleted: false,
      createdAt: DateTime(2026, 6, 14),
      updatedAt: DateTime(2026, 6, 14),
    ).copyWith(ownerId: 'lab-a');

    expect(task.ownerId, 'lab-a');
    expect(task.toSupabase()['owner_id'], 'lab-a');
  });

  test('serializes account, recurrence, and priority fields', () {
    final task = ScheduleTask(
      id: 'task-2',
      title: '月度复盘',
      startDate: DateTime(2026, 6, 14),
      endDate: DateTime(2026, 6, 14),
      isAllDay: true,
      isCompleted: false,
      createdAt: DateTime(2026, 6, 14),
      updatedAt: DateTime(2026, 6, 14),
      userId: 'user-1',
      recurrenceRule: RecurrenceRule.monthly,
      priority: 3,
    );

    final json = task.toSupabase();

    expect(json['user_id'], 'user-1');
    expect(json['recurrence_rule'], 'monthly');
    expect(json['priority'], 3);
    expect(
      ScheduleTask.fromSupabase(json).recurrenceRule,
      RecurrenceRule.monthly,
    );
  });
}
