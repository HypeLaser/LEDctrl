#!/usr/bin/env bash
set -euo pipefail

# Extract NMG payload from a pcap capture
# Usage: ./extract-nmg-from-pcap.sh <capture.pcap>

PCAP_FILE="${1:-}"
if [[ -z "$PCAP_FILE" ]]; then
    echo "Usage: ./extract-nmg-from-pcap.sh <capture.pcap>"
    exit 1
fi

OUTPUT_DIR="/Users/alexscott/Projects/LEDctrl/analysis/captures"
BASE_NAME=$(basename "$PCAP_FILE" .pcap)

echo "========================================="
echo "Extracting NMG from: $PCAP_FILE"
echo "========================================="
echo ""

# Extract TCP payloads using tshark if available
if command -v tshark &> /dev/null; then
    echo "Using tshark to extract payloads..."
    
    # Extract all TCP payload data
    tshark -r "$PCAP_FILE" -T fields -e tcp.payload -Y "tcp.port == 9520" 2>/dev/null | \
        grep -v '^$' | \
        while read line; do
            echo "$line" | xxd -r -p
        done > "$OUTPUT_DIR/${BASE_NAME}_payload.raw" 2>/dev/null || true
    
    if [[ -s "$OUTPUT_DIR/${BASE_NAME}_payload.raw" ]]; then
        echo "Raw payload saved: $OUTPUT_DIR/${BASE_NAME}_payload.raw"
        echo "Size: $(stat -f%z "$OUTPUT_DIR/${BASE_NAME}_payload.raw") bytes"
        echo ""
        echo "First 128 bytes (hex):"
        xxd -l 128 "$OUTPUT_DIR/${BASE_NAME}_payload.raw"
        echo ""
        echo "ASCII strings found:"
        strings "$OUTPUT_DIR/${BASE_NAME}_payload.raw" | head -20
    else
        echo "No payload extracted. Trying tcpdump method..."
    fi
else
    echo "tshark not found. Using tcpdump method..."
fi

# Fallback: tcpdump hex dump
HEX_FILE="$OUTPUT_DIR/${BASE_NAME}_hex.txt"
tcpdump -r "$PCAP_FILE" -x -n 2>/dev/null | grep -E "^\s+0x[0-9a-f]+:" > "$HEX_FILE" || true

if [[ -s "$HEX_FILE" ]]; then
    echo ""
    echo "Hex dump saved: $HEX_FILE"
    echo ""
    echo "First 50 lines:"
    head -50 "$HEX_FILE"
fi

echo ""
echo "========================================="
echo "For manual analysis:"
echo "  wireshark '$PCAP_FILE'"
echo "  Filter: tcp.port == 9520"
echo "  Follow TCP Stream to see full conversation"
echo "========================================="
