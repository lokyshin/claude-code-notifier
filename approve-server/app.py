"""
Claude Code Remote Approval Server v2
https://github.com/YOUR_USERNAME/claude-code-notifier

支持：
- 三种决策（允许一次 / 始终允许 / 拒绝）
- 多实例并发
- 操作详情展示（命令 / 文件内容 / Diff）
- 自动清理过期请求
"""

import time
import threading
from flask import Flask, request, jsonify, render_template

app = Flask(__name__)

approve_store = {}
store_lock = threading.Lock()

EXPIRE_SECONDS = 1800  # 30 分钟自动过期


def cleanup_expired():
    """定期清理过期请求"""
    while True:
        time.sleep(60)
        now = time.time()
        with store_lock:
            expired = [
                rid for rid, data in approve_store.items()
                if now - data["created_at"] > EXPIRE_SECONDS
            ]
            for rid in expired:
                del approve_store[rid]
                app.logger.info(f"Cleaned expired: {rid}")


cleanup_thread = threading.Thread(target=cleanup_expired, daemon=True)
cleanup_thread.start()


# ── API: 创建审批请求 ──────────────────────────────────────

@app.route("/api/request", methods=["POST"])
def create_request():
    data = request.get_json()

    if not data or "request_id" not in data:
        return jsonify({"error": "request_id is required"}), 400

    request_id = data["request_id"]

    with store_lock:
        approve_store[request_id] = {
            "status": "pending",
            "decision": None,
            "project": data.get("project", "unknown"),
            "hostname": data.get("hostname", ""),
            "created_at": time.time(),
            "resolved_at": None,
            "tool_name": data.get("tool_name", ""),
            "tool_input": data.get("tool_input", {}),
            "risk_level": data.get("risk_level", ""),
            "file_path": data.get("file_path", ""),
            "file_content": data.get("file_content", ""),
            "diff_content": data.get("diff_content", ""),
        }

    return jsonify({
        "status": "created",
        "request_id": request_id,
        "approve_url": f"/approve/{request_id}",
    })


# ── API: 查询状态 ──────────────────────────────────────────

@app.route("/api/status/<request_id>", methods=["GET"])
def get_status(request_id):
    with store_lock:
        if request_id not in approve_store:
            return jsonify({"status": "expired"})

        data = approve_store[request_id]
        return jsonify({
            "status": data["status"],
            "decision": data["decision"],
            "request_id": request_id,
        })


# ── API: 提交审批 ──────────────────────────────────────────

@app.route("/api/approve/<request_id>", methods=["POST"])
def submit_approval(request_id):
    data = request.get_json()
    action = data.get("action", "")

    valid_actions = {
        "approve": ("approved", "approve"),
        "always": ("approved", "always"),
        "reject": ("rejected", "reject"),
    }

    if action not in valid_actions:
        return jsonify({"error": "action must be approve / always / reject"}), 400

    with store_lock:
        if request_id not in approve_store:
            return jsonify({"error": "Request not found or expired"}), 404

        if approve_store[request_id]["status"] != "pending":
            return jsonify({"error": "Request already resolved"}), 409

        status, decision = valid_actions[action]
        approve_store[request_id]["status"] = status
        approve_store[request_id]["decision"] = decision
        approve_store[request_id]["resolved_at"] = time.time()

    messages = {
        "approve": "✅ 已允许（本次）",
        "always": "✅ 已允许（始终）",
        "reject": "❌ 已拒绝",
    }

    return jsonify({
        "status": status,
        "decision": decision,
        "message": messages[action],
    })


# ── 页面: 审批操作 ─────────────────────────────────────────

@app.route("/approve/<request_id>")
def approve_page(request_id):
    with store_lock:
        data = approve_store.get(request_id)

    if not data:
        return render_template("approve.html",
            error="请求不存在或已过期",
            data=None,
            request_id=request_id,
        )

    return render_template("approve.html",
        error=None,
        data=data,
        request_id=request_id,
    )


# ── 页面: 仪表盘 ──────────────────────────────────────────

@app.route("/")
def dashboard():
    with store_lock:
        pending = {
            rid: d for rid, d in approve_store.items()
            if d["status"] == "pending"
        }
        recent = dict(
            sorted(
                approve_store.items(),
                key=lambda x: x[1]["created_at"],
                reverse=True,
            )[:50]
        )

    return render_template("approve.html",
        error=None,
        data=None,
        request_id=None,
        pending=pending,
        recent=recent,
        dashboard=True,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9120, debug=False)