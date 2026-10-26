<div align="center">

# Folio

**一套注重统一外观与日常体验的个人 NixOS 桌面配置。**

<sub>NixOS · Home Manager · Niri</sub>

[项目演进](#项目演进) · [核心特点](#核心特点) · [桌面环境](#桌面环境) · [当前局限](#当前局限) · [参考资料](#参考资料)

</div>

[![Folio 桌面：Everforest 深色主题下的 Btop、Yazi 与 Foot 终端](assets/screenshots/everforest-dark-desktop.png)](assets/screenshots/everforest-dark-desktop.png)

<p align="center"><sub>Everforest 深色 · Niri · Foot · Yazi · Btop · 截图字体：Maple Mono NF CN</sub></p>

Folio 是我的个人 NixOS 与独立 Home Manager 配置，面向 `x86_64-linux`。
这个仓库记录了我的桌面选型与使用习惯，供参考和按需调整。

## 项目演进

1. **最初：所有配置放在一个文件里。** 起步直接，但随着内容增加，配置逐渐臃肿，查找和维护都变得困难。
2. **Koru：每个应用一个文件。** [Koru](https://github.com/WallyHao/koru-nixos-dotfiles) 是我第一次尝试模块化。目录更清楚了，但复杂应用仍会积累成一个大文件。
3. **Sylphy：每个应用成为一个小项目。** 我把配置、脚本与资源集中管理，并引入更严格的规范。维护边界更明确，但添加模块的成本过高，最终放弃了这个项目。
4. **Folio：重新平衡规范与使用成本。** 保留对一致性和可维护性的要求，同时更关注统一外观、工具搭配，以及命令行和面板在日常使用中的体验。

## 核心特点

| 特点 | 使用体验 |
| --- | --- |
| **统一外观** | 一次选择主题，让桌面、终端和受管理的应用使用一致的配色。 |
| **配置校验** | 常用设置提供类型与约束检查，保存配置和部署变更分开进行。 |
| **部署与恢复** | 变更可以先审阅，再构建和应用；历史记录支持检查、继续执行与回滚。 |
| **日常控制** | 命令行与本地面板提供网络、代理、音量、亮度及常用设置的管理入口。 |
| **应用安装** | 通过面板搜索和安装 Flathub 应用，无需为每次安装重新构建系统；移除时保留个人数据。 |
| **移动使用** | 同一套 USB 安装用于我的笔记本与主机，另有用于测试的一次性虚拟机环境。 |

## 桌面环境

桌面采用 Niri 的滚动布局，搭配霞鹜文楷等宽 GB（LXGW WenKai Mono GB）字体，兼顾中文与英文显示。
提供 Everforest 和 Folio Graphite 两套配色，均支持深色与浅色；截图使用调整过对比度的 Everforest 深色主题。
窗口焦点边框、光标、文件图标、状态栏与面板沿用统一配色。

<details>
<summary><strong>展开桌面组件</strong></summary>

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

实际安装的组件取决于配置选择，个人资料、凭据、笔记与会话由各应用管理。

## 当前局限

- **硬件适配**：主要用于我的笔记本与主机。用于其他设备前，需要调整磁盘标识、账户及硬件相关设置。
- **开发工具链**：组织和维护方式尚未稳定，目前还不是完整的开发环境。
- **编辑器配置**：Emacs、Org 与 Org-roam 已接入，具体工作流仍处于初步配置阶段。
- **验证范围**：构建和虚拟机检查无法覆盖所有实体硬件上的显卡、无线网络与休眠行为。

## 参考资料

- [Koru](https://github.com/WallyHao/koru-nixos-dotfiles)：我的早期配置，也是这份 README 的展示参考。
- [Flatpak](https://flatpak.org/)：用于安装桌面应用，与 Nix 管理的原生软件配合使用。
- [配置与开发指南](docs/development.md)：配置入口、开发约定与检查方式。
- [技术参考](docs/reference.md)：详细的操作说明与维护记录。

本仓库的原创代码与文档采用 [MIT 许可证](LICENSE)，第三方代码与资源保留各自的许可证及声明。
