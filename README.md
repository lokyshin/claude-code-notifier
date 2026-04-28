# Claude Code Notifier 🔔

> Get instant push notifications on your phone when Claude Code needs your attention or completes a task — works on remote Linux servers.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)

[中文文档](README_CN.md)

---

## Why

When running Claude Code on a remote Linux server, you can't hear sound alerts or see desktop popups. This tool hooks into Claude Code's event system and pushes notifications directly to your phone via your preferred messaging platform.

```
Claude Code (Remote Linux Server)
        ↓  Hook triggered
  ~/.claude/notify.sh
        ↓  curl API call
   Feishu / WeChat / WxWork
        ↓
   Your Phone 📱
```

---

## Supported Channels

| Channel | Platform | Best For | Limit |
|---------|----------|----------|-------|
| **Feishu Webhook** | Feishu App | Enterprise users | Unlimited |
| **Feishu App** | Feishu App | Personal users | Unlimited |
| **Server Chan** | WeChat | Personal users | 5/day (free) |
| **WxWork Bot** | WeChat Work | Enterprise users | 20/min |

> Multiple channels can be enabled simultaneously.

---

## Project Structure

```
claude-code-notifier/
├── README.md                 ← English documentation
├── README_CN.md              ← Chinese documentation
├── LICENSE                   ← MIT License
├── install.sh                ← One-click install script
├── notify.sh                 ← Core notification script
├── notifier.conf.example     ← Configuration template
├── settings.example.json     ← Claude Code hook config
├── .gitignore
└── docs/
    ├── feishu.md             ← Feishu setup guide (both modes)
    ├── serverchan.md         ← Server Chan setup guide
    └── wxwork.md             ← WxWork setup guide
```

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/YOUR_USERNAME/claude-code-notifier.git
cd claude-code-notifier

# 2. Run the installer
bash install.sh

# 3. Edit your config — fill in your Webhook / Key
nano ~/.claude/notifier.conf

# 4. Test it
~/.claude/notify.sh done "Claude Code Notifier is working!"

# 5. Check logs
tail -f ~/.claude/notifier.log
```

---

## Hook Events

| Event | Hook Type | When It Fires |
|-------|-----------|---------------|
| `permission` | `PermissionRequest` | Claude requests authorization (file write, shell exec, etc.) |
| `done` | `Stop` | Entire task completed or Claude exits |
| `error` | `Stop` | Claude encounters an unrecoverable error |
| `tool` | `PostToolUse` | A single tool call finishes (optional, high frequency) |

---

## Feishu: Two Modes

Feishu (Lark) supports two integration modes depending on your account type:

### Mode 1 — Webhook (Enterprise accounts)

```bash
# Add a custom bot in any Feishu group → copy the Webhook URL
FEISHU_MODE="webhook"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN"
```

### Mode 2 — App (Personal accounts)

> Personal Feishu accounts cannot create group bots.  
> Use an Open Platform app instead — token is refreshed automatically.

```bash
# Create an app at https://open.feishu.cn/app
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
FEISHU_RECEIVE_TYPE="chat_id"           # chat_id (group) or open_id (personal)
FEISHU_RECEIVE_ID="oc_xxxxxxxxxxxxxxxx"
```

Token cache mechanism:
```
First call → fetch token (valid 7200s) → cache to ~/.claude/.feishu_token_cache
Next calls → read cache → auto refresh 10 min before expiry
```

→ Full guide: [docs/feishu.md](docs/feishu.md)

---

## Configuration

After installation, edit `~/.claude/notifier.conf`:

```bash
# ── Feishu ──────────────────────────────────────────────────
USE_FEISHU=1
FEISHU_MODE="webhook"                   # webhook or app
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN"

# ── Server Chan (WeChat) ────────────────────────────────────
USE_SERVERCHAN=0
SERVERCHAN_KEY="YOUR_SENDKEY"

# ── WxWork Bot ──────────────────────────────────────────────
USE_WXWORK=0
WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY"
```

Set the channels you want to `1`, leave others at `0`.  
Multiple channels can be active at the same time.

---

## Claude Code settings.json

The installer handles this automatically.  
To configure manually, add to `~/.claude/settings.json`:

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

---

## Channel Setup Guides

- [Feishu Setup (Webhook + App modes)](docs/feishu.md)
- [Server Chan Setup](docs/serverchan.md)
- [WxWork Bot Setup](docs/wxwork.md)

---

## Remote Approval (Advanced)

Approve Claude Code permission requests directly from your phone — no need to go back to the terminal.

```
Claude Code → notify.sh → Flask Server → Phone Notification (with link)
                                ↑               ↓
                          Poll for result ← Tap Approve/Reject on phone
```

### Quick Setup

```bash
# Install approval server
cd claude-code-notifier/approve-server
pip3 install -r requirements.txt
python3 app.py  # listens on port 9120
```

### Configure

```bash
# In ~/.claude/notifier.conf
USE_REMOTE_APPROVE=1
APPROVE_SERVER="https://approve.yourdomain.com"
```

### Three Decisions

| Button | Effect |
|--------|--------|
| ✅ Allow Once | Approve this single operation |
| ✅ Always Allow | Auto-approve this type of operation going forward |
| ❌ Reject | Block the operation |

→ Full guide: [docs/remote-approve.md](docs/remote-approve.md)

## Requirements

- Bash 4+
- `curl` (pre-installed on most Linux distros)
- `python3` (for Feishu App mode JSON escaping)
- A Claude Code installation
- At least one notification channel configured

---

## Adding a New Channel

All channel logic is in `notify.sh`. To add a new channel:

```bash
# 1. Add config in notifier.conf.example
USE_NEWCHANNEL=0
NEWCHANNEL_KEY="YOUR_KEY"

# 2. Add send function in notify.sh
send_newchannel() {
  [ "${USE_NEWCHANNEL:-0}" -eq 0 ] && return
  curl -s ...
}

# 3. Call it inside notify_all()
notify_all() {
  ...
  send_newchannel "$$title" "$$msg"
}
```

> `settings.json` never needs to change when adding channels.

---

## License

MIT © 2026