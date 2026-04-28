# 飞书配置教程

Claude Code Notifier 支持三种飞书使用场景：

| 场景 | 适合 | 配置难度 | Token 有效期 |
|------|------|----------|-------------|
| A: Webhook | 企业版飞书，推送到群 | ⭐ 最简单 | 永久有效 |
| B: App → 群 | 个人版飞书，推送到群 | ⭐⭐ 简单 | 自动刷新 |
| C: App → 个人 | 个人版飞书，推送给自己 | ⭐⭐ 简单 | 自动刷新 |

> 不确定选哪种？打开飞书任意群 → 设置  
> 看得到「群机器人」→ 场景 A  
> 看不到「群机器人」→ 场景 B 或 C

---

## 场景 A：Webhook（企业版推荐）

### 获取 Webhook URL

```
1. 打开飞书，进入任意群聊
2. 点击右上角「设置」→「群机器人」→「添加机器人」
3. 选择「自定义机器人」，填写名称
4. 复制生成的 Webhook URL
```

### 配置

```bash
USE_FEISHU=1
FEISHU_MODE="webhook"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/你的TOKEN"
```

---

## 场景 B：App 推送到群（个人版）

### 创建应用

```
1. 浏览器访问 https://open.feishu.cn/app
2. 创建「企业自建应用」
3. 填写应用名称（如：Claude Notifier）
4. 凭证与基础信息 → 复制 App ID 和 App Secret
5. 权限管理 → 开通 im:message:send_as_bot
6. 版本管理 → 创建版本 → 申请发布
```

### 获取 chat_id

```bash
# 获取 token
TOKEN=$(curl -s -X POST \
  'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d '{"app_id":"你的APP_ID","app_secret":"你的APP_SECRET"}' \
  | grep -o '"tenant_access_token":"[^"]*"' | cut -d'"' -f4)

# 查询群列表（需先把机器人拉进群）
curl -s 'https://open.feishu.cn/open-apis/im/v1/chats' \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# 复制目标群的 chat_id（格式：oc_xxx）
```

### 配置

```bash
USE_FEISHU=1
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
FEISHU_RECEIVE_TYPE="chat_id"
FEISHU_RECEIVE_ID="oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

---

## 场景 C：App 推送给自己（个人版推荐）

### 创建应用

同场景 B 步骤 1-6。

### 获取 open_id

```bash
# 获取 token（同上）
TOKEN=$(curl -s -X POST \
  'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d '{"app_id":"你的APP_ID","app_secret":"你的APP_SECRET"}' \
  | grep -o '"tenant_access_token":"[^"]*"' | cut -d'"' -f4)

# 获取自己的信息
curl -s 'https://open.feishu.cn/open-apis/contact/v3/users/me' \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# 复制 open_id（格式：ou_xxx）
```

### 配置

```bash
USE_FEISHU=1
FEISHU_MODE="app"
FEISHU_APP_ID="cli_xxxxxxxxxxxxxxxx"
FEISHU_APP_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
FEISHU_RECEIVE_TYPE="open_id"
FEISHU_RECEIVE_ID="ou_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

---

## Token 缓存机制（场景 B、C）

```
首次调用 → 请求 token（有效期 7200 秒）→ 缓存到 ~/.claude/.feishu_token_cache
后续调用 → 读取缓存 → 距过期不足 10 分钟时自动刷新
```

---

## 测试

```bash
~/.claude/notify.sh done "飞书推送测试"

# 查看日志
tail -5 ~/.claude/notifier.log
```

---

## 常见问题

**Q：返回 code 99991663？**
```
权限不足。确认已开通 im:message:send_as_bot 且应用已发布。
```

**Q：返回 code 230002？**
```
机器人不在目标群中。将应用机器人手动添加到目标群。
```

**Q：场景 C 收不到消息？**
```
确认 FEISHU_RECEIVE_TYPE 设为 open_id（不是 chat_id）。
确认 open_id 是你自己的（ou_ 开头）。
```