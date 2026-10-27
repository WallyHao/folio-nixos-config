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

Folio 是我日常使用的 NixOS 与独立 Home Manager 配置，面向 `x86_64-linux`
该仓库记录了我的桌面选型、使用习惯，以及一路调整中做过的取舍，供参考借鉴

## 项目演进

Folio 是我在配置过程中逐渐试错试出来的一套配置，它延续了 Koru 大道至简的原则，同时又优先考虑了系统的易用性。

我是SUSTech Robocon ARES战队的算法组成员，已经正式退役，转而投入到足式的算法开发中。

我配置这个系统的初心是搭建训练和部署一体的环境，你可以注意到这个配置主要是面向主机的，而不是笔记本电脑（虽然我也做了我的笔记本电脑的适配）。

我第一次配置的时候，采用的是一种原始的做法，将所有的配置塞到一个配置文件，但是很快我的配置文件就膨胀到了近千行，维护成本和阅读难度激增。为了解决这个问题，我重构了我的配置文件，得到了我的下一代配置Koru，Koru是我第一个应用模块化的配置，它将每一个软件都看作一个模块，并用一个单独的文件处理安装和配置过程。Koru在最初的表现很好，但是当需要安装的软件越来越多，Koru出现了两个问题：

- 对于配置复杂的模块，如Niri、Noctalia、Emacs等，还是会出现单份配置文件过长的问题
- 对于一些常用的软件如Wechat\Steam\QQ等，用Nix安装显然也有点小题大做了，我的使用负担大

所以在下一代的配置 Sylphy 中，我对这两个问题做出了优化，让模块不再是单份文件，而是一个小项目文件夹，引入Flatpak解决部分常用软件的安装问题，Sylphy这套配置甚至还没有挺到应用就被我废止了，Sylphy同样存在两个问题：

- 每个模块都是一个小项目大大加重了配置的拓展负担
- 模块之间的依赖关系复杂，规范性约束成了开发的累赘

Sylphy的下一代就是 Folio，Folio 将多个功能类似的模块聚合在一起，大大减少了模块的数量，减轻了模块的开发和维护负担；移除系统和用户的层级区分，由manager智能的区分修改的层级归属，manager模块是其它模块的唯一依赖，并且manager统一管理了通用配置，如配色等，配置的结构复杂性大大下降

Folio 还在一些外观上做出了调整：

- 重新添加了状态栏，但是配置非常克制，只保留了工作区、输入法类型、时间三个信息，均匀分布两侧，不抢占视线焦点
- 调整启动器为fuzzel，不再用最上栏显示，布局居中提高可读性，更加人性化
- 移除了切换鼠标外观，使其更加契合主题，并保持简约
- 引入了控制面板，提高系统的易用性，但是并没有抛弃原有的CLI

有关控制面板，可能有同志会有些疑惑，为什么不直接用 Noctalia 呢？首先 Noctalia 的功能实在是太多了，大部分我都不需要，而在深度定制这个问题上，Noctalia也太麻烦了，在这个AGENT高度发达的时代，利用AGENT编写美观的前端或对前端进行修改是非常容易的，所以我选择直接用自编写的前端作为面板，当我需要添加功能时：

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
| 可选工具 | OBS Studio、Flatpak、Isaac Sim / Isaac Lab |

</details>

组件按配置需要安装；个人资料、凭据、笔记和会话则交给各应用自行管理。

## 当前局限

- **硬件适配**：主要针对我自己的笔记本和主机。换到其他设备前，需要调整磁盘标识、账户与硬件设置。
- **开发工具链**：组织与维护方式尚未定型，完整的开发环境仍在整理。
- **编辑器配置**：Neovim 已接入统一主题与常用语言服务，笔记和项目工作流仍在完善。
- **验证范围**：除构建和虚拟机检查外，显卡、无线网络与休眠等功能仍需在实机上验证。

## 参考资料

- [Koru NixOS Dotfiles](https://github.com/WallyHao/koru-nixos-dotfiles)
- [霞鹜文楷 GB](https://github.com/lxgw/LxgwWenKaiGB)
- [Flatpak](https://flatpak.org/)

---

<p align="center"><sub>原创代码与文档采用 <a href="LICENSE">MIT 许可证</a>；第三方代码与资源遵循各自的许可证及声明。</sub></p>
