"""Offline mock of the Meta WhatsApp Cloud API and Twilio WhatsApp API.

It does two things:
  * accepts the outbound calls the IRIS adapter makes and records them;
  * simulates an inbound WhatsApp user by POSTing a correctly signed webhook
    to the IRIS gateway, so the full round trip can be demonstrated without
    any Meta or Twilio credentials.
"""

import base64
import hashlib
import hmac
import json
import os
import re
import time
import urllib.parse
import uuid

import requests
from flask import Flask, jsonify, redirect, render_template_string, request, url_for

app = Flask(__name__)

META_WEBHOOK_URL = os.environ.get(
    "META_WEBHOOK_URL", os.environ.get("IRIS_WEBHOOK_URL", "http://iris:8090/webhook")
)
TWILIO_WEBHOOK_URL = os.environ.get("TWILIO_WEBHOOK_URL", "http://iris:8091/webhook")
META_APP_SECRET = os.environ.get("META_APP_SECRET", "demo-app-secret")
VERIFY_TOKEN = os.environ.get("VERIFY_TOKEN", "demo-verify-token")
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN", "demo-twilio-token")
PHONE_NUMBER_ID = os.environ.get("MOCK_PHONE_NUMBER_ID", "1234567890")
WA_SENDER = os.environ.get("MOCK_WA_SENDER", "whatsapp:+15550001111")
BUSINESS_NUMBER = WA_SENDER.replace("whatsapp:", "")

MESSAGES = []
COUNTER = {"n": 0}

# A small 120x60 PNG used by the "image" demo command.
SAMPLE_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAHgAAAA8CAIAAADoZ9gKAAAAAXNSR0IArs4c6QAAAARnQU1BAACx"
    "jwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACPSURBVHhe7dExAQAADMOg+TfdmcgByGxU4QOB"
    "FQy0YqAVG2jFQCs2UNhgKzZQ2GArNlDYYCs2UNhgKzZQ2GArNlDYYCs2UNhgKzZQ2GArNlDYYCs2"
    "UNhgKzZQ2GArNlDYYCs2UNhgKzZQ2GArNlDYYCs2UNhgKzZQ2GArNlDYYCs2UNhgKzZQ2GArNlDY"
    "YCs2UNhgKzZQ2GArNlDYYCs2UNhgKzZQ2GArNlDYAC8LAAH+9m1wAAAAAElFTkSuQmCC"
)

PAGE = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="4">
  <title>IRIS WhatsApp mock</title>
  <style>
    body { font-family: -apple-system, Segoe UI, sans-serif; margin: 24px; background: #f6f7f9; color: #1f2937; }
    h1 { margin: 0 0 4px; font-size: 22px; }
    .sub { color: #6b7280; font-size: 13px; margin-bottom: 18px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
    .card { background: #fff; border: 1px solid #e5e7eb; border-radius: 10px; padding: 16px; }
    .card h2 { margin: 0 0 12px; font-size: 15px; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { text-align: left; padding: 6px 4px; border-bottom: 1px solid #f0f1f3; vertical-align: top; }
    .in { color: #2563eb; font-weight: 600; }
    .out { color: #059669; font-weight: 600; }
    input, select, textarea { width: 100%; box-sizing: border-box; padding: 7px; margin: 4px 0 10px;
      border: 1px solid #d1d5db; border-radius: 6px; font-family: inherit; }
    button { background: #2563eb; color: #fff; border: 0; border-radius: 6px; padding: 8px 14px; cursor: pointer; }
    button.gray { background: #6b7280; }
    .row { display: flex; gap: 8px; align-items: center; }
    .msg { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 6px; padding: 8px; font-size: 12px;
      white-space: pre-wrap; word-break: break-word; max-height: 160px; overflow: auto; }
    code { background: #eef2ff; padding: 1px 4px; border-radius: 4px; }
  </style>
</head>
<body>
  <h1>IRIS WhatsApp gateway &mdash; offline mock</h1>
  <div class="sub">
    Meta webhook: <code>{{ meta_webhook }}</code> &middot; Twilio webhook: <code>{{ twilio_webhook }}</code><br>
    verify token: <code>{{ verify_token }}</code> &middot; phone number id: <code>{{ phone_id }}</code>
    &middot; auto refresh 4s
  </div>
  <div class="grid">
    <div class="card">
      <h2>Send an inbound message (simulated user)</h2>
      <form method="post" action="/mock/inbound">
        <label>From</label>
        <input name="from" value="15551234567">
        <label>Name</label>
        <input name="name" value="Alice">
        <label>Message</label>
        <input name="text" value="hello">
        <label>Message type</label>
        <select name="type">
          <option value="text">text</option>
          <option value="image">image</option>
          <option value="button">button reply</option>
        </select>
        <div class="row">
          <button type="submit">Send to IRIS (Meta format)</button>
        </div>
      </form>
      <form method="post" action="/mock/twilio-inbound" style="margin-top:12px">
        <input type="hidden" name="from" value="15551234567">
        <input type="hidden" name="name" value="Alice">
        <input type="hidden" name="text" value="hello via twilio">
        <button type="submit" class="gray">Send to IRIS (Twilio format)</button>
      </form>
      <form method="post" action="/mock/status" style="margin-top:12px">
        <input type="hidden" name="status" value="read">
        <button type="submit" class="gray">Send a read receipt</button>
      </form>
      <div class="row" style="margin-top:12px">
        {% for cmd in ['help', 'menu', 'list', 'image', 'template', 'status'] %}
        <form method="post" action="/mock/inbound">
          <input type="hidden" name="from" value="15551234567">
          <input type="hidden" name="name" value="Alice">
          <input type="hidden" name="text" value="{{ cmd }}">
          <button type="submit" class="gray">{{ cmd }}</button>
        </form>
        {% endfor %}
      </div>
    </div>
    <div class="card">
      <h2>Traffic ({{ messages|length }} messages)</h2>
      <table>
        <tr><th>Dir</th><th>Provider</th><th>To / From</th><th>Type</th><th>Message</th><th>Id</th></tr>
        {% for m in messages %}
        <tr>
          <td class="{{ 'in' if m.direction == 'IN' else 'out' }}">{{ m.direction }}</td>
          <td>{{ m.provider }}</td>
          <td>{{ m.counterparty }}</td>
          <td>{{ m.type }}</td>
          <td class="msg">{{ m.text }}</td>
          <td>{{ m.id }}</td>
        </tr>
        {% endfor %}
      </table>
      <form method="post" action="/mock/reset" style="margin-top:12px">
        <button type="submit" class="gray">Reset</button>
      </form>
    </div>
  </div>
</body>
</html>
"""


def next_id(prefix):
    COUNTER["n"] += 1
    return "{}.{:04d}{}".format(prefix, COUNTER["n"], uuid.uuid4().hex[:6])


def wants_html():
    """True for browser form posts, false for curl / API clients."""
    if request.is_json:
        return False
    return request.accept_mimetypes.best == "text/html"


def record(direction, provider, counterparty, msg_type, text, message_id):
    MESSAGES.append(
        {
            "direction": direction,
            "provider": provider,
            "counterparty": counterparty,
            "type": msg_type,
            "text": text,
            "id": message_id,
            "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
    )


def meta_signature(raw_body):
    return "sha256=" + hmac.new(
        META_APP_SECRET.encode("utf-8"), raw_body, hashlib.sha256
    ).hexdigest()


def twilio_signature(url, fields):
    data = url
    for key in sorted(fields):
        data += key + fields[key]
    digest = hmac.new(
        TWILIO_AUTH_TOKEN.encode("utf-8"), data.encode("utf-8"), hashlib.sha1
    ).digest()
    return base64.b64encode(digest).decode("ascii")


def post_to_iris(payload, signature, content_type="application/json", body=None, url=None):
    raw = body if body is not None else json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": content_type, "X-Hub-Signature-256": signature}
    last_error = None
    target = url or META_WEBHOOK_URL
    for attempt in range(4):
        try:
            response = requests.post(target, data=raw, headers=headers, timeout=10)
            return response.status_code, response.text
        except requests.RequestException as exc:  # IRIS may still be starting
            last_error = str(exc)
            time.sleep(1)
    return 0, "IRIS unreachable: {}".format(last_error)


def meta_envelope(from_number, name, message):
    return {
        "object": "whatsapp_business_account",
        "entry": [
            {
                "id": "WABA-DEMO",
                "changes": [
                    {
                        "field": "messages",
                        "value": {
                            "messaging_product": "whatsapp",
                            "metadata": {
                                "display_phone_number": BUSINESS_NUMBER,
                                "phone_number_id": PHONE_NUMBER_ID,
                            },
                            "contacts": [
                                {"profile": {"name": name}, "wa_id": from_number}
                            ],
                            "messages": [message],
                        },
                    }
                ],
            }
        ],
    }


@app.get("/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "meta_webhook": META_WEBHOOK_URL,
            "twilio_webhook": TWILIO_WEBHOOK_URL,
            "messages": len(MESSAGES),
        }
    )


@app.get("/")
def index():
    return render_template_string(
        PAGE,
        messages=list(reversed(MESSAGES))[:50],
        meta_webhook=META_WEBHOOK_URL,
        twilio_webhook=TWILIO_WEBHOOK_URL,
        verify_token=VERIFY_TOKEN,
        phone_id=PHONE_NUMBER_ID,
    )


@app.post("/mock/inbound")
def mock_inbound():
    data = request.get_json(silent=True) or request.form
    from_number = str(data.get("from", "15551234567")).replace("whatsapp:", "")
    name = data.get("name", "Alice")
    text = data.get("text", "hello")
    msg_type = data.get("type", "text")
    message_id = next_id("wamid.mock")

    message = {
        "from": from_number,
        "id": message_id,
        "timestamp": str(int(time.time())),
        "type": msg_type,
    }
    if msg_type == "image":
        message["image"] = {
            "id": "MEDIA-MOCK-1",
            "mime_type": "image/png",
            "caption": text,
            "link": request.url_root + "assets/sample.png",
        }
    elif msg_type == "button":
        message["button"] = {"text": text, "payload": text}
    elif msg_type == "interactive":
        message["interactive"] = {
            "type": "button_reply",
            "button_reply": {"id": text, "title": text},
        }
    else:
        message["text"] = {"body": text}

    payload = meta_envelope(from_number, name, message)
    raw = json.dumps(payload).encode("utf-8")
    record("IN", "meta", from_number, msg_type, text, message_id)
    status_code, response_text = post_to_iris(payload, meta_signature(raw), body=raw)
    if wants_html():
        return redirect(url_for("index"))
    return jsonify(
        {
            "sent_to_iris": True,
            "iris_status": status_code,
            "iris_response": response_text,
            "payload": payload,
            "message_id": message_id,
        }
    )


@app.post("/mock/status")
def mock_status():
    status = request.form.get("status", "read")
    recipient = request.form.get("to", "15551234567").replace("whatsapp:", "")
    message_id = next_id("wamid.out")
    payload = {
        "object": "whatsapp_business_account",
        "entry": [
            {
                "id": "WABA-DEMO",
                "changes": [
                    {
                        "field": "messages",
                        "value": {
                            "messaging_product": "whatsapp",
                            "metadata": {"phone_number_id": PHONE_NUMBER_ID},
                            "statuses": [
                                {
                                    "id": message_id,
                                    "status": status,
                                    "timestamp": str(int(time.time())),
                                    "recipient_id": recipient,
                                }
                            ],
                        },
                    }
                ],
            }
        ],
    }
    raw = json.dumps(payload).encode("utf-8")
    record("IN", "meta", recipient, "status", status, message_id)
    status_code, response_text = post_to_iris(payload, meta_signature(raw), body=raw)
    if wants_html():
        return redirect(url_for("index"))
    return jsonify({"iris_status": status_code, "iris_response": response_text})


@app.post("/mock/twilio-inbound")
def mock_twilio_inbound():
    data = request.get_json(silent=True) or request.form
    from_number = str(data.get("from", "15551234567")).replace("whatsapp:", "")
    name = data.get("name", "Alice")
    text = data.get("text", "hello via twilio")
    message_sid = next_id("SM")
    fields = {
        "AccountSid": "ACdemo",
        "SmsMessageSid": message_sid,
        "MessageSid": message_sid,
        "From": "whatsapp:+" + from_number,
        "To": WA_SENDER,
        "WaId": from_number,
        "ProfileName": name,
        "Body": text,
        "NumMedia": "0",
        "SmsStatus": "received",
    }
    record("IN", "twilio", from_number, "text", text, message_sid)
    body = urllib.parse.urlencode(fields)
    signature = twilio_signature(TWILIO_WEBHOOK_URL, fields)
    last_error = None
    status_code = 0
    response_text = ""
    for _ in range(4):
        try:
            response = requests.post(
                TWILIO_WEBHOOK_URL,
                data=body.encode("utf-8"),
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "X-Twilio-Signature": signature,
                },
                timeout=10,
            )
            status_code, response_text = response.status_code, response.text
            break
        except requests.RequestException as exc:
            last_error = str(exc)
            time.sleep(1)
    if status_code == 0:
        response_text = "IRIS unreachable: {}".format(last_error)
    if wants_html():
        return redirect(url_for("index"))
    return jsonify({"iris_status": status_code, "iris_response": response_text})


@app.post("/v21.0/<phone_number_id>/messages")
def meta_send(phone_number_id):
    """Validate key provider fields and types so the demo exposes protocol errors."""
    auth = request.headers.get("Authorization", "")
    if auth != "Bearer mock-token":
        return jsonify({"error": {"code": 190, "message": "Invalid mock access token"}}), 401
    payload = request.get_json(silent=True) or {}
    if not isinstance(payload, dict) or payload.get("messaging_product") != "whatsapp" or not payload.get("to"):
        return jsonify({"error": {"code": 100, "message": "Missing WhatsApp recipient/product"}}), 400
    recipient = str(payload.get("to", ""))
    msg_type = payload.get("type", "unknown")
    text = ""
    if msg_type == "text":
        text_object = payload.get("text", {})
        if not isinstance(text_object, dict) or not isinstance(text_object.get("body"), str) or not (1 <= len(text_object["body"]) <= 4096):
            return jsonify({"error": {"code": 100, "message": "Invalid text body"}}), 400
        if "preview_url" in text_object and type(text_object["preview_url"]) is not bool:
            return jsonify({"error": {"code": 100, "message": "preview_url must be boolean"}}), 400
        text = payload.get("text", {}).get("body", "")
    elif msg_type == "template":
        template = payload.get("template", {})
        text = "[template {}]".format(template.get("name", ""))
    elif msg_type in ("image", "audio", "video", "document", "sticker"):
        media = payload.get(msg_type, {})
        text = media.get("caption") or media.get("link") or media.get("id", "")
    elif msg_type == "location":
        location = payload.get("location", {})
        text = "({}, {})".format(location.get("latitude"), location.get("longitude"))
    elif msg_type == "interactive":
        text = payload.get("interactive", {}).get("body", {}).get("text", "")
    elif msg_type == "reaction":
        text = payload.get("reaction", {}).get("emoji", "")
    message_id = next_id("wamid.out")
    record("OUT", "meta", recipient, msg_type, str(text), message_id)
    return jsonify(
        {
            "messaging_product": "whatsapp",
            "contacts": [{"input": recipient, "wa_id": recipient}],
            "messages": [{"id": message_id, "message_status": "accepted"}],
            "mock": {"phone_number_id": phone_number_id, "authorization": bool(auth)},
        }
    )


@app.post("/2010-04-01/Accounts/<account_sid>/Messages.json")
def twilio_send(account_sid):
    """Authenticate and distinguish text, media, and Content templates; reject empty messages."""
    auth = request.authorization
    if auth is None or auth.username != account_sid or auth.password != TWILIO_AUTH_TOKEN:
        return jsonify({"code": 20003, "message": "Invalid mock credentials"}), 401
    payload = request.form
    if not payload.get("From") or not payload.get("To"):
        return jsonify({"code": 21603, "message": "From and To are required"}), 400
    content_sid = payload.get("ContentSid", "")
    if content_sid:
        if not re.fullmatch(r"HX[0-9a-fA-F]{32}", content_sid) or "Body" in payload or "MediaUrl" in payload:
            return jsonify({"code": 21619, "message": "Invalid Content template form"}), 400
        try:
            variables = json.loads(payload.get("ContentVariables", "{}"))
            if not isinstance(variables, dict):
                raise ValueError("ContentVariables must be an object")
        except (ValueError, TypeError):
            return jsonify({"code": 21656, "message": "Invalid ContentVariables"}), 400
    elif not payload.get("Body") and not payload.get("MediaUrl"):
        return jsonify({"code": 21619, "message": "Body, MediaUrl or ContentSid is required"}), 400
    recipient = str(payload.get("To", "")).replace("whatsapp:", "")
    text = "[template {}]".format(content_sid) if content_sid else payload.get("Body", "") or payload.get("MediaUrl", "")
    msg_type = "template" if content_sid else "media" if payload.get("MediaUrl") else "text"
    message_sid = next_id("SM")
    record("OUT", "twilio", recipient, msg_type, str(text), message_sid)
    return (
        jsonify(
            {
                "sid": message_sid,
                "account_sid": account_sid,
                "status": "queued",
                "to": payload.get("To"),
                "from": payload.get("From"),
                "body": payload.get("Body"),
                "error_code": None,
                "error_message": None,
            }
        ),
        201,
    )


@app.get("/mock/messages")
def mock_messages():
    return jsonify(MESSAGES)


@app.get("/mock/reset")
def mock_reset_get():
    MESSAGES.clear()
    return jsonify({"status": "reset"})


@app.post("/mock/reset")
def mock_reset():
    MESSAGES.clear()
    return jsonify({"status": "reset"})


@app.get("/assets/sample.png")
def sample_png():
    return app.response_class(SAMPLE_PNG, mimetype="image/png")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8099, debug=False)
