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

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Detect financial API calls
# Exchange APIs
if echo "$CMD" | grep -qiE '(binance|bitget|bybit|kraken|coinbase|ftx|okx|kucoin|gate\.io|huobi).*\b(transfer|withdraw|swap|order|trade|margin|futures|spot|deposit)\b'; then
    echo "BLOCKED: Financial exchange operation detected." >&2
    echo "  Command: $(echo "$CMD" | head -c 200)" >&2
    echo "  Fund transfers require explicit user approval for EACH transaction." >&2
    exit 2
fi

# Generic payment/transfer patterns
if echo "$CMD" | grep -qiE '\b(transfer|withdraw|send|swap|bridge)\b.*\b(usdt|usdc|eth|btc|sol|bnb|funds|balance|wallet)\b'; then
    echo "BLOCKED: Cryptocurrency transfer operation detected." >&2
    echo "  Command: $(echo "$CMD" | head -c 200)" >&2
    echo "  Wallet/fund operations require explicit user approval." >&2
    exit 2
fi

# Payment processor APIs
if echo "$CMD" | grep -qiE 'stripe.*\b(charge|transfer|payout)\b|paypal.*\b(payment|send|transfer)\b|square.*\b(payment|charge)\b'; then
    echo "BLOCKED: Payment processor operation detected." >&2
    echo "  Command: $(echo "$CMD" | head -c 200)" >&2
    echo "  Payment operations require explicit user approval." >&2
    exit 2
fi

exit 0
