import 'package:daily_schedule/main.dart';
import 'package:daily_schedule/models/schedule_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders multi-day task bars with end time', (tester) async {
    final task = ScheduleTask(
      id: 'task-1',
      title: '跨天任务',
      startDate: DateTime(2026, 6, 18),
      endDate: DateTime(2026, 6, 20),
      endTime: const TimeValue(17, 0),
      isAllDay: false,
      isCompleted: false,
      createdAt: DateTime(2026, 6, 14),
      updatedAt: DateTime(2026, 6, 14),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 420,
            child: CalendarBoard(
              focusedDate: DateTime(2026, 6, 17),
              mode: CalendarMode.week,
              tasks: [task],
              onDateTap: (_) {},
              onTaskTap: (_) {},
              onToggleComplete: (_) {},
              onReorderTask: (_, _) {},
              onMoveTaskToDate: (_, _) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('跨天任务'), findsOneWidget);
    expect(find.text('17:00'), findsOneWidget);
  });
}
