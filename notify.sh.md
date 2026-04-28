#!/bin/bash
# Claude Code Notifier
# https://github.com/lokyshin/claude-code-notifier
# License: MIT

TYPE=$1
CUSTOM_MSG=$2
CONFIG_FILE="${CLAUDE_NOTIFIER_CONFIG:-$HOME/.claude/notifier.conf}"

# ============================================================
# 加载配置文件
# ============================================================
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "⚠️  配置文件不存在: $CONFIG_FILE"
  echo "请运行 install.sh 或手动创建配置文件"
  echo "参考: settings.example.json"
  exit 1
fi

# ============================================================
# 日志
# ============================================================
LOG_FILE="${LOG_FILE:-$HOME/.claude/notifier.log}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$TYPE] $1" >> "$LOG_FILE"
}

# ============================================================
# 各渠道发送函数
# ============================================================

send_feishu() {
  [ "${USE_FEISHU:-0}" -eq 0 ] && return
  local title=$1 msg=$2 color=$3
  local res
  res=$(curl -s -X POST "$FEISHU_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{
      \"msg_type\": \"interactive\",
      \"card\": {
        \"header\": {
          \"title\": {\"tag\": \"plain_text\", \"content\": \"$title\"},
          \"template\": \"$color\"
        },
        \"elements\": [
          {\"tag\": \"div\", \"text\": {\"tag\": \"lark_md\", \"content\": \"$msg\"}},
          {\"tag\": \"note\", \"elements\": [{
            \"tag\": \"plain_text\",
            \"content\": \"🖥️ $(hostname) | $(date '+%Y-%m-%d %H:%M:%S')\"
          }]}
        ]
      }
    }")
  log "feishu | $title | $res"
}

send_serverchan() {
  [ "${USE_SERVERCHAN:-0}" -eq 0 ] && return
  local title=$1 msg=$2
  local res
  res=$(curl -s -X POST "https://sctapi.ftqq.com/$SERVERCHAN_KEY.send" \
    --data-urlencode "title=$title" \
    --data-urlencode "desp=$msg")
  log "serverchan | $title | $res"
}

send_wxwork() {
  [ "${USE_WXWORK:-0}" -eq 0 ] && return
  local content=$1
  local res
  res=$(curl -s -X POST "$WXWORK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"$content\"}}")
  log "wxwork | $content | $res"
}

# ============================================================
# 统一推送入口
# ============================================================
notify_all() {
  local title=$1 msg=$2 color=$3
  local hostname_str
  hostname_str=$(hostname)
  local time_str
  time_str=$(date '+%Y-%m-%d %H:%M:%S')

  send_feishu "$title" "$msg" "$color"
  send_serverchan "$title" "$msg\n\n🖥️ **服务器**: $hostname_str\n🕐 **时间**: $time_str"
  send_wxwork "$title\n> $msg\n> 🖥️ 服务器: $hostname_str\n> 🕐 时间: $time_str"
}

# ============================================================
# Hook 类型映射
# ============================================================
case $TYPE in
  "permission")
    notify_all \
      "⚠️ Claude 需要授权确认" \
      "${CUSTOM_MSG:-Claude Code 正在请求权限，请回到终端确认操作！}" \
      "yellow"
    ;;
  "done")
    notify_all \
      "✅ Claude 任务完成" \
      "${CUSTOM_MSG:-Claude Code 已完成任务执行}" \
      "green"
    ;;
  "error")
    notify_all \
      "❌ Claude 发生错误" \
      "${CUSTOM_MSG:-Claude Code 遇到错误，请检查终端！}" \
      "red"
    ;;
  "tool")
    notify_all \
      "🔧 工具执行完成" \
      "${CUSTOM_MSG:-Claude Code 完成了一个工具调用}" \
      "grey"
    ;;
  *)
    echo "Usage: $0 <permission|done|error|tool> [custom message]"
    exit 1
    ;;
esac