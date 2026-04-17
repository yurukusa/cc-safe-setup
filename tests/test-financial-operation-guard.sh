#!/bin/bash
# Tests for financial-operation-guard.sh
# Run: bash tests/test-financial-operation-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/financial-operation-guard.sh"

test_hook() {
    local input="$1" expected_exit="$2" desc="$3"
    local actual_exit=0
    echo "$input" | bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "financial-operation-guard.sh tests"
echo ""

# --- Block: Exchange API calls (#46828 pattern) ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"ex.transfer(USDT, 1446.65, spot, swap)\" bitget"}}' 2 "Block Bitget fund transfer (#46828 exact pattern)"
test_hook '{"tool_name":"Bash","tool_input":{"command":"curl https://api.binance.com/api/v3/order -X POST"}}' 2 "Block Binance order API"
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 trade.py --exchange bybit --withdraw 500"}}' 2 "Block Bybit withdrawal"
test_hook '{"tool_name":"Bash","tool_input":{"command":"ccxt kraken transfer USDT from spot to futures"}}' 2 "Block Kraken transfer via ccxt"
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"coinbase.create_order(symbol, side, amount)\""}}' 2 "Block Coinbase order"
test_hook '{"tool_name":"Bash","tool_input":{"command":"curl -X POST https://api.okx.com/api/v5/trade/order"}}' 2 "Block OKX trade order"

# --- Block: Generic crypto transfers ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"transfer(USDT, 1000, wallet_a, wallet_b)\""}}' 2 "Block USDT transfer"
test_hook '{"tool_name":"Bash","tool_input":{"command":"send_eth --to 0xabc --amount 5 --wallet main"}}' 2 "Block ETH send"
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 withdraw_btc.py --balance 0.5"}}' 2 "Block BTC withdrawal"
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"swap(usdc, 500, from_wallet)\""}}' 2 "Block USDC swap"
test_hook '{"tool_name":"Bash","tool_input":{"command":"bridge sol from mainnet to polygon --funds 100"}}' 2 "Block SOL bridge"

# --- Block: Payment processor operations ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"curl -X POST https://api.stripe.com/v1/charges -d amount=5000"}}' 2 "Block Stripe charge"
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"stripe.Transfer.create(amount=1000)\""}}' 2 "Block Stripe transfer"
test_hook '{"tool_name":"Bash","tool_input":{"command":"paypal-cli send payment --to user@email.com --amount 200"}}' 2 "Block PayPal payment"
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"square.payments.create_payment(body)\""}}' 2 "Block Square payment"

# --- Allow: Safe operations ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"curl https://api.example.com/data"}}' 0 "Allow normal API call"
test_hook '{"tool_name":"Bash","tool_input":{"command":"python3 analyze_trades.py --read-only"}}' 0 "Allow read-only trade analysis"
test_hook '{"tool_name":"Bash","tool_input":{"command":"cat balance.txt"}}' 0 "Allow reading balance file"
test_hook '{"tool_name":"Bash","tool_input":{"command":"echo transfer complete"}}' 0 "Allow echo containing transfer"
test_hook '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' 0 "Allow git push"
test_hook '{"tool_name":"Bash","tool_input":{"command":"npm install stripe"}}' 0 "Allow npm install stripe (not an operation)"
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_name":"Bash","tool_input":{}}' 0 "Allow no command"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
