const BASE_URL = 'https://api.dailydaily.top';

function request(path, options = {}) {
  const app = getApp();
  const headers = {
    'content-type': 'application/json',
    ...(options.headers || {}),
  };

  if (app?.globalData?.token) {
    headers.Authorization = `Bearer ${app.globalData.token}`;
  }

  return new Promise((resolve, reject) => {
    wx.request({
      url: `${BASE_URL}${path}`,
      method: options.method || 'GET',
      data: options.data || {},
      header: headers,
      timeout: options.timeout || 20000,
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(res.data);
          return;
        }
        reject(new Error(res.data?.error || `HTTP ${res.statusCode}`));
      },
      fail(error) {
        const message = error?.errMsg || error?.message || 'request failed';
        reject(new Error(`${path} 请求失败：${message}`));
      },
    });
  });
}

function wechatLogin(code) {
  return request('/auth/wechat-login', {
    method: 'POST',
    data: { code },
  });
}

function linkEmail(email, password) {
  return request('/auth/link-email', {
    method: 'POST',
    data: { email, password },
  });
}

function registerEmail(email, password) {
  return request('/auth/register-link-email', {
    method: 'POST',
    data: { email, password },
  });
}

function listTasks() {
  return request('/tasks');
}

function saveTask(task) {
  return request('/tasks', {
    method: 'POST',
    data: { task },
  });
}

function deleteTask(id) {
  return request(`/tasks/${id}`, {
    method: 'DELETE',
  });
}

function syncTasks(tasks) {
  return request('/sync', {
    method: 'POST',
    data: { tasks },
  });
}

module.exports = {
  BASE_URL,
  deleteTask,
  linkEmail,
  listTasks,
  registerEmail,
  saveTask,
  syncTasks,
  wechatLogin,
};
