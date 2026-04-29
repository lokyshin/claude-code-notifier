"""
Claude Code Remote Approval Server v2
https://github.com/lokyshin/claude-code-notifier
"""

import os
import time
import threading
from flask import Flask, request, jsonify, render_template

app = Flask(__name__)
app.json.ensure_ascii = False

approve_store = {}
store_lock = threading.Lock()

EXPIRE_SECONDS = int(os.environ.get("APPROVE_EXPIRE", 1800))


def cleanup_expired():
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


@app.route("/api/request", methods=["POST"])
def create_request():
    data = request.get_json()

    if not data or "request_id" not in data:
        return jsonify({"error": "request_id is required"}), 400

    request_id = data["request_id"]

    request_type = data.get("request_type", "permission")

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
            "request_type": request_type,
            "questions": data.get("questions", []),
            "option_index": None,
            "option_indices": None,
            "tui_options": data.get("tui_options", []),
            "inject_key": None,
        }

    return jsonify({
        "status": "created",
        "request_id": request_id,
        "approve_url": f"/approve/{request_id}",
    })


@app.route("/api/status/<request_id>", methods=["GET"])
def get_status(request_id):
    with store_lock:
        if request_id not in approve_store:
            return jsonify({"status": "expired"})

        data = approve_store[request_id]
        resp = {
            "status": data["status"],
            "decision": data["decision"],
            "request_id": request_id,
            "request_type": data.get("request_type", "permission"),
        }
        if data.get("option_index") is not None:
            resp["option_index"] = data["option_index"]
        if data.get("option_indices") is not None:
            resp["option_indices"] = data["option_indices"]
        if data.get("inject_key") is not None:
            resp["inject_key"] = data["inject_key"]
        return jsonify(resp)


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
        if "inject_key" in data:
            approve_store[request_id]["inject_key"] = data["inject_key"]

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


@app.route("/api/answer/<request_id>", methods=["POST"])
def submit_answer(request_id):
    data = request.get_json()
    action = data.get("action", "")

    with store_lock:
        if request_id not in approve_store:
            return jsonify({"error": "Request not found or expired"}), 404

        if approve_store[request_id]["status"] != "pending":
            return jsonify({"error": "Request already resolved"}), 409

        if action == "select":
            approve_store[request_id]["status"] = "approved"
            approve_store[request_id]["decision"] = "option"
            approve_store[request_id]["resolved_at"] = time.time()
            if "option_index" in data:
                approve_store[request_id]["option_index"] = data["option_index"]
                approve_store[request_id]["inject_key"] = str(data["option_index"] + 1)
            if "option_indices" in data:
                approve_store[request_id]["option_indices"] = data["option_indices"]
            msg = "✅ 已选择选项"
        elif action == "tui":
            approve_store[request_id]["status"] = "approved"
            approve_store[request_id]["decision"] = "tui"
            approve_store[request_id]["resolved_at"] = time.time()
            msg = "📱 请到终端操作"
        elif action == "reject":
            approve_store[request_id]["status"] = "rejected"
            approve_store[request_id]["decision"] = "reject"
            approve_store[request_id]["resolved_at"] = time.time()
            msg = "❌ 已拒绝"
        else:
            return jsonify({"error": "action must be select / tui / reject"}), 400

    return jsonify({
        "status": approve_store[request_id]["status"],
        "decision": approve_store[request_id]["decision"],
        "message": msg,
    })


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
    host = os.environ.get("APPROVE_HOST", "127.0.0.1")
    port = int(os.environ.get("APPROVE_PORT", 9120))
    debug = os.environ.get("APPROVE_DEBUG", "false").lower() == "true"

    print(f"🚀 Claude Code Approval Server")
    print(f"   Listening on {host}:{port}")
    print(f"   Dashboard: http://{host}:{port}/")
    print(f"")
    print(f"   ⚠️  请通过 Nginx 反向代理对外暴露")
    print(f"   配置 APPROVE_SERVER 为你的公网域名")

    app.run(host=host, port=port, debug=debug)