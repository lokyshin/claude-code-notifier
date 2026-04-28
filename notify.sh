#!/bin/bash
# Claude Code Notifier
# https://github.com/lokyshin/claude-code-notifier
# License: MIT
#
# 用法：~/.claude/notify.sh <permission|done|error|tool> [自定义消息]

TYPE=$1
CUSTOM_MSG=$2
CONFIG_FILE="${CLAUDE_NOTIFIER_CONFIG:-$HOME/.claude/notifier.conf}"

# ============================================================
# 加载配置
# ============================================================
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "⚠️  配置文件不存在: $CONFIG_FILE"
  echo "请先运行 install.sh 或手动创建配置文件"
  exit 1
fi

LOG_FILE="${LOG_FILE:-$HOME/.claude/notifier.log}"
TOKEN_CACHE="$HOME/.claude/.feishu_token_cache"

# ============================================================
# 工具函数
# ============================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$TYPE] $1" >> "$LOG_FILE"
}

# ============================================================
# 飞书 - 模式一：Webhook（企业版群机器人）
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
# 飞书 - 模式二：App（个人版，自动刷新 Token）
# ============================================================
_feishu_get_token() {
  # 读取缓存
  if [ -f "$TOKEN_CACHE" ]; then
    local cached_time cached_token current_time
    cached_time=$(awk -F'|' '{print $1}' "$TOKEN_CACHE")
    cached_token=$(awk -F'|' '{print $2}' "$TOKEN_CACHE")
    current_time=$(date +%s)

    # 有效期 7200 秒，提前 600 秒刷新
    if [ $((current_time - cached_time)) -lt 6600 ] && [ -n "$cached_token" ]; then
      echo "$cached_token"
      return
    fi
  fi

  # 缓存失效，重新请求
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

  # 写入缓存，限制文件权限
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

  # 构建 card 内容并转义为 JSON 字符串
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
# 飞书 - 统一入口（根据 FEISHU_MODE 自动选择）
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
      log "feishu 未知模式: ${FEISHU_MODE}，请设置为 webhook 或 app"
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
    echo "Usage: $0 <permission|done|error|tool> [message]"
    exit 1
    ;;
esac