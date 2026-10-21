# scripts

日常使用的硬件检测、SSH、代理和 VNC 脚本。

## 一键安装或更新

需要预先安装 Bash、Git 和 curl。运行：

```bash
curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/setup.sh | bash
```

默认将仓库克隆到 `~/tool`，命令链接安装到 `~/.local/bin`，并在 Bash 或 Zsh 启动文件中添加 PATH。重新打开终端即可使用；当前终端执行：

```bash
export PATH="$HOME/.local/bin:$PATH"
machine_detect -s cpu,memory,gpu
```

以后更新只需运行 `scripts_update`，也可以重复执行安装命令。更新使用 `git pull --ff-only`，遇到未提交的改动、其他分支或其他仓库会停止。已有的非 Git 目录不会被覆盖。

自定义安装位置，或跳过启动文件修改：

```bash
export SCRIPTS_DIR="$HOME/tools/scripts"
export SCRIPTS_BIN_DIR="$HOME/bin"
# 下载 setup.sh 后运行；更新时沿用相同环境变量。
bash setup.sh --no-path
```

也可以手动克隆后安装：

```bash
git clone https://github.com/bigBuffers/scripts.git ~/tool
bash ~/tool/setup.sh
```

安装只配置脚本入口。Privoxy、SSH 隧道和 VNC 服务需要手动启动。

## 命令

| 命令 | 作用 | 平台 / 依赖 |
| --- | --- | --- |
| `machine_detect` | 输出系统、CPU、内存、GPU、存储、网络等硬件信息 | Linux / macOS；部分详细信息需要 root |
| `setup_privoxy` | 安装并配置 HTTP → SOCKS5 代理及 SSH 隧道 | Ubuntu / Debian；sudo、apt、SSH |
| `ssh_bot` | 通过跳板机连接，并转发 VNC 端口 | SSH、对应网络访问权限 |
| `ssh_dcs` | 连接 DCS 主机 | SSH；可选 sshpass |
| `start_vnc` | 共享已有的 GNOME / X11 桌面 | Linux、x11vnc、VNC 密码文件 |
| `scripts_update` | 更新仓库并重新安装命令链接 | Git |

### 硬件检测

```bash
machine_detect
machine_detect -s cpu,memory,gpu
sudo "$HOME/tool/machine_detect.sh" -v -o /tmp/hw.txt
machine_detect -h
```

`-o FILE` 保存报告，`-s SECTIONS` 选择章节，`-v` 输出详细原始信息。Linux 无 root 时跳过 DMI 序列号和每个 DIMM 的详细信息。

无需安装也可运行：

```bash
curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh | bash
```

### SSH

`ssh_bot_pc.sh`、`setup_privoxy.sh` 和 `proxy_config.sh` 保留原有的个人主机、用户名及端口。换环境时先检查这些值。修改已跟踪文件后，更新前需要提交或暂存改动。

`ssh_dcs` 默认使用当前用户名连接 `dcs-sh01.nvidia.com`，推荐配置 SSH 密钥；也支持交互输入密码。可通过环境变量指定目标：

```bash
DCS_SSH_USER=your_user DCS_SSH_HOST=your_host ssh_dcs
```

如果需要 sshpass，先安装它，再设置 `DCS_SSH_PASSWORD`。密码不写入脚本或仓库。

### 代理

```bash
setup_privoxy
setup_privoxy tunnel
setup_privoxy check
setup_privoxy env
```

`proxy_config.sh` 会建立其预设的 SSH 隧道，并设置当前终端的代理环境变量，应使用 `source ~/tool/proxy_config.sh` 执行。

### VNC

先安装 x11vnc，并交互创建密码文件：

```bash
sudo apt-get install -y x11vnc
mkdir -p ~/.vnc
x11vnc -storepasswd ~/.vnc/passwd
start_vnc
start_vnc status
start_vnc stop
```

显示编号、端口和监听地址在 `start_vnc.sh` 顶部配置，原有默认值为 `:1`、`5900`，允许远程连接。
