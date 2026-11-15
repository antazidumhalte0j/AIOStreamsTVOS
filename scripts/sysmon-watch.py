#!/usr/bin/env python3
"""
Stream the memory footprint (what jetsam judges) of the processes behind AIOStreams on the Apple TV,
about once a second, without a Mac.

Needs the pymobiledevice3 tunnel running in another WSL terminal:

    sudo "$(which pymobiledevice3)" remote tunneld --protocol tcp

Then:

    uv run --python 3.13 --with pymobiledevice3 scripts/sysmon-watch.py | tee sysmon-timeline.txt

Each line: time, the sum over all processes, then MB per watched process, with the session peak of
WebContent. A line is printed when a value moves by 5 MB or more, and at least every 10 s.
If the TV drops the connection it says so and reconnects. Ctrl+C stops it.
"""

import argparse
import asyncio
import sys
import time

MB = 1024 * 1024
WATCH = {
    "com.apple.WebKit.WebContent": "WebContent",
    "AIOStreams": "app",
    "backboardd": "backboardd",
    "mediaplaybackd": "mediaplaybackd",
    "videocodecd": "videocodecd",
    "com.apple.WebKit.GPU": "WebKitGPU",
}
ORDER = list(WATCH.values())


class Printer:
    def __init__(self, step_mb: int, every_s: float):
        self.step = step_mb
        self.every = every_s
        self.last: dict[str, int] = {}
        self.last_print = 0.0
        self.peak = 0

    def sample(self, procs) -> None:
        if not procs:
            return
        total = 0
        vals: dict[str, int] = {}
        for p in procs:
            foot = p.get("physFootprint") or 0
            total += foot
            label = WATCH.get(p.get("name") or "")
            if label:
                # several WebContent processes can exist; keep the biggest
                vals[label] = max(vals.get(label, 0), foot // MB)
        vals["all"] = total // MB
        self.peak = max(self.peak, vals.get("WebContent", 0))

        moved = any(abs(vals.get(k, 0) - self.last.get(k, 0)) >= self.step for k in vals.keys() | self.last.keys())
        now = time.monotonic()
        if moved or now - self.last_print >= self.every:
            cells = [f"all={vals['all']}"] + [f"{k}={vals[k]}" for k in ORDER if k in vals]
            print(time.strftime("%H:%M:%S"), " ".join(cells), f"(WebContent peak {self.peak})", flush=True)
            self.last = vals
            self.last_print = now


async def stream(rsd, interval_ms: int, printer: Printer) -> None:
    from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
    from pymobiledevice3.services.dvt.instruments.sysmontap import Sysmontap

    async with DvtProvider(rsd) as dvt:
        # The full attribute set, as `sysmon process single` asks for; the TV closes the channel
        # when asked for a subset. (single is slow only because it looks up every process's path.)
        async with await Sysmontap.create(dvt, interval=interval_ms) as tap:
            async for procs in tap.iter_processes():
                printer.sample(procs)


async def run(interval_ms: int, step_mb: int, every_s: float) -> None:
    from pymobiledevice3.tunneld.api import get_tunneld_devices

    printer = Printer(step_mb, every_s)
    print(f"# every {interval_ms} ms; MB footprint; Ctrl+C to stop", flush=True)
    while True:
        rsds = await get_tunneld_devices()
        if not rsds:
            sys.exit("No device from tunneld. Is `pymobiledevice3 remote tunneld --protocol tcp` running?")
        rsd = rsds[0]
        try:
            await stream(rsd, interval_ms, printer)
            reason = "stream ended"
        except asyncio.CancelledError:
            raise
        except Exception as e:  # the TV dropped the channel
            reason = f"{e.__class__.__name__}: {e}"
        finally:
            try:
                await rsd.close()
            except Exception:
                pass
        print(time.strftime("%H:%M:%S"), f"# connection lost ({reason}); reconnecting", flush=True)
        await asyncio.sleep(2)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--interval", type=int, default=1000, help="sample interval in ms (default 1000)")
    ap.add_argument("--step", type=int, default=5, help="print when a value moves this many MB (default 5)")
    ap.add_argument("--every", type=float, default=10.0, help="print at least this often, seconds (default 10)")
    a = ap.parse_args()
    try:
        asyncio.run(run(a.interval, a.step, a.every))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
