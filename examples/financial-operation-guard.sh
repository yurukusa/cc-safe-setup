#!/bin/bash
# financial-operation-guard.sh — Block unauthorized financial operations
#
# Solves: Claude Code transferred $1,446 from spot to futures without
# authorization when told to "close a position". Financial APIs
# should never be called without explicit per-transaction approval. (#46828)
#
# How it works: Detects commands that interact with exchange APIs,
# wallet transfers, payment processors, or any operation involving
# fund movement. Blocks with exit 2 and requires explicit user
# confirmation.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-financial-operation-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [financial-operation-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Detect financial API calls
# Exchange APIs
if echo "$CMD" | grep -qiE '(binance|bitget|bybit|kraken|coinbase|ftx|okx|kucoin|gate\.io|huobi).*(transfer|withdraw|swap|order|trade|margin|futures|spot|deposit)'; then
    echo "BLOCKED: Financial exchange operation detected." >&2
    echo "  Command: $(echo "$CMD" | head -c 200)" >&2
    echo "  Fund transfers require explicit user approval for EACH transaction." >&2
    exit 2
fi

# Generic payment/transfer patterns
if echo "$CMD" | grep -qiE '(transfer|withdraw|send|swap|bridge)[^a-z].*\b(usdt|usdc|eth|btc|sol|bnb|funds|balance|wallet)\b'; then
    echo "BLOCKED: Cryptocurrency transfer operation detected." >&2
    echo "  Command: $(echo "$CMD" | head -c 200)" >&2
    echo "  Wallet/fund operations require explicit user approval." >&2
    exit 2
fi

# Payment processor APIs
if echo "$CMD" | grep -qiE 'stripe.*(charges?|transfers?|payouts?)|paypal.*(payments?|send|transfers?)|square.*(payments?|charges?)'; then
    echo "BLOCKED: Payment processor operation detected." >&2
    echo "  Command: $(echo "$CMD" | head -c 200)" >&2
    echo "  Payment operations require explicit user approval." >&2
    exit 2
fi

exit 0
