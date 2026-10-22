# scripts

日常使用的硬件检测、SSH、代理、VNC 和 rrLog 下载脚本。密码和 API key 不写入仓库，统一放在本地的 `.env` 文件中（见下文）。

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

以后更新只需运行 `scripts_update`，也可以重复执行安装命令。更新使用 `git pull --ff-only`，遇到未提交的改动、未跟踪文件、其他分支或其他仓库会停止。已有的非 Git 目录不会被覆盖。

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

## 本地配置：.env

需要密码、API key 或本机路径的脚本会读取仓库目录下的 `.env`。该文件已被 `.gitignore` 忽略，不会上传；换电脑时需要手动复制或重新填写。安装后：

```bash
cp ~/tool/.env.example ~/tool/.env
chmod 600 ~/tool/.env
```

格式为每行一个 `KEY=VALUE`，与 Shell 语法相同，`.env.example` 列出了全部变量。命令行中已导出的同名变量优先于 `.env`，便于临时覆盖，例如 `DCS_SSH_HOST=other ssh_dcs`。

所有 SSH 脚本的远端用户名默认取本机用户名，可用 `SSH_USER` 统一指定。密码变量留空时使用 SSH 密钥登录；填写后需要安装 `sshpass`（macOS：`brew install hudochenkov/sshpass/sshpass`）。

## 命令

| 命令 | 作用 | 平台 / 依赖 |
| --- | --- | --- |
| `machine_detect` | 输出系统、CPU、内存、GPU、存储、网络等硬件信息 | Linux / macOS；部分详细信息需要 root |
| `ssh_dcs` | 连接 DCS 主机 `dcs-sh01.nvidia.com` | SSH；可选 sshpass |
| `ssh_pc` | 连接实验室 PC（`PC_SSH_HOST`） | SSH；可选 sshpass |
| `ssh_drivefarm` | 经站点跳板机连接 drive farm 的 bot PC 并转发 VNC 端口；`ssh_bot` 等同 `ssh_drivefarm oregon` | SSH、对应网络访问权限 |
| `setup_rr_dt_ssh` | 一次性配置经 xterm 跳板机免密登录 `rr-dt` | SSH、ssh-copy-id |
| `setup_maglev` | 安装 Maglev CLI 并用 `MAGLEV_API_KEY` 登录 | curl；`.env` 中的 `MAGLEV_API_KEY` |
| `download_rrlog` | 在 DCS 主机上用 maglev 下载任务产物，并把 rrLog 拉到本机 | SSH、scp；远端已配置 maglev |
| `pull_sil_rrlogs` | 递归下载 HTTP 目录列表（SIL 产物） | Python 3、requests、beautifulsoup4 |
| `setup_privoxy` | 安装并配置 HTTP → SOCKS5 代理及 SSH 隧道 | Ubuntu / Debian；sudo、apt、SSH |
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

主机名和端口保留了原有的个人配置，可通过 `.env.example` 中列出的变量覆盖；换环境时先检查这些值。修改已跟踪文件后，更新前需要提交或暂存改动。

```bash
ssh_dcs                         # dcs-sh01.nvidia.com
DCS_SSH_HOST=other ssh_dcs      # 临时换主机
ssh_pc                          # PC_SSH_HOST，默认 10.19.183.180
ssh_bot                         # Oregon drive farm 的 bot PC
ssh_drivefarm santaclara        # Santa Clara drive farm 的 bot PC
ssh_drivefarm oregon -v         # 站点之后的参数原样传给 ssh
```

`ssh_drivefarm` 通过 `ProxyCommand` 经站点跳板机登录 bot PC，并把本机 `5910` 端口转发到远端 `5901`（VNC），可用 `DRIVEFARM_VNC_LOCAL_PORT`、`DRIVEFARM_VNC_REMOTE_PORT` 调整。

`setup_rr_dt_ssh` 在缺少 `~/.ssh/id_ed25519` 时生成密钥，向 `~/.ssh/config` 写入 `xterm-jump` 和 `rr-dt` 两个 Host，再用 `ssh-copy-id` 把公钥装到两台机器上（各输入一次密码）。之后直接 `ssh rr-dt`。

### Maglev

```bash
setup_maglev
```

从 `.env` 读取 `MAGLEV_API_KEY`，写入 Shell 启动文件，然后安装 Maglev CLI 并登录。

### rrLog 下载

```bash
download_rrlog <job_id> <test_id>
python3 ~/tool/download_rrlog.py <job_id> <test_id> [--commit HASH] [--analyze]
pull_sil_rrlogs <目录 URL> [-o 输出目录]
```

`download_rrlog` 登录 DCS 主机执行 `maglev ts jobs artifacts <job_id>:<test_id> --download /tmp/`，找到 `exec-*/output` 目录后用 scp 拉到 `RRLOG_LOCAL_DIR`（默认 `~/Downloads/claude_rrLog/rrLog`，每次先清空）。

`download_rrlog.py` 功能相同，基于 paramiko（缺少依赖时自动 pip 安装），远端已有产物时跳过 maglev 下载；加 `--analyze` 会在 `NDAS_WORKSPACE`（默认 `~/workspace/ndas`）中调用 Claude 分析崩溃，`--commit` 指定崩溃时的提交。

`pull_sil_rrlogs` 递归下载一个 HTTP 目录列表（例如 `https://pdx.s8k.io/v1/.../rrLog/`），默认保存到 `~/Downloads/SIL/`。需要 `pip install requests beautifulsoup4`。

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
