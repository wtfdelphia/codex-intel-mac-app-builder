# CLAUDE.md

本文件为在本文档目录中工作的 Claude Code (claude.ai/code) 提供指导。

## 项目概述

本项目将官方 Apple Silicon 架构的 `Codex.dmg` 重建为兼容 Intel 处理器的 macOS 应用程序。通过提取原始应用资源、创建 x86_64 架构的 Electron 运行时、重新编译原生模块，最终生成已签名的 Intel 应用包。

## 常用命令

### 构建流程
```bash
# 环境检查
./scripts/doctor.sh

# 构建 Intel 应用（DMG 在项目根目录或显式指定路径）
./scripts/build.sh [path/to/Codex.dmg] [codex_package_version]

# 安装到 /Applications
./scripts/install-built-app.sh

# 打开应用
./scripts/open-app.sh

# 更新（一步完成重建 + 安装）
./scripts/update.sh [path/to/Codex.dmg]
```

### 快捷 .command 文件（Finder 双击运行）
- `build-intel-app.command` - 执行构建
- `install-intel-app.command` - 安装到 /Applications
- `open-intel-app.command` - 打开已安装的应用
- `update-intel-app.command` - 重建并安装
- `doctor.command` - 环境检查

### 环境变量
- `CODEX_PACKAGE_VERSION` - 覆盖 @openai/codex 版本
- `CODEX_KEEP_WORKDIR=1` - 保留临时构建目录
- `ELECTRON_MIRROR` - Electron 下载镜像（中国大陆用户推荐使用淘宝镜像）

## 架构说明

### 脚本结构

**`scripts/common.sh`** - 共享工具和环境配置
- `ensure_macos_toolchain()` - 验证 Xcode CLI 工具和 SDK 可用性
- `export_macos_toolchain()` - 设置 SDKROOT、CC、CXX、CFLAGS 用于原生编译
- `plist_get()` - 使用 PlistBuddy/plutil 读取 plist 键值
- `resolve_input_dmg()` - 自动发现 Codex.dmg 位置
- 路径常量：`PROJECT_DIR`、`DIST_DIR`、`TMP_DIR`、`LOG_DIR`

**`scripts/build.sh`** - 主要构建编排
1. 挂载官方 DMG 并复制 Codex.app
2. 从 `app.asar` 提取元数据（package.json、原生模块版本）
3. 从应用依赖或 bundle 版本解析 @openai/codex 版本
4. 创建带有 x86_64 Electron 运行时的全新构建项目
5. 通过 @electron/rebuild 重新编译原生模块（better-sqlite3、node-pty）
6. 将原始资源移植到新的 Electron 外壳中
7. 用重新编译的 x86_64 版本替换原生二进制文件
8. 用 x86_64 版本替换捆绑的 codex/rg CLI 二进制文件
9. 禁用 sparkle.node（不兼容的内置更新器）
10. Ad-hoc 签名并打包为 DMG

**`scripts/install-built-app.sh`** - 将构建的应用复制到 /Applications
**`scripts/open-app.sh`** - 启动已安装的应用
**`scripts/doctor.sh`** - 验证环境先决条件

### 关键构建产物
- `dist/Codex Intel.app` - 最终 Intel 应用包
- `dist/CodexAppMacIntel.dmg` - 可分发的 DMG
- `dist/build-info.txt` - 构建元数据（版本、源 DMG、时间戳）
- `logs/build_<timestamp>.log` - 详细构建日志
- `.tmp/build_<timestamp>/` - 临时工作目录（自动清理，除非设置 KEEP_WORKDIR=1）

### 原生模块处理

构建过程重新编译两个关键的原生模块：
- **better-sqlite3** - 用于本地数据存储的 SQLite 绑定
- **node-pty** - 用于 CLI 进程生成的伪终端

重新编译后的二进制文件位置：
```
node_modules/better-sqlite3/build/Release/better_sqlite3.node
node_modules/node-pty/build/Release/pty.node
node_modules/node-pty/build/Release/spawn-helper
```

### 版本解析逻辑

构建过程从多个来源提取版本信息：
1. `app.asar/package.json` - 应用的 @openai/codex 依赖规范
2. `app.asar/package.json` - 应用的 version 字段
3. `Info.plist` - CFBundleShortVersionString（bundle 版本）
4. Electron framework `Info.plist` - CFBundleVersion（Electron 版本）

版本解析顺序：显式覆盖 → 应用依赖规范 → bundle 版本 → 回退标签（native/latest）

### 代码流依赖

```
build.sh
  └─> common.sh (ensure_macos_toolchain, export_macos_toolchain)
  └─> resolve_input_dmg()
  └─> extract_asar_file() - 使用 @electron/asar
  └─> resolve_codex_package_version() - npm view 查询
  └─> @electron/rebuild - 原生模块重新编译
  └─> codesign - Ad-hoc 签名
  └─> hdiutil - DMG 创建
```

## 关键构建约束

- 所有输出二进制文件必须是 x86_64 架构（通过 `file` 命令验证）
- 必须设置 `ELECTRON_RENDERER_URL` plist 键用于 renderer 引导
- 必须移除 sparkle.node（因更新器不兼容会在 Intel 上崩溃）
- 原生二进制文件从 build-project 复制到 app.asar.unpacked
- 构建日志记录完整的版本解析链以便调试

## 常见问题

### 网络超时错误

**症状**: `ETIMEDOUT` 或 `socket hang up` 错误

**原因**: Electron 二进制文件从 GitHub 下载，中国大陆地区网络可能不稳定

**解决方案**: 设置淘宝镜像
```bash
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ \
npm_config_electron_mirror=https://npmmirror.com/mirrors/electron/ \
./scripts/build.sh [path/to/Codex.dmg]
```

### DMG 挂载失败

**症状**: `hdiutil: attach failed - 资源忙`

**原因**: 之前的构建会话未正确卸载 DMG

**解决方案**:
```bash
hdiutil detach -force /dev/diskX  # X 为挂载的磁盘编号
```
