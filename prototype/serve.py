#!/usr/bin/env python3
"""预览用静态服务：带 no-store，改完文件刷新即生效（浏览器不会缓存旧 CSS/JS）。"""
import functools
import http.server
import os
import socketserver

PORT = 8899
ROOT = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass  # 安静点


socketserver.TCPServer.allow_reuse_address = True
handler = functools.partial(Handler, directory=ROOT)
with socketserver.TCPServer(("0.0.0.0", PORT), handler) as httpd:
    httpd.serve_forever()
