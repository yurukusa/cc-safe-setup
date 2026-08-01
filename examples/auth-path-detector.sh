#!/bin/bash
# ================================================================
# auth-path-detector.sh — Warn before driving an auth/login flow,
#                        especially on a resource that the user did
#                        not explicitly authorize.
# ================================================================
# PURPOSE:
#   When the next tool call appears to navigate to or operate on an
#   authentication path (login page, OAuth authorization endpoint,
#   credential entry form, SSO/SAML callback), emit a warning so the
#   operator can confirm that the resource is the one the user
#   permitted. Prevents the failure mode reported in Issue #55909
#   (Cowork mode) where a halt signal was followed by the model
#   driving a login flow on a different browser identifier than the
#   user had limited the work to.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|WebFetch|WebSearch|mcp__.*__(go|navigate|click|form)"
#   In practice, configure with a broad matcher; this script inspects
#   the tool input and exits silently when no auth indicator is found.
#
# WHY THIS MATTERS:
#   In Issue #55909, the user limited operations to a remote browser,
#   but the model continued to a different browser when one operation
#   failed and opened a login page there. Authentication context is
#   bound to a browser/profile identifier; driving a login flow on
#   the wrong identifier silently writes credentials into the wrong
#   trust boundary. The user's repeated halt signals were reframed
#   as "let me just do this one part" — bargaining language that the
#   halt-signal-detector hook also checks.
#
#   This hook is a complementary check at the auth-path boundary.
#   Even when the halt signal is absent, an auth flow on a non-
#   authorized resource is high-stakes and should be confirmed.
#
# WHAT IT CHECKS:
#   1. Read the tool name and tool_input from the PreToolUse payload
#   2. Extract the URL/command/text fields most likely to contain a
#      navigation target
#   3. Search for auth-path indicators (login, signin, oauth, etc.)
#   4. If found, emit a warning to stderr with the matched substring
#   5. If CC_AUTH_PATH_BLOCK=1, also exit 2 to block the tool call
#
# OUTPUT:
#   Warning to stderr with the matched indicator and a reference to
#   Issue #55909. Exit 0 (advisory) by default.
#
# CONFIGURATION:
#   CC_AUTH_PATH_BLOCK    — set to "1" to block the tool call (exit 2)
#                          when an auth-path indicator is detected.
#                          Default is advisory only.
#   CC_AUTH_PATH_EXTRA    — additional comma-separated path tokens to
#                          match (case-insensitive). Example:
#                          "verify,callback".
#   CC_AUTH_PATH_ALLOW    — comma-separated substrings; if the matched
#                          URL/command contains any, suppress the
#                          warning. Use to whitelist intentional
#                          flows (e.g. "localhost:3000/login").
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/55909
# ================================================================

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-auth-path-detector-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [auth-path-detector]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [ -z "$TOOL_NAME" ]; then
    exit 0
fi

# Pull every plausible string field from tool_input where a URL or
# auth-path command might live. Concatenate them so a single regex
# pass covers the relevant surface.
HAYSTACK=$(printf '%s' "$INPUT" | jq -r '
    def s($v): if ($v | type) == "string" then $v else "" end;
    [
      s(.tool_input.url),
      s(.tool_input.URL),
      s(.tool_input.command),
      s(.tool_input.prompt),
      s(.tool_input.query),
      s(.tool_input.path),
      s(.tool_input.target),
      s(.tool_input.location),
      s(.tool_input.address),
      s(.tool_input.endpoint),
      s(.tool_input.text),
      s(.tool_input.value)
    ] | join(" ")
' 2>/dev/null)

if [ -z "$HAYSTACK" ] || [ "$HAYSTACK" = "         " ]; then
    exit 0
fi

# Auth path indicators. Each token is matched case-insensitively
# against the haystack. The patterns are conservative to keep false
# positives low — they expect URL-style separators or word
# boundaries.
#
# Notes on selection:
# - /login, /signin, /sign-in, /log-in are the most common form paths
# - /oauth, /authorize, /authorization cover OAuth grant entry points
# - /sso, /saml cover federation callbacks
# - /credentials, /password, /reset-password cover credential entry
# - login.microsoftonline.com / accounts.google.com are concrete IdPs
# - Japanese surface: ログイン, 認証, 認可
AUTH_BASE='/login\b|/log-in\b|/signin\b|/sign-in\b|/sign_in\b|/log_in\b|/oauth\b|/oauth2\b|/authorize\b|/authorization\b|/sso\b|/saml\b|/openid\b|/credentials?\b|/password\b|/reset-password\b|/forgot-password\b|/auth/callback\b|/auth/token\b|login\.microsoftonline\.com|accounts\.google\.com|auth0\.com|okta\.com|github\.com/login|gitlab\.com/users/sign_in|ログイン|サインイン|認証ページ|ログインページ'

EXTRA="${CC_AUTH_PATH_EXTRA:-}"
if [ -n "$EXTRA" ]; then
    EXTRA_PATTERN=$(printf '%s' "$EXTRA" | tr ',' '|')
    AUTH_PATTERN="${AUTH_BASE}|${EXTRA_PATTERN}"
else
    AUTH_PATTERN="$AUTH_BASE"
fi

MATCH=$(printf '%s' "$HAYSTACK" | grep -oiE "$AUTH_PATTERN" | head -1)

if [ -z "$MATCH" ]; then
    exit 0
fi

# Allowlist: suppress when the haystack contains a permitted substring
ALLOW="${CC_AUTH_PATH_ALLOW:-}"
if [ -n "$ALLOW" ]; then
    OLDIFS=$IFS
    IFS=','
    for token in $ALLOW; do
        token_trimmed=$(printf '%s' "$token" | sed 's/^ *//;s/ *$//')
        if [ -n "$token_trimmed" ] && printf '%s' "$HAYSTACK" | grep -qiF "$token_trimmed"; then
            IFS=$OLDIFS
            exit 0
        fi
    done
    IFS=$OLDIFS
fi

SNIPPET=$(printf '%s' "$HAYSTACK" | head -c 200 | tr '\n' ' ')
cat >&2 <<EOF
🔐 auth-path-detector: 道具の呼び出しが認証の経路に向かっています。
  道具: ${TOOL_NAME}
  検出した目印: ${MATCH}
  文脈の冒頭: ${SNIPPET}
  確認のお願い:
    1. この資源 (ブラウザ、 識別子、 場所) は利用者が明示的に許可したものですか
    2. 認証の文脈はブラウザの識別子に紐付いています。 別の識別子で操作すると、 認証の合図が別の信頼の境界に書き込まれます
    3. 利用者の停止の合図 (やめて、 stop など) があった直後の認証の経路の駆動は、 部分的な協力の依頼に見えます
  Reference: https://github.com/anthropics/claude-code/issues/55909
EOF

if [ "${CC_AUTH_PATH_BLOCK:-0}" = "1" ]; then
    exit 2
fi

exit 0
