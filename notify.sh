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

# 将 \uXXXX 转义序列解码为可读 UTF-8
decode_unicode() {
  python3 -c "
import sys, json
s = sys.stdin.read().strip()
if not s: sys.exit()
try: print(json.dumps(json.loads(s), ensure_ascii=False), end='')
except: print(s, end='')
" 2>/dev/null || echo "$1"
}

# ============================================================
# 从 tmux 终端捕获当前 TUI 选项
# ============================================================
capture_tui_options() {
  local tty pane_id
  tty=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
  pane_id=$(tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null \
    | grep "/dev/$tty" | awk '{print $1}')

  if [ -z "$pane_id" ]; then
    echo "[]"
    return
  fi

  tmux capture-pane -p -t "$pane_id" 2>/dev/null | python3 -c "
import sys, json, re
lines = sys.stdin.read().split('\n')
options = []
current = []
for line in lines:
    m = re.match(r'^[\s❯>]*(\d+)\.\s+(.+)', line)
    if m:
        current.append({'num': int(m.group(1)), 'text': m.group(2).strip()})
    else:
        if current:
            options = current
            current = []
if current:
    options = current
print(json.dumps(options, ensure_ascii=False))
" 2>/dev/null || echo "[]"
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

  # AskUserQuestion: format questions/options as readable text
  if [ "$tool_name" = "AskUserQuestion" ]; then
    local question_detail
    question_detail=$(echo "$STDIN_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    qs = inp.get('questions', [])
    if not qs:
        print('')
        sys.exit()
    lines = []
    if len(qs) == 1:
        q = qs[0]
        lines.append('❓ 问题: ' + q.get('question', ''))
        multi = q.get('multiSelect', False)
        if multi:
            lines.append('（可多选）')
        opts = q.get('options', [])
        if opts:
            lines.append('选项:')
            for i, o in enumerate(opts, 1):
                desc = o.get('description', '')
                if desc:
                    lines.append(f'  {i}. {o[\"label\"]} - {desc}')
                else:
                    lines.append(f'  {i}. {o[\"label\"]}')
    else:
        lines.append(f'❓ 问题 ({len(qs)}个):')
        for qi, q in enumerate(qs, 1):
            header = q.get('header', '')
            lines.append(f'--- Q{qi}: {header} ---' if header else f'--- Q{qi} ---')
            lines.append(q.get('question', ''))
            multi = q.get('multiSelect', False)
            if multi:
                lines.append('（可多选）')
            opts = q.get('options', [])
            for i, o in enumerate(opts, 1):
                desc = o.get('description', '')
                if desc:
                    lines.append(f'  {i}. {o[\"label\"]} - {desc}')
                else:
                    lines.append(f'  {i}. {o[\"label\"]}')
    print('\n'.join(lines))
except: print('')
" 2>/dev/null)
    echo "$question_detail"
    return
  fi

  tool_input=$(echo "$STDIN_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
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
# 远程审批 - 创建审批请求并返回审批 URL
# ============================================================
create_approve_request() {
  if [ "${USE_REMOTE_APPROVE:-0}" -eq 0 ] || [ -z "$APPROVE_SERVER" ]; then
    return
  fi

  local request_id host_name project_name
  request_id="req-$(date +%s)-$$"
  host_name=$(hostname)
  project_name=$(basename "${CLAUDE_PROJECT_DIR:-unknown}" 2>/dev/null || echo "unknown")

  local post_data
  post_data=$(REQ_ID="$request_id" REQ_PROJECT="$project_name" REQ_HOST="$host_name" \
    python3 -c "
import sys, json, os
stdin_text = sys.stdin.read().strip()
d = {}
if stdin_text:
    try:
        d = json.loads(stdin_text)
    except:
        pass
tool_name = d.get('tool_name', '')
tool_input = d.get('tool_input', {})
file_path = ''
if isinstance(tool_input, dict):
    file_path = tool_input.get('file_path', tool_input.get('path', ''))
payload = {
    'request_id': os.environ['REQ_ID'],
    'project': os.environ.get('REQ_PROJECT', 'unknown'),
    'hostname': os.environ.get('REQ_HOST', ''),
    'tool_name': tool_name,
    'tool_input': tool_input,
    'risk_level': d.get('risk_level', ''),
    'file_path': file_path,
}
if tool_name == 'AskUserQuestion':
    payload['request_type'] = 'question'
    qs = tool_input.get('questions', [])
    payload['questions'] = qs

# Build tui_options from permission_suggestions (not tmux capture)
suggestions = d.get('permission_suggestions', [])
if tool_name != 'AskUserQuestion':
    if suggestions:
        s = suggestions[0]
        stype = s.get('type', '')
        if stype == 'addDirectories':
            dirs = ', '.join(s.get('directories', []))
            always_text = f'Yes, and always allow access to {dirs}'
        elif stype == 'addRules':
            rules = s.get('rules', [])
            rule_desc = rules[0].get('ruleContent', '') if rules else ''
            always_text = f'Yes, and don\\'t ask again for {rule_desc}' if rule_desc else 'Yes, always'
        else:
            always_text = 'Yes, always'
        payload['tui_options'] = [
            {'num': 1, 'text': 'Yes', 'action': 'approve'},
            {'num': 2, 'text': always_text, 'action': 'always'},
            {'num': 3, 'text': 'No', 'action': 'reject'},
        ]
    else:
        payload['tui_options'] = [
            {'num': 1, 'text': 'Yes', 'action': 'approve'},
            {'num': 2, 'text': 'No', 'action': 'reject'},
        ]

print(json.dumps(payload, ensure_ascii=False))
" <<< "$STDIN_DATA" 2>/dev/null)

  if [ -z "$post_data" ]; then
    post_data="{\"request_id\":\"$request_id\",\"hostname\":\"$host_name\"}"
  fi

  curl -s -m 3 -X POST "$APPROVE_SERVER/api/request" \
    -H 'Content-Type: application/json' \
    -d "$post_data" > /dev/null 2>&1

  log "remote-approve | created: $APPROVE_SERVER/approve/$request_id"
  echo "$APPROVE_SERVER/approve/$request_id"
}

# ============================================================
# 远程审批 - 后台轮询结果并注入终端按键
# ============================================================
poll_approve_and_inject() {
  local approve_url=$1

  if [ "${USE_REMOTE_APPROVE:-0}" -eq 0 ] || [ -z "$approve_url" ]; then
    return
  fi

  local request_id target_tty target_pane inject_method
  request_id=$(basename "$approve_url")
  target_tty=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')

  if [ -z "$target_tty" ] || [ "$target_tty" = "?" ]; then
    log "remote-approve | no TTY found (tty=$target_tty), skip polling"
    return
  fi

  # 检测可用的输入注入方式（优先级：tmux > TIOCSTI > none）
  inject_method="none"

  if [ -n "$TMUX" ]; then
    target_pane=$(tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null \
      | grep "/dev/$target_tty" | awk '{print $1}')
    [ -n "$target_pane" ] && inject_method="tmux"
  fi

  if [ "$inject_method" = "none" ] && [ -c "/dev/$target_tty" ]; then
    python3 -c "
import fcntl,struct,os
fd=os.open('/dev/$target_tty',os.O_WRONLY)
fcntl.ioctl(fd,0x5412,struct.pack('B',0))
os.close(fd)" 2>/dev/null && inject_method="tiocsti"
  fi

  if [ "$inject_method" = "none" ]; then
    log "remote-approve | no injection method (no tmux, TIOCSTI disabled), notification only"
  fi

  (
    trap '' HUP

    inject_key() {
      case "$inject_method" in
        "tmux")
          tmux send-keys -t "$target_pane" "$1" 2>/dev/null
          ;;
        "tiocsti")
          python3 -c "
import fcntl,struct,os,sys
fd=os.open(sys.argv[1],os.O_WRONLY)
[fcntl.ioctl(fd,0x5412,struct.pack('B',ord(c))) for c in sys.argv[2]]
os.close(fd)" "/dev/$target_tty" "$1" 2>/dev/null
          ;;
        *)
          return 1
          ;;
      esac
    }

    ELAPSED=0
    while [ $ELAPSED -lt ${APPROVE_EXPIRE:-300} ]; do
      sleep ${APPROVE_INTERVAL:-3}
      ELAPSED=$((ELAPSED + ${APPROVE_INTERVAL:-3}))

      RESP=$(curl -s -m 3 "$APPROVE_SERVER/api/status/$request_id" 2>/dev/null)
      [ -z "$RESP" ] && continue

      STATUS=$(echo "$RESP" | python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d.get('status',''))
except: print('')" 2>/dev/null)

      case "$STATUS" in
        "approved"|"rejected")
          DECISION=$(echo "$RESP" | python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d.get('decision',''))
except: print('')" 2>/dev/null)

          REQ_TYPE=$(echo "$RESP" | python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d.get('request_type','permission'))
except: print('permission')" 2>/dev/null)

          INJECT_KEYS=$(echo "$RESP" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    keys=d.get('inject_keys',[])
    if keys:
        print(' '.join(keys))
    else:
        k=d.get('inject_key','')
        print(k)
except: print('')" 2>/dev/null)

          if [ -n "$INJECT_KEYS" ]; then
            for k in $INJECT_KEYS; do
              if inject_key "$k"; then
                log "remote-approve | [$inject_method] key='$k' ($request_id)"
              else
                log "remote-approve | no injection, key='$k' ($request_id)"
                break
              fi
              sleep 0.3
            done
          else
            log "remote-approve | no inject_key in response ($request_id)"
          fi
          exit 0
          ;;
        "expired")
          log "remote-approve | request expired ($request_id)"
          exit 0
          ;;
      esac
    done

    log "remote-approve | timeout ${APPROVE_EXPIRE:-300}s ($request_id)"
  ) </dev/null &>/dev/null &
  disown $! 2>/dev/null

  log "remote-approve | polling bg PID=$! method=$inject_method ($request_id)"
}

# ============================================================
# 飞书 - 模式一：Webhook
# ============================================================
_feishu_send_webhook() {
  local title=$1 msg=$2 color=$3 approve_url=$4
  local res action_block=""

  if [ -n "$approve_url" ]; then
    action_block=",
          {
            \"tag\": \"action\",
            \"actions\": [
              {
                \"tag\": \"button\",
                \"text\": {\"tag\": \"plain_text\", \"content\": \"📋 点击查看并审批\"},
                \"type\": \"primary\",
                \"multi_url\": {
                  \"url\": \"$approve_url\"
                }
              }
            ]
          }"
  fi

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
          }$action_block,
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

  log "feishu[webhook] | $title | $(echo "$res" | decode_unicode)"
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
    log "feishu[app] Token 获取失败: $(echo "$response" | decode_unicode)"
    echo ""
    return
  fi

  echo "$(date +%s)|$token" > "$TOKEN_CACHE"
  chmod 600 "$TOKEN_CACHE"
  log "feishu[app] Token 刷新成功"
  echo "$token"
}

_feishu_send_app() {
  local title=$1 msg=$2 color=$3 approve_url=$4
  local token res

  token=$(_feishu_get_token)

  if [ -z "$token" ]; then
    log "feishu[app] 推送失败：Token 为空"
    return
  fi

  local post_body
  post_body=$(CARD_TITLE="$title" CARD_MSG="$msg" CARD_COLOR="$color" \
    CARD_APPROVE_URL="$approve_url" CARD_HOST="$(hostname)" \
    CARD_TIME="$(date '+%Y-%m-%d %H:%M:%S')" \
    CARD_RECEIVE_ID="$FEISHU_RECEIVE_ID" \
    python3 -c '
import json, os

title = os.environ.get("CARD_TITLE", "")
msg = os.environ.get("CARD_MSG", "").replace("\\n", "\n")
color = os.environ.get("CARD_COLOR", "blue")
approve_url = os.environ.get("CARD_APPROVE_URL", "")
host = os.environ.get("CARD_HOST", "")
time_str = os.environ.get("CARD_TIME", "")
receive_id = os.environ.get("CARD_RECEIVE_ID", "")

elements = [
    {
        "tag": "div",
        "text": {"tag": "lark_md", "content": msg}
    }
]

if approve_url:
    elements.append({
        "tag": "action",
        "actions": [
            {
                "tag": "button",
                "text": {"tag": "plain_text", "content": "📋 点击查看并审批"},
                "type": "primary",
                "multi_url": {"url": approve_url}
            }
        ]
    })

elements.append({
    "tag": "note",
    "elements": [{
        "tag": "plain_text",
        "content": f"🖥️ {host} | {time_str}"
    }]
})

card = {
    "config": {"wide_screen_mode": True},
    "header": {
        "title": {"tag": "plain_text", "content": title},
        "template": color
    },
    "elements": elements
}

body = {
    "receive_id": receive_id,
    "msg_type": "interactive",
    "content": json.dumps(card, ensure_ascii=False)
}

print(json.dumps(body, ensure_ascii=False))
' 2>/dev/null)

  if [ -z "$post_body" ]; then
    log "feishu[app] JSON 构建失败"
    return
  fi

  res=$(curl -s -X POST \
    "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${FEISHU_RECEIVE_TYPE:-chat_id}" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "$post_body")

  log "feishu[app] | $title | $(echo "$res" | decode_unicode)"
}

# ============================================================
# 飞书 - 统一入口
# ============================================================
send_feishu() {
  [ "${USE_FEISHU:-0}" -eq 0 ] && return

  local title=$1 msg=$2 color=$3 approve_url=$4

  case "${FEISHU_MODE:-webhook}" in
    "webhook")
      if [ -z "$FEISHU_WEBHOOK" ] || [[ "$FEISHU_WEBHOOK" == *"YOUR_TOKEN"* ]]; then
        log "feishu[webhook] FEISHU_WEBHOOK 未配置，跳过"
        return
      fi
      _feishu_send_webhook "$title" "$msg" "$color" "$approve_url"
      ;;
    "app")
      if [ -z "$FEISHU_APP_ID" ] || [ -z "$FEISHU_APP_SECRET" ] || [ -z "$FEISHU_RECEIVE_ID" ]; then
        log "feishu[app] App ID / Secret / Receive ID 未配置，跳过"
        return
      fi
      _feishu_send_app "$title" "$msg" "$color" "$approve_url"
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

  log "serverchan | $title | $(echo "$res" | decode_unicode)"
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

  log "wxwork | $content | $(echo "$res" | decode_unicode)"
}

# ============================================================
# 统一推送入口
# ============================================================
notify_all() {
  local title=$1 msg=$2 color=$3 approve_url=$4
  local host time_str
  host=$(hostname)
  time_str=$(date '+%Y-%m-%d %H:%M:%S')

  send_feishu "$title" "$msg" "$color" "$approve_url"
  send_serverchan "$title" "$msg\n\n🖥️ 服务器: $host\n🕐 时间: $time_str"
  send_wxwork "$title\n> $msg\n> 🖥️ $host | $time_str"
}

# ============================================================
# Hook 类型路由
# ============================================================
case $TYPE in
  "permission")
    # 检测是否为 AskUserQuestion
    ASK_TOOL_NAME=$(echo "$STDIN_DATA" | python3 -c "
import sys, json
try: d=json.load(sys.stdin); print(d.get('tool_name', ''))
except: print('')" 2>/dev/null)

    CONTEXT=$(parse_context)

    if [ "$ASK_TOOL_NAME" = "AskUserQuestion" ]; then
      DETAIL_MSG="${CONTEXT:-Claude 有一个问题需要你回答}"

      APPROVE_URL=$(create_approve_request)

      notify_all \
        "❓ Claude 有一个问题" \
        "$DETAIL_MSG" \
        "blue" \
        "$APPROVE_URL"
    else
      DETAIL_MSG="${CUSTOM_MSG:-Claude Code 正在请求权限，请回到终端确认操作！}"
      if [ -n "$CONTEXT" ]; then
        DETAIL_MSG="$DETAIL_MSG\n\n$CONTEXT"
      fi

      APPROVE_URL=$(create_approve_request)

      notify_all \
        "⚠️ Claude 需要授权确认" \
        "$DETAIL_MSG" \
        "yellow" \
        "$APPROVE_URL"
    fi

    poll_approve_and_inject "$APPROVE_URL"
    ;;
  "done")
    # 从 stdin JSON 提取项目名、工作目录、任务摘要
    DONE_PROJECT="unknown"
    DONE_CWD=""
    DONE_SUMMARY=""
    if [ -n "$STDIN_DATA" ]; then
      eval "$(echo "$STDIN_DATA" | python3 -c "
import sys, json, re, os

def shell_escape(s):
    return s.replace('\\\\', '\\\\\\\\').replace('\"', '\\\\\"').replace('\n', '\\\\n')

try:
    d = json.load(sys.stdin)

    cwd = d.get('cwd', '')
    home = os.path.expanduser('~')
    proj = os.path.basename(cwd) if cwd else ''
    if not proj or proj == os.path.basename(home):
        proj = os.path.basename(os.environ.get('CLAUDE_PROJECT_DIR', '')) or 'unknown'
    print(f'DONE_PROJECT=\"{shell_escape(proj)}\"')

    # cwd 用 ~ 缩短 home 前缀
    if cwd.startswith(home):
        cwd = '~' + cwd[len(home):]
    print(f'DONE_CWD=\"{shell_escape(cwd)}\"')

    msg = d.get('last_assistant_message', '')
    if msg:
        # 去掉代码块
        msg = re.sub(r'\x60\x60\x60.*?\x60\x60\x60', '', msg, flags=re.DOTALL)
        # 清理 markdown 格式但保留结构
        lines = []
        for line in msg.split('\n'):
            line = line.strip()
            if not line:
                if lines and lines[-1] != '':
                    lines.append('')
                continue
            # 清理 markdown 标记
            line = re.sub(r'^#{1,4}\s+', '', line)         # 标题 → 纯文本
            line = re.sub(r'\*\*(.+?)\*\*', r'\1', line)   # 加粗
            line = re.sub(r'[\x60\[\]]', '', line)          # 行内代码、链接括号
            line = re.sub(r'^\|\s*', '', line)              # 表格行首 |
            line = re.sub(r'\s*\|$', '', line)              # 表格行尾 |
            lines.append(line)
        text = '\n'.join(lines).strip()
        # 截断到 500 字符
        if len(text) > 500:
            text = text[:500] + '...'
        print(f'DONE_SUMMARY=\"{shell_escape(text)}\"')
    else:
        print('DONE_SUMMARY=\"\"')
except:
    print('DONE_PROJECT=\"unknown\"')
    print('DONE_CWD=\"\"')
    print('DONE_SUMMARY=\"\"')
" 2>/dev/null)"
    fi

    DONE_TITLE="✅ ${DONE_PROJECT} 任务完成"
    if [ -n "$CUSTOM_MSG" ]; then
      DONE_MSG="$CUSTOM_MSG"
    else
      DONE_MSG="📂 ${DONE_CWD:-$DONE_PROJECT}"
      if [ -n "$DONE_SUMMARY" ]; then
        DONE_MSG="$DONE_MSG\n\n$DONE_SUMMARY"
      fi
    fi

    notify_all \
      "$DONE_TITLE" \
      "$DONE_MSG" \
      "green"
    ;;
  "error")
    ERR_PROJECT="unknown"
    if [ -n "$STDIN_DATA" ]; then
      ERR_PROJECT=$(echo "$STDIN_DATA" | python3 -c "
import sys, json, os
try:
    d = json.load(sys.stdin)
    cwd = d.get('cwd', '')
    proj = os.path.basename(cwd) if cwd else ''
    if not proj or proj == os.path.basename(os.path.expanduser('~')):
        proj = os.path.basename(os.environ.get('CLAUDE_PROJECT_DIR', '')) or 'unknown'
    print(proj)
except: print('unknown')
" 2>/dev/null)
    fi
    : "${ERR_PROJECT:=unknown}"

    notify_all \
      "❌ ${ERR_PROJECT} 发生错误" \
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