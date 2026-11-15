// Whether the app's own reset of the side navigation (BridgeScript: hidden for two frames once the
// page holds still after "Background from artwork" or Glass changes) runs, and when, and whether
// the page's height changes meanwhile. Does nothing itself. Run it twice:
//   1. Settings open, scrolled down (NOT to the bottom first), the wash showing:
//        inspect-memory.py eval scripts/probes/sidebar-watch.js
//   2. Turn "Background from artwork" off, wait 3 s, look at the sidebar, run it again for the log.
(() => {
  const LOOK = ['data-art-wash', 'data-app-wash', 'data-art-glass'];
  const html = document.documentElement;
  const page = () => ({
    scrollY: Math.round(scrollY),
    height: html.scrollHeight,
    maxScroll: html.scrollHeight - innerHeight,
  });
  const last = window.__sidebarWatch;
  if (last) {
    window.__sidebarWatch = null;
    last.observer.disconnect();
    last.sizes.disconnect();
    removeEventListener('scroll', last.onScroll, true);
    return {
      // What the app's reset did; missing means the app has no such reset (an older build).
      appReset: window.__aioNavRedraws ? { ...window.__aioNavRedraws } : 'missing: this build has no reset',
      // Replaced, the sidebar's changes since were never seen here.
      sameSidebar: document.querySelector("[data-ui='sidebar']") === last.aside,
      armedWith: last.armedWith,
      log: last.log,
      now: page(),
    };
  }
  const aside = document.querySelector("[data-ui='sidebar']");
  if (!aside) return { error: 'no sidebar on this page' };
  const start = performance.now();
  const ms = () => Math.round(performance.now() - start);
  const state = { log: [], armedWith: page(), aside, observer: null, sizes: null, onScroll: null };
  state.observer = new MutationObserver((records) => {
    for (const r of records) {
      const now = r.target.getAttribute(r.attributeName);
      if (now === r.oldValue) continue;
      state.log.push({
        at: ms(),
        on: r.target === html ? 'html' : 'sidebar',
        attr: r.attributeName,
        from: r.oldValue,
        to: now,
        ...page(),
      });
    }
  });
  state.observer.observe(html, { attributes: true, attributeOldValue: true, attributeFilter: LOOK });
  state.observer.observe(aside, { attributes: true, attributeOldValue: true, attributeFilter: ['style', 'class'] });
  // The page's height as it changes.
  let height = html.scrollHeight;
  state.sizes = new ResizeObserver(() => {
    if (html.scrollHeight === height) return;
    state.log.push({ at: ms(), on: 'page', heightFrom: height, ...page() });
    height = html.scrollHeight;
  });
  state.sizes.observe(document.body);
  // Scrolls, at most one entry each 100 ms.
  let lastScrollLog = -1000;
  state.onScroll = () => {
    if (ms() - lastScrollLog < 100) return;
    lastScrollLog = ms();
    state.log.push({ at: lastScrollLog, on: 'scroll', ...page() });
  };
  addEventListener('scroll', state.onScroll, { capture: true, passive: true });
  window.__sidebarWatch = state;
  return {
    armed: 'turn Background from artwork off, wait 3 s, look at the sidebar, then run this again',
    appReset: window.__aioNavRedraws ? { ...window.__aioNavRedraws } : 'missing: this build has no reset',
    attrs: LOOK.filter((n) => html.hasAttribute(n)),
    ...state.armedWith,
  };
})()
