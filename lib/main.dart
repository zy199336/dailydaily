import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:uuid/uuid.dart';

import 'models/schedule_task.dart';
import 'services/schedule_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailyScheduleApp());
}

class DailyScheduleApp extends StatelessWidget {
  const DailyScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Schedule',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff4a6fff),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC'],
      ),
      home: const ScheduleHomePage(),
    );
  }
}

enum CalendarMode { month, week }

class ScheduleHomePage extends StatefulWidget {
  const ScheduleHomePage({super.key});

  @override
  State<ScheduleHomePage> createState() => _ScheduleHomePageState();
}

class _ScheduleHomePageState extends State<ScheduleHomePage>
    with WidgetsBindingObserver {
  late final Future<ScheduleRepository> _repositoryFuture;
  Timer? _syncTimer;
  List<ScheduleTask> _tasks = [];
  CalendarMode _mode = CalendarMode.month;
  DateTime _focusedDate = dateOnly(DateTime.now());
  String _syncMessage = '尚未同步';
  String _ownerId = 'default';
  String _accountLabel = '本地空间';
  bool _isSyncing = false;
  bool _syncAgain = false;
  bool _syncAgainPreferLocal = false;
  int _localEditVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repositoryFuture = ScheduleRepository.create();
    _bootstrap();
    _syncTimer = Timer.periodic(const Duration(seconds: 25), (_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
    }
  }

  Future<void> _bootstrap() async {
    final repository = await _repositoryFuture;
    final local = await repository.loadLocal();
    setState(() {
      _tasks = local;
      _ownerId = repository.ownerId;
      _accountLabel = _labelForRepository(repository);
    });
    if (repository.currentUser == null) {
      await _openAccountDialog(requireAccount: true);
    }
    await _sync();
  }

  Future<void> _sync({bool preferLocal = false}) async {
    if (_isSyncing) {
      _syncAgain = true;
      _syncAgainPreferLocal = _syncAgainPreferLocal || preferLocal;
      return;
    }
    final syncVersion = _localEditVersion;
    final syncTasks = [..._tasks];
    if (mounted) {
      setState(() {
        _isSyncing = true;
        _syncMessage = '同步中...';
      });
    }
    final repository = await _repositoryFuture;
    var result = const SyncResult(success: false, message: '同步失败，本地已保存');
    var hasNewerLocalEdits = false;
    try {
      result = await repository
          .sync(syncTasks, preferLocal: preferLocal)
          .timeout(const Duration(seconds: 25));
      hasNewerLocalEdits = _localEditVersion != syncVersion;
      if (hasNewerLocalEdits) {
        await repository.saveLocal(_tasks);
      }
      if (!mounted) return;
      if (!hasNewerLocalEdits && !preferLocal) {
        final latest = await repository.loadLocal();
        if (!mounted) return;
        setState(() => _tasks = latest);
      }
    } on TimeoutException {
      result = const SyncResult(success: false, message: '同步超时，本地已保存');
      await repository.saveLocal(_tasks);
      hasNewerLocalEdits = true;
    } catch (error) {
      result = SyncResult(success: false, message: '同步失败，本地已保存：$error');
      await repository.saveLocal(_tasks);
      hasNewerLocalEdits = true;
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncMessage = hasNewerLocalEdits
              ? '本地修改已保存，等待同步...'
              : result.message;
          _accountLabel = _labelForRepository(repository);
        });
      } else {
        _isSyncing = false;
      }
    }
    if (_syncAgain || hasNewerLocalEdits) {
      final nextPreferLocal = _syncAgainPreferLocal || hasNewerLocalEdits;
      _syncAgain = false;
      _syncAgainPreferLocal = false;
      unawaited(_sync(preferLocal: nextPreferLocal));
    }
  }

  String _labelForRepository(ScheduleRepository repository) {
    final email = repository.currentUser?.email;
    if (email != null && email.isNotEmpty) return email;
    return repository.ownerId;
  }

  Future<void> _saveTasks(List<ScheduleTask> next, {bool sync = true}) async {
    _localEditVersion++;
    setState(() => _tasks = next);
    final repository = await _repositoryFuture;
    await repository.saveLocal(next);
    if (sync) {
      if (_isSyncing) {
        _syncAgain = true;
        _syncAgainPreferLocal = true;
        return;
      }
      unawaited(_sync(preferLocal: true));
    }
  }

  void _goToday() {
    setState(() => _focusedDate = dateOnly(DateTime.now()));
  }

  Future<void> _openSyncSpaceDialog() async {
    final controller = TextEditingController(text: _ownerId);
    final nextOwnerId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同步空间'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '空间 ID',
            helperText: '电脑和安卓端填写同一个 ID 即可同步同一份日程。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nextOwnerId == null) return;
    final repository = await _repositoryFuture;
    final ownerTasks = await repository.updateOwnerId(nextOwnerId, _tasks);
    if (!mounted) return;
    setState(() {
      _ownerId = repository.ownerId;
      _tasks = ownerTasks;
      _syncMessage = '同步空间已切换';
    });
    await _sync();
  }

  Future<void> _openAccountDialog({bool requireAccount = false}) async {
    final repository = await _repositoryFuture;
    if (!mounted) return;
    final emailController = TextEditingController(
      text: repository.currentUser?.email ?? '',
    );
    final passwordController = TextEditingController();
    var isBusy = false;
    String? errorText;

    Future<void> submit(
      BuildContext context,
      StateSetter setDialogState,
      Future<String?> Function(String email, String password) action,
    ) async {
      final email = emailController.text.trim();
      final password = passwordController.text;
      if (email.isEmpty || password.isEmpty) {
        setDialogState(() => errorText = '请输入邮箱和密码');
        return;
      }
      setDialogState(() {
        isBusy = true;
        errorText = null;
      });
      try {
        await action(email, password);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (error) {
        setDialogState(() {
          isBusy = false;
          errorText = '$error';
        });
      }
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: !requireAccount,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentUser = repository.currentUser;
          return AlertDialog(
            title: const Text('账户'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentUser != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle),
                      title: Text(currentUser.email ?? currentUser.id),
                      subtitle: const Text('当前账户'),
                    )
                  else ...[
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '邮箱'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                    ),
                  ],
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!requireAccount)
                TextButton(
                  onPressed: isBusy ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              if (currentUser != null)
                FilledButton.tonal(
                  onPressed: isBusy
                      ? null
                      : () async {
                          await repository.signOut();
                          if (context.mounted) Navigator.of(context).pop(true);
                        },
                  child: const Text('退出登录'),
                )
              else ...[
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () =>
                            submit(context, setDialogState, repository.signUp),
                  child: const Text('注册'),
                ),
                FilledButton(
                  onPressed: isBusy
                      ? null
                      : () =>
                            submit(context, setDialogState, repository.signIn),
                  child: const Text('登录'),
                ),
              ],
            ],
          );
        },
      ),
    );

    emailController.dispose();
    passwordController.dispose();
    if (changed != true) return;
    final latest = await repository.loadLocal();
    if (!mounted) return;
    setState(() {
      _tasks = latest;
      _accountLabel = _labelForRepository(repository);
      _syncMessage = repository.currentUser == null ? '已退出登录' : '已登录';
    });
    await _sync();
  }

  void _move(int delta) {
    setState(() {
      if (_mode == CalendarMode.month) {
        _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + delta);
      } else {
        _focusedDate = _focusedDate.add(Duration(days: delta * 7));
      }
    });
  }

  void _changeMode(CalendarMode mode) {
    if (mode == _mode) return;
    setState(() {
      if (_mode == CalendarMode.month && mode == CalendarMode.week) {
        _focusedDate = _weekFocusDateForCurrentMonth();
      }
      _mode = mode;
    });
  }

  DateTime _weekFocusDateForCurrentMonth() {
    final today = dateOnly(DateTime.now());
    if (today.year == _focusedDate.year && today.month == _focusedDate.month) {
      return today;
    }

    final monthTasks =
        _tasks
            .where(
              (task) =>
                  !task.isDeleted &&
                  task.startDate.year == _focusedDate.year &&
                  task.startDate.month == _focusedDate.month,
            )
            .toList()
          ..sort(_compareTaskPriority);
    if (monthTasks.isNotEmpty) {
      return monthTasks.first.startDate;
    }
    return _focusedDate;
  }

  Future<void> _openTaskSheet({DateTime? date, ScheduleTask? task}) async {
    if (date != null && !isSameDay(_focusedDate, date)) {
      setState(() => _focusedDate = dateOnly(date));
    }
    final saved = await showModalBottomSheet<ScheduleTask?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskEditorSheet(
        initialDate: date ?? _focusedDate,
        task: task,
        onDelete: task == null ? null : () => _deleteTask(task),
      ),
    );
    if (saved == null) return;
    final now = DateTime.now();
    final repository = await _repositoryFuture;
    final existingIndex = _tasks.indexWhere((task) => task.id == saved.id);
    final priority = saved.spansMultipleDays
        ? 0
        : existingIndex >= 0
        ? saved.priority
        : _nextPriorityForDate(saved.startDate);
    final normalized = saved.copyWith(
      updatedAt: now,
      deviceId: repository.deviceId,
      ownerId: repository.ownerId,
      userId: repository.currentUser?.id,
      priority: priority,
    );
    final next = [..._tasks];
    if (existingIndex >= 0) {
      next[existingIndex] = normalized;
    } else {
      next.add(normalized);
    }
    await _saveTasks(next);
  }

  Future<void> _openDayDetailSheet(DateTime date) async {
    final selectedDate = dateOnly(date);
    if (!isSameDay(_focusedDate, selectedDate)) {
      setState(() => _focusedDate = selectedDate);
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DayDetailSheet(
        date: selectedDate,
        tasks: _tasksForDate(selectedDate),
        onAdd: () {
          Navigator.of(sheetContext).pop();
          _openTaskSheet(date: selectedDate);
        },
        onTaskTap: (task) {
          Navigator.of(sheetContext).pop();
          _openTaskSheet(task: task);
        },
        onToggle: _toggleComplete,
      ),
    );
  }

  List<ScheduleTask> _tasksForDate(DateTime date) {
    final expandedTasks = _expandedTasksForRange(
      _tasks.where((task) => !task.isDeleted).toList(),
      date,
      date,
    );
    return expandedTasks
        .where(
          (task) => !_isOutsideRange(task.startDate, task.endDate, date, date),
        )
        .toList()
      ..sort((a, b) {
        if (a.spansMultipleDays != b.spansMultipleDays) {
          return a.spansMultipleDays ? -1 : 1;
        }
        return _compareTaskPriority(a, b);
      });
  }

  int _nextPriorityForDate(DateTime date) {
    final sameDayTasks = _tasks.where(
      (task) =>
          !task.isDeleted &&
          !task.spansMultipleDays &&
          isSameDay(task.startDate, date),
    );
    if (sameDayTasks.isEmpty) return 1;
    return sameDayTasks
            .map((task) => task.priority)
            .fold<int>(0, (max, value) => value > max ? value : max) +
        1;
  }

  List<ScheduleTask> _renumberTasksForDate(
    List<ScheduleTask> tasks,
    DateTime date,
    DateTime now,
    ScheduleRepository repository,
  ) {
    final sameDay =
        tasks
            .where(
              (task) =>
                  !task.isDeleted &&
                  !task.spansMultipleDays &&
                  isSameDay(task.startDate, date),
            )
            .toList()
          ..sort((a, b) {
            if (a.isCompleted != b.isCompleted) {
              return a.isCompleted ? 1 : -1;
            }
            return _compareTaskPriority(a, b);
          });

    final updatedById = <String, ScheduleTask>{};
    for (var i = 0; i < sameDay.length; i++) {
      updatedById[sameDay[i].id] = sameDay[i].copyWith(
        priority: i + 1,
        updatedAt: now,
        deviceId: repository.deviceId,
        ownerId: repository.ownerId,
        userId: repository.currentUser?.id,
      );
    }
    return tasks.map((task) => updatedById[task.id] ?? task).toList()
      ..sort(_compareTaskPriority);
  }

  Future<void> _reorderTask(ScheduleTask source, ScheduleTask target) async {
    if (source.recurrenceRule != RecurrenceRule.none) return;
    if (target.spansMultipleDays) return;
    final targetDate = dateOnly(target.startDate);
    if (source.spansMultipleDays) {
      await _moveTaskToDate(source, targetDate);
      return;
    }
    final duration = source.endDate.difference(source.startDate).inDays;
    final sourceWasSameDay = isSameDay(source.startDate, targetDate);
    final sameDay =
        _tasks
            .where(
              (task) =>
                  !task.isDeleted &&
                  !task.spansMultipleDays &&
                  isSameDay(task.startDate, targetDate) &&
                  task.id != source.id,
            )
            .toList()
          ..sort(_compareTaskPriority);
    final targetIndex = sameDay.indexWhere((task) => task.id == target.id);
    if (targetIndex < 0) return;
    final originalSameDay =
        _tasks
            .where(
              (task) =>
                  !task.isDeleted &&
                  !task.spansMultipleDays &&
                  isSameDay(task.startDate, targetDate),
            )
            .toList()
          ..sort(_compareTaskPriority);
    final originalSourceIndex = sourceWasSameDay
        ? originalSameDay.indexWhere((task) => task.id == source.id)
        : -1;
    final originalTargetIndex = originalSameDay.indexWhere(
      (task) => task.id == target.id,
    );
    final sourceWasBeforeTarget =
        originalSourceIndex >= 0 &&
        originalTargetIndex >= 0 &&
        originalSourceIndex < originalTargetIndex;

    final now = DateTime.now();
    final repository = await _repositoryFuture;
    final movedSource = source.copyWith(
      startDate: targetDate,
      endDate: targetDate.add(Duration(days: duration)),
      updatedAt: now,
      deviceId: repository.deviceId,
      ownerId: repository.ownerId,
      userId: repository.currentUser?.id,
    );
    final insertIndex = sourceWasBeforeTarget ? targetIndex + 1 : targetIndex;
    sameDay.insert(insertIndex.clamp(0, sameDay.length), movedSource);
    final updatedById = <String, ScheduleTask>{};
    for (var i = 0; i < sameDay.length; i++) {
      updatedById[sameDay[i].id] = sameDay[i].copyWith(
        priority: i + 1,
        updatedAt: now,
        deviceId: repository.deviceId,
        ownerId: repository.ownerId,
        userId: repository.currentUser?.id,
      );
    }
    final next = _tasks.map((task) => updatedById[task.id] ?? task).toList()
      ..sort(_compareTaskPriority);
    await _saveTasks(next);
  }

  Future<void> _moveTaskToDate(ScheduleTask source, DateTime date) async {
    if (source.recurrenceRule != RecurrenceRule.none) return;
    final targetDate = dateOnly(date);
    if (isSameDay(source.startDate, targetDate)) return;

    final now = DateTime.now();
    final repository = await _repositoryFuture;
    final duration = source.endDate.difference(source.startDate).inDays;
    final nextPriority = source.spansMultipleDays
        ? 0
        : _nextPriorityForDate(targetDate);
    final moved = source.copyWith(
      startDate: targetDate,
      endDate: targetDate.add(Duration(days: duration)),
      priority: nextPriority,
      updatedAt: now,
      deviceId: repository.deviceId,
      ownerId: repository.ownerId,
      userId: repository.currentUser?.id,
    );
    final next =
        _tasks.map((task) => task.id == source.id ? moved : task).toList()
          ..sort(_compareTaskPriority);
    await _saveTasks(next);
  }

  Future<void> _deleteTask(ScheduleTask task) async {
    final now = DateTime.now();
    final repository = await _repositoryFuture;
    final next = _tasks
        .map(
          (item) => item.id == task.id
              ? item.copyWith(
                  deletedAt: now,
                  updatedAt: now,
                  deviceId: repository.deviceId,
                )
              : item,
        )
        .toList();
    if (!mounted) return;
    Navigator.of(context).pop();
    await _saveTasks(next);
  }

  Future<void> _toggleComplete(ScheduleTask task) async {
    final now = DateTime.now();
    final repository = await _repositoryFuture;
    final toggled = _tasks
        .map(
          (item) => item.id == task.id
              ? item.copyWith(
                  isCompleted: !item.isCompleted,
                  updatedAt: now,
                  deviceId: repository.deviceId,
                )
              : item,
        )
        .toList();
    final next = task.spansMultipleDays
        ? toggled
        : _renumberTasksForDate(toggled, task.startDate, now, repository);
    await _saveTasks(next);
  }

  @override
  Widget build(BuildContext context) {
    final visibleTasks = _tasks.where((task) => !task.isDeleted).toList();
    final isCompact = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (!isCompact) const _SideRail(),
            Expanded(
              child: Column(
                children: [
                  _CalendarHeader(
                    focusedDate: _focusedDate,
                    mode: _mode,
                    isSyncing: _isSyncing,
                    syncMessage: _syncMessage,
                    accountLabel: _accountLabel,
                    onAdd: () => _openTaskSheet(date: _focusedDate),
                    onModeChanged: _changeMode,
                    onPrevious: () => _move(-1),
                    onToday: _goToday,
                    onNext: () => _move(1),
                    onSync: _sync,
                    onOwnerTap: _openSyncSpaceDialog,
                    onAccountTap: () => _openAccountDialog(),
                  ),
                  const _WeekdayHeader(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final calendarWidth = isCompact
                            ? constraints.maxWidth
                            : constraints.maxWidth < 720
                            ? 720.0
                            : constraints.maxWidth;
                        final board = SizedBox(
                          width: calendarWidth,
                          height: constraints.maxHeight,
                          child: CalendarBoard(
                            focusedDate: _focusedDate,
                            mode: _mode,
                            tasks: visibleTasks,
                            onDateTap: _openDayDetailSheet,
                            onTaskTap: (task) => _openTaskSheet(task: task),
                            onToggleComplete: _toggleComplete,
                            onReorderTask: _reorderTask,
                            onMoveTaskToDate: _moveTaskToDate,
                          ),
                        );
                        if (isCompact) return board;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: board,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.check_box,
      Icons.calendar_month,
      Icons.apps,
      Icons.radio_button_checked,
      Icons.schedule,
      Icons.search,
      Icons.sync,
      Icons.notifications,
      Icons.help,
    ];
    return Container(
      width: 58,
      color: const Color(0xfff6f6f7),
      child: Column(
        children: [
          const SizedBox(height: 18),
          const CircleAvatar(
            radius: 17,
            backgroundColor: Colors.white,
            child: Icon(Icons.event_note, color: Color(0xff4a6fff)),
          ),
          const SizedBox(height: 28),
          for (final icon in icons)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(
                icon,
                color: icon == Icons.calendar_month
                    ? const Color(0xff4a6fff)
                    : const Color(0xff9a9a9c),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.focusedDate,
    required this.mode,
    required this.isSyncing,
    required this.syncMessage,
    required this.accountLabel,
    required this.onAdd,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
    required this.onSync,
    required this.onOwnerTap,
    required this.onAccountTap,
  });

  final DateTime focusedDate;
  final CalendarMode mode;
  final bool isSyncing;
  final String syncMessage;
  final String accountLabel;
  final VoidCallback onAdd;
  final ValueChanged<CalendarMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;
  final VoidCallback onSync;
  final VoidCallback onOwnerTap;
  final VoidCallback onAccountTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCompact) ...[
              const Icon(Icons.view_sidebar_outlined, size: 30),
              const SizedBox(width: 14),
            ],
            Text(
              '${focusedDate.year}年${focusedDate.month}月',
              style: TextStyle(
                fontSize: isCompact ? 24 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$syncMessage · $accountLabel',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSyncing ? const Color(0xff4a6fff) : Colors.grey[600],
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '账户',
              onPressed: onAccountTap,
              icon: const Icon(Icons.account_circle),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '同步空间',
              onPressed: onOwnerTap,
              icon: const Icon(Icons.key),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '同步',
              onPressed: isSyncing ? null : onSync,
              icon: isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: '新增任务',
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 8),
            SegmentedButton<CalendarMode>(
              segments: const [
                ButtonSegment(value: CalendarMode.month, label: Text('月')),
                ButtonSegment(value: CalendarMode.week, label: Text('周')),
              ],
              selected: {mode},
              onSelectionChanged: (value) => onModeChanged(value.first),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: '上一页',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton(onPressed: onToday, child: const Text('今天')),
            IconButton.outlined(
              tooltip: '下一页',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        );
        final compactStatus = Text(
          '$syncMessage · $accountLabel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSyncing ? const Color(0xff4a6fff) : Colors.grey[600],
            fontSize: 12,
          ),
        );
        final compactPrimaryActions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CompactIconButton(
              tooltip: '账户',
              onPressed: onAccountTap,
              icon: Icons.account_circle,
              filled: true,
            ),
            _CompactIconButton(
              tooltip: '同步空间',
              onPressed: onOwnerTap,
              icon: Icons.key,
              filled: true,
            ),
            _CompactIconButton(
              tooltip: '同步',
              onPressed: isSyncing ? null : onSync,
              icon: Icons.sync,
              filled: true,
              isBusy: isSyncing,
            ),
            _CompactIconButton(
              tooltip: '新增任务',
              onPressed: onAdd,
              icon: Icons.add,
            ),
          ],
        );
        final compactNavigation = Row(
          children: [
            Expanded(
              child: SegmentedButton<CalendarMode>(
                segments: const [
                  ButtonSegment(value: CalendarMode.month, label: Text('月')),
                  ButtonSegment(value: CalendarMode.week, label: Text('周')),
                ],
                selected: {mode},
                onSelectionChanged: (value) => onModeChanged(value.first),
              ),
            ),
            const SizedBox(width: 6),
            _CompactIconButton(
              tooltip: '上一页',
              onPressed: onPrevious,
              icon: Icons.chevron_left,
            ),
            SizedBox(
              width: 58,
              height: 40,
              child: OutlinedButton(
                onPressed: onToday,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('今天'),
              ),
            ),
            _CompactIconButton(
              tooltip: '下一页',
              onPressed: onNext,
              icon: Icons.chevron_right,
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(12, isCompact ? 12 : 18, 12, 12),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: compactStatus),
                        const SizedBox(width: 8),
                        compactPrimaryActions,
                      ],
                    ),
                    const SizedBox(height: 8),
                    compactNavigation,
                  ],
                )
              : Row(children: [title, const Spacer(), controls]),
        );
      },
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.filled = false,
    this.isBusy = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool filled;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final child = isBusy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 21);
    final style = IconButton.styleFrom(
      fixedSize: const Size(40, 40),
      minimumSize: const Size(40, 40),
      padding: EdgeInsets.zero,
    );
    if (filled) {
      return IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        style: style,
        icon: child,
      );
    }
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      style: style,
      icon: child,
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xffededed))),
      ),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xff9c9c9c),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CalendarBoard extends StatelessWidget {
  const CalendarBoard({
    super.key,
    required this.focusedDate,
    required this.mode,
    required this.tasks,
    required this.onDateTap,
    required this.onTaskTap,
    required this.onToggleComplete,
    required this.onReorderTask,
    required this.onMoveTaskToDate,
  });

  final DateTime focusedDate;
  final CalendarMode mode;
  final List<ScheduleTask> tasks;
  final ValueChanged<DateTime> onDateTap;
  final ValueChanged<ScheduleTask> onTaskTap;
  final ValueChanged<ScheduleTask> onToggleComplete;
  final void Function(ScheduleTask source, ScheduleTask target) onReorderTask;
  final void Function(ScheduleTask source, DateTime date) onMoveTaskToDate;

  @override
  Widget build(BuildContext context) {
    final weeks = mode == CalendarMode.month
        ? _monthWeeks(focusedDate)
        : [_weekDates(focusedDate)];
    final rangeStart = weeks.first.first;
    final rangeEnd = weeks.last.last;
    final visibleTasks = _expandedTasksForRange(tasks, rangeStart, rangeEnd);
    return Column(
      children: [
        for (final week in weeks)
          Expanded(
            child: CalendarWeekRow(
              week: week,
              focusedMonth: focusedDate.month,
              tasks: visibleTasks,
              isMonthMode: mode == CalendarMode.month,
              onDateTap: onDateTap,
              onTaskTap: onTaskTap,
              onToggleComplete: onToggleComplete,
              onReorderTask: onReorderTask,
              onMoveTaskToDate: onMoveTaskToDate,
            ),
          ),
      ],
    );
  }
}

class CalendarWeekRow extends StatelessWidget {
  const CalendarWeekRow({
    super.key,
    required this.week,
    required this.focusedMonth,
    required this.tasks,
    required this.isMonthMode,
    required this.onDateTap,
    required this.onTaskTap,
    required this.onToggleComplete,
    required this.onReorderTask,
    required this.onMoveTaskToDate,
  });

  final List<DateTime> week;
  final int focusedMonth;
  final List<ScheduleTask> tasks;
  final bool isMonthMode;
  final ValueChanged<DateTime> onDateTap;
  final ValueChanged<ScheduleTask> onTaskTap;
  final ValueChanged<ScheduleTask> onToggleComplete;
  final void Function(ScheduleTask source, ScheduleTask target) onReorderTask;
  final void Function(ScheduleTask source, DateTime date) onMoveTaskToDate;

  @override
  Widget build(BuildContext context) {
    final multiDaySegments = _multiDaySegmentsForWeek(week, tasks);
    final dayTasks = _singleDayTasksForWeek(week, tasks);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        final dayTaskTop = 42 + _laneCount(multiDaySegments) * 28 + 4;
        return Stack(
          children: [
            Row(
              children: [
                for (final date in week)
                  Expanded(
                    child: _DayCell(
                      date: date,
                      isCurrentMonth: date.month == focusedMonth,
                      isToday: isSameDay(date, DateTime.now()),
                      onTap: () => onDateTap(date),
                      onAcceptTask: (task) => onMoveTaskToDate(task, date),
                    ),
                  ),
              ],
            ),
            for (var i = 0; i < multiDaySegments.length; i++)
              Positioned(
                left: multiDaySegments[i].startIndex * cellWidth + 6,
                top: 42 + multiDaySegments[i].lane * 28,
                width: multiDaySegments[i].dayCount * cellWidth - 12,
                height: 24,
                child: TaskBar(
                  task: multiDaySegments[i].task,
                  showNumber: false,
                  showEndTime: multiDaySegments[i].endsInThisWeek,
                  onTap: () => onTaskTap(multiDaySegments[i].task),
                  onToggle: () => onToggleComplete(multiDaySegments[i].task),
                ),
              ),
            for (var dayIndex = 0; dayIndex < week.length; dayIndex++)
              for (
                var taskIndex = 0;
                taskIndex < dayTasks[dayIndex].length;
                taskIndex++
              )
                Positioned(
                  left: dayIndex * cellWidth + 6,
                  top: dayTaskTop + taskIndex * 28,
                  width: cellWidth - 12,
                  height: 24,
                  child: TaskBar(
                    task: dayTasks[dayIndex][taskIndex],
                    number: taskIndex + 1,
                    showEndTime:
                        !dayTasks[dayIndex][taskIndex].isAllDay &&
                        dayTasks[dayIndex][taskIndex].endTime != null,
                    onTap: () => onTaskTap(dayTasks[dayIndex][taskIndex]),
                    onToggle: () =>
                        onToggleComplete(dayTasks[dayIndex][taskIndex]),
                    onReorder: (source) =>
                        onReorderTask(source, dayTasks[dayIndex][taskIndex]),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.onTap,
    required this.onAcceptTask,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final VoidCallback onTap;
  final ValueChanged<ScheduleTask> onAcceptTask;

  @override
  Widget build(BuildContext context) {
    final color = isCurrentMonth
        ? const Color(0xff202124)
        : const Color(0xffa6a6a6);
    return DragTarget<ScheduleTask>(
      onWillAcceptWithDetails: (details) =>
          details.data.recurrenceRule == RecurrenceRule.none &&
          !isSameDay(details.data.startDate, date),
      onAcceptWithDetails: (details) => onAcceptTask(details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        return InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: highlighted ? const Color(0xffeef3ff) : Colors.transparent,
              border: const Border(
                right: BorderSide(color: Color(0xffeeeeee)),
                bottom: BorderSide(color: Color(0xffeeeeee)),
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.topLeft,
              child: isToday
                  ? Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xff4a6fff),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      date.day == 1
                          ? '${date.month}月${date.day}日'
                          : '${date.day}',
                      style: TextStyle(
                        color: color,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class TaskBar extends StatelessWidget {
  const TaskBar({
    super.key,
    required this.task,
    required this.showEndTime,
    required this.onTap,
    required this.onToggle,
    this.number,
    this.showNumber = true,
    this.onReorder,
  });

  final ScheduleTask task;
  final int? number;
  final bool showNumber;
  final bool showEndTime;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final ValueChanged<ScheduleTask>? onReorder;

  @override
  Widget build(BuildContext context) {
    final isDone = task.isCompleted;
    final bar = Material(
      color: isDone ? const Color(0xffd8e1fb) : const Color(0xff8da6f8),
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            children: [
              GestureDetector(
                onTap: onToggle,
                child: Icon(
                  isDone ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 17,
                  color: isDone ? Colors.white70 : const Color(0xff395084),
                ),
              ),
              const SizedBox(width: 4),
              if (showNumber && number != null) ...[
                Text(
                  '$number.',
                  style: TextStyle(
                    color: isDone
                        ? const Color(0xff8d95a6)
                        : const Color(0xff273a68),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDone
                        ? const Color(0xff8d95a6)
                        : const Color(0xff273a68),
                    fontSize: 15,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (showEndTime && !task.isAllDay && task.endTime != null)
                Text(
                  task.endTime!.format(),
                  style: const TextStyle(
                    color: Color(0xff40527a),
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    Widget child = bar;
    if (onReorder != null) {
      child = DragTarget<ScheduleTask>(
        onWillAcceptWithDetails: (details) =>
            details.data.id != task.id &&
            details.data.recurrenceRule == RecurrenceRule.none &&
            task.recurrenceRule == RecurrenceRule.none,
        onAcceptWithDetails: (details) => onReorder!(details.data),
        builder: (context, candidateData, rejectedData) {
          final highlighted = candidateData.isNotEmpty;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: highlighted
                  ? Border.all(color: const Color(0xff2547e8), width: 2)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: bar,
          );
        },
      );
    }

    return LongPressDraggable<ScheduleTask>(
      data: task,
      feedback: SizedBox(
        width: 180,
        height: 24,
        child: Opacity(opacity: 0.85, child: bar),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );
  }
}

class DayDetailSheet extends StatefulWidget {
  const DayDetailSheet({
    super.key,
    required this.date,
    required this.tasks,
    required this.onAdd,
    required this.onTaskTap,
    required this.onToggle,
  });

  final DateTime date;
  final List<ScheduleTask> tasks;
  final VoidCallback onAdd;
  final ValueChanged<ScheduleTask> onTaskTap;
  final ValueChanged<ScheduleTask> onToggle;

  @override
  State<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<DayDetailSheet> {
  late List<ScheduleTask> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = [...widget.tasks];
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720, maxHeight: height * 0.78),
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(widget.date),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '当天任务',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton.outlined(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _tasks.isEmpty
                      ? Center(
                          child: Text(
                            '今天还没有任务',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                          itemCount: _tasks.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            return _DayTaskTile(
                              task: task,
                              number: task.spansMultipleDays
                                  ? null
                                  : _singleDayNumberFor(index),
                              onTap: () => widget.onTaskTap(task),
                              onToggle: () {
                                setState(() {
                                  _tasks[index] = task.copyWith(
                                    isCompleted: !task.isCompleted,
                                  );
                                });
                                widget.onToggle(task);
                              },
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: widget.onAdd,
                        icon: const Icon(Icons.add),
                        label: const Text('新增任务'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _singleDayNumberFor(int index) {
    var number = 0;
    for (var i = 0; i <= index; i++) {
      if (!_tasks[i].spansMultipleDays) number++;
    }
    return number;
  }
}

class _DayTaskTile extends StatelessWidget {
  const _DayTaskTile({
    required this.task,
    required this.number,
    required this.onTap,
    required this.onToggle,
  });

  final ScheduleTask task;
  final int? number;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isDone = task.isCompleted;
    final subtitle = <String>[
      if (task.spansMultipleDays)
        '${_formatDate(task.startDate)} - ${_formatDate(task.endDate)}',
      if (!task.isAllDay && task.startTime != null)
        [
          task.startTime!.format(),
          if (task.endTime != null) task.endTime!.format(),
        ].join(' - '),
      if (task.description != null && task.description!.isNotEmpty)
        task.description!,
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: IconButton(
        tooltip: isDone ? '标记未完成' : '完成任务',
        onPressed: onToggle,
        icon: Icon(
          isDone ? Icons.check_box : Icons.check_box_outline_blank,
          color: isDone ? const Color(0xff8d95a6) : const Color(0xff395084),
        ),
      ),
      title: Text(
        '${number == null ? '' : '$number. '}${task.title}',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isDone ? const Color(0xff8d95a6) : const Color(0xff202124),
          decoration: isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({
    super.key,
    required this.initialDate,
    this.task,
    this.onDelete,
  });

  final DateTime initialDate;
  final ScheduleTask? task;
  final VoidCallback? onDelete;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late DateTime _startDate;
  late DateTime _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  late bool _isAllDay;
  late RecurrenceRule _recurrenceRule;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    _startDate = task?.startDate ?? dateOnly(widget.initialDate);
    _endDate = task?.endDate ?? dateOnly(widget.initialDate);
    _startTime = task?.startTime == null
        ? null
        : TimeOfDay(
            hour: task!.startTime!.hour,
            minute: task.startTime!.minute,
          );
    _endTime = task?.endTime == null
        ? null
        : TimeOfDay(hour: task!.endTime!.hour, minute: task.endTime!.minute);
    _isAllDay = task?.isAllDay ?? true;
    _recurrenceRule = task?.recurrenceRule ?? RecurrenceRule.none;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = dateOnly(picked);
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = dateOnly(picked);
        if (_endDate.isBefore(_startDate)) _startDate = _endDate;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
          : (_endTime ?? const TimeOfDay(hour: 18, minute: 0)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
      _isAllDay = false;
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final now = DateTime.now();
    final existing = widget.task;
    final task = ScheduleTask(
      id: existing?.id ?? const Uuid().v4(),
      title: title,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      startTime: _isAllDay || _startTime == null
          ? null
          : TimeValue(_startTime!.hour, _startTime!.minute),
      endTime: _isAllDay || _endTime == null
          ? null
          : TimeValue(_endTime!.hour, _endTime!.minute),
      isAllDay: _isAllDay,
      isCompleted: existing?.isCompleted ?? false,
      recurrenceRule: _recurrenceRule,
      priority: existing?.priority ?? 0,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      deviceId: existing?.deviceId,
    );
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('日期')),
                      ButtonSegment(value: 1, label: Text('时间段')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (value) =>
                        setState(() => _tab = value.first),
                  ),
                  const SizedBox(height: 18),
                  _DateSummary(start: _startDate, end: _endDate),
                  const Divider(height: 30),
                  TextField(
                    controller: _titleController,
                    autofocus: widget.task == null,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: '准备做什么？',
                      border: InputBorder.none,
                    ),
                  ),
                  TextField(
                    controller: _descriptionController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '描述',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_tab == 0) _buildDateTab() else _buildTimeTab(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (widget.onDelete != null)
                        TextButton.icon(
                          onPressed: widget.onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('删除'),
                        ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(onPressed: _save, child: const Text('确定')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTab() {
    return Column(
      children: [
        _ResponsivePickerPair(
          first: _PickerTile(
            icon: Icons.sunny,
            label: '开始日期',
            value: _formatDate(_startDate),
            onTap: () => _pickDate(isStart: true),
          ),
          second: _PickerTile(
            icon: Icons.event_available,
            label: '结束日期',
            value: _formatDate(_endDate),
            onTap: () => _pickDate(isStart: false),
          ),
        ),
        SwitchListTile(
          value: _isAllDay,
          onChanged: (value) => setState(() => _isAllDay = value),
          title: const Text('全天'),
          contentPadding: EdgeInsets.zero,
        ),
        _RecurrenceTile(
          value: _recurrenceRule,
          onChanged: (value) => setState(() => _recurrenceRule = value),
        ),
      ],
    );
  }

  Widget _buildTimeTab() {
    return Column(
      children: [
        _ResponsivePickerPair(
          first: _PickerTile(
            icon: Icons.play_arrow,
            label: '开始',
            value: _formatDate(_startDate),
            onTap: () => _pickDate(isStart: true),
          ),
          second: _PickerTile(
            icon: Icons.schedule,
            label: '时间',
            value: _startTime?.format(context) ?? '选择',
            onTap: () => _pickTime(isStart: true),
          ),
        ),
        const SizedBox(height: 10),
        _ResponsivePickerPair(
          first: _PickerTile(
            icon: Icons.stop,
            label: '结束',
            value: _formatDate(_endDate),
            onTap: () => _pickDate(isStart: false),
          ),
          second: _PickerTile(
            icon: Icons.schedule,
            label: '时间',
            value: _endTime?.format(context) ?? '选择',
            onTap: () => _pickTime(isStart: false),
          ),
        ),
        SwitchListTile(
          value: _isAllDay,
          onChanged: (value) => setState(() => _isAllDay = value),
          title: const Text('全天'),
          contentPadding: EdgeInsets.zero,
        ),
        _RecurrenceTile(
          value: _recurrenceRule,
          onChanged: (value) => setState(() => _recurrenceRule = value),
        ),
        const _PickerTile(
          icon: Icons.public,
          label: '时区',
          value: 'Shanghai, GMT +8',
          onTap: null,
        ),
      ],
    );
  }
}

class _ResponsivePickerPair extends StatelessWidget {
  const _ResponsivePickerPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(children: [first, second]);
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _DateSummary extends StatelessWidget {
  const _DateSummary({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final days = end.difference(start).inDays + 1;
    final text = days <= 1
        ? '${start.month}月${start.day}日'
        : '${start.month}月${start.day}日，持续$days天';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xfff0f2f6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_month, size: 20, color: Color(0xff4a6fff)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xff4a6fff),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.grey[700]),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontSize: 16)),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _RecurrenceTile extends StatelessWidget {
  const _RecurrenceTile({required this.value, required this.onChanged});

  final RecurrenceRule value;
  final ValueChanged<RecurrenceRule> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.repeat, color: Colors.grey[700]),
      title: const Text('重复'),
      trailing: DropdownButton<RecurrenceRule>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final rule in RecurrenceRule.values)
            DropdownMenuItem(value: rule, child: Text(rule.label)),
        ],
        onChanged: (rule) {
          if (rule != null) onChanged(rule);
        },
      ),
    );
  }
}

class _TaskSegment {
  const _TaskSegment({
    required this.task,
    required this.startIndex,
    required this.dayCount,
    required this.lane,
    required this.endsInThisWeek,
  });

  final ScheduleTask task;
  final int startIndex;
  final int dayCount;
  final int lane;
  final bool endsInThisWeek;

  int get endIndex => startIndex + dayCount - 1;
}

List<_TaskSegment> _multiDaySegmentsForWeek(
  List<DateTime> week,
  List<ScheduleTask> tasks,
) {
  final weekStart = week.first;
  final weekEnd = week.last;
  final candidates = <_TaskSegment>[];
  for (final task in tasks.where((task) => task.spansMultipleDays)) {
    if (task.endDate.isBefore(weekStart) || task.startDate.isAfter(weekEnd)) {
      continue;
    }
    final visibleStart = task.startDate.isBefore(weekStart)
        ? weekStart
        : task.startDate;
    final visibleEnd = task.endDate.isAfter(weekEnd) ? weekEnd : task.endDate;
    final startIndex = visibleStart.difference(weekStart).inDays;
    final dayCount = visibleEnd.difference(visibleStart).inDays + 1;
    candidates.add(
      _TaskSegment(
        task: task,
        startIndex: startIndex,
        dayCount: dayCount,
        lane: 0,
        endsInThisWeek: isSameDay(visibleEnd, task.endDate),
      ),
    );
  }
  candidates.sort((a, b) {
    final byStart = a.startIndex.compareTo(b.startIndex);
    if (byStart != 0) return byStart;
    return b.dayCount.compareTo(a.dayCount);
  });

  const maxLanes = 5;
  final laneSegments = List.generate(maxLanes, (_) => <_TaskSegment>[]);
  final placed = <_TaskSegment>[];
  for (final candidate in candidates) {
    for (var lane = 0; lane < maxLanes; lane++) {
      final canUseLane = laneSegments[lane].every(
        (existing) => !_segmentsOverlap(candidate, existing),
      );
      if (!canUseLane) continue;
      final placedSegment = _TaskSegment(
        task: candidate.task,
        startIndex: candidate.startIndex,
        dayCount: candidate.dayCount,
        lane: lane,
        endsInThisWeek: candidate.endsInThisWeek,
      );
      laneSegments[lane].add(placedSegment);
      placed.add(placedSegment);
      break;
    }
  }
  return placed..sort((a, b) => a.lane.compareTo(b.lane));
}

bool _segmentsOverlap(_TaskSegment a, _TaskSegment b) {
  return a.startIndex <= b.endIndex && b.startIndex <= a.endIndex;
}

int _laneCount(List<_TaskSegment> segments) {
  if (segments.isEmpty) return 0;
  return segments
          .map((segment) => segment.lane)
          .reduce((a, b) => a > b ? a : b) +
      1;
}

List<List<ScheduleTask>> _singleDayTasksForWeek(
  List<DateTime> week,
  List<ScheduleTask> tasks,
) {
  return [
    for (final date in week)
      (tasks
          .where(
            (task) =>
                !task.spansMultipleDays && isSameDay(task.startDate, date),
          )
          .toList()
        ..sort(_compareTaskPriority)),
  ];
}

int _compareTaskPriority(ScheduleTask a, ScheduleTask b) {
  final aPriority = a.priority <= 0 ? 999999 : a.priority;
  final bPriority = b.priority <= 0 ? 999999 : b.priority;
  final byPriority = aPriority.compareTo(bPriority);
  if (byPriority != 0) return byPriority;
  final byDate = a.startDate.compareTo(b.startDate);
  if (byDate != 0) return byDate;
  return a.createdAt.compareTo(b.createdAt);
}

List<ScheduleTask> _expandedTasksForRange(
  List<ScheduleTask> tasks,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final expanded = <ScheduleTask>[];
  for (final task in tasks) {
    if (task.recurrenceRule == RecurrenceRule.none) {
      if (!_isOutsideRange(
        task.startDate,
        task.endDate,
        rangeStart,
        rangeEnd,
      )) {
        expanded.add(task);
      }
      continue;
    }
    expanded.addAll(_recurringOccurrencesForRange(task, rangeStart, rangeEnd));
  }
  return expanded;
}

List<ScheduleTask> _recurringOccurrencesForRange(
  ScheduleTask task,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final duration = task.endDate.difference(task.startDate).inDays;
  final occurrences = <ScheduleTask>[];
  DateTime currentStart;

  switch (task.recurrenceRule) {
    case RecurrenceRule.none:
      return [task];
    case RecurrenceRule.daily:
      currentStart = task.startDate;
      final missedDays = rangeStart.difference(task.endDate).inDays;
      if (missedDays > 0) {
        currentStart = currentStart.add(Duration(days: missedDays));
      }
      while (!currentStart.isAfter(rangeEnd)) {
        final currentEnd = currentStart.add(Duration(days: duration));
        if (!_isOutsideRange(currentStart, currentEnd, rangeStart, rangeEnd)) {
          occurrences.add(
            task.copyWith(startDate: currentStart, endDate: currentEnd),
          );
        }
        currentStart = currentStart.add(const Duration(days: 1));
      }
      break;
    case RecurrenceRule.monthly:
      currentStart = task.startDate;
      var monthOffset = 0;
      while (currentStart.isBefore(rangeStart) &&
          currentStart.add(Duration(days: duration)).isBefore(rangeStart)) {
        monthOffset++;
        currentStart = _shiftDateByMonths(task.startDate, monthOffset);
      }
      while (!currentStart.isAfter(rangeEnd)) {
        final currentEnd = currentStart.add(Duration(days: duration));
        if (!_isOutsideRange(currentStart, currentEnd, rangeStart, rangeEnd)) {
          occurrences.add(
            task.copyWith(startDate: currentStart, endDate: currentEnd),
          );
        }
        monthOffset++;
        currentStart = _shiftDateByMonths(task.startDate, monthOffset);
      }
      break;
    case RecurrenceRule.yearly:
      currentStart = task.startDate;
      var yearOffset = 0;
      while (currentStart.isBefore(rangeStart) &&
          currentStart.add(Duration(days: duration)).isBefore(rangeStart)) {
        yearOffset++;
        currentStart = _shiftDateByMonths(task.startDate, yearOffset * 12);
      }
      while (!currentStart.isAfter(rangeEnd)) {
        final currentEnd = currentStart.add(Duration(days: duration));
        if (!_isOutsideRange(currentStart, currentEnd, rangeStart, rangeEnd)) {
          occurrences.add(
            task.copyWith(startDate: currentStart, endDate: currentEnd),
          );
        }
        yearOffset++;
        currentStart = _shiftDateByMonths(task.startDate, yearOffset * 12);
      }
      break;
  }
  return occurrences;
}

bool _isOutsideRange(
  DateTime startDate,
  DateTime endDate,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  return endDate.isBefore(rangeStart) || startDate.isAfter(rangeEnd);
}

DateTime _shiftDateByMonths(DateTime date, int months) {
  final shiftedMonth = date.month + months;
  final targetMonthFirst = DateTime(date.year, shiftedMonth);
  final lastDay = DateTime(
    targetMonthFirst.year,
    targetMonthFirst.month + 1,
    0,
  ).day;
  return DateTime(
    targetMonthFirst.year,
    targetMonthFirst.month,
    date.day > lastDay ? lastDay : date.day,
  );
}

List<List<DateTime>> _monthWeeks(DateTime focusedDate) {
  final firstOfMonth = DateTime(focusedDate.year, focusedDate.month);
  final lastOfMonth = DateTime(focusedDate.year, focusedDate.month + 1, 0);
  final start = firstOfMonth.subtract(Duration(days: firstOfMonth.weekday % 7));
  final end = lastOfMonth.add(Duration(days: 6 - (lastOfMonth.weekday % 7)));
  final days = end.difference(start).inDays + 1;
  return [
    for (var i = 0; i < days; i += 7)
      [for (var d = 0; d < 7; d++) start.add(Duration(days: i + d))],
  ];
}

List<DateTime> _weekDates(DateTime date) {
  final start = dateOnly(date).subtract(Duration(days: date.weekday % 7));
  return [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
}

String _formatDate(DateTime date) => '${date.month}月${date.day}日';
