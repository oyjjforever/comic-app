# Comic Reader 移动端

基于 Flutter 的漫画/视频阅读客户端，通过局域网连接 Electron 版 [comic-reader](../3.electron/comic-reader) 服务器（默认端口 9527），支持手机、平板与 Android TV。

## 功能特性

### 连接
- **全自动连接**：优先直连上次成功的服务器（2s 快速探测），失败自动扫描局域网（桌面 mDNS / Android 子网扫描）并连接第一台发现的服务器，全程无需手动输入
- 断线重试一键操作

### 漫画
- 多数据源目录树（懒加载，服务器配置的全部资源路径都显示为树根）
- 树顶"已收藏"分组（folder tags，与桌面端实时同步）、树节点书签标记、长按收藏目录
- 收藏 / 浏览历史 / 下载历史视图，本地搜索过滤
- 沉浸式阅读器：左右翻页、双指缩放、进度条、前后预加载；支持键盘/遥控器翻页

### 视频
- 多数据源目录树（含叶子目录）
- 视频卡片显示 `1080p · 时长`（ffprobe 元数据）
- **封面两级获取**：服务器 ffmpeg 封面优先（`/api/video-cover`，支持桌面端自定义帧，If-Modified-Since 304 校验更新）→ 客户端 media_kit 解码生成回退（240px JPEG，内存/磁盘双缓存）
- 播放器：倍速、±10s、全屏、音量/进度遥控器操作、屏幕常亮、拖动不卡顿（seek 合并）

### 适配
- 深色主题（Electron 版设计语言：紫灰面板 + 橙色强调 `#FF9205`）
- 响应式布局：手机（底部导航+抽屉树） / 平板竖屏（可收起侧栏） / 平板横屏与 TV（常驻侧栏，≥840dp，网格自适应列数）
- **Android TV / D-pad**：全焦点导航（橙色描边+放大高亮），leanback launcher 图标，遥控器按键全覆盖（方向键移动、OK 确认、菜单键操作）

## 服务端要求

连接的 Electron comic-reader 需包含以下 HTTP API（均为本项目配套新增）：

| 接口 | 说明 |
|---|---|
| `GET /api/server/info` | 返回 `resourcePaths[]` / `videoResourcePaths[]` 多数据源数组 |
| `GET /api/browse/tree?includeLeaf=` | 目录树（视频模块传 true 含叶子） |
| `GET /api/video-cover?path=` | 视频 ffmpeg 封面（缓存命中含自定义帧优先；响应头 `X-Video-Width/Height/Duration` 元数据；支持 If-Modified-Since） |
| `GET/POST/DELETE /api/tags/folders*` | 目录收藏（folder tags，树顶分组数据源，与桌面端共用 `database.db`） |

旧版服务器可运行：客户端探测到 404 自动回退（单数据源、本地生成封面、无收藏分组）。

## 构建

```bash
# 依赖
flutter pub get

# 调试运行（需连接设备）
flutter run

# Release APK
flutter build apk --release

# 图标
dart run flutter_launcher_icons
```

Android 权限：局域网（`INTERNET` / `NEARBY_WIFI_DEVICES` / `ACCESS_FINE_LOCATION`）、APK 自更新（`REQUEST_INSTALL_PACKAGES`）。TV 支持通过 `LEANBACK_LAUNCHER` + leanback feature 声明。

## 技术栈

| 领域 | 选型 |
|---|---|
| 状态管理 | Provider（`AppState` 单源，watch/select 分级订阅） |
| 网络 | http（统一 15s 超时 + 友好错误） |
| 图片 | cached_network_image（`memCacheWidth` 限制解码内存） |
| 阅读器 | photo_view（缩放）+ PageView（翻页/预加载） |
| 视频 | media_kit（libmpv；缩略图 Player 池 ×2、播放器局域网预读调优） |
| 自更新 | GitHub Release 检测 + dio 下载安装（频率限制/跳过版本） |

## 项目结构

```
lib/
├── core/
│   ├── models/          # ServerInfo / FolderInfo / FileInfo / FolderTag ...
│   ├── network/         # ApiClient（超时收口）、ServerDiscovery（mDNS/子网扫描）
│   ├── services/        # VideoThumbnailService（封面两级+缓存）、更新、下载
│   ├── state/           # AppState（浏览/收藏/树/多数据源）
│   ├── theme/           # 深色主题（AppColors / buildAppTheme）
│   └── widgets/         # MediaCard（焦点高亮）、responsive 断点
└── features/
    ├── discovery/       # 自动连接页
    ├── home/            # 底部导航 / NavigationRail 骨架
    ├── browser/         # 漫画浏览 + 目录树（folder tags 分组）
    ├── video/           # 视频浏览 + 播放器
    ├── reader/          # 漫画阅读器
    └── settings/        # 设置（连接信息/更新/缓存）
```

## 已知说明

- 服务器（Electron 端）修改 `src/server/` 后需重启 `npm run dev`（electron-vite 不自动重启 main 进程）
- 视频封面磁盘缓存在客户端 `video-covers/`（md5 键 + 版本盐），封面策略升级会自动失效旧缓存
- 局域网信任模型：API 未做资源路径越权校验（与桌面端一致），请勿暴露公网
