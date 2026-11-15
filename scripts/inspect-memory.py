#!/usr/bin/env python3
"""
Watch the AIOStreams page's memory on the Apple TV through Web Inspector, without a Mac.

Needs a running pymobiledevice3 tunnel (in another WSL terminal):

    sudo "$(which pymobiledevice3)" remote tunneld --protocol tcp

Then, with the app open on the TV:

    uv run --python 3.13 --with pymobiledevice3 scripts/inspect-memory.py watch

While it runs it prints WebKit's own memory split (JavaScript, images, layers, page, ...)
and the page's counts every few seconds, and writes every sample to memory-<time>.jsonl.
Type  s + Enter  to take a JavaScript heap snapshot (saved as heap-<time>.json and summarised),
      g + Enter  to force a garbage collection,
      q + Enter  to stop.

A saved snapshot can be summarised again later, on any machine with Python:

    python3 scripts/inspect-memory.py analyze heap-<time>.json

Taking a snapshot makes WebContent build the whole heap as one JSON string, so it briefly
needs a lot of extra memory. Take it on a quiet screen, not when the app is already near
its limit, or the snapshot itself can get the page killed.
"""

import argparse
import asyncio
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

PAGE_PROBE = r"""
(() => {
  let q = null;
  try { q = typeof window.__aioQueryStats === 'function' ? window.__aioQueryStats() : null; } catch (e) { q = String(e); }
  return {
    url: location.hash || location.pathname,
    nodes: document.getElementsByTagName('*').length,
    imgs: document.images.length,
    videos: document.getElementsByTagName('video').length,
    pages: document.querySelectorAll('[data-page]').length,
    anims: document.getAnimations ? document.getAnimations().length : -1,
    query: q,
  };
})()
"""

MB = 1024 * 1024


def stamp() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


def unwrap(response):
    """Commands sent through a target come back wrapped; return the inner protocol message."""
    if isinstance(response, dict) and "params" in response and "message" in response["params"]:
        return json.loads(response["params"]["message"])
    if isinstance(response, str):
        return json.loads(response)
    return response


# ---------------------------------------------------------------- snapshot summary


def analyze(snapshot: dict, top: int = 30) -> str:
    nodes = snapshot["nodes"]
    names = snapshot["nodeClassNames"]
    stride = 7 if snapshot.get("type") == "GCDebugging" else 4

    count = Counter()
    size = Counter()
    total = 0
    class_of = {}
    for i in range(0, len(nodes), stride):
        node_id, node_size, cls = nodes[i], nodes[i + 1], names[nodes[i + 2]]
        count[cls] += 1
        size[cls] += node_size
        total += node_size
        class_of[node_id] = cls

    lines = [
        f"JS heap: {total / MB:.1f} MB in {len(nodes) // stride:,} cells"
        " (own sizes; images, layers and DOM C++ memory are not in here)",
        "",
        f"{'class':<40} {'cells':>10} {'MB':>9}",
    ]
    for cls, s in size.most_common(top):
        lines.append(f"{cls[:40]:<40} {count[cls]:>10,} {s / MB:>9.2f}")

    # Which property names hold the most objects: shows which data shape fills the heap
    # (e.g. thousands of catalog items each carrying "description", "links", ...).
    edges = snapshot.get("edges", [])
    edge_types = snapshot.get("edgeTypes", [])
    edge_names = snapshot.get("edgeNames", [])
    prop = edge_types.index("Property") if "Property" in edge_types else -1
    by_name = Counter()
    strings_by_name = Counter()
    for i in range(0, len(edges), 4):
        if edges[i + 2] != prop:
            continue
        name = edge_names[edges[i + 3]]
        by_name[name] += 1
        if class_of.get(edges[i + 1]) == "string":
            strings_by_name[name] += 1
    if by_name:
        lines += ["", f"{'property name':<40} {'refs':>10} {'to strings':>11}"]
        for name, n in by_name.most_common(top):
            lines.append(f"{name[:40]:<40} {n:>10,} {strings_by_name[name]:>11,}")

    # Detached DOM wrappers: elements that JS still points at.
    elements = defaultdict(int)
    for i in range(0, len(nodes), stride):
        if nodes[i + 3] & 0b100:
            elements[names[nodes[i + 2]]] += 1
    if elements:
        lines += ["", "DOM element wrappers held by JS:"]
        for cls, n in sorted(elements.items(), key=lambda kv: -kv[1])[:top]:
            lines.append(f"  {cls:<38} {n:>10,}")
    return "\n".join(lines)


# ---------------------------------------------------------------- live watch


class Watch:
    def __init__(self, session, log_path: Path, every: float):
        self.session = session
        self.log = log_path.open("a", encoding="utf-8")
        self.every = every
        self.memory = None  # latest Memory.trackingUpdate categories
        self.peak = 0
        self.busy = False

    def write(self, kind: str, data) -> None:
        self.log.write(json.dumps({"t": time.time(), "kind": kind, "data": data}) + "\n")
        self.log.flush()

    def on_tracking(self, message) -> None:
        event = message["params"]["event"]
        cats = {c["type"]: c["size"] for c in event.get("categories", [])}
        self.memory = cats
        self.peak = max(self.peak, sum(cats.values()))
        self.write("memory", cats)

    def on_pressure(self, message) -> None:
        print(f"\n!! memory pressure: {message['params']}")
        self.write("pressure", message["params"])

    async def command(self, method: str, **params):
        message = unwrap(await self.session.send_command(method, **params))
        if isinstance(message, dict) and "error" in message:
            raise RuntimeError(f"{method}: {message['error'].get('message', message['error'])}")
        return message.get("result", {}) if isinstance(message, dict) else message

    async def start(self) -> bool:
        handlers = self.session.response_methods
        handlers["Memory.trackingUpdate"] = self.on_tracking
        handlers["Memory.memoryPressure"] = self.on_pressure
        handlers["Memory.trackingStart"] = lambda _: None
        handlers["Memory.trackingComplete"] = lambda _: None
        try:
            await self.command("Memory.enable")
            await self.command("Memory.startTracking")
            return True
        except Exception as e:  # tvOS builds may leave the Memory domain out
            print(f"WebKit memory tracking unavailable ({e}); showing page counts only.")
            return False

    async def sample_loop(self) -> None:
        while True:
            if not self.busy:
                try:
                    page = await self.session.runtime_evaluate(PAGE_PROBE, return_by_value=True)
                except Exception as e:
                    page = {"error": str(e)}
                self.write("page", page)
                print(self.line(page))
            await asyncio.sleep(self.every)

    def line(self, page) -> str:
        parts = [time.strftime("%H:%M:%S")]
        if self.memory:
            total = sum(self.memory.values())
            split = " ".join(f"{k} {v / MB:.0f}" for k, v in sorted(self.memory.items(), key=lambda kv: -kv[1]))
            parts.append(f"total {total / MB:.0f} MB (peak {self.peak / MB:.0f}) | {split}")
        if isinstance(page, dict) and "error" not in page:
            q = page.get("query")
            qs = ""
            if isinstance(q, dict):
                qs = f" | queries {q.get('queries')} pages {q.get('pages')} items {q.get('items', '-')}"
            parts.append(
                f"| {page.get('url')} nodes {page.get('nodes')} imgs {page.get('imgs')}"
                f" data-page {page.get('pages')} anims {page.get('anims')}{qs}"
            )
        else:
            parts.append(f"| page probe failed: {page}")
        return " ".join(parts)

    async def snapshot(self) -> None:
        self.busy = True
        try:
            print("Collecting garbage, then taking heap snapshot (can take a while)...")
            await self.session.heap_gc()
            data = await self.session.heap_snapshot()
            path = Path(f"heap-{stamp()}.json")
            path.write_text(data, encoding="utf-8")
            print(f"Saved {path} ({len(data) / MB:.1f} MB)\n")
            print(analyze(json.loads(data)))
            print()
        except Exception as e:
            print(f"Snapshot failed: {e}")
        finally:
            self.busy = False

    async def input_loop(self) -> None:
        while True:
            key = (await asyncio.to_thread(sys.stdin.readline)).strip().lower()
            if key == "q":
                return
            if key == "s":
                await self.snapshot()
            elif key == "g":
                await self.session.heap_gc()
                print("Garbage collected.")


async def pick_page(inspector, match: str):
    pages = await inspector.get_open_application_pages(timeout=3)
    for ap in pages:
        if match.lower() in str(ap).lower():
            return ap
    if pages:
        print("Pages found: " + ", ".join(str(p) for p in pages))
    return None


async def watch(args) -> None:
    from pymobiledevice3.services.webinspector import WebinspectorService
    from pymobiledevice3.tunneld.api import get_tunneld_devices

    rsds = await get_tunneld_devices()
    if not rsds:
        sys.exit("No device from tunneld. Is `pymobiledevice3 remote tunneld --protocol tcp` running?")
    rsd = rsds[0]

    inspector = WebinspectorService(lockdown=rsd)
    try:
        await inspector.connect()
        async with inspector:
            ap = await pick_page(inspector, args.match)
            if ap is None:
                sys.exit(f"No open page matching {args.match!r}. Open the app on the TV first.")
            print(f"Attached to {ap}")
            session = await inspector.inspector_session(ap.application, ap.page)
            await session.runtime_enable()
            await session.heap_enable()

            log_path = Path(f"memory-{stamp()}.jsonl")
            w = Watch(session, log_path, args.every)
            await w.start()
            print(f"Logging to {log_path}. s+Enter = heap snapshot, g+Enter = GC, q+Enter = quit.\n")

            sampler = asyncio.create_task(w.sample_loop())
            try:
                await w.input_loop()
            finally:
                sampler.cancel()
                try:
                    await w.command("Memory.stopTracking")
                except Exception:
                    pass
    finally:
        await inspector.close()
        await rsd.close()


# ---------------------------------------------------------------- composited layers

DESCRIBE_NODE = r"""function () {
  const el = this.nodeType === 1 ? this : this.parentElement;
  if (!el) return String(this.nodeName);
  let s = el.tagName.toLowerCase();
  if (el.id) s += '#' + el.id;
  const cls = typeof el.className === 'string' ? el.className.trim().split(/\s+/).slice(0, 4).join('.') : '';
  if (cls) s += '.' + cls;
  for (const a of ['data-page', 'data-tv-layer', 'data-row', 'aria-label']) {
    if (el.hasAttribute && el.hasAttribute(a)) s += `[${a}=${(el.getAttribute(a) || '').slice(0, 30)}]`;
  }
  const r = el.getBoundingClientRect();
  return `${s} ${Math.round(r.width)}x${Math.round(r.height)}`;
}"""


class Layers:
    """Polls LayerTree.layersForNode on the whole document and reports the layers' backing-store
    memory. On every new peak it lists the biggest layers, what element owns them and why WebKit
    composited them."""

    def __init__(self, session, every: float, top: int, step_mb: int):
        self.session = session
        self.every = every
        self.top = top
        self.step = step_mb * MB
        self.root = None
        self.peak = 0
        self.last_total = -1

    async def command(self, method: str, timeout: float = 10.0, **params):
        try:
            raw = await asyncio.wait_for(self.session.send_command(method, **params), timeout)
        except asyncio.TimeoutError:
            raise RuntimeError(f"{method}: no answer from the TV in {timeout:.0f} s") from None
        message = unwrap(raw)
        if isinstance(message, dict) and "error" in message:
            raise RuntimeError(f"{method}: {message['error'].get('message', message['error'])}")
        return message.get("result", {}) if isinstance(message, dict) else message

    async def document(self) -> int:
        doc = await self.command("DOM.getDocument")
        return doc["root"]["nodeId"]

    async def describe(self, node_id) -> str:
        try:
            obj = (await self.command("DOM.resolveNode", nodeId=node_id))["object"]
            res = await self.command(
                "Runtime.callFunctionOn", objectId=obj["objectId"], functionDeclaration=DESCRIBE_NODE, returnByValue=True
            )
            await self.command("Runtime.releaseObject", objectId=obj["objectId"])
            return res["result"].get("value", "?")
        except Exception as e:
            return f"node {node_id} ({e.__class__.__name__})"

    async def reasons(self, layer_id) -> str:
        try:
            r = (await self.command("LayerTree.reasonsForCompositingLayer", layerId=layer_id))["compositingReasons"]
            return ",".join(k for k, v in r.items() if v)
        except Exception:
            return ""

    async def poll(self) -> None:
        if self.root is None:
            self.root = await self.document()
        try:
            layers = (await self.command("LayerTree.layersForNode", nodeId=self.root))["layers"]
        except RuntimeError:
            self.root = await self.document()  # the document node went stale
            layers = (await self.command("LayerTree.layersForNode", nodeId=self.root))["layers"]
        total = sum(l.get("memory", 0) for l in layers)
        if self.last_total < 0 or abs(total - self.last_total) >= self.step:
            print(f"{time.strftime('%H:%M:%S')} layers {len(layers):4} memory {total / MB:7.1f} MB (peak {max(self.peak, total) / MB:.0f})", flush=True)
            self.last_total = total
        if total > self.peak + self.step:
            self.peak = total
            await self.dump(layers, total)

    async def dump(self, layers, total) -> None:
        print(f"  -- new peak {total / MB:.0f} MB in {len(layers)} layers; biggest:", flush=True)
        for l in sorted(layers, key=lambda l: -l.get("memory", 0))[: self.top]:
            mem = l.get("memory", 0)
            if mem < MB:
                break
            b = l.get("bounds", {})
            who = await self.describe(l["nodeId"]) if "nodeId" in l else "(no node)"
            if l.get("pseudoElement"):
                who += f" ::{l['pseudoElement']}"
            why = await self.reasons(l["layerId"])
            print(
                f"  {mem / MB:6.1f} MB  {int(b.get('width', 0))}x{int(b.get('height', 0))}  paints {l.get('paintCount', 0):<4} {who}  [{why}]",
                flush=True,
            )

    async def loop(self) -> None:
        while True:
            try:
                await self.poll()
            except Exception as e:
                print(f"{time.strftime('%H:%M:%S')} layer poll failed: {e}", flush=True)
                self.root = None
                await asyncio.sleep(1)
            await asyncio.sleep(self.every)


async def layers(args) -> None:
    from pymobiledevice3.services.webinspector import WebinspectorService
    from pymobiledevice3.tunneld.api import get_tunneld_devices

    rsds = await get_tunneld_devices()
    if not rsds:
        sys.exit("No device from tunneld. Is `pymobiledevice3 remote tunneld --protocol tcp` running?")
    rsd = rsds[0]

    inspector = WebinspectorService(lockdown=rsd)
    try:
        await inspector.connect()
        async with inspector:
            ap = await pick_page(inspector, args.match)
            if ap is None:
                sys.exit(f"No open page matching {args.match!r}. Open the app on the TV first.")
            print(f"Attached to {ap}")
            try:
                session = await asyncio.wait_for(inspector.inspector_session(ap.application, ap.page), 15)
            except asyncio.TimeoutError:
                sys.exit(
                    "The page didn't open an inspector session in 15 s. Close any other inspector on it "
                    "(js-shell, another run of this script), then try again."
                )
            print("Inspector session open", flush=True)
            # LayerTree and DOM push events (layerTreeDidChange, setChildNodes, ...) this script
            # doesn't need; drop them instead of logging each as unhandled.
            session._missing_id_in_message = lambda message: None
            lt = Layers(session, args.every, args.top, args.step)
            for step in ("Runtime.enable", "DOM.getDocument", "LayerTree.enable"):
                print(f"  {step} ...", flush=True)
                try:
                    await lt.command(step)
                except RuntimeError as e:
                    sys.exit(f"Stopped: {e}")
            if args.css:
                # A test style, in the page only while this runs (and until the page reloads).
                await session.runtime_evaluate(
                    "(() => { let s = document.getElementById('aio-test-css');"
                    " if (!s) { s = document.createElement('style'); s.id = 'aio-test-css'; document.head.appendChild(s); }"
                    f" s.textContent = {json.dumps(args.css)}; return true; }})()",
                    return_by_value=True,
                )
                print(f"Test CSS added: {args.css}", flush=True)
            print("Polling layers; Ctrl+C to stop.\n", flush=True)
            try:
                await lt.loop()
            finally:
                if args.css:
                    try:
                        await asyncio.wait_for(
                            session.runtime_evaluate(
                                "document.getElementById('aio-test-css')?.remove(), true", return_by_value=True
                            ),
                            5,
                        )
                        print("Test CSS removed.", flush=True)
                    except BaseException:
                        print("Couldn't remove the test CSS; reopen the app to clear it.", flush=True)
    finally:
        await inspector.close()
        await rsd.close()


async def evaluate(args) -> None:
    """Runs a JavaScript file in the page and prints what it returns, as JSON."""
    from pymobiledevice3.services.webinspector import WebinspectorService
    from pymobiledevice3.tunneld.api import get_tunneld_devices

    script = Path(args.file).read_text(encoding="utf-8")
    rsds = await get_tunneld_devices()
    if not rsds:
        sys.exit("No device from tunneld. Is `pymobiledevice3 remote tunneld --protocol tcp` running?")
    rsd = rsds[0]
    inspector = WebinspectorService(lockdown=rsd)
    try:
        await inspector.connect()
        async with inspector:
            ap = await pick_page(inspector, args.match)
            if ap is None:
                sys.exit(f"No open page matching {args.match!r}. Open the app on the TV first.")
            try:
                session = await asyncio.wait_for(inspector.inspector_session(ap.application, ap.page), 15)
            except asyncio.TimeoutError:
                sys.exit("The page didn't open an inspector session in 15 s. Close any other inspector on it, then try again.")
            session._missing_id_in_message = lambda message: None
            await session.runtime_enable()
            body = script.strip().rstrip(';')
            if args.wait:
                # Awaited, so a probe may be async (one that asks the server). Not every WebKit answers
                # an awaited evaluate, so only on asking.
                expression = f"Promise.resolve({body}).then((v) => JSON.stringify(v))"
                raw = await asyncio.wait_for(
                    session.send_command(
                        "Runtime.evaluate", expression=expression, returnByValue=True, awaitPromise=True
                    ),
                    30,
                )
                message = unwrap(raw)
                outcome = message.get("result", {}) if isinstance(message, dict) else {}
                if outcome.get("wasThrown") or "exceptionDetails" in outcome:
                    sys.exit(f"The probe threw: {outcome.get('result', {}).get('description', outcome)}")
                result = outcome.get("result", {}).get("value")
            else:
                # Returned as a JSON string, so the whole value comes back however deep it is.
                result = await asyncio.wait_for(
                    session.runtime_evaluate(f"JSON.stringify({body})", return_by_value=True), 20
                )
            if result is None or result == "":
                sys.exit(f"The page returned nothing for the probe (raw answer: {result!r}).")
            try:
                print(json.dumps(json.loads(result), indent=2))
            except (TypeError, ValueError):
                print(result)
    finally:
        await inspector.close()
        await rsd.close()


def main() -> None:
    # Print each line at once, also through `| tee` (otherwise Ctrl+C loses what was buffered).
    sys.stdout.reconfigure(line_buffering=True)
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("watch", help="live memory log; s/g/q commands")
    w.add_argument("--every", type=float, default=3.0, help="seconds between page samples (default 3)")
    w.add_argument("--match", default="aiostv", help="text to find the page by (default: aiostv)")
    a = sub.add_parser("analyze", help="summarise a saved heap snapshot")
    a.add_argument("file")
    a.add_argument("--top", type=int, default=30)
    l = sub.add_parser("layers", help="composited layer memory, with the biggest layers at each new peak")
    l.add_argument("--every", type=float, default=0.2, help="seconds between polls (default 0.2)")
    l.add_argument("--top", type=int, default=12, help="layers to list at a new peak (default 12)")
    l.add_argument("--step", type=int, default=10, help="MB change that prints a line (default 10)")
    l.add_argument("--match", default="aiostv", help="text to find the page by (default: aiostv)")
    l.add_argument("--css", default="", help="test CSS to add to the page while this runs")
    e = sub.add_parser("eval", help="run a JavaScript file in the page and print what it returns")
    e.add_argument("file")
    e.add_argument("--match", default="aiostv", help="text to find the page by (default: aiostv)")
    e.add_argument("--wait", action="store_true", help="await a probe that returns a promise")
    args = parser.parse_args()
    if args.cmd == "eval":
        asyncio.run(evaluate(args))
        return

    if args.cmd == "analyze":
        print(analyze(json.loads(Path(args.file).read_text(encoding="utf-8")), args.top))
    elif args.cmd == "layers":
        try:
            asyncio.run(layers(args))
        except KeyboardInterrupt:
            pass
    else:
        asyncio.run(watch(args))


if __name__ == "__main__":
    main()
