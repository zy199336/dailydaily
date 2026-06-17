import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase SQL is scoped to daily_schedule objects', () {
    final sql = File('supabase_daily_schedule.sql').readAsStringSync();
    final lowered = sql.toLowerCase();

    expect(lowered, isNot(contains('drop ')));
    expect(lowered, isNot(contains('truncate ')));
    expect(lowered, isNot(contains('delete from')));
    expect(lowered, contains('public.daily_schedule_tasks'));

    final publicObjectPattern = RegExp(r'public\.([a-zA-Z0-9_]+)');
    final publicObjects = publicObjectPattern
        .allMatches(sql)
        .map((match) => match.group(1)!)
        .toSet();

    expect(publicObjects, {'daily_schedule_tasks'});
  });
}
