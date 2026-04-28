# 企业微信机器人配置教程

企业微信群机器人通过 Webhook 接收消息，配置简单，无推送频率限制。

---

## 效果预览

```
企业微信群收到消息：
✅ Claude 任务完成
> Claude Code 已完成任务执行
> 🖥️ your-server | 2025-01-01 12:00:00
```

---

## 前提条件

```
需要有企业微信账号
个人注册企业微信免费，不需要真实企业认证
注册地址：https://work.weixin.qq.com
```

---

## 第一步：创建企业微信群

```
1. 打开企业微信 App
2. 点击右上角「+」→「发起群聊」
3. 选择成员（至少2人，可以拉入自己的小号）
4. 创建群聊
```

> 也可以使用已有的企业微信群

---

## 第二步：添加群机器人

```
1. 进入目标群聊
2. 点击右上角「···」（更多）
3. 选择「群机器人」→「添加机器人」
4. 点击「新创建一个机器人」
5. 填写机器人名称（如：Claude Notifier）
6. 点击「添加机器人」
7. 复制生成的 Webhook 地址
```

Webhook 格式：
```
https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

## 第三步：配置 notifier.conf

```bash
USE_WXWORK=1
WXWORK_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY"
```

---

## 第四步：测试

```bash
~/.claude/notify.sh done "企业微信推送测试成功！"
```

企业微信群应在几秒内收到消息。

```bash
# 查看推送日志
cat ~/.claude/notifier.log
```

---

## 消息格式

企业微信机器人支持 Markdown，推送效果示例：

```markdown
## ⚠️ Claude 需要授权确认
> Claude Code 正在请求权限，请回到终端确认操作！
> 🖥️ your-server | 2025-01-01 12:00:00

## ✅ Claude 任务完成
> Claude Code 已完成任务执行
> 🖥️ your-server | 2025-01-01 12:00:00

## ❌ Claude 发生错误
> Claude Code 遇到错误，请检查终端！
> 🖥️ your-server | 2025-01-01 12:00:00
```

---

## 企业微信 vs 其他渠道对比

| 对比项 | 企业微信机器人 | Server酱 | 飞书 Webhook |
|--------|--------------|----------|-------------|
| 推送频率限制 | 20条/分钟 | 5条/天（免费版） | 无限制 |
| 是否需要注册 | 需要企业微信账号 | 微信账号即可 | 飞书账号 |
| 消息样式 | Markdown | Markdown | 卡片消息 |
| 适合人群 | 企业用户 | 个人用户 | 均可 |

---

## 常见问题

**Q：返回 `{"errcode":93000,"errmsg":"invalid webhook url"}`？**
```
原因：Webhook URL 填写错误
解决：重新进入群机器人设置复制完整 URL
```

**Q：返回 `{"errcode":45033,"errmsg":"exceed max api daily quota"}`？**
```
原因：超过每分钟 20 条推送限制
解决：减少 PostToolUse 类型的推送频率
     settings.json 中为 PostToolUse 指定具体 matcher
     而不是留空匹配所有工具
```

**Q：Webhook 泄露了怎么办？**
```
1. 企业微信群 → 群机器人 → 选中机器人 → 「重置 Webhook」
2. 更新 notifier.conf 中的 WXWORK_WEBHOOK
```

**Q：能推送到多个企业微信群吗？**
```bash
# 在 notify.sh 末尾 send_wxwork 函数中
# 支持配置多个 Webhook，修改如下：

send_wxwork() {
  [ "${USE_WXWORK:-0}" -eq 0 ] && return
  local content=$1

  # 支持多个群
  for webhook in "$WXWORK_WEBHOOK" "${WXWORK_WEBHOOK_2:-}" "${WXWORK_WEBHOOK_3:-}"; do
    [ -z "$webhook" ] && continue
    curl -s -X POST "$webhook" \
      -H 'Content-Type: application/json' \
      -d "{\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"$content\"}}"
  done
}

# notifier.conf 中添加：
WXWORK_WEBHOOK_2="第二个群的 Webhook"
```