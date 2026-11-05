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

"""Helpers shared by the Component Governance pipeline steps (ADR-047).

The steps run on an Azure DevOps agent. Errors and warnings use the agent's
logging commands, so they show in the run summary.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

GITHUB_API = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
BOT_NAME = "osdu-spi component governance"
BOT_EMAIL = "osdu-spi-component-governance@users.noreply.github.com"
POLL_SECONDS = int(os.environ.get("CG_POLL_SECONDS", "30"))


def fail(msg):
    print(f"##[error]{msg}", flush=True)
    sys.exit(1)


def warn(msg):
    print(f"##vso[task.logissue type=warning]{msg}", flush=True)


def git(*args, env=None):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True,
                          env=None if env is None else {**os.environ, **env}).stdout.strip()


def write_json(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def extraheaders():
    out = subprocess.run(["git", "config", "--local", "--get-regexp", r"^http\..*\.extraheader$"],
                         capture_output=True, text=True).stdout
    return [line.split(" ", 1) for line in out.splitlines() if " " in line]


def checkout_token():
    """The GitHub App installation token a `persistCredentials: true` checkout stores as an HTTP extra header.

    The agent masks the service connection's token in logs; nothing here prints it."""
    for _, value in extraheaders():
        if value.lower().startswith("authorization: basic "):
            return base64.b64decode(value.split()[-1]).decode().split(":", 1)[1]
    fail("The checkout did not persist a GitHub credential")


def drop_credentials():
    for key, _ in extraheaders():
        subprocess.run(["git", "config", "--local", "--unset-all", key], check=True)


def github(token, path, method="GET", body=None, query=None):
    """Calls the GitHub REST API. Raises urllib.error.HTTPError on an error status."""
    url = f"{GITHUB_API}/{path.lstrip('/')}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data, headers={
        "Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def github_or_fail(token, path, method="GET", body=None, query=None):
    try:
        return github(token, path, method, body, query)
    except urllib.error.HTTPError as e:
        fail(f"{method} {GITHUB_API}/{path.lstrip('/')} returned HTTP {e.code}: {e.read()[:500]!r}")


def ado_auth():
    return "Basic " + base64.b64encode((":" + os.environ["SYSTEM_ACCESSTOKEN"]).encode()).decode()


def ado_get(url, tries=3, raw=False):
    """GET an Azure DevOps REST URL with the job access token, retrying throttling and server errors."""
    for attempt in range(1, tries + 1):
        req = urllib.request.Request(url, headers={"Authorization": ado_auth(), "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                body = r.read()
                return body.decode("utf-8", errors="replace") if raw else json.loads(body)
        except urllib.error.HTTPError as e:
            msg = f"GET {url.split('?')[0]} returned HTTP {e.code}: {e.read()[:300]!r}"
            if (e.code < 500 and e.code != 429) or attempt == tries:
                fail(msg)
        except (urllib.error.URLError, TimeoutError) as e:
            msg = f"GET {url.split('?')[0]} failed: {e}"
            if attempt == tries:
                fail(msg)
        print(f"{msg}; retrying in {POLL_SECONDS} s", flush=True)
        time.sleep(POLL_SECONDS)
