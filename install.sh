#!/bin/bash
# Claude Code Notifier 一键安装脚本

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "🚀 Installing Claude Code Notifier..."

# 创建目录
mkdir -p "$CLAUDE_DIR"

# 复制脚本
cp "$REPO_DIR/notify.sh" "$CLAUDE_DIR/notify.sh"
chmod +x "$CLAUDE_DIR/notify.sh"
echo "✅ notify.sh 已安装到 $CLAUDE_DIR"

# 创建配置文件（如果不存在）
if [ ! -f "$CLAUDE_DIR/notifier.conf" ]; then
  cp "$REPO_DIR/notifier.conf.example" "$CLAUDE_DIR/notifier.conf"
  echo "📝 配置文件已创建：$CLAUDE_DIR/notifier.conf"
  echo "⚠️  请编辑配置文件填入你的 Webhook/Key"
else
  echo "⏭️  配置文件已存在，跳过覆盖"
fi

# 处理 settings.json
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  cp "$REPO_DIR/settings.example.json" "$SETTINGS_FILE"
  echo "✅ settings.json 已创建"
else
  echo "⚠️  settings.json 已存在，请手动合并以下内容："
  cat "$REPO_DIR/settings.example.json"
fi

echo ""
echo "🎉 安装完成！"
echo ""
echo "下一步："
echo "  1. 编辑配置文件：nano $CLAUDE_DIR/notifier.conf"
echo "  2. 测试推送：$CLAUDE_DIR/notify.sh done '测试消息'"
echo "  3. 查看日志：tail -f $CLAUDE_DIR/notifier.log"