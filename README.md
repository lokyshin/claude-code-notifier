# Claude Code Notifier

Push Claude Code events (permission requests, questions, task completion) to your phone in real time. Approve operations and answer questions directly from your phone — keystrokes are automatically injected into the terminal. No more sitting in front of the screen waiting for Claude to pop up a dialog.

[中文文档](README_CN.md)

## Features

### Permission Approval Push
When Claude Code needs authorization (shell commands, file writes/edits, etc.), you get a notification card on your phone showing the operation type, risk level, command or file path. Tap an approval button (Allow / Always Allow / Reject), and the result is automatically injected into the terminal so Claude continues execution.

### Question Selection Push
When Claude asks a question (`AskUserQuestion`), your phone displays the full question and option cards with single/multi-select support. Your selection is sent back to the terminal automatically — no need to switch back to your computer.

### Task Completion Notification
When Claude finishes (`Stop` Hook), you receive a rich notification with:
- **Project name**: extracted from the `cwd` basename, e.g. "claude-code-notifier task complete"
- **Working directory**: full `cwd` path (home abbreviated to `~`)
- **Task summary**: `last_assistant_message` content (code blocks and markdown stripped, truncated to 500 chars)

When running multiple Claude sessions in parallel, you can instantly tell which one finished and what it did.

### TUI Option Sync
The approval page dynamically renders buttons matching the terminal TUI (2 or 3 options). The "Always" option description is parsed from `permission_suggestions` (e.g. "Always allow access to /path/to/dir").

### Multi-Channel Push
Enable one or more notification channels simultaneously:
- **Feishu (Lark)**: Webhook mode (group bot) or App mode (personal messages), with interactive cards and approval buttons
- **ServerChan**: Push to personal WeChat
- **WeChat Work**: Group bot Webhook

### Remote Approval Server
Built-in Flask approval server providing:
- Mobile-first web approval page
- Dashboard for all pending and historical requests
- RESTful API for custom notification channel integration
- Auto-expiring requests (default 30 minutes)

### Keystroke Auto-Injection
After approval, keystrokes are injected into the terminal running Claude Code:
1. **tmux send-keys** (recommended): just run Claude Code inside a tmux session
2. **TIOCSTI ioctl**: fallback for non-tmux environments (disabled on some kernels)
3. **Notification-only mode**: if neither method is available, sends a notification reminding you to go back to the terminal

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│      Claude Code TUI shows permission prompt / question      │
└─────────────────────────────────────────────────────────────┘
                            │
              Hook triggers notify.sh (reads stdin JSON)
                            │
                ┌───────────┴───────────┐
                │                       │
       Multi-channel push         approve-server creates request
    (Feishu/ServerChan/WxWork)      POST /api/request
                │                       │
                ▼                       ▼
       Phone notification ──────→ Open approval page (mobile Web UI)
                                        │
                              Choose Allow / Always Allow / Reject
                              or select question options
                                        │
                                POST /api/approve or /api/answer
                                        │
                         notify.sh background polls /api/status
                                        │
                              Detects result + inject_key
                                        │
                           tmux send-keys injects keystroke
                                        │
                              Claude Code continues
```

## Project Structure

```
claude-code-notifier/
├── notify.sh                        # Main script: Hook entry, context parsing, push, approval polling, key injection
├── notifier.conf.example            # Configuration template
├── README.md                        # English documentation
├── README_CN.md                     # Chinese documentation
└── approve-server/                  # Flask remote approval server
    ├── app.py                       # Backend API: create/query/approve/answer
    ├── templates/
    │   └── approve.html             # Mobile approval page (permission + question + dashboard)
    ├── requirements.txt             # Python dependencies (flask>=3.0, gunicorn>=21.2)
    └── claude-approve.service       # systemd service template
```

## Installation

### Option 1: Using a zip migration package (recommended)

If you received a `claude-code-notifier-YYYYMMDD-HHMMSS.zip` package:

```bash
# 1. Extract
unzip claude-code-notifier-*.zip -d /tmp/claude-code-notifier

# 2. Deploy to ~/.claude/
cp /tmp/claude-code-notifier/notify.sh ~/.claude/notify.sh
chmod +x ~/.claude/notify.sh
cp /tmp/claude-code-notifier/notifier.conf.example ~/.claude/notifier.conf

# 3. Deploy approval server
cp -r /tmp/claude-code-notifier/approve-server ~/.claude/approve-server
cd ~/.claude/approve-server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 4. Edit config
vim ~/.claude/notifier.conf

# 5. Configure Claude Code Hooks (see below)
```

### Option 2: Manual deployment

```bash
# 1. Clone the repo
git clone https://github.com/lokyshin/claude-code-notifier.git
cd claude-code-notifier

# 2. Deploy main script
cp notify.sh ~/.claude/notify.sh
chmod +x ~/.claude/notify.sh

# 3. Create config file
cp notifier.conf.example ~/.claude/notifier.conf
# Edit and fill in your notification channel credentials
vim ~/.claude/notifier.conf

# 4. Deploy approval server
cp -r approve-server ~/.claude/approve-server
cd ~/.claude/approve-server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Configure Notification Channels

Edit `~/.claude/notifier.conf`, enable at least one channel:

#### Feishu - App Mode (recommended, supports personal messages)

```bash
USE_FEISHU=1
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
FEISHU_RECEIVE_TYPE="open_id"           # open_id / chat_id / user_id
FEISHU_RECEIVE_ID="ou_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

> Requires creating an app on the Feishu Open Platform with `im:message:send_as_bot` permission.

#### Feishu - Webhook Mode (group bot, simpler setup)

```bash
USE_FEISHU=1
FEISHU_MODE="webhook"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

#### ServerChan (push to personal WeChat)

```bash
USE_SERVERCHAN=1
SERVERCHAN_KEY="SCTxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

> Get your key at [sct.ftqq.com](https://sct.ftqq.com).

#### WeChat Work Group Bot

```bash
USE_WXWORK=1
WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Configure Remote Approval

```bash
# Enable in notifier.conf
USE_REMOTE_APPROVE=1
APPROVE_SERVER="https://your-domain.com"   # Publicly accessible URL
APPROVE_TIMEOUT=300                        # Polling timeout in seconds (default 300)
APPROVE_INTERVAL=3                         # Polling interval in seconds (default 3)
```

### Start the Approval Server

#### Method 1: systemd (recommended, auto-start on boot)

```bash
# Edit service file, replace YOUR_USERNAME
sed -i "s/YOUR_USERNAME/$(whoami)/g" ~/.claude/approve-server/claude-approve.service

# Install and start
sudo cp ~/.claude/approve-server/claude-approve.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now claude-approve

# Check status
sudo systemctl status claude-approve
```

#### Method 2: Manual start

```bash
cd ~/.claude/approve-server
source venv/bin/activate
gunicorn -w 1 --threads 2 -b 0.0.0.0:9120 app:app
```

#### Nginx Reverse Proxy (recommended with HTTPS)

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

### Configure Claude Code Hooks

Add to `~/.claude/settings.json`:

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

> **Note**: The `PermissionRequest` Hook handles both permission requests and `AskUserQuestion` events. The `Stop` Hook triggers task completion notifications.

## Approval Server API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Dashboard showing pending and recent requests |
| `/approve/<id>` | GET | Single request approval page (mobile-optimized) |
| `/api/request` | POST | Create approval request (called by notify.sh) |
| `/api/status/<id>` | GET | Query request status (polled by notify.sh) |
| `/api/approve/<id>` | POST | Submit permission approval: `approve` / `always` / `reject` |
| `/api/answer/<id>` | POST | Submit question answer: `select` / `tui` / `reject` |

### Create Approval Request

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

### Submit Approval

```bash
curl -X POST https://your-domain.com/api/approve/req-1234567890-12345 \
  -H 'Content-Type: application/json' \
  -d '{"action": "approve", "inject_key": "1"}'
```

## Configuration Reference

### notifier.conf Options

| Option | Default | Description |
|--------|---------|-------------|
| `USE_FEISHU` | `0` | Enable Feishu notifications (0=off, 1=on) |
| `FEISHU_MODE` | `webhook` | Feishu mode: `webhook` or `app` |
| `FEISHU_WEBHOOK` | - | Webhook URL (webhook mode) |
| `FEISHU_APP_ID` | - | App ID (app mode) |
| `FEISHU_APP_SECRET` | - | App secret (app mode) |
| `FEISHU_RECEIVE_TYPE` | `chat_id` | Receiver type: `open_id` / `chat_id` / `user_id` |
| `FEISHU_RECEIVE_ID` | - | Receiver ID (app mode) |
| `USE_SERVERCHAN` | `0` | Enable ServerChan |
| `SERVERCHAN_KEY` | - | ServerChan API key |
| `USE_WXWORK` | `0` | Enable WeChat Work |
| `WXWORK_WEBHOOK` | - | WeChat Work Webhook URL |
| `USE_REMOTE_APPROVE` | `0` | Enable remote approval server |
| `APPROVE_SERVER` | - | Approval server public URL |
| `APPROVE_TIMEOUT` | `300` | Approval polling timeout (seconds) |
| `APPROVE_INTERVAL` | `3` | Approval polling interval (seconds) |
| `LOG_FILE` | `~/.claude/notifier.log` | Log file path |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_NOTIFIER_CONFIG` | Custom config file path (default `~/.claude/notifier.conf`) |
| `CLAUDE_PROJECT_DIR` | Current project directory (set automatically by Claude Code) |
| `APPROVE_HOST` | Approval server listen address (default `127.0.0.1`) |
| `APPROVE_PORT` | Approval server port (default `9120`) |
| `APPROVE_EXPIRE` | Request expiry time in seconds (default `1800`) |
| `APPROVE_DEBUG` | Flask debug mode (`true`/`false`) |

## Migration

### Using a zip package

1. Package on source machine: the project provides timestamped zip packages
2. Transfer to target machine
3. Extract and follow the installation steps above
4. Edit `~/.claude/notifier.conf` with your notification channel config
5. Add Hooks to `~/.claude/settings.json`
6. If using remote approval, start approve-server and configure Nginx

### Prerequisites on Target Machine

- Python 3.8+
- tmux (recommended, for keystroke injection)
- Claude Code CLI
- curl (for HTTP API calls in notify.sh)
- Nginx (optional, for HTTPS reverse proxy)

## Logs & Debugging

Logs are written to `~/.claude/notifier.log` by default, recording every push and approval event:

```bash
# Watch live logs
tail -f ~/.claude/notifier.log

# Watch approval server logs
sudo journalctl -u claude-approve -f
```

Feishu App mode token cache is at `~/.claude/.feishu_token_cache`, auto-refreshed with a 110-minute TTL.

## Security Notes

- `notifier.conf` contains API keys — set permissions with `chmod 600 ~/.claude/notifier.conf`
- Expose the approval server through Nginx + HTTPS, don't expose port 9120 directly
- Approval requests are stored in memory and cleared on server restart
- Token cache file permissions are automatically set to 600

## License

MIT
