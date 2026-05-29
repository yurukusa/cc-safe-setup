#!/bin/bash
# proxy-capture-suggester.sh — Surface HTTPS proxy capture path for compliance-bound operators
#
# Background:
#   v2.1.150+ injects server-side strings into the system prompt via two cached channels:
#   the bootstrap API `client_data` field and the GrowthBook `tengu_heron_brook` flag.
#   The opt-out env vars (CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1, DISABLE_GROWTHBOOK=1)
#   close the injection channel going forward, and cache-residue-detector.sh prompts
#   removal of pre-opt-out cached values. Neither produces a reconstructible audit trail
#   of what the agent was instructed at the time of any logged action.
#
#   For operators in regulated industries (financial services, healthcare, government,
#   defense) the audit trail gap is the structural concern. The opt-outs answer
#   "stop trusting Anthropic with the prompt", but compliance frameworks (SOX, HIPAA,
#   FedRAMP, PCI-DSS, EU AI Act Article 12) also require "produce the exact prompt that
#   was sent for any logged tool execution within the retention window".
#
#   The only operator-side path to that audit trail is HTTPS proxy capture: an MITM
#   proxy between the Claude Code client and api.anthropic.com that records the full
#   request body of every API call. Anthropic does not provide a first-party audit
#   export; the proxy capture path is the workaround.
#
#   Reference: https://github.com/anthropics/claude-code/issues/62061 (46+ reactions)
#              https://gist.github.com/yurukusa/03839b3c3f88e1cce38fb0f2c127544d (v2.1.150 audit paths)
#
# What this hook does:
#   On SessionStart, when CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 is set, inspect the
#   environment for an active HTTPS proxy configuration. If none is present, emit a
#   one-time advisory naming three audit-grade proxy tools with concrete invocation,
#   the CA-trust step required for TLS termination, and the env-var bridge that wires
#   Claude Code's API client into the proxy.
#
#   The hook is opt-in. Most operators do not need an audit trail and would not
#   benefit from running an MITM proxy locally; it adds attack surface, latency, and
#   maintenance overhead. The advisory only fires when an operator has explicitly
#   declared compliance intent via the opt-in env var.
#
# When this hook does NOT fire:
#   - CC_PROXY_CAPTURE_SUGGESTER_ENABLE is unset or set to 0 (the default)
#   - CC_PROXY_CAPTURE_SUGGESTER_QUIET=1 (silenced after acknowledgement)
#   - An HTTPS proxy is already active (HTTPS_PROXY / https_proxy / ALL_PROXY contains a value)
#
# When this hook DOES fire (default behavior with ENABLE=1):
#   - SessionStart and no HTTPS_PROXY-family env var is set → emit the four-tool advisory
#   - SessionStart and a proxy IS set but ANTHROPIC_LOG_DIR is unset → emit a shorter
#     advisory pointing out that proxy capture is active but no local log sink is configured
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/proxy-capture-suggester.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1   — opt in to the advisory (default off)
#   CC_PROXY_CAPTURE_SUGGESTER_QUIET=1    — silence permanently after acknowledgement
#
# Privacy: the hook reads only the names of standard proxy env vars (HTTPS_PROXY,
# https_proxy, ALL_PROXY, NO_PROXY, ANTHROPIC_LOG_DIR). It never reads, transmits, or
# logs the values themselves.

set -u

# Silenced permanently after acknowledgement
if [ "${CC_PROXY_CAPTURE_SUGGESTER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Opt-in: silent unless the operator explicitly declared compliance intent
if [ "${CC_PROXY_CAPTURE_SUGGESTER_ENABLE:-0}" != "1" ]; then
  exit 0
fi

# Check for an active HTTPS proxy (uppercase or lowercase, plus ALL_PROXY)
PROXY_ACTIVE=0
for var in HTTPS_PROXY https_proxy ALL_PROXY all_proxy; do
  # shellcheck disable=SC1083
  eval val="\${$var:-}"
  if [ -n "${val:-}" ]; then
    PROXY_ACTIVE=1
    break
  fi
done

if [ "$PROXY_ACTIVE" = "1" ]; then
  # Proxy is active. Check whether an audit log sink is configured.
  if [ -z "${ANTHROPIC_LOG_DIR:-}" ]; then
    cat >&2 <<'EOF'
[proxy-capture-suggester] HTTPS proxy is active but ANTHROPIC_LOG_DIR is unset.
  Compliance-grade audit trails require a stable on-disk sink for the captured
  request bodies. Configure one before relying on the proxy capture for evidence:

    export ANTHROPIC_LOG_DIR="$HOME/.claude/api-audit-log"
    mkdir -p "$ANTHROPIC_LOG_DIR"

  mitmproxy: --save-stream-file "$ANTHROPIC_LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ).flow"
  Burp Suite: Project options -> HTTP -> Logging -> Requests -> file in $ANTHROPIC_LOG_DIR
  Charles: Tools -> Auto Save -> directory in $ANTHROPIC_LOG_DIR, format .chlsj

  Silence this advisory once configured:
    export CC_PROXY_CAPTURE_SUGGESTER_QUIET=1
EOF
  fi
  exit 0
fi

# No proxy active — emit the full four-tool advisory.
cat >&2 <<'EOF'
[proxy-capture-suggester] Compliance audit intent declared (CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
but no HTTPS proxy is configured. Without one, you cannot reconstruct the system prompt that
was sent at the time of any logged tool execution. The v2.1.150 server-side injection channel
(GrowthBook tengu_heron_brook + bootstrap client_data) is acknowledged-intentional by Anthropic;
opt-out env vars close the channel going forward but produce no audit trail.

Four operator-side proxy options that terminate TLS and record the full request body:

  1. mitmproxy (free, scriptable, recommended for compliance pipelines)
       brew install mitmproxy            # macOS
       pipx install mitmproxy            # Linux
     Start:
       mitmproxy --mode regular --listen-port 8080 \
                 --save-stream-file "$HOME/.claude/api-audit-log/$(date -u +%Y%m%dT%H%M%SZ).flow"
     Bridge:
       export HTTPS_PROXY=http://127.0.0.1:8080
       export SSL_CERT_FILE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
     Verify: a single Claude Code prompt should produce a .flow file with the request body.

  2. Burp Suite Community (free, GUI, common in enterprise pen-test contexts)
     Proxy listener: 127.0.0.1:8080. Configure HTTPS_PROXY as above. Export the Burp CA cert
     and set SSL_CERT_FILE to its path. Project options -> HTTP -> Logging -> Requests for
     persistent capture.

  3. Charles Proxy (commercial, $50, GUI, common on macOS dev workstations)
     Default listener 127.0.0.1:8888. Tools -> Auto Save for persistent capture. Trust the
     Charles root certificate via Charles -> Help -> SSL Proxying.

  4. Anthropic SDK direct logging (free, lightweight, no proxy)
     Set ANTHROPIC_LOG=debug to dump every request to stderr; redirect stderr to a file
     and rotate. This captures less metadata than a proper proxy (no response timing, no
     TLS handshake detail) but produces a request-body audit trail with no MITM overhead.

The four paths above produce an audit trail that pairs with cache-residue-detector.sh
(closes the cache gap) and server-side-prompt-injection-detector.sh (warns on missing
opt-outs). Together these three hooks cover the v2.1.150 audit surface for operators in
regulated industries.

Silence this advisory after configuring a proxy:
  export CC_PROXY_CAPTURE_SUGGESTER_QUIET=1

References:
  https://github.com/anthropics/claude-code/issues/62061  (v2.1.150 injection report, 46+ reactions)
  https://gist.github.com/yurukusa/03839b3c3f88e1cce38fb0f2c127544d  (four audit paths writeup)
EOF

exit 0
