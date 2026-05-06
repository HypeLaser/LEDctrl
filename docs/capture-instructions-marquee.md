# Capture Instructions: Multi-Row Continuous Marquee

## Goal
Capture the exact bytes the Editor v3.99 sends when configured for continuous scrolling of multiple rows.

## Setup
1. Open Sigma Editor v3.99 via the app: **Tools > Open Editor v3.99** (or Shift+Cmd+E)
2. Create a message with these exact rows:
   ```
   ONE
   TWO
   THREE
   FOUR
   FIVE
   ```
3. Set the mode to **Move Left** for both In and Out effects
4. Set speed to **Medium Fast**
5. Set hold/pause to **2 seconds**
6. Ensure the message is **NOT** using "Auto Typeset" or word-wrap (this should be off for marquee)

## Capture Steps

### Option A: Using tcpdump (recommended)

```bash
# In Terminal, run this BEFORE clicking Send in the Editor:
cd /Users/alexscott/Projects/LEDctrl/analysis/captures
sudo tcpdump -i en0 -s 0 -w editor-marquee-continuous-$(date +%Y%m%d-%H%M%S).pcap 'host 192.168.11.6'

# Then click Send in the Editor
# Wait for the sign to finish displaying all rows
# Press Ctrl+C in Terminal to stop capture
```

### Option B: Using the app's built-in capture

The app can trigger a capture automatically if you add a debug button, but tcpdump is more reliable.

## What to Capture

I need to see:
1. **Is it one NMG file or multiple files?** (watch for multiple `sendFile` commands)
2. **The exact row separator bytes** between rows in the NMG text body
3. **The auto-typeset mode** ('a' or 'b')
4. **Whether init bytes `18 01 09` are present**
5. **The hold time format** (3 or 4 digits)

## After Capture

Please run:
```bash
cd /Users/alexscott/Projects/LEDctrl/analysis/captures
ls -lt *.pcap | head -5
```

And tell me the filename of the new capture. I'll decode it immediately.

## Current Hypothesis (to be verified)

For continuous Marquee scrolling, the Editor likely:
- Uses **'a' mode** (not 'b' mode) - 'a' mode treats text as one long line
- Concatenates all rows into a single long text string with spaces between them
- Uses **plain `0d` or spaces** as separators (NOT the `0d 18 03 0b 40` stop-start separator)
- Applies Move Left effects to the whole message, not per-row

This is fundamentally different from the "page through rows" behavior we've been implementing.
