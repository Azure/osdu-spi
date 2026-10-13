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
# Fixture harness for the java-release resolver and the per-release stages the
# canonical Dockerfiles must carry for it. No Docker daemon, no network.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$HERE/../../actions/java-release/resolve.py"
BUILD="$HERE/../../../build"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note()  { printf '\n== %s\n' "$*"; }
die()   { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()    { printf 'ok: %s\n' "$*"; }

pom() {
  local name="$1" props="$2" extra="${3:-}"
  cat > "$TMP/$name.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <properties>
$props
  </properties>
$extra
</project>
EOF
  echo "$TMP/$name.xml"
}

expect() {
  local want="$1" file="$2" got
  got=$(python3 -I "$RESOLVE" "$file" 2>/dev/null) || die "$file: resolver failed, wanted $want"
  [ "$got" = "$want" ] || die "$file: got '$got', wanted '$want'"
}

expect_fail() {
  local pattern="$1" file="$2" err
  if err=$(python3 -I "$RESOLVE" "$file" 2>&1 >/dev/null); then
    die "$file: resolver succeeded, wanted a failure matching '$pattern'"
  fi
  grep -q "$pattern" <<<"$err" || die "$file: error '$err' does not match '$pattern'"
}

note "precedence"
expect 25 "$(pom release '    <maven.compiler.release>25</maven.compiler.release>')"
expect 25 "$(pom indirect '    <java.version>25</java.version>
    <maven.compiler.release>${java.version}</maven.compiler.release>')"
expect 17 "$(pom release-wins '    <java.version>25</java.version>
    <maven.compiler.release>17</maven.compiler.release>')"
expect 25 "$(pom java-version '    <java.version>25</java.version>')"
ok "maven.compiler.release, then java.version, with \${} expansion"

note "default"
expect 17 "$(pom source-target '    <maven.compiler.source>25</maven.compiler.source>
    <maven.compiler.target>25</maven.compiler.target>')"
expect 17 "$TMP/absent.xml"
ok "17 when neither key is set or there is no pom"

note "profiles do not count"
expect 17 "$(pom profile '    <foo>bar</foo>' '  <profiles><profile><id>x</id><properties><java.version>25</java.version></properties></profile></profiles>')"
ok "a profile's properties are ignored"

note "failures"
expect_fail "Java release 21 .* not supported; the build images carry 17, 25" "$(pom unsupported '    <maven.compiler.release>21</maven.compiler.release>')"
expect_fail "does not resolve within the pom" "$(pom dangling '    <maven.compiler.release>${parent.java}</maven.compiler.release>')"
expect_fail "does not resolve within the pom" "$(pom cycle '    <a>${b}</a>
    <b>${a}</b>
    <java.version>${a}</java.version>')"
ok "unsupported and unresolvable releases fail with a reason"

note "every supported release has an image stage"
SUPPORTED=$(python3 -I -c 'import importlib.util,sys; s=importlib.util.spec_from_file_location("r", sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(" ".join(m.SUPPORTED))' "$RESOLVE")
for v in $SUPPORTED; do
  grep -qE "^FROM mcr\.microsoft\.com/openjdk/jdk:${v}-azurelinux@sha256:[0-9a-f]{64} AS runtime-${v}\$" "$BUILD/Dockerfile" \
    || die "build/Dockerfile has no digest-pinned runtime-${v} stage"
  grep -qE "^FROM docker\.io/library/maven:3\.9-eclipse-temurin-${v}@sha256:[0-9a-f]{64} AS maven-${v}\$" "$BUILD/acceptance.Dockerfile" \
    || die "build/acceptance.Dockerfile has no digest-pinned maven-${v} stage"
done
grep -q '^FROM runtime-${JAVA_VERSION}$' "$BUILD/Dockerfile" || die "build/Dockerfile must select its base by JAVA_VERSION"
grep -q '^FROM maven-${JAVA_VERSION}$' "$BUILD/acceptance.Dockerfile" || die "build/acceptance.Dockerfile must select its base by JAVA_VERSION"
for f in Dockerfile acceptance.Dockerfile; do
  [ "$(grep -n '^ARG JAVA_VERSION=17$' "$BUILD/$f" | cut -d: -f1)" -lt "$(grep -n '^FROM' "$BUILD/$f" | head -1 | cut -d: -f1)" ] \
    || die "build/$f must declare ARG JAVA_VERSION=17 before its first FROM"
done
ok "stages for: $SUPPORTED"

printf '\nAll java-release checks passed.\n'
