import 'dart:convert';

import 'package:intl/intl.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');
final _timeFormat = DateFormat('HH:mm:ss');

enum RecurrenceRule {
  none('none', '不重复'),
  daily('daily', '每天'),
  monthly('monthly', '每月'),
  yearly('yearly', '每年');

  const RecurrenceRule(this.value, this.label);

  final String value;
  final String label;

  static RecurrenceRule fromValue(String? value) {
    return RecurrenceRule.values.firstWhere(
      (rule) => rule.value == value,
      orElse: () => RecurrenceRule.none,
    );
  }
}

class ScheduleTask {
  const ScheduleTask({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.isAllDay,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.startTime,
    this.endTime,
    this.deletedAt,
    this.deviceId,
    this.ownerId = 'default',
    this.userId,
    this.recurrenceRule = RecurrenceRule.none,
    this.priority = 0,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  final TimeValue? startTime;
  final TimeValue? endTime;
  final bool isAllDay;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;
  final String ownerId;
  final String? userId;
  final RecurrenceRule recurrenceRule;
  final int priority;

  bool get isDeleted => deletedAt != null;

  bool get spansMultipleDays => !_isSameDay(startDate, endDate);

  ScheduleTask copyWith({
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    TimeValue? startTime,
    TimeValue? endTime,
    bool? isAllDay,
    bool? isCompleted,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? deviceId,
    String? ownerId,
    String? userId,
    RecurrenceRule? recurrenceRule,
    int? priority,
  }) {
    return ScheduleTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: dateOnly(startDate ?? this.startDate),
      endDate: dateOnly(endDate ?? this.endDate),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAllDay: isAllDay ?? this.isAllDay,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt,
      deviceId: deviceId ?? this.deviceId,
      ownerId: ownerId ?? this.ownerId,
      userId: userId ?? this.userId,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'start_date': _dateFormat.format(startDate),
      'end_date': _dateFormat.format(endDate),
      'start_time': startTime?.toDatabaseValue(),
      'end_time': endTime?.toDatabaseValue(),
      'is_all_day': isAllDay,
      'is_completed': isCompleted,
      'owner_id': ownerId,
      'user_id': userId,
      'recurrence_rule': recurrenceRule.value,
      'priority': priority,
      'device_id': deviceId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toSupabase();

  static ScheduleTask fromSupabase(Map<String, dynamic> json) {
    return ScheduleTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      startDate: dateOnly(DateTime.parse(json['start_date'] as String)),
      endDate: dateOnly(DateTime.parse(json['end_date'] as String)),
      startTime: TimeValue.tryParse(json['start_time'] as String?),
      endTime: TimeValue.tryParse(json['end_time'] as String?),
      isAllDay: json['is_all_day'] as bool? ?? false,
      isCompleted: json['is_completed'] as bool? ?? false,
      ownerId: json['owner_id'] as String? ?? 'default',
      userId: json['user_id'] as String?,
      recurrenceRule: RecurrenceRule.fromValue(
        json['recurrence_rule'] as String?,
      ),
      priority: json['priority'] as int? ?? 0,
      deviceId: json['device_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String).toLocal(),
    );
  }

  static List<ScheduleTask> listFromJsonString(String value) {
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(ScheduleTask.fromSupabase)
        .toList();
  }

  static String listToJsonString(List<ScheduleTask> tasks) {
    return jsonEncode(tasks.map((task) => task.toJson()).toList());
  }
}

class TimeValue {
  const TimeValue(this.hour, this.minute);

  final int hour;
  final int minute;

  String format() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String toDatabaseValue() => '${format()}:00';

  static TimeValue? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed =
        _timeFormat.tryParse(value) ?? DateFormat('HH:mm').tryParse(value);
    if (parsed == null) return null;
    return TimeValue(parsed.hour, parsed.minute);
  }
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isSameDay(DateTime a, DateTime b) => _isSameDay(a, b);

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
