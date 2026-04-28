# 飞书配置教程

Claude Code Notifier 支持两种飞书接入方式，根据你的账号类型选择：

| 模式 | 适合 | 配置难度 | Token 有效期 |
|------|------|----------|-------------|
| `webhook` | 企业版飞书 | ⭐ 最简单 | 永久有效 |
| `app` | 个人版飞书 | ⭐⭐ 简单 | 自动刷新 |

---

## 模式一：Webhook（企业版推荐）

### 第一步：创建群机器人

```
1. 打开飞书，进入任意群聊
2. 点击右上角「设置」
3. 选择「群机器人」→「添加机器人」
4. 选择「自定义机器人」
5. 填写机器人名称（如：Claude Notifier）
6. 复制生成的 Webhook URL
```

### 第二步：配置 notifier.conf

```bash
USE_FEISHU=1
FEISHU_MODE="webhook"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/你复制的TOKEN"
```

### 第三步：测试

```bash
~/.claude/notify.sh done "飞书 Webhook 测试成功！"
```

---

## 模式二：App（个人版推荐）

### 第一步：创建飞书应用

```
1. 浏览器访问 https://open.feishu.cn/app
2. 点击「创建企业自建应用」
3. 填写应用名称（如：Claude Notifier）和描述
4. 进入应用 →「凭证与基础信息」
5. 复制 App ID 和 App Secret
```

### 第二步：开通权限

```
应用页面 →「权限管理」→ 搜索并开通：
  ✅ im:message:send_as_bot   （发送消息，必须）
  ✅ im:chat:readonly          （读取群信息，获取 chat_id 时需要）
```

### 第三步：发布应用

```
「版本管理与发布」→「创建版本」→ 填写版本号 → 「申请发布」→「确认发布」
```

> 个人版飞书无需审核，直接发布即可。

### 第四步：获取 chat_id 或 open_id

**推送到群（chat_id）：**

```bash
# 先手动获取一次 token
TOKEN=$(curl -s -X POST \
  'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d '{"app_id":"你的APP_ID","app_secret":"你的APP_SECRET"}' \
  | grep -o '"tenant_access_token":"[^"]*"' | cut -d'"' -f4)

# 查询机器人所在群列表
curl -s -X GET 'https://open.feishu.cn/open-apis/im/v1/chats' \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# 在返回结果中找到目标群，复制 chat_id
# 格式：oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**推送给自己（open_id）：**

```bash
# 获取自己的 open_id
curl -s 'https://open.feishu.cn/open-apis/contact/v3/users/me' \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# 复制返回结果中的 open_id
# 格式：ou_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 第五步：配置 notifier.conf

```bash
USE_FEISHU=1
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 推送到群：
FEISHU_RECEIVE_TYPE="chat_id"
FEISHU_RECEIVE_ID="oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 或推送给自己：
# FEISHU_RECEIVE_TYPE="open_id"
# FEISHU_RECEIVE_ID="ou_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### 第六步：测试

```bash
~/.claude/notify.sh done "飞书 App 模式测试成功！"

# 查看日志确认 token 刷新正常
cat ~/.claude/notifier.log
```

---

## Token 缓存机制（App 模式）

```
首次调用
  ↓
请求 API 获取 token（有效期 7200 秒）
  ↓
缓存到 ~/.claude/.feishu_token_cache
  ↓
后续每次调用先读缓存
  ↓
距获取时间 > 6600 秒？
  ↓ Yes              ↓ No
重新请求 API      直接使用缓存
```

---

## 常见问题

**Q：返回 `code: 99991663`？**
```
原因：权限不足
解决：检查是否开通 im:message:send_as_bot 权限，并确认应用已发布
```

**Q：返回 `code: 230002`？**
```
原因：机器人不在目标群中
解决：把应用机器人手动添加到目标群
     飞书群 → 设置 → 群机器人 → 添加机器人 → 找到你创建的应用
```

**Q：token 缓存文件在哪？**
```bash
cat ~/.claude/.feishu_token_cache
# 格式：时间戳|token
```