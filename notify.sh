#!/bin/bash
# Claude Code Notifier
# https://github.com/lokyshin/claude-code-notifier
# License: MIT

TYPE=$1
CUSTOM_MSG=$2
CONFIG_FILE="${CLAUDE_NOTIFIER_CONFIG:-$HOME/.claude/notifier.conf}"

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

LOG_FILE="${LOG_FILE:-$HOME/.claude/notifier.log}"
TOKEN_CACHE="$HOME/.claude/.feishu_token_cache"

# ============================================================
# 读取 stdin（Claude Code 传入的 Hook 上下文 JSON）
# ============================================================
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$TYPE] $1" >> "$LOG_FILE"
}

# ============================================================
# 解析 Hook 上下文
# ============================================================
parse_context() {
  if [ -z "$STDIN_DATA" ]; then
    echo ""
    return
  fi

  local tool_name tool_input risk_level

  # 用 python3 解析 JSON（兼容性最好）
  tool_name=$(echo "$STDIN_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except: pass
" 2>/dev/null)

  tool_input=$(echo "$STDIN_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    # 提取关键信息
    if 'command' in inp:
        print(inp['command'][:200])
    elif 'file_path' in inp:
        print(inp['file_path'])
    elif 'path' in inp:
        print(inp['path'])
    else:
        print(json.dumps(inp, ensure_ascii=False)[:200])
except: pass
" 2>/dev/null)

  risk_level=$(echo "$STDIN_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('risk_level', ''))
except: pass
" 2>/dev/null)

  # 构造详细描述
  local detail=""

  if [ -n "$tool_name" ]; then
    case "$tool_name" in
      "Bash")     detail="🔧 操作类型: 执行 Shell 命令" ;;
      "Write")    detail="📝 操作类型: 写入文件" ;;
      "Read")     detail="📖 操作类型: 读取文件" ;;
      "Edit")     detail="✏️ 操作类型: 编辑文件" ;;
      *)          detail="🔧 操作类型: $tool_name" ;;
    esac
  fi

  if [ -n "$tool_input" ]; then
    detail="$detail\n📋 操作内容: $tool_input"
  fi

  if [ -n "$risk_level" ]; then
    case "$risk_level" in
      "high")   detail="$detail\n🔴 风险等级: 高" ;;
      "medium") detail="$detail\n🟡 风险等级: 中" ;;
      "low")    detail="$detail\n🟢 风险等级: 低" ;;
    esac
  fi

  echo "$detail"
}

# ============================================================
# 飞书 - 模式一：Webhook
# ============================================================
_feishu_send_webhook() {
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
          {
            \"tag\": \"div\",
            \"text\": {\"tag\": \"lark_md\", \"content\": \"$msg\"}
          },
          {
            \"tag\": \"note\",
            \"elements\": [{
              \"tag\": \"plain_text\",
              \"content\": \"🖥️ $(hostname) | $(date '+%Y-%m-%d %H:%M:%S')\"
            }]
          }
        ]
      }
    }")

  log "feishu[webhook] | $title | $res"
}

# ============================================================
# 飞书 - 模式二：App（自动刷新 Token）
# ============================================================
_feishu_get_token() {
  if [ -f "$TOKEN_CACHE" ]; then
    local cached_time cached_token current_time
    cached_time=$(awk -F'|' '{print $1}' "$TOKEN_CACHE")
    cached_token=$(awk -F'|' '{print $2}' "$TOKEN_CACHE")
    current_time=$(date +%s)

    if [ $((current_time - cached_time)) -lt 6600 ] && [ -n "$cached_token" ]; then
      echo "$cached_token"
      return
    fi
  fi

  local response token
  response=$(curl -s -X POST \
    'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
    -H 'Content-Type: application/json' \
    -d "{
      \"app_id\": \"$FEISHU_APP_ID\",
      \"app_secret\": \"$FEISHU_APP_SECRET\"
    }")

  token=$(echo "$response" | grep -o '"tenant_access_token":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$token" ]; then
    log "feishu[app] Token 获取失败: $response"
    echo ""
    return
  fi

  echo "$(date +%s)|$token" > "$TOKEN_CACHE"
  chmod 600 "$TOKEN_CACHE"
  log "feishu[app] Token 刷新成功"
  echo "$token"
}

_feishu_send_app() {
  local title=$1 msg=$2 color=$3
  local token res card

  token=$(_feishu_get_token)

  if [ -z "$token" ]; then
    log "feishu[app] 推送失败：Token 为空"
    return
  fi

  card=$(cat <<EOF
{
  "config": {"wide_screen_mode": true},
  "header": {
    "title": {"tag": "plain_text", "content": "$title"},
    "template": "$color"
  },
  "elements": [
    {
      "tag": "div",
      "text": {"tag": "lark_md", "content": "$msg"}
    },
    {
      "tag": "note",
      "elements": [{
        "tag": "plain_text",
        "content": "🖥️ $(hostname) | $(date '+%Y-%m-%d %H:%M:%S')"
      }]
    }
  ]
}
EOF
)

  res=$(curl -s -X POST \
    "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${FEISHU_RECEIVE_TYPE:-chat_id}" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "{
      \"receive_id\": \"$FEISHU_RECEIVE_ID\",
      \"msg_type\": \"interactive\",
      \"content\": $(echo "$card" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    }")

  log "feishu[app] | $title | $res"
}

# ============================================================
# 飞书 - 统一入口
# ============================================================
send_feishu() {
  [ "${USE_FEISHU:-0}" -eq 0 ] && return

  local title=$1 msg=$2 color=$3

  case "${FEISHU_MODE:-webhook}" in
    "webhook")
      if [ -z "$FEISHU_WEBHOOK" ] || [[ "$FEISHU_WEBHOOK" == *"YOUR_TOKEN"* ]]; then
        log "feishu[webhook] FEISHU_WEBHOOK 未配置，跳过"
        return
      fi
      _feishu_send_webhook "$title" "$msg" "$color"
      ;;
    "app")
      if [ -z "$FEISHU_APP_ID" ] || [ -z "$FEISHU_APP_SECRET" ] || [ -z "$FEISHU_RECEIVE_ID" ]; then
        log "feishu[app] App ID / Secret / Receive ID 未配置，跳过"
        return
      fi
      _feishu_send_app "$title" "$msg" "$color"
      ;;
    *)
      log "feishu 未知模式: ${FEISHU_MODE}"
      ;;
  esac
}

# ============================================================
# Server酱（个人微信）
# ============================================================
send_serverchan() {
  [ "${USE_SERVERCHAN:-0}" -eq 0 ] && return

  local title=$1 msg=$2 res

  if [ -z "$SERVERCHAN_KEY" ] || [[ "$SERVERCHAN_KEY" == *"YOUR_"* ]]; then
    log "serverchan SERVERCHAN_KEY 未配置，跳过"
    return
  fi

  res=$(curl -s -X POST "https://sctapi.ftqq.com/$SERVERCHAN_KEY.send" \
    --data-urlencode "title=$title" \
    --data-urlencode "desp=$msg")

  log "serverchan | $title | $res"
}

# ============================================================
# 企业微信机器人
# ============================================================
send_wxwork() {
  [ "${USE_WXWORK:-0}" -eq 0 ] && return

  local content=$1 res

  if [ -z "$WXWORK_WEBHOOK" ] || [[ "$WXWORK_WEBHOOK" == *"YOUR_KEY"* ]]; then
    log "wxwork WXWORK_WEBHOOK 未配置，跳过"
    return
  fi

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
  local host time_str
  host=$(hostname)
  time_str=$(date '+%Y-%m-%d %H:%M:%S')

  send_feishu "$title" "$msg" "$color"
  send_serverchan "$title" "$msg\n\n🖥️ 服务器: $host\n🕐 时间: $time_str"
  send_wxwork "$title\n> $msg\n> 🖥️ $host | $time_str"
}

# ============================================================
# Hook 类型路由
# ============================================================
case $TYPE in
  "permission")
    # 解析 Claude Code 传入的上下文
    CONTEXT=$(parse_context)
    DETAIL_MSG="${CUSTOM_MSG:-Claude Code 正在请求权限，请回到终端确认操作！}"
    if [ -n "$CONTEXT" ]; then
      DETAIL_MSG="$DETAIL_MSG\n\n$CONTEXT"
    fi

    notify_all \
      "⚠️ Claude 需要授权确认" \
      "$DETAIL_MSG" \
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
    CONTEXT=$(parse_context)
    TOOL_MSG="${CUSTOM_MSG:-Claude Code 完成了一个工具调用}"
    if [ -n "$CONTEXT" ]; then
      TOOL_MSG="$TOOL_MSG\n\n$CONTEXT"
    fi

    notify_all \
      "🔧 工具执行完成" \
      "$TOOL_MSG" \
      "grey"
    ;;
  *)
    echo "Usage: $0 <permission|done|error|tool> [message]"
    exit 1
    ;;
esac