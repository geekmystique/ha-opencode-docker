#!/bin/bash
# standalone/rootfs started as a copy of ha_opencode/rootfs (see
# standalone/README.md) and has since diverged on purpose in ~18 files
# (bashio replaced with plain env vars, SUPERVISOR_TOKEN replaced with
# HA_ACCESS_TOKEN, and so on). The other ~140 files are still meant to be
# identical. This script is the only thing standing between that and silent
# rot: it flags any ha_opencode/rootfs file that changed between two refs
# whose standalone/rootfs counterpart (same relative path) did NOT change in
# the same diff.
#
# A file that exists only in ha_opencode/rootfs (a Supervisor/Ingress-only
# service standalone deliberately doesn't have, e.g. ha-facing-mcp) has no
# counterpart to check and is silently skipped - there is nothing to port.
#
# This is a nudge, not a gate: not every upstream change needs porting
# (comments, Supervisor-only logic, unrelated features), so it always exits
# 0 and reports through GitHub Actions ::warning:: annotations instead of
# failing the build. A human still has to look and decide.
#
# Usage: scripts/check-standalone-drift.sh [BASE_REF] [HEAD_REF]
# Defaults: BASE_REF=origin/main, HEAD_REF=HEAD

set -euo pipefail

BASE_REF="${1:-origin/main}"
HEAD_REF="${2:-HEAD}"

cd "$(git rev-parse --show-toplevel)"

if ! git rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null; then
    echo "Could not resolve BASE_REF '${BASE_REF}' (shallow checkout? first commit on a branch?) - skipping drift check."
    exit 0
fi
if ! git rev-parse --verify -q "${HEAD_REF}^{commit}" >/dev/null; then
    echo "Could not resolve HEAD_REF '${HEAD_REF}' - skipping drift check."
    exit 0
fi

changed_upstream=$(git diff --name-only "${BASE_REF}...${HEAD_REF}" -- ha_opencode/rootfs || true)
changed_standalone=$(git diff --name-only "${BASE_REF}...${HEAD_REF}" -- standalone/rootfs || true)

if [ -z "${changed_upstream}" ]; then
    echo "No ha_opencode/rootfs changes between ${BASE_REF} and ${HEAD_REF} - nothing to check."
    exit 0
fi

drifted=0
while IFS= read -r file; do
    [ -n "${file}" ] || continue
    rel="${file#ha_opencode/rootfs/}"
    standalone_path="standalone/rootfs/${rel}"

    # No standalone counterpart (e.g. a Supervisor/Ingress-only service) -
    # nothing to port.
    [ -e "${standalone_path}" ] || continue

    if ! grep -qxF "${standalone_path}" <<< "${changed_standalone}"; then
        echo "::warning file=${file}::ha_opencode changed this file but ${standalone_path} was not touched in the same change. If the change is user-facing or logic-bearing (not just a comment/formatting tweak), standalone/ likely needs the same fix - see standalone/README.md for the porting pattern (bashio::config -> plain env var, SUPERVISOR_TOKEN -> HA_ACCESS_TOKEN fallback)."
        drifted=1
    fi
done <<< "${changed_upstream}"

if [ "${drifted}" -eq 0 ]; then
    echo "No drift: every changed ha_opencode/rootfs file with a standalone/rootfs counterpart was updated in the same change."
fi

exit 0
