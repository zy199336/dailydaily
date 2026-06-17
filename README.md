# DailyDaily / 日日程

DailyDaily is a cross-platform calendar task app for Windows, Android, and WeChat Mini Program. It supports account-based sync through Supabase and an optional Aliyun-hosted API backup.

DailyDaily 是一个跨 Windows、Android 和微信小程序的日历任务应用。它支持通过 Supabase 进行账号同步，并通过部署在阿里云上的 API 做辅助备份。

## Features / 功能

- Month and week calendar views.
- Create, edit, delete, complete, and reorder tasks.
- Drag tasks between dates on Flutter clients.
- Drag onto a target task to move across dates and insert at that position.
- Completed single-day tasks automatically move to the end of that day and priorities are renumbered.
- Multi-day tasks render as continuous bars across calendar cells.
- Recurring tasks support daily, monthly, and yearly recurrence.
- Local-first edits: local UI and storage update immediately, then sync in the background.
- Account login/register dialog is shown on startup when no account is available.
- Supabase account sync plus Aliyun API backup.

- 支持月视图和周视图。
- 支持新建、编辑、删除、完成和排序任务。
- Flutter 客户端支持跨日期拖动任务。
- 拖到某一天的某个任务上时，会移动到该日期并插入到该任务位置。
- 单日任务完成后会自动移动到当天末尾，并重新编号优先级。
- 跨天任务会在日历格中显示为连续条。
- 支持每天、每月、每年重复任务。
- 本地优先编辑：界面和本地存储立即更新，后台再同步。
- 启动时如果没有账号信息，会直接弹出登录/注册界面。
- 支持 Supabase 账号同步和阿里云 API 备份。

## Platforms / 平台

- Windows desktop: Flutter Windows.
- Android: Flutter APK.
- WeChat Mini Program: `wechat-miniprogram/`.
- Backend API: `server/daily-api/`.

- Windows 桌面端：Flutter Windows。
- Android 端：Flutter APK。
- 微信小程序：`wechat-miniprogram/`。
- 后端 API：`server/daily-api/`。

## Sync Architecture / 同步架构

The Flutter app stores data locally first, then syncs to:

- Supabase table: `public.daily_schedule_tasks`
- Aliyun API base URL: `http://8.130.81.36/daily-api`

Local edits are pushed with local priority. This prevents old cloud data from overwriting a task that was just completed, moved, or reordered locally.

Flutter 应用会先写入本地，再同步到：

- Supabase 表：`public.daily_schedule_tasks`
- 阿里云 API 地址：`http://8.130.81.36/daily-api`

本地编辑会以本地为优先进行推送，避免旧云端数据覆盖刚完成、移动或排序的任务。

## Repository Layout / 目录结构

```text
android/                  Flutter Android project
lib/                      Flutter app source code
server/daily-api/         Node/Fastify API for WeChat and Aliyun backup
test/                     Flutter unit/widget tests
wechat-miniprogram/       WeChat Mini Program project
windows/                  Flutter Windows project
supabase_daily_schedule.sql
```

```text
android/                  Flutter Android 工程
lib/                      Flutter 应用源码
server/daily-api/         Node/Fastify API，用于微信和阿里云备份
test/                     Flutter 单元测试和组件测试
wechat-miniprogram/       微信小程序工程
windows/                  Flutter Windows 工程
supabase_daily_schedule.sql
```

## Setup / 初始化

Install Flutter and ensure Windows and Android build toolchains are available.

安装 Flutter，并确保 Windows 和 Android 构建工具链可用。

```powershell
flutter pub get
flutter analyze
flutter test
```

Before using Supabase sync, run the SQL in `supabase_daily_schedule.sql` in the Supabase SQL editor. More details are in `SUPABASE_SETUP.md`.

使用 Supabase 同步前，请在 Supabase SQL Editor 中执行 `supabase_daily_schedule.sql`。详细说明见 `SUPABASE_SETUP.md`。

## Run Locally / 本地运行

Windows:

```powershell
flutter run -d windows
```

Android:

```powershell
flutter run -d android
```

WeChat Mini Program:

Import `wechat-miniprogram/` in WeChat DevTools.

微信小程序：

在微信开发者工具中导入 `wechat-miniprogram/`。

## Build / 构建

Windows:

```powershell
flutter build windows
```

Output:

```text
build\windows\x64\runner\Release\daily_schedule.exe
```

Android APK:

```powershell
flutter build apk --release
```

Output:

```text
build\app\outputs\flutter-apk\app-release.apk
```

## Backend / 后端

The backend service is in `server/daily-api/`.

后端服务位于 `server/daily-api/`。

```powershell
cd server\daily-api
npm install
npm start
```

Required environment variables:

必需环境变量：

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
WECHAT_APPID
WECHAT_SECRET
TOKEN_SECRET
PORT
```

Main endpoints:

主要接口：

- `GET /health`
- `POST /auth/wechat-login`
- `POST /auth/link-email`
- `POST /auth/register-link-email`
- `GET /tasks`
- `POST /tasks`
- `PATCH /tasks/:id`
- `DELETE /tasks/:id`
- `POST /sync`

## Release Artifacts / 发布产物

Release artifacts are not committed to git. Build outputs such as APK and Windows binaries should be uploaded to GitHub Releases.

发布产物不提交到 git。APK 和 Windows 二进制文件应上传到 GitHub Releases。

## Security Notes / 安全说明

- Do not commit `.pem` keys, local server logs, `.env` files, or WeChat private project configs.
- The repository `.gitignore` excludes local key files such as `*.pem`.
- If a secret was ever committed by mistake, rotate it immediately.

- 不要提交 `.pem` 密钥、本地服务器日志、`.env` 文件或微信本地私有配置。
- 仓库 `.gitignore` 已排除 `*.pem` 等本地密钥文件。
- 如果密钥曾被误提交，请立即重置。

## License / 许可证

Private project unless a license is added later.

未添加许可证前，本项目按私有项目处理。
