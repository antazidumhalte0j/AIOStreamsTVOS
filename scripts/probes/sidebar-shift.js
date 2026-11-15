// Where the side navigation is laid out before and after "Background from artwork" is turned off,
// for the sidebar that's drawn further down the screen after it (Settings, scrolled down).
// Run it twice:
//   1. Settings open and scrolled down a little, the wash showing:
//        inspect-memory.py eval scripts/probes/sidebar-shift.js     (prints "armed" and the "before")
//   2. Turn "Background from artwork" off on the TV, wait a few seconds, run it again: it prints
//      before, just after and 2 s after. A third run starts over.
// Each run answers at once; the change is watched for in the page between the two runs.
(() => {
  const html = document.documentElement;
  const box = (e) => {
    if (!e) return null;
    const b = e.getBoundingClientRect();
    return [Math.round(b.left), Math.round(b.top), Math.round(b.width), Math.round(b.height)];
  };
  const name = (e) =>
    e.tagName.toLowerCase() +
    (e.dataset && e.dataset.ui ? '[ui=' + e.dataset.ui + ']' : '') +
    (e.dataset && e.dataset.page !== undefined ? '[page=' + e.dataset.page + ']' : '');
  // What each element from the sidebar up to the root does that could move a fixed box.
  const chain = (e) => {
    const out = [];
    for (; e; e = e.parentElement) {
      const s = getComputedStyle(e);
      const odd = {};
      if (s.position !== 'static') odd.position = s.position;
      if (s.transform !== 'none') odd.transform = s.transform;
      if (s.filter !== 'none') odd.filter = s.filter;
      const backdrop = s.backdropFilter || s.webkitBackdropFilter;
      if (backdrop && backdrop !== 'none') odd.backdrop = backdrop;
      if (s.willChange !== 'auto') odd.willChange = s.willChange;
      if (s.contain !== 'none') odd.contain = s.contain;
      if (s.opacity !== '1') odd.opacity = s.opacity;
      if (s.top !== 'auto') odd.top = s.top;
      out.push({ el: name(e), box: box(e), ...odd });
    }
    return out;
  };
  const snap = (tag) => {
    const aside = document.querySelector("[data-ui='sidebar']");
    const vv = window.visualViewport;
    return {
      tag,
      path: location.hash,
      scrollY: Math.round(scrollY),
      inner: [innerWidth, innerHeight],
      viewport: vv && { offsetTop: vv.offsetTop, pageTop: vv.pageTop, height: vv.height, scale: vv.scale },
      attrs: [...html.attributes].map((a) => a.name).filter((n) => n.startsWith('data-')),
      sidebar: box(aside),
      rail: box(document.querySelector("[data-ui='tv-rail']")),
      // What's under the top-left and bottom-left of the screen, where the rail should be.
      atTopLeft: document.elementsFromPoint(30, 30).slice(0, 4).map(name),
      atBottomLeft: document.elementsFromPoint(30, innerHeight - 30).slice(0, 4).map(name),
      chain: chain(aside),
    };
  };

  const last = window.__sidebarShift;
  if (last && last.soon) {
    window.__sidebarShift = null;
    return { before: last.before, soon: last.soon, after: last.after || 'not yet: run again in 2 s' };
  }
  if (last) {
    // Armed, but the wash is still on.
    if (html.hasAttribute('data-art-wash'))
      return { waiting: 'Background from artwork is still on: turn it off, then run this again', before: last.before };
    window.__sidebarShift = null;
    return { waiting: 'the change was missed; turn the wash back on and run this again to start over', before: last.before };
  }

  if (!html.hasAttribute('data-art-wash'))
    return { error: 'Background from artwork is not showing a wash on this page', now: snap('now') };
  const state = { before: snap('before') };
  window.__sidebarShift = state;
  const watch = new MutationObserver(() => {
    if (html.hasAttribute('data-art-wash')) return;
    watch.disconnect();
    state.soon = snap('just after');
    setTimeout(() => (state.after = snap('2 s after')), 2000);
  });
  watch.observe(html, { attributeFilter: ['data-art-wash'] });
  return { armed: 'now turn Background from artwork off, then run this again', before: state.before };
})()
