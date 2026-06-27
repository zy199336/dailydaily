import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import '../models/schedule_task.dart';

const supabaseUrl = 'https://kawhxjhiqqjjinbxcoqm.supabase.co';
const supabaseKey = 'sb_publishable_XUdjz7gv0_M8nvGp8s3iVQ_jigFlgE-';
const scheduleTable = 'daily_schedule_tasks';
const aliyunApiBaseUrl = 'https://api.dailydaily.top';

class SyncResult {
  const SyncResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class ScheduleRepository {
  ScheduleRepository._({
    required this.client,
    required this.storeFile,
    required this.deviceId,
    required this.ownerId,
  });

  static const _storeFileName = 'daily_schedule_store_v1.json';
  static const _authSessionKey = 'auth_session';

  final SupabaseClient client;
  final File storeFile;
  final String deviceId;
  StreamSubscription<AuthState>? _authStateSubscription;
  String ownerId;

  User? get currentUser => client.auth.currentUser;

  bool get _hasAliyunSession =>
      client.auth.currentSession?.accessToken.isNotEmpty == true;

  static Future<ScheduleRepository> create() async {
    final directory = await _storageDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final storeFile = File(
      '${directory.path}${Platform.pathSeparator}$_storeFileName',
    );
    var deviceId = const Uuid().v4();
    var ownerId = 'default';
    if (await storeFile.exists()) {
      try {
        final raw = await storeFile.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        deviceId = json['device_id'] as String? ?? deviceId;
        ownerId = _normalizeOwnerId(json['owner_id'] as String? ?? ownerId);
      } catch (_) {
        deviceId = const Uuid().v4();
      }
    }
    final repository = ScheduleRepository._(
      client: SupabaseClient(supabaseUrl, supabaseKey),
      storeFile: storeFile,
      deviceId: deviceId,
      ownerId: ownerId,
    );
    await repository._restoreAuthSession();
    repository._watchAuthSession();
    return repository;
  }

  Future<List<ScheduleTask>> loadLocal() async {
    try {
      final store = await _readStore();
      return _tasksForOwner(store, ownerId);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLocal(List<ScheduleTask> tasks) async {
    final parent = storeFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final accountId = currentUser?.id;
    final store = await _readStore();
    final tasksByOwner = _tasksByOwnerMap(store);
    tasksByOwner[ownerId] = tasks
        .map(
          (task) => task.copyWith(ownerId: ownerId, userId: accountId).toJson(),
        )
        .toList();
    await _writeStore(tasksByOwner);
  }

  Future<List<ScheduleTask>> updateOwnerId(
    String nextOwnerId,
    List<ScheduleTask> tasks,
  ) async {
    await saveLocal(tasks);
    ownerId = _normalizeOwnerId(nextOwnerId);
    return loadLocal();
  }

  Future<String?> signIn(String email, String password) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await _saveAuthSession(response.session);
    return response.user?.id;
  }

  Future<String?> signUp(String email, String password) async {
    final response = await client.auth.signUp(email: email, password: password);
    await _saveAuthSession(response.session);
    return response.user?.id;
  }

  Future<void> signOut() async {
    await client.auth.signOut();
    await _saveAuthSession(null);
  }

  Future<SyncResult> sync(
    List<ScheduleTask> localTasks, {
    bool preferLocal = false,
  }) async {
    try {
      final accountId = currentUser?.id;
      final normalizedLocal = localTasks
          .map((task) => task.copyWith(ownerId: ownerId, userId: accountId))
          .toList();
      if (preferLocal) {
        if (normalizedLocal.isNotEmpty) {
          await client
              .from(scheduleTable)
              .upsert(normalizedLocal.map((task) => task.toSupabase()).toList())
              .timeout(const Duration(seconds: 15));
        }
        final aliyunBackupOk = await _pushAliyunTasks(normalizedLocal);
        await saveLocal(normalizedLocal);
        if (_hasAliyunSession && !aliyunBackupOk) {
          return const SyncResult(
            success: false,
            message: 'Supabase 已同步，阿里云备份失败',
          );
        }
        final backupText = _hasAliyunSession ? 'Supabase + 阿里云' : 'Supabase';
        return SyncResult(success: true, message: '$backupText 同步完成');
      }

      final supabaseTasks = await _loadSupabaseTasks(accountId);
      final aliyunTasks = await _loadAliyunTasks();

      final merged = mergeTasksByLatest(normalizedLocal, [
        ...supabaseTasks,
        ...aliyunTasks,
      ]);
      if (merged.isNotEmpty) {
        await client
            .from(scheduleTable)
            .upsert(merged.map((task) => task.toSupabase()).toList())
            .timeout(const Duration(seconds: 15));
        final aliyunBackupOk = await _pushAliyunTasks(merged);
        await saveLocal(merged);
        if (_hasAliyunSession && !aliyunBackupOk) {
          return const SyncResult(
            success: false,
            message: 'Supabase 已同步，阿里云备份失败',
          );
        }
      }
      await saveLocal(merged);
      final backupText = _hasAliyunSession ? 'Supabase + 阿里云' : 'Supabase';
      return SyncResult(success: true, message: '$backupText 同步完成');
    } on SocketException {
      await saveLocal(localTasks);
      return const SyncResult(success: false, message: '网络不可用，已保留本地修改');
    } on PostgrestException catch (error) {
      await saveLocal(localTasks);
      if (error.code == 'PGRST205' ||
          error.code == '42P01' ||
          error.message.contains(scheduleTable)) {
        return const SyncResult(
          success: false,
          message: '请先在 Supabase 执行建表 SQL',
        );
      }
      return SyncResult(success: false, message: '同步失败：${error.message}');
    } catch (error) {
      await saveLocal(localTasks);
      return SyncResult(success: false, message: '同步失败：$error');
    }
  }

  Future<List<ScheduleTask>> _loadSupabaseTasks(String? accountId) async {
    final remoteRows = accountId == null
        ? await client.from(scheduleTable).select().eq('owner_id', ownerId)
        : await client.from(scheduleTable).select().eq('user_id', accountId);
    return (remoteRows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ScheduleTask.fromSupabase)
        .toList();
  }

  Future<List<ScheduleTask>> _loadAliyunTasks() async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return [];
    try {
      final response = await http
          .get(
            Uri.parse('$aliyunApiBaseUrl/tasks'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return [];
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = payload['tasks'];
      if (rows is! List<dynamic>) return [];
      return rows
          .cast<Map<String, dynamic>>()
          .map(ScheduleTask.fromSupabase)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> _pushAliyunTasks(List<ScheduleTask> tasks) async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return true;
    try {
      final response = await http
          .post(
            Uri.parse('$aliyunApiBaseUrl/sync'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'tasks': tasks.map((task) => task.toSupabase()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}

String _normalizeOwnerId(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'default' : trimmed;
}

extension on ScheduleRepository {
  void _watchAuthSession() {
    _authStateSubscription?.cancel();
    _authStateSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        unawaited(_saveAuthSession(null));
        return;
      }
      if (state.session != null &&
          (state.event == AuthChangeEvent.initialSession ||
              state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.tokenRefreshed ||
              state.event == AuthChangeEvent.userUpdated ||
              state.event == AuthChangeEvent.passwordRecovery)) {
        unawaited(_saveAuthSession(state.session));
      }
    });
  }

  Future<void> _restoreAuthSession() async {
    try {
      final store = await _readStore();
      final rawSession = store[ScheduleRepository._authSessionKey];
      if (rawSession is! Map<String, dynamic>) return;
      final response = await client.auth
          .recoverSession(jsonEncode(rawSession))
          .timeout(const Duration(seconds: 12));
      await _saveAuthSession(response.session);
    } catch (_) {
      await _saveAuthSession(null);
    }
  }

  Future<void> _saveAuthSession(Session? session) async {
    final store = await _readStore();
    final tasksByOwner = _tasksByOwnerMap(store);
    await _writeStore(
      tasksByOwner,
      authSession: session?.toJson(),
      clearAuthSession: session == null,
    );
  }

  Future<Map<String, dynamic>> _readStore() async {
    if (!await storeFile.exists()) return <String, dynamic>{};
    final raw = await storeFile.readAsString();
    if (raw.isEmpty) return <String, dynamic>{};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _writeStore(
    Map<String, List<Map<String, dynamic>>> tasksByOwner, {
    Map<String, dynamic>? authSession,
    bool clearAuthSession = false,
  }) async {
    final existing = await _readStore();
    final existingAuthSession = existing[ScheduleRepository._authSessionKey];
    final payload = jsonEncode({
      'device_id': deviceId,
      'owner_id': ownerId,
      'tasks_by_owner': tasksByOwner,
      if (authSession != null)
        ScheduleRepository._authSessionKey: authSession
      else if (!clearAuthSession && existingAuthSession is Map<String, dynamic>)
        ScheduleRepository._authSessionKey: existingAuthSession,
    });
    await storeFile.writeAsString(payload);
  }

  Map<String, List<Map<String, dynamic>>> _tasksByOwnerMap(
    Map<String, dynamic> store,
  ) {
    final raw = store['tasks_by_owner'];
    final result = <String, List<Map<String, dynamic>>>{};
    if (raw is Map<String, dynamic>) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is List<dynamic>) {
          result[entry.key] = value.cast<Map<String, dynamic>>();
        }
      }
    }

    final legacyTasks = store['tasks'];
    final legacyOwner = _normalizeOwnerId(
      store['owner_id'] as String? ?? ownerId,
    );
    if (legacyTasks is List<dynamic> && !result.containsKey(legacyOwner)) {
      result[legacyOwner] = legacyTasks.cast<Map<String, dynamic>>();
    }
    return result;
  }

  List<ScheduleTask> _tasksForOwner(
    Map<String, dynamic> store,
    String ownerId,
  ) {
    final tasksByOwner = _tasksByOwnerMap(store);
    final tasks = tasksByOwner[ownerId] ?? const <Map<String, dynamic>>[];
    return tasks.map(ScheduleTask.fromSupabase).toList();
  }
}

List<ScheduleTask> mergeTasksByLatest(
  List<ScheduleTask> localTasks,
  List<ScheduleTask> remoteTasks,
) {
  final merged = <String, ScheduleTask>{};
  for (final task in [...remoteTasks, ...localTasks]) {
    final current = merged[task.id];
    if (current == null || !task.updatedAt.isBefore(current.updatedAt)) {
      merged[task.id] = task;
    }
  }
  final tasks = merged.values.toList()
    ..sort((a, b) {
      final byDate = a.startDate.compareTo(b.startDate);
      if (byDate != 0) return byDate;
      final byPriority = a.priority.compareTo(b.priority);
      if (byPriority != 0) return byPriority;
      return a.createdAt.compareTo(b.createdAt);
    });
  return tasks;
}

Future<Directory> _storageDirectory() async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData${Platform.pathSeparator}DailySchedule');
    }
  }
  return Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}DailySchedule',
  );
}
