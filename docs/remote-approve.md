# 远程审批配置教程

在手机上直接审批 Claude Code 的权限请求，无需回到终端。

---

## 架构

```
Claude Code 实例 A ──┐
Claude Code 实例 B ──┼──→ notify.sh ──→ Flask 审批服务
Claude Code 实例 C ──┘         ↓              ↓
                          飞书/微信通知    手机审批页面
                         （带审批链接）   （允许/始终/拒绝）
                                              ↓
                                     notify.sh 轮询获取结果
                                              ↓
                                     返回给 Claude Code
```

---

## 部署审批服务

### 基础部署

```bash
cd claude-code-notifier/approve-server

# 安装依赖
pip3 install -r requirements.txt

# 启动（开发模式）
python3 app.py
# 默认监听 0.0.0.0:9120
```

### 生产环境部署

```bash
pip3 install gunicorn

# 前台运行
gunicorn -w 2 -b 0.0.0.0:9120 app:app

# 后台运行
nohup gunicorn -w 2 -b 0.0.0.0:9120 app:app > approve.log 2>&1 &

# 或用 systemd（推荐）
```

### systemd 服务文件

```ini
# /etc/systemd/system/claude-approve.service
[Unit]
Description=Claude Code Approval Server
After=network.target

[Service]
User=your_user
WorkingDirectory=/home/your_user/.claude/approve-server
ExecStart=/usr/local/bin/gunicorn -w 2 -b 0.0.0.0:9120 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable claude-approve
sudo systemctl start claude-approve
```

---

## 配置内网穿透 / 反向代理

审批服务需要手机能访问到，通过你已有的内网穿透暴露 9120 端口。

Nginx 反向代理示例：

```nginx
server {
    listen 443 ssl;
    server_name approve.yourdomain.com;

    # 建议配合你的单点登录系统
    # auth_request /sso/verify;

    location / {
        proxy_pass http://127.0.0.1:9120;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 配置 notifier.conf

```bash
# 在 notifier.conf 末尾「我的配置」区域添加：

USE_REMOTE_APPROVE=1
APPROVE_SERVER="https://approve.yourdomain.com"
APPROVE_TIMEOUT=300     # 等待审批超时（秒），默认 5 分钟
APPROVE_INTERVAL=3      # 轮询间隔（秒）
```

---

## 审批决策说明

| 按钮 | 返回值 | 效果 |
|------|--------|------|
| ✅ 允许本次 | `{"decision": "approve"}` | 仅允许当前这一次操作 |
| ✅ 始终允许 | `{"decision": "always"}` | 以后同类操作自动允许，不再询问 |
| ❌ 拒绝 | `{"decision": "reject"}` | 阻止当前操作 |

---

## 多实例并发

每次权限请求自动生成唯一 ID：

```
格式：{项目目录名}_{时间戳}_{随机4字节hex}
示例：my-project_1719900000_a3f2b1c8
```

审批仪表盘 `https://approve.yourdomain.com/` 可查看所有实例的待审批请求。

---

## 安全建议

```
1. 配合你的单点登录（SSO）保护审批页面
2. 不要直接暴露到公网不做认证
3. 审批请求 30 分钟后自动清理
4. Token 缓存文件权限 600（仅自己可读）
5. 生产环境考虑用 Redis 替代内存存储
```

---

## 能力边界

| 场景 | 能否远程处理 |
|------|-------------|
| 权限审批（允许/始终/拒绝） | ✅ 可以 |
| 查看命令详情 | ✅ 可以 |
| 查看文件内容 | ✅ 可以 |
| 查看 Diff 变更 | ✅ 可以 |
| 输入文字回答追问 | ❌ 需要终端 |
| 终端内 Tab 切换 | ❌ 需要终端 |