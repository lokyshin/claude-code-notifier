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

| Channel | Platform | Best For |
|---------|----------|----------|
| **Feishu 飞书** | Feishu App | Enterprise / Personal |
| **Server Chan 方糖** | WeChat | Personal |
| **WxWork Bot 企业微信** | WeChat Work | Enterprise |

> Multiple channels can be enabled at the same time.

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
    ├── feishu.md             ← Feishu setup guide
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

## Configuration

After installation, edit `~/.claude/notifier.conf`:

```bash
# ── Feishu Bot ──────────────────────────────────────────────
USE_FEISHU=1
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN"

# ── Server Chan (WeChat) ────────────────────────────────────
USE_SERVERCHAN=0
SERVERCHAN_KEY="YOUR_SENDKEY"

# ── WxWork Bot ──────────────────────────────────────────────
USE_WXWORK=0
WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY"
```

Set the channel you want to `1`, leave others at `0`.

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

- [Feishu Bot Setup](docs/feishu.md)
- [Server Chan Setup](docs/serverchan.md)
- [WxWork Bot Setup](docs/wxwork.md)

---

## Requirements

- Bash 4+
- `curl` (pre-installed on most Linux distros)
- A Claude Code installation
- One of the supported notification channels

---

## Contributing

PRs are welcome! Ideas for new channels:

- [ ] Telegram Bot
- [ ] Bark (iOS)
- [ ] Ntfy
- [ ] DingTalk 钉钉

---

## License

MIT © 2025