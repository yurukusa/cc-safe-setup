#!/bin/bash
# ================================================================
# deployment-readback-gate.sh — Stop-hook gate that verifies
#                                deployment-completion claims
#                                against authoritative version
#                                registries
# ================================================================
# PURPOSE:
#   Stop hook. When the assistant's closeout text contains a
#   deployment-completion claim (matched against a configurable
#   phrase list), the hook parses the named target, queries the
#   deployment system's authoritative version registry through a
#   provider-specific adapter, compares the queried version
#   against the claimed version, and refuses the closeout if
#   the query fails or the versions don't match.
#
#   Sibling of dispatch-receipt.sh and commitment-carry-forward-
#   arrest.sh. Where dispatch-receipt records and gates *agent
#   dispatch* operations and commitment-carry-forward records
#   and gates *commitment* claims, this hook records and gates
#   *deployment-completion* claims at the Stop boundary.
#
#   Out-of-band-source pattern: the hook reads from a source
#   structurally different from the source the claim derives
#   from (model narrative vs. CI/CD registry).
#
# TRIGGER: Stop
#
# WHY THIS MATTERS:
#   anthropics/claude-code#61699 reported a case where the model
#   claimed "deployment complete" while the actual deployment
#   state diverged from the claim. @giruuuuj framed this as the
#   rule-installation vs. rule-articulation surface distinction.
#   The cluster catalog at the matrix Gist:
#     https://gist.github.com/yurukusa/bb3812006d92d49cf55db74a65fc4032
#   places this as Row 12: closeout-after-deployment-claim
#   lifecycle event, MAST mode 3.3 (no verification).
#
# RECEIPT FORMAT (one JSONL per evaluated closeout):
#   {"ts":"2026-05-24T10:30:00Z",
#    "adapter":"gh|kubectl|terraform",
#    "target":"<resolved deployment target>",
#    "claimed_version":"<version string extracted from closeout>",
#    "queried_version":"<version string returned by adapter>",
#    "decision":"execute" | "refuse-mismatch" | "refuse-query-failure" | "execute-bypassed"}
#
# RECEIPT LOCATION:
#   ${HOME}/.claude/receipts/deployment-readback-YYYY-MM-DD.jsonl
#
# CONFIGURATION:
#   DRG_ADAPTER — "gh" | "kubectl" | "terraform" (required when
#     enabled; if unset, the hook exits silently without parsing)
#
#   DRG_PHRASE_LIST — comma-separated list of phrases that
#     trigger the gate. Default:
#     "deployed,deployment complete,shipped to production,rolled out"
#
#   DRG_GH_REPO — for gh adapter, "<owner>/<repo>" (required for
#     gh adapter)
#
#   DRG_KUBECTL_NAMESPACE — for kubectl adapter, target namespace
#     (required for kubectl adapter)
#
#   DRG_KUBECTL_DEPLOYMENT — for kubectl adapter, deployment name
#     (required for kubectl adapter)
#
#   DRG_TERRAFORM_OUTPUT — for terraform adapter, name of the
#     terraform output to query (required for terraform adapter)
#
#   DRG_STRICT_MODE=1 — refuse any closeout containing a
#     deployment phrase even if the target cannot be resolved.
#     Default 0 (skip verification when target cannot be resolved).
#
#   DRG_BYPASS=1 — single-call escape hatch. The receipt is still
#     written (with decision="execute-bypassed"); refuse logic is
#     skipped.
#
#   DRG_RECEIPT_DIR — override the receipt directory
#     (default: ${HOME}/.claude/receipts)
#
# RELATED:
#   https://github.com/anthropics/claude-code/issues/61699
#   https://github.com/anthropics/claude-code/issues/61388
#   https://github.com/yurukusa/cc-safe-setup/issues/313
#   https://github.com/yurukusa/cc-safe-setup/pull/283   (dispatch-receipt sibling)
#   https://github.com/yurukusa/cc-safe-setup/pull/296   (commitment-carry-forward sibling)
# ================================================================

set -u

INPUT=$(cat)

# Stop hook receives the assistant's final text in stop_hook_active context.
# We look at the latest assistant message text from the transcript.
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# If no transcript path, try to read closeout text directly from input
# (test mode and some hook configurations supply it inline)
CLOSEOUT_TEXT=$(printf '%s' "$INPUT" | jq -r '.closeout_text // empty' 2>/dev/null)

if [ -z "$CLOSEOUT_TEXT" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
    # Read last assistant message from JSONL transcript
    CLOSEOUT_TEXT=$(tail -200 "$TRANSCRIPT_PATH" 2>/dev/null | \
        grep '"role":"assistant"' | tail -1 | \
        jq -r '.message.content[]? | select(.type=="text") | .text' 2>/dev/null | tr '\n' ' ')
fi

# No text to evaluate, exit silently
if [ -z "$CLOSEOUT_TEXT" ]; then
    exit 0
fi

# Phrase matching
PHRASE_LIST="${DRG_PHRASE_LIST:-deployed,deployment complete,shipped to production,rolled out}"
MATCHED_PHRASE=""
IFS=','
for phrase in $PHRASE_LIST; do
    # Trim whitespace
    phrase=$(printf '%s' "$phrase" | sed 's/^ *//;s/ *$//')
    if [ -z "$phrase" ]; then
        continue
    fi
    # Case-insensitive match
    if printf '%s' "$CLOSEOUT_TEXT" | grep -iqF "$phrase"; then
        MATCHED_PHRASE="$phrase"
        break
    fi
done
unset IFS

# No deployment phrase in closeout, exit silently
if [ -z "$MATCHED_PHRASE" ]; then
    exit 0
fi

# Adapter selection
ADAPTER="${DRG_ADAPTER:-}"
if [ -z "$ADAPTER" ]; then
    # Adapter not configured; in strict mode this would refuse, but the
    # default position is exit-silent to avoid friction on uninstrumented
    # projects. Operator must opt in via DRG_ADAPTER.
    exit 0
fi

# Resolve target via adapter
TARGET=""
CLAIMED_VERSION=""
QUERIED_VERSION=""
QUERY_FAILED=0

# Extract claimed version: simple heuristic — first sha-like or vN.N.N or vN string
# near the matched phrase. More sophisticated parsing in follow-up.
CLAIMED_VERSION=$(printf '%s' "$CLOSEOUT_TEXT" | grep -oE 'v[0-9]+(\.[0-9]+){0,2}|[0-9a-f]{7,40}' | head -1)

case "$ADAPTER" in
    gh)
        TARGET="${DRG_GH_REPO:-}"
        if [ -z "$TARGET" ]; then
            QUERY_FAILED=1
        else
            # Query latest deployment status
            QUERIED_VERSION=$(gh api "repos/${TARGET}/deployments?per_page=1" 2>/dev/null | \
                jq -r '.[0].sha // empty' 2>/dev/null)
            if [ -z "$QUERIED_VERSION" ]; then
                QUERY_FAILED=1
            fi
        fi
        ;;
    kubectl)
        NS="${DRG_KUBECTL_NAMESPACE:-}"
        DEPLOY="${DRG_KUBECTL_DEPLOYMENT:-}"
        if [ -z "$NS" ] || [ -z "$DEPLOY" ]; then
            QUERY_FAILED=1
        else
            TARGET="${NS}/${DEPLOY}"
            QUERIED_VERSION=$(kubectl get deployment "$DEPLOY" -n "$NS" \
                -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null)
            if [ -z "$QUERIED_VERSION" ]; then
                QUERY_FAILED=1
            fi
        fi
        ;;
    terraform)
        OUTPUT_NAME="${DRG_TERRAFORM_OUTPUT:-}"
        if [ -z "$OUTPUT_NAME" ]; then
            QUERY_FAILED=1
        else
            TARGET="terraform-output:${OUTPUT_NAME}"
            QUERIED_VERSION=$(terraform output -raw "$OUTPUT_NAME" 2>/dev/null)
            if [ -z "$QUERIED_VERSION" ]; then
                QUERY_FAILED=1
            fi
        fi
        ;;
    *)
        # Unknown adapter, exit silently with no receipt (configuration error)
        exit 0
        ;;
esac

# Compute decision
BYPASS="${DRG_BYPASS:-0}"
STRICT="${DRG_STRICT_MODE:-0}"
DECISION="execute"

if [ "$QUERY_FAILED" = "1" ]; then
    if [ "$STRICT" = "1" ]; then
        DECISION="refuse-query-failure"
    else
        # Non-strict mode: query failure exits silently with receipt for audit
        DECISION="execute"
    fi
elif [ -n "$CLAIMED_VERSION" ] && [ -n "$QUERIED_VERSION" ]; then
    # Both versions known: compare
    # Match is true if either contains the other (sha truncation, prefix match)
    if [ "$CLAIMED_VERSION" = "$QUERIED_VERSION" ]; then
        DECISION="execute"
    elif printf '%s' "$QUERIED_VERSION" | grep -qF "$CLAIMED_VERSION"; then
        DECISION="execute"
    elif printf '%s' "$CLAIMED_VERSION" | grep -qF "$QUERIED_VERSION"; then
        DECISION="execute"
    else
        DECISION="refuse-mismatch"
    fi
elif [ "$STRICT" = "1" ]; then
    # Strict mode and one of the versions is empty: refuse
    DECISION="refuse-mismatch"
fi

if [ "$BYPASS" = "1" ] && [ "$DECISION" != "execute" ]; then
    DECISION="execute-bypassed"
fi

# Write receipt
RECEIPT_DIR="${DRG_RECEIPT_DIR:-${HOME}/.claude/receipts}"
mkdir -p "$RECEIPT_DIR" 2>/dev/null
RECEIPT_FILE="${RECEIPT_DIR}/deployment-readback-$(date +%Y-%m-%d).jsonl"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ADAPTER_JSON=$(printf '%s' "$ADAPTER" | jq -Rs -c .)
TARGET_JSON=$(printf '%s' "$TARGET" | jq -Rs -c .)
CLAIMED_JSON=$(printf '%s' "$CLAIMED_VERSION" | jq -Rs -c .)
QUERIED_JSON=$(printf '%s' "$QUERIED_VERSION" | jq -Rs -c .)
PHRASE_JSON=$(printf '%s' "$MATCHED_PHRASE" | jq -Rs -c .)

printf '{"ts":"%s","adapter":%s,"target":%s,"matched_phrase":%s,"claimed_version":%s,"queried_version":%s,"decision":"%s"}\n' \
    "$TS" "$ADAPTER_JSON" "$TARGET_JSON" "$PHRASE_JSON" "$CLAIMED_JSON" "$QUERIED_JSON" "$DECISION" \
    >> "$RECEIPT_FILE" 2>/dev/null

if [ "$DECISION" = "refuse-mismatch" ]; then
    echo "BLOCKED: deployment-readback-gate — claimed version does not match queried version." >&2
    echo "" >&2
    echo "Matched phrase: \"$MATCHED_PHRASE\"" >&2
    echo "Adapter: $ADAPTER" >&2
    echo "Target: $TARGET" >&2
    echo "Claimed version (from closeout text): ${CLAIMED_VERSION:-<not parsed>}" >&2
    echo "Queried version (from $ADAPTER): ${QUERIED_VERSION:-<empty>}" >&2
    echo "Receipt: $RECEIPT_FILE" >&2
    echo "" >&2
    echo "Principle: deployment-completion claims must reconcile with the deployment system's authoritative state." >&2
    echo "  (https://github.com/anthropics/claude-code/issues/61699)" >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  1. Re-query the deployment system manually and confirm the actual state." >&2
    echo "  2. Re-issue with DRG_BYPASS=1 if the gate is a false positive (recorded in receipt)." >&2
    exit 2
fi

if [ "$DECISION" = "refuse-query-failure" ]; then
    echo "BLOCKED: deployment-readback-gate — deployment query failed (strict mode)." >&2
    echo "" >&2
    echo "Matched phrase: \"$MATCHED_PHRASE\"" >&2
    echo "Adapter: $ADAPTER" >&2
    echo "Receipt: $RECEIPT_FILE" >&2
    echo "" >&2
    echo "Possible causes:" >&2
    echo "  - Adapter configuration is incomplete (check DRG_${ADAPTER^^}_* variables)" >&2
    echo "  - Authentication failed (check gh auth status / kubectl config / terraform state)" >&2
    echo "  - Deployment target does not exist yet (no prior deployment to compare against)" >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  1. Fix the adapter configuration and re-issue." >&2
    echo "  2. Or unset DRG_STRICT_MODE to allow query failures (receipt-only)." >&2
    echo "  3. Or re-issue with DRG_BYPASS=1 (recorded in receipt)." >&2
    exit 2
fi

exit 0
