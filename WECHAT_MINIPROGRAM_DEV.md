# 微信小程序开发说明

## 工程位置

小程序工程目录：

```text
C:\Users\yzhen\Downloads\Daily\wechat-miniprogram
```

在微信开发者工具中选择“导入项目”，目录选上面的 `wechat-miniprogram`，AppID 已写入 `project.config.json`。

## 开发阶段请求地址

当前小程序临时请求：

```text
http://8.130.81.36
```

备案未完成前，在微信开发者工具中勾选“不校验合法域名、web-view 域名、TLS 版本以及 HTTPS 证书”后调试。

备案通过后，把 `miniprogram/utils/api.js` 里的 `BASE_URL` 改成：

```text
https://api.dailydaily.top
```

并在微信公众平台后台把 `https://api.dailydaily.top` 加到 request 合法域名。

## 后端接口

服务器使用 PM2 托管：

```text
daily-api
```

健康检查：

```text
http://8.130.81.36/health
```

主要接口：

- `POST /auth/wechat-login`
- `GET /tasks`
- `POST /tasks`
- `PATCH /tasks/:id`
- `DELETE /tasks/:id`
- `POST /sync`

## 安全提醒

AppSecret 只配置在服务器 `/opt/daily-api/.env`，不要写进小程序前端。由于开发时已经在对话中提供过 AppSecret，正式发布前建议在微信公众平台重置一次 Secret，然后更新服务器 `.env` 并重启 `daily-api`。
