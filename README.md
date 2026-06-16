<p align="center">
  <img src="images/logo.svg" width="120" height="120" alt="Claude Code Notifier Logo">
</p>

<h1 align="center">Claude Code Notifier</h1>

<p align="center">
  Push Claude Code events to your phone in real time.<br>
  Approve permissions, answer questions, track task completion — all from your phone.<br>
  Keystrokes auto-injected into the terminal. No more waiting at the screen.
</p>

<p align="center">
  <a href="README_CN.md">中文文档</a>
</p>

---

## Screenshots

> Feishu (Lark) as an example. ServerChan and WeChat Work are also supported.

### Notification Cards

Task completion and permission requests arrive as rich cards in your chat.

<p align="center">
  <img src="images/1_notification.png" width="320">
</p>

### Permission Request → Remote Approval

Tap the card to open the approval page. See the operation type, risk level, file path, and full input details. Choose **Yes** / **Yes, always** / **No** — keystroke is injected into the terminal automatically.

<table>
  <tr>
    <td align="center" width="50%">
      <img src="images/2_request.jpg" width="280"><br>
      <sub>Approval page with operation details</sub>
    </td>
    <td align="center" width="50%">
      <img src="images/3_approved.png" width="280"><br>
      <sub>After tapping "Yes, always"</sub>
    </td>
  </tr>
</table>

### Single Question

When Claude asks a question (`AskUserQuestion`), your phone shows the full question and options. Select an answer or go back to the terminal.

<table>
  <tr>
    <td align="center" width="50%">
      <img src="images/4_single_question.png" width="280"><br>
      <sub>Question notification in chat</sub>
    </td>
    <td align="center" width="50%">
      <img src="images/5_single_question.png" width="280"><br>
      <sub>Approval page with options</sub>
    </td>
  </tr>
</table>

### Multi-Question with Tabs

Multiple questions are displayed as tabs. Answer each one, then submit all at once.

<table>
  <tr>
    <td align="center" width="33%">
      <img src="images/6_multi_question.png" width="220"><br>
      <sub>Notification listing all questions</sub>
    </td>
    <td align="center" width="33%">
      <img src="images/7_multi_question.jpg" width="220"><br>
      <sub>Tab view — answering Q1</sub>
    </td>
    <td align="center" width="34%">
      <img src="images/8_multi_question.png" width="220"><br>
      <sub>All answered — ready to submit</sub>
    </td>
  </tr>
</table>

### Task Completion

When Claude finishes, you get a rich notification with the project name, working directory, and a full task summary — instantly distinguish which session completed and what it did.

<p align="center">
  <img src="images/9_task_complete.jpg" width="320">
</p>

---

## Features

**Permission Approval** — Phone notification with operation type, risk level, and command/file details. Tap Allow / Always Allow / Reject, result injected into terminal.

**Question Selection** — Full question and options on phone. Supports single-select, multi-select, and multi-question tabs. Selection auto-sent back to terminal.

**Task Completion** — Rich notification with project name (from `cwd`), working directory, and task summary from `last_assistant_message` (markdown stripped, max 500 chars).

**TUI Option Sync** — Approval buttons match the terminal TUI (2 or 3 buttons). "Always" description parsed from `permission_suggestions`.

**Keystroke Injection** — Three methods, auto-detected:
1. **tmux send-keys** (recommended)
2. **TIOCSTI ioctl** (fallback)
3. **Notification-only** (if neither available)

---

### Hook Subprocess Loses tmux Environment Variables

**Problem**: Claude Code executes `notify.sh` as a hook subprocess. This subprocess may not inherit `$TMUX` and `$TMUX_PANE` environment variables, resulting in:

```
remote-approve | no TTY and no tmux pane found, skip polling
```

**Solution**: Add dynamic detection to `~/.claude/notifier.conf`:

```bash
# ── tmux (hook subprocess may lose TMUX/TMUX_PANE, auto-detect) ──
if [ -z "$TMUX" ]; then
  _tmux_sock=$(find /tmp/tmux-$(id -u)/ -type s 2>/dev/null | head -1)
  if [ -n "$_tmux_sock" ]; then
    _tmux_pid=$(tmux -S "$_tmux_sock" display-message -p '#{pid}' 2>/dev/null)
    TMUX="${_tmux_sock},${_tmux_pid:-0},0"
    export TMUX
  fi
fi
if [ -z "$TARGET_PANE" ] && [ -z "$TMUX_PANE" ]; then
  TARGET_PANE=$(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
    | grep -i 'claude\|node\|bun' | head -1 | awk '{print $1}')
  [ -z "$TARGET_PANE" ] && TARGET_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
fi
```

This config is portable — copy to any new server without modification. Logic:

1. If `$TMUX` exists (normal case) → use it directly
2. If missing → auto-discover the current user's tmux socket and rebuild the variable
3. If neither `$TARGET_PANE` nor `$TMUX_PANE` exist → find the pane running claude/node/bun

---

**Multi-Channel** — Enable one or more simultaneously:
- **Feishu** — Webhook (group bot) or App (personal), with interactive cards
- **ServerChan** — Push to WeChat
- **WeChat Work** — Group bot Webhook

**Approval Server** — Flask server with mobile-first page, dashboard, RESTful API, auto-expiring requests.

---

## How It Works

```
Claude Code TUI (permission / question)
        │
  Hook → notify.sh (reads stdin JSON)
        │
   ┌────┴────┐
   ▼         ▼
 Push      approve-server
 notification   POST /api/request
   │              │
   ▼              ▼
 Phone ──→ Approval page (mobile Web UI)
              │
         Tap Allow / Reject / Select
              │
         POST /api/approve or /api/answer
              │
         notify.sh polls /api/status
              │
         tmux send-keys → terminal
              │
         Claude Code continues
```

---

## Project Structure

```
claude-code-notifier/
├── notify.sh                     # Hook entry, parsing, push, polling, key injection
├── notifier.conf.example         # Config template
├── README.md / README_CN.md      # Docs
├── images/                       # Logo and screenshots
└── approve-server/
    ├── app.py                    # Backend API
    ├── templates/approve.html    # Mobile approval page
    ├── requirements.txt          # Python deps
    └── claude-approve.service    # systemd template
```

---

## Installation

### Clone from GitHub

```bash
git clone https://github.com/lokyshin/claude-code-notifier.git
cd claude-code-notifier

cp notify.sh ~/.claude/notify.sh && chmod +x ~/.claude/notify.sh
cp notifier.conf.example ~/.claude/notifier.conf

cp -r approve-server ~/.claude/approve-server
cd ~/.claude/approve-server
python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt
```

### From zip package

```bash
unzip claude-code-notifier-*.zip -d /tmp/ccn
cp /tmp/ccn/notify.sh ~/.claude/notify.sh && chmod +x ~/.claude/notify.sh
cp /tmp/ccn/notifier.conf.example ~/.claude/notifier.conf
cp -r /tmp/ccn/approve-server ~/.claude/approve-server
cd ~/.claude/approve-server
python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt
```

Then edit `~/.claude/notifier.conf` with your channel credentials.

---

## Configuration

### Notification Channels

Edit `~/.claude/notifier.conf`, enable at least one:

**Feishu App** (recommended):
```bash
USE_FEISHU=1
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
FEISHU_RECEIVE_TYPE="open_id"
FEISHU_RECEIVE_ID="ou_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

**Feishu Webhook**:
```bash
USE_FEISHU=1
FEISHU_MODE="webhook"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx-xxxx"
```

**ServerChan** (WeChat): `USE_SERVERCHAN=1` + `SERVERCHAN_KEY="SCTxxx..."`

**WeChat Work**: `USE_WXWORK=1` + `WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/..."`

### Remote Approval

```bash
USE_REMOTE_APPROVE=1
APPROVE_SERVER="https://your-domain.com"
APPROVE_INTERVAL=3
APPROVE_EXPIRE=300
```

> **Security**: The approval API has no built-in auth. Keep `APPROVE_EXPIRE` short (120-300s). For internet-facing servers, add Nginx Basic Auth or mTLS.

### Claude Code Hooks

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "~/.claude/notify.sh permission", "timeout": 10 }]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "~/.claude/notify.sh done", "timeout": 10 }]
      }
    ]
  }
}
```

> `PermissionRequest` handles both permission requests and `AskUserQuestion` events.

---

## Starting the Approval Server

**systemd** (recommended):
```bash
sed -i "s/YOUR_USERNAME/$(whoami)/g" ~/.claude/approve-server/claude-approve.service
sudo cp ~/.claude/approve-server/claude-approve.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now claude-approve
```

**Manual**:
```bash
cd ~/.claude/approve-server && source venv/bin/activate
gunicorn -w 1 --threads 2 -b 0.0.0.0:9120 app:app
```

**Nginx** (HTTPS):
```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;
    ssl_certificate /path/to/cert.pem;
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

---

### Split Deployment

When Claude Code runs on an internal/cloud server (e.g., AWS) that cannot be directly accessed by your phone, you can deploy the approval server separately on a publicly accessible machine.

**Architecture**:

```
┌─ Internal Server (Claude Code) ─┐    ┌─ Public Server (Approval) ─┐    ┌─ Phone ─┐
│                                  │    │                            │    │         │
│ notify.sh ──outbound POST────→   │ ─→ │ Flask:9120                 │ ←─ │ Feishu  │
│            ──outbound poll────→  │ ─→ │ (approval page)            │ ─→ │ approve │
│ tmux inject ← gets result        │    │                            │    │         │
└──────────────────────────────────┘    └────────────────────────────┘    └─────────┘
```

**Key points**:
- Internal server only needs outbound network — no inbound ports required
- Approval page is on the public server — phone accesses it directly
- Multiple Claude Code instances can share one approval server (distinguished by hostname)

**Internal server config**:

```bash
# ~/.claude/notifier.conf
USE_REMOTE_APPROVE=1
APPROVE_SERVER="https://your-public-domain.com"   # points to remote approval server
APPROVE_INTERVAL=3
APPROVE_EXPIRE=300
```

**Public server**: only needs `approve-server/` deployed with Nginx + HTTPS.

---

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Dashboard |
| `/approve/<id>` | GET | Approval page (mobile) |
| `/api/request` | POST | Create request (notify.sh) |
| `/api/status/<id>` | GET | Query status (notify.sh polls) |
| `/api/approve/<id>` | POST | Permission: `approve` / `always` / `reject` |
| `/api/answer/<id>` | POST | Question answer |

---

## Config Reference

| Option | Default | Description |
|--------|---------|-------------|
| `USE_FEISHU` | `0` | Enable Feishu |
| `FEISHU_MODE` | `webhook` | `webhook` or `app` |
| `FEISHU_WEBHOOK` | - | Webhook URL |
| `FEISHU_APP_ID` / `APP_SECRET` | - | App credentials |
| `FEISHU_RECEIVE_TYPE` | `chat_id` | `open_id` / `chat_id` / `user_id` |
| `FEISHU_RECEIVE_ID` | - | Receiver ID |
| `USE_SERVERCHAN` | `0` | Enable ServerChan |
| `SERVERCHAN_KEY` | - | API key |
| `USE_WXWORK` | `0` | Enable WeChat Work |
| `WXWORK_WEBHOOK` | - | Webhook URL |
| `USE_REMOTE_APPROVE` | `0` | Enable approval server |
| `APPROVE_SERVER` | - | Server URL |
| `APPROVE_INTERVAL` | `3` | Poll interval (s) |
| `APPROVE_EXPIRE` | `300` | Request expiry + poll timeout (s) |
| `TARGET_PANE` | (auto-detect) | Force a specific tmux pane ID (e.g., `%1`) for cases where hook subprocesses cannot auto-detect |
| `LOG_FILE` | `~/.claude/notifier.log` | Log path |

| Env Variable | Description |
|-------------|-------------|
| `CLAUDE_NOTIFIER_CONFIG` | Config path (default `~/.claude/notifier.conf`) |
| `CLAUDE_PROJECT_DIR` | Project dir (set by Claude Code) |
| `APPROVE_HOST` / `APPROVE_PORT` | Server bind (default `127.0.0.1:9120`) |
| `APPROVE_EXPIRE` | Request expiry (default `300`) |
| `APPROVE_DEBUG` | Flask debug mode |

---

## Prerequisites

- Python 3.8+ / tmux (recommended) / Claude Code CLI / curl / Nginx (optional)

## Logs & Security

```bash
tail -f ~/.claude/notifier.log          # notify.sh logs
sudo journalctl -u claude-approve -f    # approval server logs
```

- `chmod 600 ~/.claude/notifier.conf` — contains API keys
- Expose approval server via Nginx + HTTPS, not port 9120 directly
- Requests stored in memory, cleared on restart
- Token cache permissions auto-set to 600

## License

MIT
