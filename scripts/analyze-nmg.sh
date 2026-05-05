#!/usr/bin/env bash
set -euo pipefail

# Analyze a captured vendor Nmg file or hex dump
# Usage: ./analyze-nmg.sh <file.nmg or file.hex>

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
    echo "Usage: ./analyze-nmg.sh <file.nmg or file.hex>"
    exit 1
fi

echo "========================================="
echo "Nmg File Analysis"
echo "========================================="
echo "File: $FILE"
echo ""

# Determine file type
if [[ "$FILE" == *.hex ]]; then
    # Convert hex dump back to binary for analysis
    echo "Hex dump detected — parsing..."
    # Simple hex parser: extract hex bytes and show structure
    grep -oE '[0-9a-fA-F]{2}' "$FILE" | head -300 | xargs -n16 printf '%s ' | sed 's/ $//' | while read line; do
        echo "$line"
    done
    echo ""
    echo "Total bytes in hex dump:"
    grep -oE '[0-9a-fA-F]{2}' "$FILE" | wc -l
else
    # Binary Nmg file
    echo "Binary Nmg file detected"
    echo "Size: $(stat -f%z "$FILE") bytes"
    echo ""
    echo "First 256 bytes (hex):"
    xxd -l 256 "$FILE"
    echo ""
    echo "Control characters (0x01-0x1F):"
    xxd "$FILE" | grep -E "0[0-9a-f]|1[0-9a-f]" | head -20
    echo ""
    echo "ASCII text strings:"
    strings "$FILE" | head -20
fi

echo ""
echo "========================================="
echo "Key things to look for in mixed-font Nmg:"
echo "1. Multiple font selector bytes (0x1F ...)"
echo "2. Multiple size code bytes (0x1A ...)"
echo "3. Inline font-change control codes"
echo "4. Different from our single-font 0x1F + 0x1A pattern"
echo "========================================="
