// When the changes land as "Background from artwork" is turned off, and whether the side
// navigation's reset (BridgeScript's, hidden two frames and shown) puts it back when it runs once
// the page has been quiet for QUIET_MS. Run it twice:
//   1. Settings open, scrolled down, the wash showing:  inspect-memory.py eval scripts/probes/sidebar-timing.js
//   2. Turn "Background from artwork" off, wait 3 s, look at the sidebar, run it again for the log.
(() => {
  const QUIET_MS = 1000;
  const LOOK = ['data-art-wash', 'data-app-wash', 'data-art-glass', 'data-app-color', 'data-app-backdrop'];
  const html = document.documentElement;
  const last = window.__sidebarTiming;
  if (last) {
    window.__sidebarTiming = null;
    last.observer.disconnect();
    clearTimeout(last.timer);
    return { log: last.log, resets: last.resets };
  }
  const start = performance.now();
  const ms = () => Math.round(performance.now() - start);
  const state = { log: [], resets: [], timer: 0, observer: null };
  const aside = () => document.querySelector("[data-ui='sidebar']");
  const reset = () => {
    const el = aside();
    if (!el) return state.resets.push({ at: ms(), error: 'no sidebar' });
    state.resets.push({ at: ms(), scrollY: Math.round(scrollY) });
    el.style.setProperty('display', 'none', 'important');
    void html.offsetHeight;
    requestAnimationFrame(() => requestAnimationFrame(() => el.style.removeProperty('display')));
  };
  state.observer = new MutationObserver((records) => {
    let changed = false;
    for (const r of records) {
      if (r.type === 'attributes' && r.target === html) {
        const now = html.getAttribute(r.attributeName);
        if (now === r.oldValue) continue;
        state.log.push({ at: ms(), attr: r.attributeName, from: r.oldValue, to: now });
        changed = true;
      } else if (r.type === 'childList') {
        const name = (n) => (n.dataset && n.dataset.ui) || n.nodeName.toLowerCase();
        const added = [...r.addedNodes].filter((n) => n.nodeType === 1).map(name);
        const removed = [...r.removedNodes].filter((n) => n.nodeType === 1).map(name);
        if (!added.length && !removed.length) continue;
        state.log.push({ at: ms(), in: name(r.target), added, removed });
        changed = true;
      }
    }
    if (!changed || state.resets.length) return;
    clearTimeout(state.timer);
    state.timer = setTimeout(reset, QUIET_MS);
  });
  state.observer.observe(html, { attributes: true, attributeOldValue: true, attributeFilter: LOOK });
  const background = document.querySelector("[data-ui='page-background']");
  if (background) state.observer.observe(background, { childList: true, subtree: true });
  window.__sidebarTiming = state;
  return {
    armed: 'turn Background from artwork off, wait 3 s, look at the sidebar, then run this again',
    scrollY: Math.round(scrollY),
    attrs: LOOK.filter((n) => html.hasAttribute(n)),
  };
})()
