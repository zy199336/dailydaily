const api = require('./utils/api');

App({
  globalData: {
    token: wx.getStorageSync('daily_token') || '',
    openid: wx.getStorageSync('daily_openid') || '',
    linked: wx.getStorageSync('daily_linked') || false,
    email: wx.getStorageSync('daily_email') || '',
  },

  async ensureLogin() {
    if (this.globalData.token) return this.globalData.token;

    const loginResult = await withTimeout(new Promise((resolve, reject) => {
      wx.login({
        success: resolve,
        fail(error) {
          reject(new Error(`微信登录失败：${error?.errMsg || 'unknown'}`));
        },
      });
    }), 15000, '微信登录超时');

    if (!loginResult.code) {
      throw new Error('微信登录失败');
    }

    const response = await api.wechatLogin(loginResult.code);
    if (!response.ok || !response.token) {
      throw new Error(response.errmsg || '后端登录失败');
    }

    this.globalData.token = response.token;
    this.globalData.openid = response.openid || '';
    this.globalData.linked = Boolean(response.linked);
    this.globalData.email = response.email || '';
    wx.setStorageSync('daily_token', response.token);
    wx.setStorageSync('daily_openid', response.openid || '');
    wx.setStorageSync('daily_linked', Boolean(response.linked));
    wx.setStorageSync('daily_email', response.email || '');
    return response.token;
  },

  applyAuth(response) {
    if (!response?.token) return;
    this.globalData.token = response.token;
    this.globalData.openid = response.openid || this.globalData.openid;
    this.globalData.linked = Boolean(response.linked);
    this.globalData.email = response.email || '';
    wx.setStorageSync('daily_token', this.globalData.token);
    wx.setStorageSync('daily_openid', this.globalData.openid);
    wx.setStorageSync('daily_linked', this.globalData.linked);
    wx.setStorageSync('daily_email', this.globalData.email);
  },

  applyAccount(account) {
    if (!account) return;
    this.globalData.linked = Boolean(account.linked);
    this.globalData.email = account.email || '';
    wx.setStorageSync('daily_linked', this.globalData.linked);
    wx.setStorageSync('daily_email', this.globalData.email);
  },

  logout() {
    this.globalData.token = '';
    this.globalData.openid = '';
    this.globalData.linked = false;
    this.globalData.email = '';
    wx.removeStorageSync('daily_token');
    wx.removeStorageSync('daily_openid');
    wx.removeStorageSync('daily_linked');
    wx.removeStorageSync('daily_email');
  },
});

function withTimeout(promise, timeoutMs, message) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
