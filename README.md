# Quick Shell Scripts

本项目汇集了一系列用于 Android (Termux)、ADB 以及跨平台 Shell 环境配置的快捷脚本。旨在简化 Termux 的部署、Shizuku 的配置以及 Zsh 环境的快速搭建。

`init_zsh.sh` 运行时可选择 `Starship` 或 `Powerlevel10k` 作为提示符；选择 `Starship` 时会自动把默认配置同步到 `~/.config/starship.toml`。

## 📂 目录结构

```text
.
├── init_light.sh           # android 内配置 息屏命令脚本 环境脚本
├── init_shizuku.sh           # Shizuku 环境脚本
├── init_zsh.sh               # 跨平台 Zsh 一键配置脚本（支持选择 Starship / Powerlevel10k）
├── README.md                 # 说明文档
├── rish_shizuku.dex          # Shizuku 运行核心文件 (init_shizuku.sh 依赖)
├── termux-init               # Termux 初始化与安装工具
│   ├── init_termux.sh        # 推送到 Termux 执行的初始化逻辑
│   ├── install_termux.bat    # Windows 端一键安装脚本
│   ├── install_termux.sh     # Linux/Mac 端一键安装脚本
│   └── termux.sh             # 快速进入 Termux Shell 的脚本
└── termux-py                 # Termux Python 工具集
    └── logcat.py             # 日志调试打印工具