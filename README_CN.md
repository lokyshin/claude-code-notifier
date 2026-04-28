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

| 渠道 | 接收端 | 适合人群 | 频率限制 |
|------|--------|----------|----------|
| **飞书 Webhook** | 飞书 App | 企业版用户 | 无限制 |
| **飞书 App** | 飞书 App | 个人版用户 | 无限制 |
| **Server酱** | 个人微信 | 个人用户 | 5条/天（免费版）|
| **企业微信机器人** | 企业微信 | 企业用户 | 20条/分钟 |

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
    ├── feishu.md             ← 飞书配置教程（含双模式）
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

## 飞书：两种接入模式

飞书根据账号类型提供两种接入方式：

### 模式一：Webhook（企业版推荐）

```bash
# 飞书群 → 设置 → 群机器人 → 添加自定义机器人 → 复制 Webhook
FEISHU_MODE="webhook"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN"
```

### 模式二：App（个人版推荐）

> 个人版飞书无法添加群机器人，需在开放平台创建应用。  
> Token 每 2 小时过期，脚本会自动刷新，无需手动维护。

```bash
# 在 https://open.feishu.cn/app 创建应用后填入
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
FEISHU_RECEIVE_TYPE="chat_id"           # chat_id（群）或 open_id（个人）
FEISHU_RECEIVE_ID="oc_xxxxxxxxxxxxxxxx"
```

Token 缓存机制：
```
首次调用 → 请求 token（有效期 7200 秒）→ 缓存到 ~/.claude/.feishu_token_cache
后续调用 → 读取缓存 → 距过期不足 10 分钟时自动刷新
```

→ 完整教程：[docs/feishu.md](docs/feishu.md)

---

## 配置说明

安装完成后编辑 `~/.claude/notifier.conf`：

```bash
# ── 飞书 ────────────────────────────────────────────────────
USE_FEISHU=1
FEISHU_MODE="webhook"                   # webhook 或 app，二选一

# webhook 模式填这个
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN"

# app 模式填这些
# FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
# FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# FEISHU_RECEIVE_TYPE="chat_id"
# FEISHU_RECEIVE_ID="oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# ── Server酱（微信推送）────────────────────────────────────
USE_SERVERCHAN=0
SERVERCHAN_KEY="YOUR_SENDKEY"

# ── 企业微信机器人 ──────────────────────────────────────────
USE_WXWORK=0
WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY"
```

把想启用的渠道设为 `1`，其余保持 `0`。多个渠道可以同时开启。

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

- [飞书配置教程（Webhook + App 双模式）](docs/feishu.md)
- [Server酱配置教程](docs/serverchan.md)
- [企业微信机器人配置教程](docs/wxwork.md)

---

## 远程审批（高级功能）

在手机上直接审批 Claude Code 的权限请求，无需回到终端操作。

```
Claude Code → notify.sh → Flask 审批服务 → 飞书/微信通知（带链接）
                                ↑                    ↓
                          轮询获取结果 ←── 手机点击 允许/拒绝
```

### 快速部署

```bash
# 安装审批服务
cd claude-code-notifier/approve-server
pip3 install -r requirements.txt
python3 app.py  # 监听端口 9120
```

### 配置

```bash
# 在 ~/.claude/notifier.conf 中添加
USE_REMOTE_APPROVE=1
APPROVE_SERVER="https://approve.yourdomain.com"
```

### 三种审批决策

| 按钮 | 效果 |
|------|------|
| ✅ 允许本次 | 仅允许当前这一次操作 |
| ✅ 始终允许 | 以后同类操作自动允许，不再询问 |
| ❌ 拒绝 | 阻止当前操作 |

→ 完整教程：[docs/remote-approve.md](docs/remote-approve.md)

## 环境要求

- Bash 4+
- `curl`（Linux 一般自带，运行 `curl --version` 确认）
- `python3`（飞书 App 模式需要，用于 JSON 转义）
- 已安装 Claude Code
- 至少配置一个推送渠道

---

## 扩展新渠道

所有渠道逻辑都在 `notify.sh` 中，扩展只需三步：

```bash
# 1. notifier.conf.example 新增配置项
USE_NEWCHANNEL=0
NEWCHANNEL_KEY="YOUR_KEY"

# 2. notify.sh 新增发送函数
send_newchannel() {
  [ "${USE_NEWCHANNEL:-0}" -eq 0 ] && return
  curl -s ...
}

# 3. notify_all() 里调用
notify_all() {
  ...
  send_newchannel "$$title" "$$msg"
}
```

> `settings.json` 完全不需要改动，所有渠道扩展只修改 `notify.sh`。

---

## 常见问题

**Q：写入 settings.json 后需要重启什么吗？**
```
不需要，Claude Code 启动时自动读取配置，无需重启任何服务。
```

**Q：notify.sh 执行了但没收到通知？**
```
查看日志：cat ~/.claude/notifier.log
确认 curl 返回值是否正常，根据错误码对照各渠道文档排查。
```

**Q：能同时推送到多个渠道吗？**
```
可以，把多个渠道都设为 USE_xxx=1 即可同时推送。
```

**Q：飞书个人版和企业版怎么区分？**
```
企业版：可以在群里添加「自定义机器人」→ 用 webhook 模式
个人版：群设置里没有机器人选项 → 用 app 模式
```

**Q：PostToolUse 每步都通知太频繁怎么办？**
```
在 settings.json 中用 matcher 指定特定工具：
"matcher": "Bash"   只监听 Shell 命令
"matcher": "Write"  只监听文件写入
```

---

## License

MIT © 2026