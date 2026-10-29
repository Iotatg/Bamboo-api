#!/usr/bin/env python3
"""A stand-in for the APInex upstream, so the gateway can be tested offline.

Speaks just enough: GET /v1/models, POST /v1/chat/completions with and
without stream. Prices and tokens are fixed so the ledger is checkable.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("[mock] " + fmt % args, flush=True)

    def _send(self, status, payload, content_type="application/json"):
        body = payload.encode() if isinstance(payload, str) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/v1/models"):
            self._send(200, {
                "object": "list",
                "data": [
                    {"id": "gpt/4o-mini", "context_window": 128000,
                     "pricing": {"prompt": "0.00000015", "completion": "0.0000006"}},
                    {"id": "claude/sonnet-5", "context_window": 200000,
                     "pricing": {"prompt": "0.000003", "completion": "0.000015"}},
                    {"id": "free/llama-3-8b", "context_window": 8192},
                ],
            })
        else:
            self._send(404, {"error": {"message": "not found"}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw)
        except ValueError:
            self._send(400, {"error": {"message": "bad json"}})
            return

        if self.headers.get("Authorization") == "Bearer bad-key":
            self._send(401, {"error": {"message": "invalid upstream key"}})
            return

        model = body.get("model", "unknown")
        last = ""
        if isinstance(body.get("messages"), list) and body["messages"]:
            last = str(body["messages"][-1].get("content", ""))[:80]

        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            pieces = ["The ", "ledger ", "balances ", "to ", "zero."]
            for piece in pieces:
                chunk = {
                    "id": "chatcmpl-mock",
                    "object": "chat.completion.chunk",
                    "created": int(time.time()),
                    "model": model,
                    "choices": [{"index": 0, "delta": {"content": piece}, "finish_reason": None}],
                }
                self._chunk("data: " + json.dumps(chunk) + "\n\n")
            final = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": model,
                "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 12, "completion_tokens": 5, "total_tokens": 17},
            }
            self._chunk("data: " + json.dumps(final) + "\n\n")
            self._chunk("data: [DONE]\n\n")
            self._chunk("")
            return

        self._send(200, {
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": model,
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": "echo: " + last},
                "finish_reason": "stop",
            }],
            "usage": {"prompt_tokens": 12, "completion_tokens": 5, "total_tokens": 17},
        })

    def _chunk(self, text):
        data = text.encode()
        self.wfile.write(("%X\r\n" % len(data)).encode() + data + b"\r\n")
        self.wfile.flush()


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 9001), Handler)
    print("mock upstream on http://127.0.0.1:9001/v1", flush=True)
    server.serve_forever()
