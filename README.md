<div align="center">

# Folio

**为日常使用打磨的个人 NixOS 桌面。**

![NixOS](assets/badges/nixos.svg)
![Home Manager](assets/badges/home-manager.svg)
![Niri](assets/badges/niri.svg)
[![MIT 许可证](assets/badges/license.svg)](LICENSE)

[项目演进](#项目演进) · [核心特点](#核心特点) · [桌面环境](#桌面环境) · [当前局限](#当前局限) · [参考资料](#参考资料)

</div>

[![Folio 桌面预览：Everforest 深色主题下的 Btop、Yazi 与 Foot 终端](assets/screenshots/everforest-dark-desktop.png)](assets/screenshots/everforest-dark-desktop.png)

<p align="center"><sub>Everforest 深色 · Niri · Foot · Yazi · Btop<br>截图摄于 2026-10-22，使用 Maple Mono NF CN 字体。点击图片查看原图。</sub></p>

Folio 是我日常使用的 NixOS 与独立 Home Manager 配置，面向 `x86_64-linux`。
这个仓库记录了我的桌面选型、使用习惯，以及持续调整中的取舍，供参考和按需借鉴。

## 项目演进

**最初 · 单文件配置**：所有设置都写在一个 Nix 文件里。起步简单，内容增多后，查找和维护逐渐变得困难。

**Koru · 每个应用一个文件**：[Koru](https://github.com/WallyHao/koru-nixos-dotfiles) 是我的第一次模块化尝试。目录更清晰了，但复杂应用的配置仍会积累成一个大文件。

**Sylphy · 每个应用一个小项目**：配置、脚本和资源各有归属，也有了更严格的维护约定。不过，添加模块的成本越来越高，我最终放弃了这个项目。

**Folio · 重新寻找平衡**：保留清晰、一致的维护约定，把更多精力放在统一外观、工具搭配和日常操作上，逐步完善命令行与本地控制面板。

## 核心特点

| 特点 | 日常使用 |
| --- | --- |
| **统一外观** | 一次选择主题，桌面、终端与受管理应用使用一致的配色。 |
| **配置校验** | 保存设置时检查类型与约束，部署前审阅变更。 |
| **部署记录** | 构建与应用过程留有记录，便于检查进度、继续执行和回滚。 |
| **本地控制** | 通过命令行与面板管理 Wi-Fi、代理、音量、亮度和常用设置。 |
| **应用安装** | 在面板中搜索、安装 Flathub 应用，无需重新构建系统；卸载时保留个人数据。 |
| **移动使用** | 同一套 USB 安装在我的笔记本与主机之间切换，另有一次性虚拟机用于验证改动。 |

## 桌面环境

桌面采用 **Niri** 的滚动布局，默认使用 **霞鹜文楷等宽 GB**（`LXGW WenKai Mono GB`），兼顾中英文混排。

**Everforest** 与 **Folio Graphite** 均提供深色和浅色配色。
窗口焦点边框、光标、状态栏、通知与面板随主题统一调整；预览图使用经过对比度调整的 Everforest 深色主题。

<details>
<summary><strong>桌面组件与工具选型</strong></summary>

| 用途 | 组件 |
| --- | --- |
| 窗口管理 | Niri，带焦点边框淡出补丁 |
| 状态栏、启动器与通知 | Waybar、Fuzzel、Mako |
| 终端与 Shell | Foot、Zsh、Powerlevel10k |
| 文件与检索 | Yazi、eza、fd、fzf、ripgrep、zoxide |
| 系统监控 | Btop |
| 编辑与笔记 | Emacs、Org、Org-roam |
| 编程助手 | Codex CLI、Pi |
| 浏览器 | Zen Browser Beta |
| 文档与图像 | Zathura、imv、Typst |
| 输入法 | Fcitx5、Rime Ice |
| 字体与光标 | 霞鹜文楷等宽 GB、重新配色的 GoogleDot 光标 |
| 桌面控制 | Folio 本地浏览器面板 |
| 可选工具 | OBS Studio、Flatpak 应用、Isaac Sim / Isaac Lab 辅助工具 |

</details>

组件按配置选择安装，个人资料、凭据、笔记与会话由各应用管理。

## 当前局限

- **硬件适配**：主要用于我的笔记本与主机。迁移到其他设备前，需要调整磁盘标识、账户及硬件设置。
- **开发工具链**：组织与维护方式尚未定型，完整的开发环境仍在整理中。
- **编辑器配置**：Emacs、Org 与 Org-roam 已接入，具体工作流还在完善。
- **验证范围**：构建与虚拟机检查之外，显卡、无线网络和休眠等功能仍需在实体设备上验证。

## 参考资料

- [配置与开发指南](docs/development.md)：配置入口、开发约定与检查方式。
- [技术参考](docs/reference.md)：详细操作、部署与维护说明。
- [Koru](https://github.com/WallyHao/koru-nixos-dotfiles)：我的早期配置，也是这份 README 的展示参考。
- [霞鹜文楷 GB](https://github.com/lxgw/LxgwWenKaiGB)：当前默认字体的上游项目。
- [Flatpak](https://flatpak.org/)：用于安装和管理桌面应用，与 Nix 原生软件配合使用。

---

<p align="center"><sub>原创代码与文档采用 <a href="LICENSE">MIT 许可证</a>；第三方代码与资源保留各自的许可证及声明。</sub></p>
