#!/usr/bin/env python3
"""
Turn one `pymobiledevice3 developer dvt sysmon process single` JSON dump (on stdin) into one line:
the time and the memory footprint (MB, what jetsam judges) of the processes that matter here.

    pymobiledevice3 developer dvt sysmon process single --tunnel "" 2>/dev/null | python3 scripts/sysmon-line.py
"""

import json
import sys
import time

MB = 1024 * 1024
WANT = {
    "com.apple.WebKit.WebContent": "WebContent",
    "AIOStreams": "app",
    "backboardd": "backboardd",
    "mediaplaybackd": "mediaplaybackd",
    "videocodecd": "videocodecd",
    "com.apple.WebKit.GPU": "WebKitGPU",
    "com.apple.WebKit.Networking": "WebKitNet",
}

try:
    procs = json.load(sys.stdin)
except Exception as e:
    print(time.strftime("%H:%M:%S"), f"no data ({e.__class__.__name__})", flush=True)
    sys.exit(0)

parts = []
total = 0
for p in procs:
    foot = p.get("physFootprint") or 0
    total += foot
    label = WANT.get(p.get("name", ""))
    if label:
        parts.append(f"{label}={foot // MB}")
print(time.strftime("%H:%M:%S"), f"all={total // MB}", " ".join(sorted(parts)), flush=True)
