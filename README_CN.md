# Claude Code Notifier 🔔

> 在远程服务器运行 Claude Code 时，实时推送任务状态到你的手机。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)

[English Documentation](README.md)

---

## 为什么需要这个工具

在远程 Linux 服务器上运行 Claude Code 时，你无法听到提示音，也看不到桌面弹窗。  
这个工具通过 Claude Code 的 Hook 机制，在任务完成或需要你确认时，直接把通知推送到手机。

```
Claude Code（远程 Linux 服务器）
        ↓  Hook 触发
  ~/.claude/notify.sh
        ↓  curl 调用 API
   飞书 / 微信 / 企业微信
        ↓
   你的手机 📱
```

---

## 支持的推送渠道

| 渠道 | 接收端 | 适合人群 |
|------|--------|----------|
| **飞书机器人** | 飞书 App | 个人 / 企业均可 |
| **Server酱（方糖）** | 个人微信 | 个人用户 |
| **企业微信机器人** | 企业微信 | 企业用户 |

> 多个渠道可以同时开启。

---

## 项目结构

```
claude-code-notifier/
├── README.md                 ← 英文文档
├── README_CN.md              ← 中文文档（当前文件）
├── LICENSE                   ← MIT 开源协议
├── install.sh                ← 一键安装脚本
├── notify.sh                 ← 核心推送脚本
├── notifier.conf.example     ← 配置文件模板
├── settings.example.json     ← Claude Code Hook 配置示例
├── .gitignore
└── docs/
    ├── feishu.md             ← 飞书配置教程
    ├── serverchan.md         ← Server酱配置教程
    └── wxwork.md             ← 企业微信配置教程
```

---

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/YOUR_USERNAME/claude-code-notifier.git
cd claude-code-notifier

# 2. 一键安装
bash install.sh

# 3. 编辑配置文件，填入你的 Webhook 或 Key
nano ~/.claude/notifier.conf

# 4. 测试推送
~/.claude/notify.sh done "Claude Code Notifier 配置成功！"

# 5. 查看日志
tail -f ~/.claude/notifier.log
```

---

## Hook 事件说明

| 事件参数 | 对应 Hook 类型 | 触发时机 |
|---------|--------------|---------|
| `permission` | `PermissionRequest` | Claude 请求权限时（写文件、执行命令等需要你确认） |
| `done` | `Stop` | 整个任务完成，或 Claude 主动退出 |
| `error` | `Stop` | Claude 遇到无法继续的错误 |
| `tool` | `PostToolUse` | 单个工具调用完成后（可选，频率较高） |

---

## 配置说明

安装完成后编辑 `~/.claude/notifier.conf`：

```bash
# ── 飞书机器人 ──────────────────────────────────────────────
# 获取方式：飞书群 → 设置 → 群机器人 → 添加自定义机器人
USE_FEISHU=1
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/你的TOKEN"

# ── Server酱（微信推送）────────────────────────────────────
# 获取方式：https://sct.ftqq.com 微信登录后获取 SendKey
USE_SERVERCHAN=0
SERVERCHAN_KEY="你的SENDKEY"

# ── 企业微信机器人 ──────────────────────────────────────────
# 获取方式：企业微信群 → 右键群名 → 添加群机器人
USE_WXWORK=0
WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY"
```

把想启用的渠道设为 `1`，其余保持 `0` 即可。

---

## Claude Code 配置

安装脚本会自动处理。如需手动配置，将以下内容写入 `~/.claude/settings.json`：

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

## 各渠道配置教程

- [飞书机器人配置教程](docs/feishu.md)
- [Server酱配置教程](docs/serverchan.md)
- [企业微信机器人配置教程](docs/wxwork.md)

---

## 环境要求

- Bash 4+
- `curl`（Linux 一般自带，可用 `curl --version` 确认）
- 已安装 Claude Code
- 至少配置一个推送渠道

---

## 常见问题

**Q：写入 settings.json 后需要重启什么吗？**  
A：不需要，Claude Code 启动时自动读取配置，无需重启任何服务。

**Q：notify.sh 执行了但没收到通知？**  
A：查看日志 `cat ~/.claude/notifier.log`，确认 curl 返回值是否正常。

**Q：能同时推送到多个渠道吗？**  
A：可以，把多个渠道都设为 `USE_xxx=1` 即可同时推送。

**Q：PostToolUse 每步都通知太频繁怎么办？**  
A：在 `settings.json` 中用 `matcher` 指定特定工具，例如只监听 `"Bash"`。

---

## 参与贡献

欢迎提交 PR！期待支持更多渠道：

- [ ] Telegram Bot
- [ ] Bark（iOS）
- [ ] Ntfy
- [ ] 钉钉机器人

---

## License

MIT © 2026