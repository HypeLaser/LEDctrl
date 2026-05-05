#!/usr/bin/env bash
set -euo pipefail

# Capture Sigma Editor network traffic for analysis
# This captures the raw TCP bytes sent to the sign for reverse-engineering

SIGN_IP="${1:-192.168.11.6}"
SIGN_PORT="9520"
CAPTURE_DIR="/Users/alexscott/Projects/LEDctrl/analysis/captures"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PCAP_FILE="$CAPTURE_DIR/vendor_capture_$TIMESTAMP.pcap"

echo "========================================="
echo "Sigma Editor Network Capture"
echo "========================================="
echo ""
echo "Target sign: $SIGN_IP:$SIGN_PORT"
echo ""
echo "CAPTURE SCENARIOS:"
echo ""
echo "1) MIXED FONT SIZES"
echo "   - Open Sigma Editor 3.99"
echo "   - Create message with DIFFERENT font sizes in one message"
echo "   - Example: 'HELLO' in 5-high, 'WORLD' in 7-high"
echo "   - Send to sign"
echo ""
echo "2) INSERT COUNTER / SPECIAL TIME"
echo "   - Create a message with 'Insert Counter' or 'Insert Special Time'"
echo "   - These show countdown timers on the sign"
echo "   - Send to sign"
echo ""
echo "3) BOTH TOGETHER"
echo "   - Create a message with mixed fonts AND a counter"
echo "   - Send to sign"
echo ""
echo "Press Enter when ready to start capture..."
read -r

mkdir -p "$CAPTURE_DIR"

echo "Starting tcpdump (run 'sudo' if this fails)..."
sudo tcpdump -i any -w "$PCAP_FILE" host $SIGN_IP and port $SIGN_PORT 2>/dev/null &
TCPDUMP_PID=$!

echo ""
echo "Capture started (PID: $TCPDUMP_PID)"
echo "Output: $PCAP_FILE"
echo ""
echo "NOW: Go to Sigma Editor, create your message, and send it."
echo ""
echo "Press Enter when you have SENT the message to stop capture..."
read -r

sudo kill -INT $TCPDUMP_PID 2>/dev/null || true
wait $TCPDUMP_PID 2>/dev/null || true

echo ""
echo "========================================="
echo "Capture saved to: $PCAP_FILE"
echo ""
echo "NEXT STEPS:"
echo "1. Open in Wireshark: wireshark '$PCAP_FILE'"
echo "2. Filter: tcp.port == 9520"
echo "3. Right-click a packet → Follow → TCP Stream"
echo "4. Save the raw bytes for analysis"
echo ""
echo "Or run: ./scripts/extract-nmg-from-pcap.sh '$PCAP_FILE'"
echo "========================================="
