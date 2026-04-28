#!/bin/bash
# Claude Code Notifier - 安装脚本

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "🚀 Installing Claude Code Notifier..."
echo ""

# ── 创建目录 ──
mkdir -p "$CLAUDE_DIR"

# ── 安装通知脚本 ──
cp "$REPO_DIR/notify.sh" "$CLAUDE_DIR/notify.sh"
chmod 755 "$CLAUDE_DIR/notify.sh"
echo "✅ notify.sh → $CLAUDE_DIR/notify.sh"

# ── 创建配置文件 ──
if [ ! -f "$CLAUDE_DIR/notifier.conf" ]; then
  cp "$REPO_DIR/notifier.conf.example" "$CLAUDE_DIR/notifier.conf"
  echo "✅ notifier.conf → $CLAUDE_DIR/notifier.conf"
  echo "   ⚠️  请编辑配置文件填入你的 Webhook/Key"
else
  echo "⏭️  notifier.conf 已存在，跳过（不覆盖你的配置）"
fi

# ── 处理 settings.json ──
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  cp "$REPO_DIR/settings.example.json" "$SETTINGS_FILE"
  echo "✅ settings.json → $SETTINGS_FILE"
else
  echo "⏭️  settings.json 已存在"
  echo "   如需手动合并，参考 settings.example.json"
fi

# ── 可选：安装审批服务 ──
echo ""
read -p "是否安装远程审批服务？(y/N): " install_approve

if [[ "$install_approve" =~ ^[Yy]$ ]]; then
  APPROVE_DIR="$CLAUDE_DIR/approve-server"
  mkdir -p "$APPROVE_DIR/templates"

  cp "$REPO_DIR/approve-server/app.py" "$APPROVE_DIR/app.py"
  cp "$REPO_DIR/approve-server/requirements.txt" "$APPROVE_DIR/requirements.txt"
  cp "$REPO_DIR/approve-server/templates/approve.html" "$APPROVE_DIR/templates/approve.html"

  echo "✅ 审批服务 → $APPROVE_DIR"

  read -p "是否现在安装 Python 依赖？(y/N): " install_deps
  if [[ "$install_deps" =~ ^[Yy]$ ]]; then
    pip3 install -r "$APPROVE_DIR/requirements.txt"
    echo "✅ Python 依赖安装完成"
  fi

  echo ""
  echo "启动审批服务："
  echo "  cd $APPROVE_DIR && python3 app.py"
  echo ""
  echo "记得在 notifier.conf 中配置："
  echo "  USE_REMOTE_APPROVE=1"
  echo "  APPROVE_SERVER=\"https://your-domain.com\""
fi

# ── 完成 ──
echo ""
echo "════════════════════════════════════════"
echo "🎉 安装完成！"
echo "════════════════════════════════════════"
echo ""
echo "下一步："
echo "  1. 编辑配置:  nano $CLAUDE_DIR/notifier.conf"
echo "  2. 测试推送:  $CLAUDE_DIR/notify.sh done '测试消息'"
echo "  3. 查看日志:  tail -f $CLAUDE_DIR/notifier.log"
echo ""