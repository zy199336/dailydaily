const api = require('../../utils/api');
const dateUtil = require('../../utils/date');

const recurrenceOptions = [
  { label: '不重复', value: 'none' },
  { label: '每天重复', value: 'daily' },
  { label: '每月重复', value: 'monthly' },
  { label: '每年重复', value: 'yearly' },
];
const sortRowHeight = 118;

Page({
  localEditVersion: 0,
  pendingSyncCount: 0,
  syncStatusTimer: null,

  data: {
    title: '',
    viewMode: 'month',
    currentDate: '',
    selectedDate: '',
    syncText: '准备同步',
    days: [],
    weekDays: [],
    tasks: [],
    selectedSpanningTasks: [],
    selectedDayTasks: [],
    showDayPanel: false,
    showTaskForm: false,
    showAccountPanel: false,
    accountRequired: false,
    accountEmail: '',
    accountPassword: '',
    accountText: '微信独立空间',
    sortMode: false,
    draggingTaskId: '',
    draggingIndex: -1,
    dragStartY: 0,
    sortDirty: false,
    recurrenceLabels: recurrenceOptions.map((item) => item.label),
    recurrenceIndex: 0,
    form: emptyForm(dateUtil.formatDate(new Date())),
  },

  async onLoad() {
    const today = dateUtil.formatDate(new Date());
    this.setData({
      currentDate: today,
      selectedDate: today,
    });
    this.rebuildCalendar();
    await this.loginAndSync();
    this.requireAccountIfNeeded();
  },

  async onPullDownRefresh() {
    await this.syncFromServer();
    wx.stopPullDownRefresh();
  },

  onUnload() {
    if (this.syncStatusTimer) clearTimeout(this.syncStatusTimer);
    this.syncStatusTimer = null;
  },

  async loginAndSync() {
    wx.showLoading({ title: '同步中' });
    try {
      await getApp().ensureLogin();
      this.refreshAccountText();
      await this.syncFromServer();
      this.requireAccountIfNeeded();
    } catch (error) {
      this.setData({ syncText: '同步失败' });
      wx.showToast({ title: error.message || '同步失败', icon: 'none' });
    } finally {
      wx.hideLoading();
    }
  },

  async syncFromServer() {
    const syncVersion = this.localEditVersion;
    const response = await api.listTasks();
    getApp().applyAccount(response.account);
    const tasks = (response.tasks || []).map(normalizeRemoteTask);
    if (this.localEditVersion !== syncVersion) {
      this.setData({ syncText: '本地修改已保存，等待同步' });
      this.refreshAccountText();
      return;
    }
    this.setData({
      tasks,
      syncText: `同步完成 · ${tasks.length}项`,
    });
    this.refreshAccountText();
    this.rebuildCalendar();
  },

  refreshAccountText() {
    const app = getApp();
    const email = app.globalData.email;
    this.setData({
      accountText: app.globalData.linked && email ? email : '微信独立空间',
    });
  },

  openAccountPanel() {
    const app = getApp();
    this.setData({
      showAccountPanel: true,
      accountRequired: false,
      accountEmail: app.globalData.email || '',
      accountPassword: '',
    });
  },

  requireAccountIfNeeded() {
    const app = getApp();
    if (app.globalData.linked && app.globalData.email) return;
    this.setData({
      showAccountPanel: true,
      accountRequired: true,
      accountEmail: app.globalData.email || '',
      accountPassword: '',
    });
  },

  closeAccountPanel() {
    if (this.data.accountRequired) {
      wx.showToast({ title: '请先登录/绑定账户', icon: 'none' });
      return;
    }
    this.setData({ showAccountPanel: false, accountPassword: '' });
  },

  onAccountInput(event) {
    const field = event.currentTarget.dataset.field;
    this.setData({ [field]: event.detail.value });
  },

  async submitAccountLink() {
    await this.submitAccount(api.linkEmail, '已切换到邮箱账户');
  },

  async submitAccountRegister() {
    await this.submitAccount(api.registerEmail, '已注册并切换到账户');
  },

  async submitAccount(action, successText) {
    const email = this.data.accountEmail.trim();
    const password = this.data.accountPassword;
    if (!email || !password) {
      wx.showToast({ title: '请输入邮箱和密码', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '绑定中' });
    try {
      await getApp().ensureLogin();
      const response = await action(email, password);
      getApp().applyAuth(response);
      this.setData({
        showAccountPanel: false,
        accountRequired: false,
        accountPassword: '',
      });
      this.refreshAccountText();
      await this.syncFromServer();
      wx.showToast({ title: successText, icon: 'none' });
    } catch (error) {
      wx.showToast({ title: error.message || '账户处理失败', icon: 'none' });
    } finally {
      wx.hideLoading();
    }
  },

  setMonthView() {
    this.setData({ viewMode: 'month' });
    this.rebuildCalendar();
  },

  setWeekView() {
    this.setData({ viewMode: 'week' });
    this.rebuildCalendar();
  },

  goToday() {
    const today = dateUtil.formatDate(new Date());
    this.setData({
      currentDate: today,
      selectedDate: today,
    });
    this.rebuildCalendar();
  },

  goPrevious() {
    const current = dateUtil.toDate(this.data.currentDate);
    const next =
      this.data.viewMode === 'month'
        ? new Date(current.getFullYear(), current.getMonth() - 1, 1)
        : dateUtil.addDays(current, -7);
    this.setData({ currentDate: dateUtil.formatDate(next) });
    this.rebuildCalendar();
  },

  goNext() {
    const current = dateUtil.toDate(this.data.currentDate);
    const next =
      this.data.viewMode === 'month'
        ? new Date(current.getFullYear(), current.getMonth() + 1, 1)
        : dateUtil.addDays(current, 7);
    this.setData({ currentDate: dateUtil.formatDate(next) });
    this.rebuildCalendar();
  },

  openDayDetail(event) {
    const selectedDate = event.currentTarget.dataset.date;
    this.setData({
      selectedDate,
      showDayPanel: true,
    });
    this.rebuildSelectedTasks();
    this.rebuildCalendar();
  },

  closeDayPanel() {
    this.setData({ showDayPanel: false, sortMode: false });
  },

  openCreateForm() {
    this.setData({
      form: emptyForm(this.data.selectedDate || dateUtil.formatDate(new Date())),
      recurrenceIndex: 0,
      showTaskForm: true,
    });
  },

  openEditForm(event) {
    const id = event.currentTarget.dataset.id;
    const task = this.data.tasks.find((item) => item.id === id);
    if (!task) return;
    const recurrenceIndex = Math.max(
      0,
      recurrenceOptions.findIndex((item) => item.value === task.recurrenceRule),
    );
    this.setData({
      form: { ...task },
      recurrenceIndex,
      showTaskForm: true,
    });
  },

  closeTaskForm() {
    this.setData({ showTaskForm: false });
  },

  onFormInput(event) {
    const field = event.currentTarget.dataset.field;
    this.setData({ [`form.${field}`]: event.detail.value });
  },

  onStartDateChange(event) {
    const startDate = event.detail.value;
    const endDate =
      this.data.form.endDate < startDate ? startDate : this.data.form.endDate;
    this.setData({
      'form.startDate': startDate,
      'form.endDate': endDate,
    });
  },

  onEndDateChange(event) {
    this.setData({ 'form.endDate': event.detail.value });
  },

  onAllDayChange(event) {
    this.setData({ 'form.isAllDay': event.detail.value });
  },

  onStartTimeChange(event) {
    this.setData({ 'form.startTime': event.detail.value });
  },

  onEndTimeChange(event) {
    this.setData({ 'form.endTime': event.detail.value });
  },

  onRecurrenceChange(event) {
    const index = Number(event.detail.value);
    this.setData({
      recurrenceIndex: index,
      'form.recurrenceRule': recurrenceOptions[index].value,
    });
  },

  async submitTask() {
    const form = this.data.form;
    if (!form.title.trim()) {
      wx.showToast({ title: '请输入任务名称', icon: 'none' });
      return;
    }
    if (form.endDate < form.startDate) {
      wx.showToast({ title: '结束日期不能早于开始日期', icon: 'none' });
      return;
    }

    const now = new Date().toISOString();
    const priority = form.id ? form.priority : this.nextPriority(form.startDate);
    const task = {
      ...form,
      id: form.id || createLocalId(),
      title: form.title.trim(),
      description: form.description.trim(),
      priority,
      createdAt: form.createdAt || now,
      updatedAt: now,
    };
    const editVersion = this.applyLocalTasks(
      upsertTask(this.data.tasks, task),
      '本地已保存，正在同步',
    );
    this.setData({
      selectedDate: task.startDate,
      showTaskForm: false,
      showDayPanel: true,
    });

    try {
      const response = await api.saveTask(toApiTask(task));
      const savedTask = normalizeRemoteTask(response.task);
      this.applyRemoteTask(savedTask, editVersion, '同步完成', task.id);
    } catch (error) {
      this.finishSyncFailure(editVersion, '本地已保存，云端同步失败');
      wx.showToast({ title: error.message || '本地已保存，云端同步失败', icon: 'none' });
    }
  },

  async toggleCompleted(event) {
    const id = event.currentTarget.dataset.id;
    const task = this.data.tasks.find((item) => item.id === id);
    if (!task) return;
    const now = new Date().toISOString();
    const nextTask = { ...task, isCompleted: !task.isCompleted, updatedAt: now };
    const tasks = isMultiDay(task)
      ? upsertTask(this.data.tasks, nextTask)
      : renumberTasksForDate(upsertTask(this.data.tasks, nextTask), task.startDate, now);
    const editVersion = this.applyLocalTasks(tasks, '本地已保存，正在同步');
    try {
      const changedTasks = tasks.filter(
        (item) =>
          !isMultiDay(item) &&
          item.startDate === task.startDate &&
          item.recurrenceRule === 'none',
      );
      const responses = await Promise.all(
        changedTasks.map((item) => api.saveTask(toApiTask(item))),
      );
      if (this.localEditVersion !== editVersion) {
        this.finishSyncSuccess(editVersion, '同步完成');
        return;
      }
      let syncedTasks = this.data.tasks;
      responses.forEach((response) => {
        syncedTasks = upsertTask(syncedTasks, normalizeRemoteTask(response.task));
      });
      this.setData({ tasks: syncedTasks });
      this.rebuildCalendar();
      this.finishSyncSuccess(editVersion, '同步完成');
    } catch (error) {
      this.finishSyncFailure(editVersion, '本地已保存，云端同步失败');
      wx.showToast({ title: error.message || '本地已保存，云端同步失败', icon: 'none' });
    }
  },

  enterSortMode() {
    if (this.data.selectedDayTasks.length < 2) return;
    this.setData({
      sortMode: true,
    });
    wx.showToast({ title: '长按排序已开启', icon: 'none' });
  },

  exitSortMode() {
    this.setData({
      sortMode: false,
      draggingTaskId: '',
      draggingIndex: -1,
      dragStartY: 0,
      sortDirty: false,
    });
  },

  onSortDragStart(event) {
    const index = Number(event.currentTarget.dataset.index);
    const touch = event.touches?.[0];
    this.setData({
      draggingTaskId: event.currentTarget.dataset.id,
      draggingIndex: index,
      dragStartY: touch ? touch.clientY : 0,
      sortDirty: false,
    });
  },

  onSortDragMove(event) {
    if (!this.data.sortMode || this.data.draggingIndex < 0) return;
    const touch = event.touches?.[0];
    if (!touch) return;
    const delta = touch.clientY - this.data.dragStartY;
    if (Math.abs(delta) < sortRowHeight / 2) return;

    const direction = delta > 0 ? 1 : -1;
    const currentIndex = this.data.draggingIndex;
    const targetIndex = currentIndex + direction;
    const dayTasks = this.data.selectedDayTasks.slice();
    if (targetIndex < 0 || targetIndex >= dayTasks.length) return;

    const [moved] = dayTasks.splice(currentIndex, 1);
    dayTasks.splice(targetIndex, 0, moved);

    this.setData({
      selectedDayTasks: dayTasks.map((task, index) => ({
        ...task,
        numberLabel: `${index + 1}.`,
        priority: index + 1,
      })),
      draggingIndex: targetIndex,
      dragStartY: touch.clientY,
      sortDirty: true,
    });
  },

  async onSortDragEnd() {
    if (!this.data.sortDirty) {
      this.setData({ draggingTaskId: '', draggingIndex: -1, dragStartY: 0 });
      return;
    }
    await this.saveSortedTasks(this.data.selectedDayTasks);
  },

  async movePriority(event) {
    const id = event.currentTarget.dataset.id;
    const direction = Number(event.currentTarget.dataset.direction);
    const dayTasks = this.data.selectedDayTasks;
    const index = dayTasks.findIndex((item) => item.id === id);
    const targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= dayTasks.length) return;

    const current = dayTasks[index];
    const target = dayTasks[targetIndex];
    await this.saveTwoTasks(
      { ...current, priority: target.priority },
      { ...target, priority: current.priority },
    );
  },

  confirmDelete(event) {
    const id = event.currentTarget.dataset.id;
    wx.showModal({
      title: '删除任务',
      content: '确定删除这个任务吗？',
      success: async (result) => {
        if (!result.confirm) return;
        const previousTasks = this.data.tasks;
        const editVersion = this.applyLocalTasks(
          previousTasks.filter((task) => task.id !== id),
          '本地已删除，正在同步',
        );
        try {
          await api.deleteTask(id);
          this.finishSyncSuccess(editVersion, '同步完成');
        } catch (error) {
          this.finishSyncFailure(editVersion, '本地已删除，云端同步失败');
          wx.showToast({ title: error.message || '本地已删除，云端同步失败', icon: 'none' });
        }
      },
    });
  },

  async saveExistingTask(task) {
    const nextTask = {
      ...task,
      updatedAt: new Date().toISOString(),
    };
    const editVersion = this.applyLocalTasks(
      upsertTask(this.data.tasks, nextTask),
      '本地已保存，正在同步',
    );
    try {
      const response = await api.saveTask(toApiTask(nextTask));
      this.applyRemoteTask(
        normalizeRemoteTask(response.task),
        editVersion,
        '同步完成',
        nextTask.id,
      );
    } catch (error) {
      this.finishSyncFailure(editVersion, '本地已保存，云端同步失败');
      wx.showToast({ title: error.message || '本地已保存，云端同步失败', icon: 'none' });
    }
  },

  async saveTwoTasks(first, second) {
    const now = new Date().toISOString();
    const nextFirst = { ...first, updatedAt: now };
    const nextSecond = { ...second, updatedAt: now };
    const editVersion = this.applyLocalTasks(
      upsertTask(upsertTask(this.data.tasks, nextFirst), nextSecond),
      '本地排序已保存，正在同步',
    );
    try {
      const firstResponse = await api.saveTask(toApiTask(nextFirst));
      const secondResponse = await api.saveTask(toApiTask(nextSecond));
      if (this.localEditVersion !== editVersion) {
        this.finishSyncSuccess(editVersion, '同步完成');
        return;
      }
      let tasks = mergeRemoteTask(
        this.data.tasks,
        normalizeRemoteTask(firstResponse.task),
        nextFirst.id,
      );
      tasks = mergeRemoteTask(
        tasks,
        normalizeRemoteTask(secondResponse.task),
        nextSecond.id,
      );
      this.setData({ tasks });
      this.rebuildCalendar();
      this.finishSyncSuccess(editVersion, '同步完成');
    } catch (error) {
      this.finishSyncFailure(editVersion, '本地排序已保存，云端同步失败');
      wx.showToast({ title: error.message || '本地排序已保存，云端同步失败', icon: 'none' });
    }
  },

  async saveSortedTasks(dayTasks) {
    const now = new Date().toISOString();
    const reordered = dayTasks.map((task, index) => ({
      ...task,
      priority: index + 1,
      updatedAt: now,
    }));
    let localTasks = this.data.tasks;
    reordered.forEach((task) => {
      localTasks = upsertTask(localTasks, task);
    });
    const editVersion = this.applyLocalTasks(localTasks, '本地排序已保存，正在同步');
    this.setData({
      draggingTaskId: '',
      draggingIndex: -1,
      dragStartY: 0,
      sortDirty: false,
    });
    try {
      const responses = await Promise.all(
        reordered.map((task) => api.saveTask(toApiTask(task))),
      );
      if (this.localEditVersion !== editVersion) {
        this.finishSyncSuccess(editVersion, '同步完成');
        return;
      }
      let tasks = this.data.tasks;
      responses.forEach((response, index) => {
        tasks = mergeRemoteTask(
          tasks,
          normalizeRemoteTask(response.task),
          reordered[index].id,
        );
      });
      this.setData({
        tasks,
        draggingTaskId: '',
        draggingIndex: -1,
        dragStartY: 0,
        sortDirty: false,
      });
      this.rebuildCalendar();
      this.finishSyncSuccess(editVersion, '同步完成');
    } catch (error) {
      this.finishSyncFailure(editVersion, '本地排序已保存，云端同步失败');
      wx.showToast({ title: error.message || '本地排序已保存，云端同步失败', icon: 'none' });
    }
  },

  applyLocalTasks(tasks, syncText) {
    this.localEditVersion += 1;
    this.pendingSyncCount += 1;
    this.setData({ tasks, syncText });
    this.rebuildCalendar();
    this.scheduleSyncStatusFallback(this.localEditVersion);
    return this.localEditVersion;
  },

  applyRemoteTask(task, editVersion, syncText, localId) {
    if (this.localEditVersion !== editVersion) {
      this.finishSyncSuccess(editVersion, syncText);
      return;
    }
    const tasks = mergeRemoteTask(this.data.tasks, task, localId);
    this.setData({ tasks });
    this.rebuildCalendar();
    this.finishSyncSuccess(editVersion, syncText);
  },

  finishSyncSuccess(editVersion, syncText) {
    this.pendingSyncCount = Math.max(0, this.pendingSyncCount - 1);
    this.clearSyncStatusFallbackIfIdle();
    if (
      editVersion === this.localEditVersion ||
      (this.pendingSyncCount === 0 && isSyncingText(this.data.syncText))
    ) {
      this.setData({ syncText });
    }
  },

  finishSyncFailure(editVersion, syncText) {
    this.pendingSyncCount = Math.max(0, this.pendingSyncCount - 1);
    this.clearSyncStatusFallbackIfIdle();
    if (editVersion === this.localEditVersion || this.pendingSyncCount === 0) {
      this.setData({ syncText });
    }
  },

  scheduleSyncStatusFallback(editVersion) {
    if (this.syncStatusTimer) clearTimeout(this.syncStatusTimer);
    this.syncStatusTimer = setTimeout(() => {
      if (
        editVersion === this.localEditVersion &&
        this.pendingSyncCount > 0 &&
        isSyncingText(this.data.syncText)
      ) {
        this.pendingSyncCount = 0;
        this.syncStatusTimer = null;
        this.setData({ syncText: '本地已保存' });
      }
    }, 8000);
  },

  clearSyncStatusFallbackIfIdle() {
    if (this.pendingSyncCount > 0 || !this.syncStatusTimer) return;
    clearTimeout(this.syncStatusTimer);
    this.syncStatusTimer = null;
  },

  nextPriority(date) {
    const tasks = this.data.tasks.filter(
      (task) =>
        !isMultiDay(task) &&
        task.startDate === date &&
        task.recurrenceRule === 'none',
    );
    return tasks.length + 1;
  },

  rebuildCalendar() {
    const current = dateUtil.toDate(this.data.currentDate);
    const isMonthView = this.data.viewMode === 'month';
    const dates =
      isMonthView
        ? dateUtil.monthGrid(current)
        : mondayWeekGrid(current);
    const currentMonth = current.getMonth();
    const selectedDate = this.data.selectedDate;
    const today = dateUtil.formatDate(new Date());
    const days = dates.map((date) => {
      const formatted = dateUtil.formatDate(date);
      const tasks = this.tasksForDate(formatted);
      return {
        date: formatted,
        dayLabel: labelForDay(date),
        weekName: weekNameForDate(date),
        dateLabel: `${date.getMonth() + 1}/${date.getDate()}`,
        isCurrentMonth: date.getMonth() === currentMonth,
        isToday: formatted === today,
        isSelected: formatted === selectedDate,
        visibleTasks: tasks.slice(0, 4),
        moreCount: Math.max(0, tasks.length - 4),
      };
    });

    this.setData({
      title: dateUtil.titleFor(current),
      days,
      weekDays: isMonthView ? [] : days,
    });
    this.rebuildSelectedTasks();
  },

  rebuildSelectedTasks() {
    const tasks = this.tasksForDate(this.data.selectedDate);
    const selectedDayTasks = tasks.filter((task) => !task.isSpanning);
    this.setData({
      selectedSpanningTasks: tasks.filter((task) => task.isSpanning),
      selectedDayTasks,
    });
  },

  tasksForDate(date) {
    const tasks = this.data.tasks
      .filter((task) => occursOn(task, date))
      .map((task) => ({
        ...task,
        isSpanning: isMultiDay(task),
        numberLabel: isMultiDay(task) ? '' : `${task.priority || 1}.`,
        recurrenceLabel: recurrenceLabel(task.recurrenceRule),
        timeLabel: task.isAllDay ? '全天' : `${task.startTime}-${task.endTime}`,
      }));

    const spanning = tasks
      .filter((task) => task.isSpanning)
      .sort((a, b) => a.startDate.localeCompare(b.startDate));
    const singleDay = tasks
      .filter((task) => !task.isSpanning)
      .sort((a, b) => (a.priority || 0) - (b.priority || 0));

    return [...spanning, ...renumber(singleDay)];
  },
});

function emptyForm(date) {
  return {
    id: '',
    title: '',
    description: '',
    startDate: date,
    endDate: date,
    startTime: '09:00',
    endTime: '10:00',
    isAllDay: true,
    isCompleted: false,
    recurrenceRule: 'none',
    priority: 0,
  };
}

function createLocalId() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (char) => {
    const random = Math.floor(Math.random() * 16);
    const value = char === 'x' ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

function normalizeRemoteTask(task) {
  return {
    id: task.id,
    title: task.title || '',
    description: task.description || '',
    startDate: task.start_date || task.startDate,
    endDate: task.end_date || task.endDate || task.start_date || task.startDate,
    startTime: task.start_time || task.startTime || '09:00',
    endTime: task.end_time || task.endTime || '10:00',
    isAllDay: task.is_all_day ?? task.isAllDay ?? true,
    isCompleted: task.is_completed ?? task.isCompleted ?? false,
    recurrenceRule: task.recurrence_rule || task.recurrenceRule || 'none',
    priority: Number(task.priority || 0),
    createdAt: task.created_at || task.createdAt || new Date().toISOString(),
    updatedAt: task.updated_at || task.updatedAt || new Date().toISOString(),
  };
}

function toApiTask(task) {
  return {
    id: task.id || undefined,
    title: task.title,
    description: task.description,
    startDate: task.startDate,
    endDate: task.endDate,
    startTime: task.isAllDay ? null : task.startTime,
    endTime: task.isAllDay ? null : task.endTime,
    isAllDay: task.isAllDay,
    isCompleted: task.isCompleted,
    recurrenceRule: task.recurrenceRule,
    priority: task.priority,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
  };
}

function occursOn(task, date) {
  if (task.recurrenceRule === 'daily') {
    return date >= task.startDate;
  }

  if (task.recurrenceRule === 'monthly') {
    if (date < task.startDate) return false;
    return dateUtil.toDate(date).getDate() === dateUtil.toDate(task.startDate).getDate();
  }

  if (task.recurrenceRule === 'yearly') {
    if (date < task.startDate) return false;
    const target = dateUtil.toDate(date);
    const start = dateUtil.toDate(task.startDate);
    return target.getMonth() === start.getMonth() && target.getDate() === start.getDate();
  }

  return dateUtil.isBetween(date, task.startDate, task.endDate);
}

function isMultiDay(task) {
  return task.startDate !== task.endDate;
}

function isSyncingText(value) {
  const text = String(value || '');
  return text.includes('正在同步') || text.includes('等待同步');
}

function renumber(tasks) {
  return tasks.map((task, index) => ({
    ...task,
    priority: task.priority || index + 1,
    numberLabel: `${index + 1}.`,
  }));
}

function upsertTask(tasks, task) {
  const index = tasks.findIndex((item) => item.id === task.id);
  if (index < 0) return [...tasks, task];
  const next = tasks.slice();
  next[index] = task;
  return next;
}

function mergeRemoteTask(tasks, task, localId) {
  const next =
    localId && localId !== task.id
      ? tasks.filter((item) => item.id !== localId)
      : tasks;
  return upsertTask(next, task);
}

function renumberTasksForDate(tasks, date, updatedAt) {
  const sameDay = tasks
    .filter(
      (task) =>
        !isMultiDay(task) &&
        task.startDate === date &&
        task.recurrenceRule === 'none',
    )
    .sort((a, b) => {
      if (a.isCompleted !== b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return (a.priority || 0) - (b.priority || 0);
    })
    .map((task, index) => ({
      ...task,
      priority: index + 1,
      updatedAt,
    }));
  let next = tasks;
  sameDay.forEach((task) => {
    next = upsertTask(next, task);
  });
  return next;
}

function labelForDay(date) {
  if (date.getDate() === 1) {
    return `${date.getMonth() + 1}月1日`;
  }
  return String(date.getDate());
}

function recurrenceLabel(value) {
  const option = recurrenceOptions.find((item) => item.value === value);
  return option ? option.label : '不重复';
}

function mondayWeekGrid(date) {
  const target = dateUtil.toDate(date);
  const day = target.getDay();
  const mondayOffset = day === 0 ? -6 : 1 - day;
  const monday = dateUtil.addDays(target, mondayOffset);
  return Array.from({ length: 7 }, (_, index) => dateUtil.addDays(monday, index));
}

function weekNameForDate(date) {
  return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][date.getDay()];
}
