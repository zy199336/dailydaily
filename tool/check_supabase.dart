import 'dart:convert';
import 'dart:io';

import 'package:daily_schedule/services/schedule_repository.dart';

Future<void> main() async {
  final uri = Uri.parse(
    '$supabaseUrl/rest/v1/$scheduleTable?select=id&limit=1',
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers
      ..set('apikey', supabaseKey)
      ..set('authorization', 'Bearer $supabaseKey');
    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode == HttpStatus.ok) {
      stdout.writeln('OK: Supabase table "$scheduleTable" is reachable.');
      stdout.writeln(body);
      return;
    }

    stdout.writeln('NOT READY: Supabase returned HTTP ${response.statusCode}.');
    if (body.isNotEmpty) stdout.writeln(body);
    stdout.writeln(
      'Run supabase_daily_schedule.sql in the Supabase SQL Editor.',
    );
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}
