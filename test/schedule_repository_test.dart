import 'package:daily_schedule/models/schedule_task.dart';
import 'package:daily_schedule/services/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeTasksByLatest keeps newer task version', () {
    final older = _task(title: '旧标题', updatedAt: DateTime(2026, 6, 14, 9));
    final newer = _task(title: '新标题', updatedAt: DateTime(2026, 6, 14, 10));

    final merged = mergeTasksByLatest([older], [newer]);

    expect(merged, hasLength(1));
    expect(merged.single.title, '新标题');
  });

  test('mergeTasksByLatest prefers local task when timestamps tie', () {
    final timestamp = DateTime(2026, 6, 14, 10);
    final local = _task(title: '本地完成', updatedAt: timestamp);
    final remote = _task(title: '云端旧状态', updatedAt: timestamp);

    final merged = mergeTasksByLatest([local], [remote]);

    expect(merged, hasLength(1));
    expect(merged.single.title, '本地完成');
  });

  test('mergeTasksByLatest sorts by start date then created time', () {
    final later = _task(
      id: 'later',
      title: '晚一点',
      startDate: DateTime(2026, 6, 20),
      createdAt: DateTime(2026, 6, 14, 8),
    );
    final earlier = _task(
      id: 'earlier',
      title: '早一点',
      startDate: DateTime(2026, 6, 18),
      createdAt: DateTime(2026, 6, 14, 9),
    );

    final merged = mergeTasksByLatest([later, earlier], []);

    expect(merged.map((task) => task.id), ['earlier', 'later']);
  });
}

ScheduleTask _task({
  String id = 'same-id',
  required String title,
  DateTime? startDate,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = createdAt ?? DateTime(2026, 6, 14);
  return ScheduleTask(
    id: id,
    title: title,
    startDate: startDate ?? DateTime(2026, 6, 18),
    endDate: startDate ?? DateTime(2026, 6, 18),
    isAllDay: true,
    isCompleted: false,
    createdAt: created,
    updatedAt: updatedAt ?? created,
  );
}
