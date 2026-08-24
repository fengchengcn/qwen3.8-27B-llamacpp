#!/usr/bin/env python3
"""诊断用：记录转发到 llama-server 的请求体。监听 0.0.0.0:9151 -> 127.0.0.1:9150"""
import http.server, http.client, time, os

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "captured.log")
UP = ("127.0.0.1", 9150)

class P(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def _forward(self, method):
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else b""
        with open(LOG, "a") as f:
            f.write("\n===== %s %s %s =====\n" % (time.strftime("%H:%M:%S"), method, self.path))
            f.write((body.decode("utf-8", "replace"))[:30000] + "\n")
        conn = http.client.HTTPConnection(*UP, timeout=900)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in ("connection", "host", "content-length")}
        headers["Host"] = UP[0]
        try:
            conn.request(method, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            out = resp.read()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() not in ("connection", "transfer-encoding"):
                    self.send_header(k, v)
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
        except Exception as e:
            with open(LOG, "a") as f:
                f.write("PROXY ERROR: %s\n" % e)
            try:
                self.send_response(502); self.end_headers(); self.wfile.write(str(e).encode())
            except Exception:
                pass
    do_POST = lambda s: s._forward("POST")
    do_GET  = lambda s: s._forward("GET")
    def log_message(self, *a): pass

http.server.ThreadingHTTPServer(("0.0.0.0", 9151), P).serve_forever()
