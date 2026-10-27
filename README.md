<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/header-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/header-light.svg">
    <img src="assets/branding/header-light.svg" width="720" alt="Folio — 一份为日常使用而打磨的个人 NixOS 桌面配置。">
  </picture>
</h1>

![NixOS](assets/badges/nixos.svg)
![Home Manager](assets/badges/home-manager.svg)
![Niri](assets/badges/niri.svg)
[![MIT 许可证](assets/badges/license.svg)](LICENSE)

[项目演进](#项目演进) · [核心特点](#核心特点) · [桌面环境](#桌面环境) · [当前局限](#当前局限) · [部署指南](#部署指南) · [参考资料](#参考资料)

</div>

[![Folio 桌面预览：Everforest 深色主题下的 Btop、Yazi 与 Foot 终端](assets/screenshots/everforest-dark-desktop.png)](assets/screenshots/everforest-dark-desktop.png)

<p align="center"><sub>Everforest 深色 · Niri · Foot · Yazi · Btop<br>截图摄于 2026-10-27，字体为霞鹜文楷等宽 GB。点击图片可查看原图。</sub></p>

Folio 是我日常使用的 NixOS 与独立 Home Manager 配置，面向 `x86_64-linux`。
台式机和笔记本均可在已经安装好的 NixOS 上使用下述本机部署流程。
该仓库记录了我的桌面选型、使用习惯，以及一路调整中做过的取舍，供参考借鉴。

## 项目演进

Folio 是配置过程中逐渐试错试出来的一套配置，它延续了 Koru 大道至简的原则，同时又优先考虑了系统的易用性。我是SUSTech Robocon ARES战队的算法组成员，已经正式退役，转而投入到足式的算法开发中。我配置这个系统的初心是搭建训练和部署一体的环境，你可以注意到这个配置主要是面向主机的，而不是笔记本电脑（虽然我也做了我的笔记本电脑的适配）。

我第一次配置的时候，采用的是一种原始的做法，将所有的配置塞到一个配置文件，但是很快我的配置文件就膨胀到了近千行，维护成本和阅读难度激增。为了解决这个问题，我重构了我的配置文件，得到了我的下一代配置Koru，Koru是我第一个应用模块化的配置，它将每一个软件都看作一个模块，并用一个单独的文件处理安装和配置过程。Koru在最初的表现很好，但是当需要安装的软件越来越多，Koru出现了两个问题：

- 对于配置复杂的模块，如Niri、Noctalia、Emacs等，还是会出现单份配置文件过长的问题
- 对于一些常用的软件如Wechat\Steam\QQ等，用Nix安装显然也有点小题大做了，我的使用负担大

**在 Koru 下一代的配置 Sylphy 中对于上述两个问题进行了优化**，让模块不再是单份文件，而是一个小项目文件夹，引入Flatpak解决部分常用软件的安装问题，Sylphy这套配置甚至还没有挺到应用就被我废止了，Sylphy同样存在两个问题：

- 每个模块都是一个小项目大大加重了配置的拓展负担
- 模块之间的依赖关系复杂，规范性约束成了开发的累赘

**Sylphy 的下一代也就是 Folio 尝试解决了这些问题**，Folio 将多个功能类似的模块聚合在一起，大大减少了模块的数量，减轻了模块的开发和维护负担；

移除系统和用户的层级区分，由manager智能的区分修改的层级归属，manager模块是其它模块的唯一依赖，并且manager统一管理了通用配置，如配色等，配置的结构复杂性大大下降

**Folio 还在一些外观上做出了调整**：

- 重新添加了状态栏，但是配置非常克制，只保留了工作区、输入法类型、时间三个信息，均匀分布两侧，不抢占视线焦点
- 调整启动器为fuzzel，不再用最上栏显示，布局居中提高可读性，更加人性化
- 移除了切换鼠标外观，使其更加契合主题，并保持简约
- 引入了控制面板，提高系统的易用性，但是并没有抛弃原有的CLI

有关控制面板，可能有同志会有些疑惑，为什么不直接用 Noctalia 呢？

首先 Noctalia 的功能实在是太多了，大部分我都不需要，而在深度定制这个问题上，Noctalia也太麻烦了，在这个AGENT高度发达的时代，利用AGENT编写美观的前端或对前端进行修改是非常容易的，所以我选择直接用自编写的前端作为面板，当我需要添加功能时：

- 编写对应功能的CLI（easy，甚至可能有现成的）
- 调整面板的界面接入CLI（easy，用AGENT拓展功能）
- 美化面板外观和微调功能（easy，有大量可复用的美化工具）

虽然这个办法会有较大的内存开销（要打开浏览器，占用约500M），但是这只是瞬时开销，用完就会关闭面板，这点内存无伤大雅，反而是Noctalia的常驻开销更不可接受

## 核心特点

- **统一桌面外观**：桌面、终端和受管应用引用同一套配色，换主题时一起切换，不必逐个调整。
- **软件安装更省事**：常用应用交给 Flatpak 管理，在面板里搜索即可安装，卸载时保留个人数据，也不用为加个应用重新构建系统。
- **按功能模块化**：每项功能自带模型、实现、运行时和测试，规范约束与可扩展性之间保持平衡，改一处不影响别处。
- **一体化配置管理**：用户与系统的配置改动统一管理，保存时校验、部署前审阅、过程留档，系统重构由工具接手。

## 桌面环境

桌面基于 **Niri** 的滚动布局，默认字体为 **霞鹜文楷等宽 GB**（`LXGW WenKai Mono GB`），中英文混排更协调。

**Everforest** 与 **Folio Graphite** 各提供深色和浅色两套配色。
焦点边框、光标、状态栏、通知与面板都会随主题同步变化；预览图用的是经过对比度调整的 Everforest 深色主题。

<details>
<summary><strong>桌面组件与工具选型</strong></summary>

| 用途 | 组件 |
| --- | --- |
| 窗口管理 | Niri |
| 状态栏、启动器与通知 | Waybar、Fuzzel、Mako |
| 终端 | Foot、Zsh、Powerlevel10k |
| 文件检索 | Yazi、eza、fd、fzf、ripgrep、zoxide |
| 系统监控 | Btop |
| 编辑笔记 | Neovim |
| 编程助手 | Codex、Pi |
| 浏览器 | Zen Browser Beta |
| 文档图像 | Zathura、imv、Typst |
| 输入法 | Fcitx5、Rime Ice |
| 字体光标 | 霞鹜文楷等宽 GB、重新配色的 GoogleDot 光标 |
| 控制面板 | Folio 本地浏览器面板 |
| 可选工具 | OBS Studio、Flatpak（Isaac Sim / Isaac Lab 仅供作者个人目标） |

</details>

组件按配置需要安装；个人资料、凭据、笔记和会话则交给各应用自行管理。

## 当前局限

- **硬件适配**：通用部署沿用本机安装配置；专用显卡驱动、混合显卡及休眠仍需按设备调整，目前仅支持 `x86_64-linux`。
- **开发工具链**：组织与维护方式尚未定型，完整的开发环境仍在整理。
- **编辑器配置**：Neovim 已接入统一主题与常用语言服务，笔记和项目工作流仍在完善。
- **验证范围**：除构建和虚拟机检查外，显卡、无线网络与休眠等功能仍需在实机上验证。

## 部署指南

### 1. 在全新 NixOS 上准备命令

先完成 NixOS 安装，重启进入硬盘上的系统，并以有 `sudo` 权限的普通用户登录。
需要联网，且 `/etc/nixos/` 中保留安装时的 `configuration.nix` 和
`hardware-configuration.nix`。当前只支持 `x86_64-linux`，部署命令及提示均为英文。

不用提前安装 Git、Just 或启用 flakes。NixOS 自带的 `nix-shell` 可以临时提供所需工具：

```sh
nix-shell -p git just jq
git clone https://github.com/WallyHao/folio-nixos-config.git
cd folio-nixos-config
just
```

后续首次部署命令都在这个 shell 和仓库目录内执行，**不要使用 `sudo just`**。
脚本仅在安装系统阶段调用 `sudo`，并自行向 Nix 传入 flakes 所需的实验功能。
如果安装环境没有配置 nixpkgs channel，可用下面的命令进入临时 shell，再克隆仓库：

```sh
nix --extra-experimental-features 'nix-command flakes' shell \
  github:NixOS/nixpkgs/nixos-unstable#git \
  github:NixOS/nixpkgs/nixos-unstable#just \
  github:NixOS/nixpkgs/nixos-unstable#jq --command bash
```

这些临时工具用于启动部署；系统与用户环境的构建使用仓库 `flake.lock` 锁定的依赖。

### 2. 初始化本机配置

```sh
just init
```

初始化使用当前普通用户的用户名、UID、家目录、登录 shell，以及本机主机名、时区和系统语言。
系统语言目前支持 `en_US.UTF-8`、`en_GB.UTF-8` 和 `zh_CN.UTF-8`。
目前部署账户的登录 shell 支持 Bash / Zsh，用户名和主机名须以小写字母开头，
仅含小写字母、数字和连字符，最长 64 字符。不符合主机名规则时，可显式指定：

```sh
just init --hostname my-laptop
```

如果安装配置位于其他目录：

```sh
just init --config-dir /path/to/nixos --hostname my-desktop
```

生成的文件如下，全部保留在本地并由 `.gitignore` 排除：

| 文件 | 用途 |
| --- | --- |
| `folio-target.json` | 选择 `local` 目标，防止误用作者个人目标或虚拟机目标。 |
| `modules/manager/configuration/targets/local/host.json` | 本机账户与初始环境信息。 |
| `modules/manager/configuration/targets/local/host.nix` | 额外硬件配置入口，如显卡、笔记本电源管理。 |
| `modules/manager/configuration/targets/local/installation/` | 安装配置中所有 `.nix` 文件的快照，入口为 `configuration.nix`。 |

`just init` 不会覆盖已经生成的本机配置。后续直接编辑这些文件；每台机器应分别克隆、初始化，
不要把另一台机器的 `local/` 目录复制过来。部署显式使用 `path:` flake，
因此被 Git 忽略的本机文件仍会参与构建，无需 `git add -f`。

### 3. 检查硬件与安装配置

构建前检查 `local/installation/configuration.nix`、其导入文件和 `local/host.nix`：

- 保留本机的磁盘 UUID、文件系统、挂载选项、交换分区、加密磁盘和引导器设置。
  `local` 目标关闭 Folio 自带的存储配置，不分区、不格式化磁盘，也不要求特定根文件系统或 UEFI。
- 保留原来的 `system.stateVersion`、账户声明和密码配置。已有用户继续使用自己的密码，
  不会创建作者的 `folio` 账户或设置演示密码。普通用户会加入桌面与 Folio 管理所需的用户组。
- 台式机和笔记本均沿用安装时的硬件探测结果；Intel / AMD / NVIDIA 驱动按本机需要补充到
  `local/host.nix`。不会套用作者的 NVIDIA 驱动组合或 PRIME bus ID。
  笔记本若增加 TLP，应同时关闭默认的 `services.power-profiles-daemon.enable`，避免电源管理冲突。
- 默认使用 Niri + greetd + NetworkManager。安装器配置中的 GDM、SDDM、LightDM、自动登录和
  独立 wpa_supplicant 会在本机目标中关闭。可以从快照中移除原有 GNOME / Plasma 等桌面声明，
  减少重复安装；其他自定义显示管理器或网络服务需要自行协调。
- 快照只复制 `.nix` 文件。相对路径引用的其他文件、目录外的导入及自定义 flakes 依赖需要自行补齐。
  Nix 源码会进入可读取的 Nix store，请先移除其中直接写入的密码、密钥、订阅凭据，改用运行时文件。

这个流程不会引入作者私有的代理订阅路径和 Pi 工作目录。
**Isaac Sim / Isaac Lab 是作者个人需求，`local` 目标完全不接入 Isaac 模块、软件包或安装步骤。**

### 4. 构建、部署、重启

```sh
just build
just deploy
sudo reboot
```

`just build` 构建本机系统和用户环境，不激活；首次构建可能需要较长时间和较多磁盘空间。
`just deploy` 使用 `nixos-rebuild boot` 安装系统，将新系统设为下次启动项。
它不立即切换当前系统，也不删除旧 generation。
如需立即切换，可使用 `just switch`；切换显示服务可能结束当前桌面会话，之后需要重新登录刷新用户组。

重启后以**初始化时的同一用户**登录，在原来的仓库目录执行：

```sh
cd ~/folio-nixos-config
nix-shell -p just jq --run 'just home'
```

若没有 channel，可用前面的临时 shell 命令进入，再执行 `just home`。
`just home` 通过已经运行的 Folio 用户管理服务规划、构建并激活 Home Manager 环境，
会记录部署历史；不需要单独安装 Home Manager，也不要使用 `sudo`。
已有受管文件冲突时会使用 Folio 的唯一备份名保留原文件。
随后注销并重新登录，进入 Niri 会话。

部署命令速查：

| 命令 | 行为 |
| --- | --- |
| `just` / `just --list` | 显示英文帮助。 |
| `just init --help` | 查看初始化选项。 |
| `just build` | 只构建本机系统和用户环境。 |
| `just deploy` | 安装系统到下次启动项，之后重启并运行 `just home`。 |
| `just switch` | 立即激活系统，适合明确需要即时切换的场景。 |
| `just home` | 通过 Folio 管理器构建并应用当前用户环境。 |
| `just plan` | 审阅后续系统与用户的配置改动。 |

### 5. 后续更新与回退

首次安装完成后，偏好与模块选择保存在 Folio 配置库中，修改 Nix 初始默认值不会覆盖它们。
使用 CLI 或面板修改配置，再通过 Folio 审阅、构建、应用；系统已经包含 Just。

```sh
git pull --ff-only
folio config show
just plan
folio build PLAN_ID
folio apply PLAN_ID
```

将 `PLAN_ID` 替换为计划命令返回的 ID。以后修改 `local/host.nix` 或安装快照，也通过这个流程部署。
`just build`、`just deploy` 和 `just switch` 是首次安装入口，直接使用初始配置；
已经使用 Folio 管理偏好后，日常更新应使用 `just plan`，避免重新应用初始默认值。
涉及模型变更时按 [模型升级说明](docs/reference.md#recovery-and-model-upgrades) 操作。

若新系统不能正常启动，在引导菜单选择上一个 NixOS generation。
系统仍可登录时，可恢复上一个系统 generation：

```sh
sudo nixos-rebuild switch --rollback
```

后续由 Folio 记录的完整部署可通过 `folio history` 查看，再使用 `folio rollback PLAN_ID` 恢复。
`just home` 失败时可修正冲突后重试，不必重新执行 `just init`。
`/etc/nixos` 原始文件不会被修改；初始化后构建使用仓库中的安装快照。
更多 CLI、应用与恢复说明见 [详细参考](docs/reference.md)。

## 参考资料

- [NixOS 手册](https://nixos.org/manual/nixos/stable/)
- [Just 手册](https://just.systems/man/en/)
- [Koru NixOS Dotfiles](https://github.com/WallyHao/koru-nixos-dotfiles)
- [霞鹜文楷 GB](https://github.com/lxgw/LxgwWenKaiGB)
- [Flatpak](https://flatpak.org/)

---

<p align="center"><sub>原创代码与文档采用 <a href="LICENSE">MIT 许可证</a>；第三方代码与资源遵循各自的许可证及声明。</sub></p>
