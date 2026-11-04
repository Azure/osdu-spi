#!/usr/bin/env python3
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""A scripted HTTP API on 127.0.0.1 for the component governance harness.

Usage: fake_api.py ROUTES.json PORT_FILE LOG_FILE

ROUTES is a list of {"method", "path", "responses"}. path is a regular
expression matched against the full request path and query. Each request
takes the route's next response; the last one repeats. A response is
{"status", "json"} or {"status", "text"}; the string {base} in a body becomes
this server's base URL. Every request is appended to LOG_FILE as one JSON
line {method, path, auth, body}. An unmatched request gets 418, a client error every caller fails on.
"""

import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

routes_file, port_file, log_file = sys.argv[1:4]
with open(routes_file, encoding="utf-8") as f:
    ROUTES = [dict(r, regex=re.compile(r["path"]), served=0) for r in json.load(f)]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode() if length else ""
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps({"method": self.command, "path": self.path, "auth": self.headers.get("Authorization"),
                                "body": json.loads(raw) if raw else None}) + "\n")
        for route in ROUTES:
            if route["method"] == self.command and route["regex"].fullmatch(self.path):
                resp = route["responses"][min(route["served"], len(route["responses"]) - 1)]
                route["served"] += 1
                break
        else:
            resp = {"status": 418, "text": f"unmatched {self.command} {self.path}"}
        base = f"http://127.0.0.1:{self.server.server_address[1]}"
        if "json" in resp:
            body, ctype = json.dumps(resp["json"]).replace("{base}", base).encode(), "application/json"
        else:
            body, ctype = resp.get("text", "").replace("{base}", base).encode(), "text/plain"
        self.send_response(resp.get("status", 200))
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_PATCH = do_PUT = do_DELETE = handle_any


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file + ".tmp", "w", encoding="utf-8") as f:
    f.write(str(server.server_address[1]))
os.replace(port_file + ".tmp", port_file)
server.serve_forever()
