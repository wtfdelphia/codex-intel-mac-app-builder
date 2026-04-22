# Codex Intel Mac App Builder

本项目旨在将官方的 `Codex.dmg` 重建为一个兼容 Intel 处理器的 macOS 应用程序包。

这是一个针对 Intel MacBook Pro 机器的非官方兼容工作流。核心思路是：

- 使用官方 Codex 应用程序作为来源
- 保留原始的应用程序资源
- 针对 `x86_64` 架构重新编译 Electron 运行时和原生模块
- 生成一个在本地签名的 Intel 版应用程序和 DMG 文件

## 本项目的功能

- 将官方 `Codex.dmg` 转换为 `Codex Intel.app`
- 将重建后的应用程序安装到 `/Applications`（应用程序目录）
- 打开重建后的应用程序
- 在官方发布更新后，再次重建该应用程序
- 在开始之前运行环境检查

## 为什么会有这个项目

如果官方的 Codex macOS 客户端仅发布适用于 Apple Silicon (M芯片) 的版本，Intel Mac 将无法直接运行它。本项目围绕官方应用程序资源重新构建了运行环境，从而使该客户端能够在 Intel 硬件上运行。

## 重要限制

- 这是非官方的项目
- 重建后的应用程序中禁用了内置的客户端自动更新功能
- 当 OpenAI 发布新的官方 `Codex.dmg` 时，您需要再次进行重建
- 重建后的应用程序是在本地进行 Ad-hoc 签名的，因此 macOS 在首次运行时可能仍会显示安全提示

## 环境要求

- macOS 操作系统
- 主要是针对 Intel Mac 设备
- `bash`、`hdiutil`、`ditto`、`codesign`、`xattr`、`file`
- Node.js 和 npm
- 构建期间需要网络连接
- 手动从 OpenAI 下载的官方 `Codex.dmg` 文件

## 项目结构

- `scripts/build.sh`
  将官方应用程序重建为 Intel 应用程序包和 DMG 文件。
- `scripts/install-built-app.sh`
  将重建后的应用程序复制到 `/Applications/Codex Intel.app` 目录。
- `scripts/open-app.sh`
  打开已安装的 Intel 应用程序。
- `scripts/update.sh`
  在您下载了较新的官方 DMG 后，重新构建并重新安装 Intel 应用程序。
- `scripts/doctor.sh`
  检查本机环境、工具链和项目输出。

## 快速开始

1. 将官方的 `Codex.dmg` 放在此项目文件夹旁边，或者明确传递其文件路径。
2. 在您的 Mac 上运行以下命令：

```sh
cd /path/to/codex-intel-mac-app-builder
chmod +x scripts/*.sh *.command
./scripts/doctor.sh
./scripts/build.sh /absolute/path/to/Codex.dmg
./scripts/install-built-app.sh
./scripts/open-app.sh
```

### 网络问题解决方案

如果构建过程中遇到 Electron 下载超时（`ETIMEDOUT` 或 `socket hang up`），请设置镜像源：

```sh
# 使用淘宝镜像（推荐中国大陆用户）
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ \
npm_config_electron_mirror=https://npmmirror.com/mirrors/electron/ \
./scripts/build.sh /absolute/path/to/Codex.dmg
```

其他镜像源：
- 官方镜像（默认）：`https://electronjs.org/`
- 阿里云镜像：`https://npm.taobao.org/mirrors/electron/`

## 更新流程

当新的官方 Codex 应用程序发布时：

1. 下载新的官方 `Codex.dmg`
2. 替换旧的 DMG 文件
3. 运行如下命令：

```sh
./scripts/update.sh /absolute/path/to/Codex.dmg
```

## 版本匹配

构建器会尝试从 `app.asar` 中读取源应用程序元数据，并安装匹配的 `@openai/codex` 软件包版本，而不是直接使用 `latest` 最新版本。

如果版本自动检测失败，您可以手动覆盖它：

```sh
CODEX_PACKAGE_VERSION=0.111.0 ./scripts/build.sh /absolute/path/to/Codex.dmg
```

或者：

```sh
./scripts/build.sh /absolute/path/to/Codex.dmg 0.111.0
```

## 输出产物

构建成功后：

- `dist/Codex Intel.app`
- `dist/CodexAppMacIntel.dmg`
- `dist/build-info.txt`
- `logs/build_<timestamp>.log`

## Finder 访达快捷入口

- `build-intel-app.command`
- `install-intel-app.command`
- `open-intel-app.command`
- `update-intel-app.command`
- `doctor.command`
