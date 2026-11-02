#!/usr/bin/env bash
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

#
# Builds the trust store a suite JVM uses behind its port-forwards: the suite
# image's own JDK cacerts plus each CA certificate the forwarded endpoints serve.
# In-cluster services sign with a private CA, which a client trusting only the
# JVM store rejects. The CA is read through the forward, which already reaches
# the published pod over the authenticated Kubernetes API.
#
# The caller mounts <out-dir> and points the suite at it with
#   JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=<mount>/cacerts -Djavax.net.ssl.trustStorePassword=changeit
#
# Usage: forward-truststore.sh <image|--host-jdk> <out-dir> <port>...
# CONTAINER_ENGINE names the engine that runs the image (default docker; podman works too).
# --host-jdk builds the store from the host JDK instead, for a suite Maven runs on the host.
# Exit 1 when a port serves no CA certificate or the import fails.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <image|--host-jdk> <out-dir> <port>..." >&2
  exit 1
fi
image="$1"
engine="${CONTAINER_ENGINE:-docker}"
mkdir -p "$2"
# Absolute and physical, so the engine mounts the directory rather than a named volume.
out="$(CDPATH= cd -- "$2" && pwd -P)"
shift 2

rm -f "$out"/ca-*.pem "$out"/chain-*.pem "$out"/served-*.txt "$out/cacerts"
added=0
for port in "$@"; do
  [[ "$port" =~ ^[0-9]+$ ]] || { echo "port '$port' is not a number" >&2; exit 1; }
  # A server that accepts but never finishes the handshake gets 20 seconds; no timeout(1) needed.
  served="$out/served-$port.txt"
  openssl s_client -connect "127.0.0.1:$port" -showcerts < /dev/null > "$served" 2> /dev/null &
  client=$!
  for _ in $(seq 1 40); do
    kill -0 "$client" 2> /dev/null || break
    sleep 0.5
  done
  kill "$client" 2> /dev/null || true
  wait "$client" 2> /dev/null || true
  awk -v dir="$out" -v port="$port" '
        /BEGIN CERTIFICATE/ { n++; on = 1; file = sprintf("%s/chain-%s-%d.pem", dir, port, n) }
        on { print > file }
        /END CERTIFICATE/ { on = 0; close(file) }' "$served"
  rm -f "$served"
  found=0
  for cert in "$out"/chain-"$port"-*.pem; do
    [[ -f "$cert" ]] || continue
    constraints=$(openssl x509 -in "$cert" -noout -text 2> /dev/null \
      | awk '/^ *X509v3 Basic Constraints:/ { getline; print; exit }')
    if [[ "$constraints" =~ ^[[:space:]]*CA:TRUE ]]; then
      mv "$cert" "$out/ca-${cert##*/chain-}"
      found=1
      added=$((added + 1))
    else
      rm -f "$cert"
    fi
  done
  [[ "$found" == 1 ]] || { echo "127.0.0.1:$port served no CA certificate" >&2; exit 1; }
done

# The keytool and cacerts of the JVM that reads the store; $1 is the store's directory.
import='
  set -e
  java_home="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
  cp "$java_home/lib/security/cacerts" "$1/cacerts"
  chmod u+w "$1/cacerts"
  for ca in "$1"/ca-*.pem; do
    "$java_home/bin/keytool" -importcert -noprompt -alias "${ca##*/}" -file "$ca" -keystore "$1/cacerts" -storepass changeit > /dev/null
  done'
if [[ "$image" == --host-jdk ]]; then
  # The JVM Maven starts: JAVA_HOME, else the java on PATH, whose home a launcher stub would hide.
  java_home="${JAVA_HOME:-$( { java -XshowSettings:properties -version 2>&1 || true; } | awk -F' = ' '/^ *java.home = / { print $2 }')}"
  [[ -n "$java_home" && -x "$java_home/bin/keytool" ]] || { echo "no host JDK keytool (set JAVA_HOME)" >&2; exit 1; }
  JAVA_HOME="$java_home" sh -c "$import" sh "$out"
else
  run=("$engine" run --rm --user "$(id -u):$(id -g)")
  # Rootless Podman maps the caller to container root, so --user alone lands on a subordinate ID that cannot write the mount.
  if [[ "$engine" == *podman* && "$("$engine" info --format '{{.Host.Security.Rootless}}' 2> /dev/null)" == true ]]; then
    run+=(--userns=keep-id)
  fi
  "${run[@]}" --entrypoint sh -v "$out:/trust" "$image" -c "$import" sh /trust
fi
[[ -s "$out/cacerts" ]] || { echo "the trust store was not written" >&2; exit 1; }
echo "trust store: $added forwarded CA certificates added"
