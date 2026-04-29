# Claude Code Notifier

将 Claude Code 的权限请求、问题选择、任务完成等事件实时推送到手机，支持在手机上直接审批操作，按键自动注入终端。告别守在电脑前等 Claude 弹框 -- 随时随地掌控 AI 工作流。

[English Documentation](README.md)

## 功能特性

### 权限审批推送
Claude Code 执行 Shell 命令、写入/编辑文件等需要授权时，手机收到通知卡片，显示操作类型、风险等级、命令内容或文件路径。点击审批按钮（允许/始终允许/拒绝），结果自动注入终端，Claude 继续执行。

### 问题选择推送
Claude 向用户提问（AskUserQuestion）时，手机显示完整问题和选项卡片，支持单选/多选。选择后自动回填终端，无需切回电脑操作。

### 任务完成通知
Claude 执行完毕（Stop Hook）时推送完整通知。从 Hook stdin JSON 自动提取：
- **项目名**：取 `cwd` 工作目录 basename 作为标题，如"✅ claude-code-notifier 任务完成"
- **工作目录**：显示完整 `cwd` 路径（home 缩写为 `~`），如"📂 ~/claude-code-notifier"
- **任务摘要**：取 `last_assistant_message` 完整内容（去除代码块和 markdown 格式，保留结构，截断 500 字符）

多个 Claude 会话并行时，在手机上一眼区分哪个完成了、做了什么。

### TUI 选项同步
审批页面动态显示与终端 TUI 一致的选项按钮（2 个或 3 个），从 `permission_suggestions` 解析 Always 选项的具体描述（如"始终允许访问 /path/to/dir"）。

### 多通道推送
同时支持多个通知渠道，至少配置一个即可：
- **飞书（Feishu）**：Webhook 模式（群机器人）或 App 模式（个人消息），支持交互卡片和审批按钮
- **Server酱（ServerChan）**：推送到个人微信
- **企业微信（WeChat Work）**：企业微信群机器人 Webhook

### 远程审批服务
内置 Flask 审批服务器，提供：
- 移动端优先的 Web 审批页面
- 仪表盘（Dashboard）查看所有待审批和历史请求
- RESTful API，可对接自定义通知渠道
- 请求自动过期清理（默认 30 分钟）

### 按键自动注入
审批后自动将按键注入运行 Claude Code 的终端：
1. **tmux send-keys**（推荐）：在 tmux 会话中运行 Claude Code 即可
2. **TIOCSTI ioctl**：备选方案，适用于无 tmux 环境（部分内核已禁用）
3. **仅通知模式**：以上均不可用时，仅发送通知提醒回终端操作

## 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│         Claude Code TUI 弹出权限提示 / 提问                  │
└─────────────────────────────────────────────────────────────┘
                            │
              Hook 触发 notify.sh（读取 stdin JSON）
                            │
                ┌───────────┴───────────┐
                │                       │
        多通道推送通知            approve-server 创建审批请求
     (飞书/Server酱/企微)         POST /api/request
                │                       │
                ▼                       ▼
        手机收到通知卡片 ──────→ 打开审批页面（移动端 Web UI）
                                        │
                              选择 允许 / 始终允许 / 拒绝
                              或选择问题选项
                                        │
                                POST /api/approve 或 /api/answer
                                        │
                         notify.sh 后台轮询 /api/status
                                        │
                              检测到审批结果 + inject_key
                                        │
                           tmux send-keys 注入终端按键
                                        │
                              Claude Code 继续执行
```

## 项目结构

```
claude-code-notifier/
├── notify.sh                        # 主脚本：Hook 入口、上下文解析、消息推送、审批轮询、按键注入
├── notifier.conf.example            # 配置文件模板
├── README.md                        # 英文文档
├── README_CN.md                     # 中文文档（当前文件）
└── approve-server/                  # Flask 远程审批服务
    ├── app.py                       # 后端 API：创建/查询/审批/回答
    ├── templates/
    │   └── approve.html             # 移动端审批页面（权限审批 + 问题选择 + 仪表盘）
    ├── requirements.txt             # Python 依赖（flask>=3.0, gunicorn>=21.2）
    └── claude-approve.service       # systemd 服务模板
```

## 安装部署

### 方式一：使用 zip 迁移包（推荐）

如果你收到了 `claude-code-notifier-YYYYMMDD-HHMMSS.zip` 迁移包：

```bash
# 1. 解压
unzip claude-code-notifier-*.zip -d /tmp/claude-code-notifier

# 2. 部署到 ~/.claude/
cp /tmp/claude-code-notifier/notify.sh ~/.claude/notify.sh
chmod +x ~/.claude/notify.sh
cp /tmp/claude-code-notifier/notifier.conf.example ~/.claude/notifier.conf

# 3. 部署审批服务
cp -r /tmp/claude-code-notifier/approve-server ~/.claude/approve-server
cd ~/.claude/approve-server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 4. 编辑配置
vim ~/.claude/notifier.conf

# 5. 配置 Claude Code Hooks（见下方）
```

### 方式二：手动部署

```bash
# 1. 克隆项目
git clone https://github.com/lokyshin/claude-code-notifier.git
cd claude-code-notifier

# 2. 部署主脚本
cp notify.sh ~/.claude/notify.sh
chmod +x ~/.claude/notify.sh

# 3. 创建配置文件
cp notifier.conf.example ~/.claude/notifier.conf
# 编辑并填入你的通知渠道凭据
vim ~/.claude/notifier.conf

# 4. 部署审批服务
cp -r approve-server ~/.claude/approve-server
cd ~/.claude/approve-server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 配置通知渠道

编辑 `~/.claude/notifier.conf`，至少启用一个通知渠道：

#### 飞书 - App 模式（推荐，支持个人消息）

```bash
USE_FEISHU=1
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
FEISHU_RECEIVE_TYPE="open_id"           # open_id / chat_id / user_id
FEISHU_RECEIVE_ID="ou_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

> 需要在飞书开放平台创建应用，开启 `im:message:send_as_bot` 权限。

#### 飞书 - Webhook 模式（群机器人，配置简单）

```bash
USE_FEISHU=1
FEISHU_MODE="webhook"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

#### Server酱（推送到个人微信）

```bash
USE_SERVERCHAN=1
SERVERCHAN_KEY="SCTxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

> 在 [sct.ftqq.com](https://sct.ftqq.com) 获取 Key。

#### 企业微信群机器人

```bash
USE_WXWORK=1
WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### 配置远程审批服务

```bash
# 在 notifier.conf 中启用
USE_REMOTE_APPROVE=1
APPROVE_SERVER="https://your-domain.com"   # 公网可访问地址
APPROVE_TIMEOUT=300                        # 轮询超时秒数（默认 300）
APPROVE_INTERVAL=3                         # 轮询间隔秒数（默认 3）
```

### 启动审批服务

#### 方法一：systemd（推荐，开机自启）

```bash
# 编辑 service 文件，替换 YOUR_USERNAME
sed -i "s/YOUR_USERNAME/$(whoami)/g" ~/.claude/approve-server/claude-approve.service

# 安装并启动服务
sudo cp ~/.claude/approve-server/claude-approve.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now claude-approve

# 查看状态
sudo systemctl status claude-approve
```

#### 方法二：手动启动

```bash
cd ~/.claude/approve-server
source venv/bin/activate
gunicorn -w 1 --threads 2 -b 0.0.0.0:9120 app:app
```

#### Nginx 反向代理（推荐配 HTTPS）

```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://127.0.0.1:9120;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 配置 Claude Code Hooks

编辑 `~/.claude/settings.json`，在 `hooks` 中添加：

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/notify.sh permission",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/notify.sh done",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

> **说明**：`PermissionRequest` Hook 同时处理权限请求和 `AskUserQuestion` 事件。`Stop` Hook 在任务完成时触发通知。

## 审批服务 API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/` | GET | 仪表盘，显示待审批和最近请求列表 |
| `/approve/<id>` | GET | 单个请求的审批页面（移动端优化） |
| `/api/request` | POST | 创建审批请求（notify.sh 调用） |
| `/api/status/<id>` | GET | 查询请求状态（notify.sh 轮询） |
| `/api/approve/<id>` | POST | 提交权限审批：`approve` / `always` / `reject` |
| `/api/answer/<id>` | POST | 提交问题回答：`select` / `tui` / `reject` |

### 创建审批请求

```bash
curl -X POST https://your-domain.com/api/request \
  -H 'Content-Type: application/json' \
  -d '{
    "request_id": "req-1234567890-12345",
    "project": "my-project",
    "hostname": "my-server",
    "tool_name": "Bash",
    "tool_input": {"command": "npm install"},
    "risk_level": "low"
  }'
```

### 提交审批

```bash
curl -X POST https://your-domain.com/api/approve/req-1234567890-12345 \
  -H 'Content-Type: application/json' \
  -d '{"action": "approve", "inject_key": "1"}'
```

## 配置参考

### notifier.conf 完整配置项

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `USE_FEISHU` | `0` | 启用飞书通知（0=关闭, 1=开启） |
| `FEISHU_MODE` | `webhook` | 飞书模式：`webhook` 或 `app` |
| `FEISHU_WEBHOOK` | - | Webhook URL（webhook 模式） |
| `FEISHU_APP_ID` | - | 应用 ID（app 模式） |
| `FEISHU_APP_SECRET` | - | 应用密钥（app 模式） |
| `FEISHU_RECEIVE_TYPE` | `chat_id` | 接收者类型：`open_id` / `chat_id` / `user_id` |
| `FEISHU_RECEIVE_ID` | - | 接收者 ID（app 模式） |
| `USE_SERVERCHAN` | `0` | 启用 Server酱 |
| `SERVERCHAN_KEY` | - | Server酱 API Key |
| `USE_WXWORK` | `0` | 启用企业微信 |
| `WXWORK_WEBHOOK` | - | 企业微信 Webhook URL |
| `USE_REMOTE_APPROVE` | `0` | 启用远程审批服务 |
| `APPROVE_SERVER` | - | 审批服务公网地址 |
| `APPROVE_TIMEOUT` | `300` | 审批轮询超时（秒） |
| `APPROVE_INTERVAL` | `3` | 审批轮询间隔（秒） |
| `LOG_FILE` | `~/.claude/notifier.log` | 日志文件路径 |

### 环境变量

| 变量 | 说明 |
|------|------|
| `CLAUDE_NOTIFIER_CONFIG` | 自定义配置文件路径（默认 `~/.claude/notifier.conf`） |
| `CLAUDE_PROJECT_DIR` | 当前项目目录（Claude Code 自动设置） |
| `APPROVE_HOST` | 审批服务监听地址（默认 `127.0.0.1`） |
| `APPROVE_PORT` | 审批服务端口（默认 `9120`） |
| `APPROVE_EXPIRE` | 请求过期时间/秒（默认 `1800`） |
| `APPROVE_DEBUG` | Flask 调试模式（`true`/`false`） |

## 迁移到其他机器

### 使用 zip 包迁移

1. 在源机器打包：项目已提供时间戳 zip 包
2. 传输到目标机器
3. 解压并按上方安装步骤部署
4. 修改 `~/.claude/notifier.conf` 中的通知渠道配置
5. 修改 `~/.claude/settings.json` 添加 Hooks
6. 如需远程审批，启动 approve-server 并配置 Nginx

### 需要在目标机器准备的环境

- Python 3.8+
- tmux（推荐，用于按键注入）
- Claude Code CLI
- curl（notify.sh 调用 HTTP 接口）
- Nginx（可选，用于 HTTPS 反向代理）

## 日志与调试

日志文件默认位于 `~/.claude/notifier.log`，记录每次推送和审批事件：

```bash
# 查看实时日志
tail -f ~/.claude/notifier.log

# 查看审批服务日志
sudo journalctl -u claude-approve -f
```

飞书 App 模式的 Token 缓存位于 `~/.claude/.feishu_token_cache`，TTL 110 分钟自动刷新。

## 安全注意事项

- `notifier.conf` 包含 API 密钥，建议设置权限 `chmod 600 ~/.claude/notifier.conf`
- 审批服务建议通过 Nginx + HTTPS 对外暴露，不要直接暴露 9120 端口
- 审批请求在内存中存储，服务重启后清空
- Token 缓存文件权限自动设为 600

## 许可

MIT
