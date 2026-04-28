# Server酱配置教程

Server酱（方糖）是一个将消息推送到微信的服务，个人用户免费使用。

---

## 效果预览

```
微信收到消息来源：「方糖」公众号
标题：✅ Claude 任务完成
内容：Claude Code 已完成任务执行

🖥️ 服务器: your-server
🕐 时间: 2025-01-01 12:00:00
```

---

## 第一步：注册并获取 SendKey

```
1. 浏览器访问 https://sct.ftqq.com
2. 点击右上角「登录」
3. 微信扫码登录
4. 登录后点击「SendKey」
5. 复制 SendKey（格式：SCT_xxxxxxxxxxxxxxxxxx）
```

---

## 第二步：绑定微信接收端

```
1. 微信搜索公众号：「方糖」
2. 关注公众号
3. 公众号会自动绑定你的账号
4. 之后所有推送都会在这个公众号收到
```

> ⚠️ 必须用登录 sct.ftqq.com 的同一个微信账号关注公众号

---

## 第三步：配置 notifier.conf

```bash
USE_SERVERCHAN=1
SERVERCHAN_KEY="SCT_xxxxxxxxxxxxxxxxxx"
```

---

## 第四步：测试

```bash
~/.claude/notify.sh done "Server酱推送测试成功！"
```

微信「方糖」公众号应在几秒内收到消息。

```bash
# 查看推送日志
cat ~/.claude/notifier.log
```

---

## 免费版限制

| 项目 | 免费版 |
|------|--------|
| 每日推送条数 | 5条/天 |
| 消息保留时间 | 24小时 |
| 多设备推送 | ❌ |

> 如果每天触发次数较多，建议升级套餐或配合其他渠道使用

---

## 消息格式说明

Server酱支持 Markdown 格式，notifier.sh 推送内容示例：

```
标题：⚠️ Claude 需要授权确认

正文：
Claude Code 正在请求权限，请回到终端确认操作！

🖥️ 服务器: your-hostname
🕐 时间: 2025-01-01 12:00:00
```

---

## 常见问题

**Q：推送日志显示成功但微信没收到？**
```
1. 确认微信已关注「方糖」公众号
2. 确认关注的微信和登录 sct.ftqq.com 的微信是同一个
3. 检查微信是否屏蔽了公众号消息
```

**Q：返回 `{"errno":1,"errmsg":"Key not found"}`？**
```
原因：SendKey 填写错误
解决：重新登录 sct.ftqq.com 复制正确的 SendKey
```

**Q：返回 `{"errno":1,"errmsg":"Too many requests"}`？**
```
原因：超过免费版每日推送限制（5条/天）
解决：
  1. 升级 Server酱套餐
  2. 减少 PostToolUse 类型的推送频率
  3. 改用飞书或企业微信（无频率限制）
```

**Q：如何查看历史推送记录？**
```
登录 https://sct.ftqq.com → 「消息记录」查看所有推送历史
```