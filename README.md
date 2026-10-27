<div align="center">

# Folio

**一份为日常使用而打磨的个人 NixOS 桌面配置。**

![NixOS](assets/badges/nixos.svg)
![Home Manager](assets/badges/home-manager.svg)
![Niri](assets/badges/niri.svg)
[![MIT 许可证](assets/badges/license.svg)](LICENSE)

[项目演进](#项目演进) · [核心特点](#核心特点) · [桌面环境](#桌面环境) · [当前局限](#当前局限) · [参考资料](#参考资料)

</div>

[![Folio 桌面预览：Everforest 深色主题下的 Btop、Yazi 与 Foot 终端](assets/screenshots/everforest-dark-desktop.png)](assets/screenshots/everforest-dark-desktop.png)

<p align="center"><sub>Everforest 深色 · Niri · Foot · Yazi · Btop<br>截图摄于 2026-10-27，字体为霞鹜文楷等宽 GB。点击图片可查看原图。</sub></p>

Folio 是我每天在用的 NixOS 与独立 Home Manager 配置，面向 `x86_64-linux`。
仓库里记录了桌面选型、使用习惯，以及一路调整中做过的取舍，供参考借鉴。

## 项目演进

Folio 是试错试出来的。最初所有设置都挤在一个 Nix 文件里，起步省事，可内容一多，查找和维护就成了负担。后来我写了 [Koru](https://github.com/WallyHao/koru-nixos-dotfiles)，把配置按应用拆成一个个文件，目录清楚了不少，但复杂应用的配置很快又会堆成一个大文件。再往后的 Sylphy 走得更远，让每个应用都成为独立小项目，配置、脚本和资源各归各处，维护约定也更严格——代价是新增模块越来越费劲，最后还是放弃了。几次折腾下来，想要的东西反而清楚了：既要长期管得住，又不能让每加一个模块都先付出很大代价。Folio 就是在两者之间重新找平衡，把大部分精力放回统一外观、工具搭配和日常操作上，命令行与本地控制面板也一点点补齐。

## 核心特点

- **统一外观**：桌面、终端和受管应用引用同一套配色，换主题时一起切换，不必逐个调整。
- **软件安装更省事**：常用应用交给 Flatpak 管理，在面板里搜索即可安装，卸载时保留个人数据，也不用为加个应用重新构建系统。
- **按功能模块化**：每项功能自带模型、实现、运行时和测试，规范约束与可扩展性之间保持平衡，改一处不影响别处。
- **一体化配置管理**：用户与系统的配置改动统一管理，保存时校验、部署前审阅、过程留档，系统重构由工具接手，使用者只需关心自己想要什么。

## 桌面环境

桌面基于 **Niri** 的滚动布局，默认字体为 **霞鹜文楷等宽 GB**（`LXGW WenKai Mono GB`），中英文混排更协调。

**Everforest** 与 **Folio Graphite** 各提供深色和浅色两套配色。
焦点边框、光标、状态栏、通知与面板都会随主题同步变化；预览图用的是经过对比度调整的 Everforest 深色主题。

<details>
<summary><strong>桌面组件与工具选型</strong></summary>

| 用途 | 组件 |
| --- | --- |
| 窗口管理 | Niri，带焦点边框淡出补丁 |
| 状态栏、启动器与通知 | Waybar、Fuzzel、Mako |
| 终端与 Shell | Foot、Zsh、Powerlevel10k |
| 文件与检索 | Yazi、eza、fd、fzf、ripgrep、zoxide |
| 系统监控 | Btop |
| 编辑与笔记 | Neovim，集成文件检索、补全与语言服务 |
| 编程助手 | Codex CLI、Pi |
| 浏览器 | Zen Browser Beta |
| 文档与图像 | Zathura、imv、Typst |
| 输入法 | Fcitx5、Rime Ice |
| 字体与光标 | 霞鹜文楷等宽 GB、重新配色的 GoogleDot 光标 |
| 桌面控制 | Folio 本地浏览器面板 |
| 可选工具 | OBS Studio、Flatpak 应用、Isaac Sim / Isaac Lab 辅助工具 |

</details>

组件按配置需要安装；个人资料、凭据、笔记和会话则交给各应用自行管理。

## 当前局限

- **硬件适配**：主要针对我自己的笔记本和主机。换到其他设备前，需要调整磁盘标识、账户与硬件设置。
- **开发工具链**：组织与维护方式尚未定型，完整的开发环境仍在整理。
- **编辑器配置**：Neovim 已接入统一主题与常用语言服务，笔记和项目工作流仍在完善。
- **验证范围**：除构建和虚拟机检查外，显卡、无线网络与休眠等功能仍需在实机上验证。

## 参考资料

- [配置与开发指南](docs/development.md)：配置入口、开发约定与检查方式。
- [技术参考](docs/reference.md)：详细的操作、部署与维护说明。
- [Koru](https://github.com/WallyHao/koru-nixos-dotfiles)：我的早期配置，也是 README 排版与 Neovim 配色的参考。
- [霞鹜文楷 GB](https://github.com/lxgw/LxgwWenKaiGB)：默认字体的上游项目。
- [Flatpak](https://flatpak.org/)：用来安装和管理桌面应用，与 Nix 原生软件配合使用。

---

<p align="center"><sub>原创代码与文档采用 <a href="LICENSE">MIT 许可证</a>；第三方代码与资源遵循各自的许可证及声明。</sub></p>
