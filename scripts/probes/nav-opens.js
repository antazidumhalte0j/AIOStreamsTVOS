// What opens the side navigation by itself, as holding Down through the home page's rows has done.
// Does nothing to the page. Records each key the page gets, each focus move, focus dropped to
// nothing and the focused element taken off the page, and on each entry into the navigation from
// the page, the events before it and the call stack that focused it (which tells the app's bridge
// script, `focusNav`, from the page's own code). Run it twice:
//   1. With the app open:   inspect-memory.py eval scripts/probes/nav-opens.js
//   2. Hold Down through the home page's rows until the navigation opens; then run it again for the
//      log (it keeps recording, so it can be run again after another try).
// A page reload (the app's own, after a memory kill) takes the recorder with it: run step 1 again.
(() => {
  const NAV = '[data-ui="tv-rail"], [data-ui="sidebar"], [data-ui="corner-menu"]';
  const KEEP = 150;
  const TRAIL = 50;
  const OPENS = 5;

  const report = (s) => ({
    recording: `${Math.round((performance.now() - s.start) / 1000)} s`,
    route: location.hash || location.pathname,
    opens: s.opens,
    recent: s.events.slice(-25),
  });
  if (window.__navOpens) return report(window.__navOpens);

  const s = { start: performance.now(), events: [], opens: [], watched: null };
  const ms = () => Math.round(performance.now() - s.start);
  const push = (e) => {
    s.events.push({ at: ms(), ...e });
    if (s.events.length > KEEP) s.events.splice(0, s.events.length - KEEP);
  };
  const desc = (el) => {
    if (!el) return 'nothing';
    if (el === document.body) return 'body';
    if (!(el instanceof Element)) return String(el);
    const row = el.closest('[data-ui=media-row]');
    const ui = el.getAttribute('data-ui') || el.closest('[data-ui]')?.getAttribute('data-ui') || '';
    const text = (el.getAttribute('aria-label') || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 30);
    const r = el.getBoundingClientRect();
    return (
      `${el.tagName.toLowerCase()}[${ui}]` +
      (row ? ` row=${row.getAttribute('data-row')}` : '') +
      (el.closest('[data-nav=title]') ? ' title' : '') +
      (el.closest(NAV) ? ' NAV' : '') +
      (el.isConnected ? '' : ' GONE') +
      (text ? ` "${text}"` : '') +
      ` @${Math.round(r.left)},${Math.round(r.top)}`
    );
  };

  addEventListener(
    'keydown',
    (e) => push({ ev: 'key', key: e.key, rep: e.repeat || undefined, on: desc(document.activeElement), y: Math.round(scrollY) }),
    true
  );
  document.addEventListener(
    'focusin',
    (e) => {
      const to = e.target;
      s.watched = to instanceof Element ? to : null;
      push({ ev: 'focus', to: desc(to), from: desc(e.relatedTarget) });
      const fromNav = e.relatedTarget instanceof Element && !!e.relatedTarget.closest(NAV);
      if (!(to instanceof Element) || !to.closest(NAV) || fromNav) return;
      // Inside the focus call, so the stack runs back through whatever focused it.
      const stack = String(new Error().stack || '')
        .split('\n')
        .slice(1, 22)
        .map((line) => (line.length > 170 ? line.slice(0, 80) + ' ... ' + line.slice(-80) : line));
      s.opens.push({
        at: ms(),
        route: location.hash || location.pathname,
        y: Math.round(scrollY),
        to: desc(to),
        from: desc(e.relatedTarget),
        stack,
        trail: s.events.slice(-TRAIL),
      });
      if (s.opens.length > OPENS) s.opens.shift();
    },
    true
  );
  document.addEventListener(
    'focusout',
    (e) => {
      const from = e.target;
      setTimeout(() => {
        const now = document.activeElement;
        if (!now || now === document.body)
          push({ ev: 'lost', from: desc(from), stillOnPage: from instanceof Element && from.isConnected });
      }, 0);
    },
    true
  );
  new MutationObserver(() => {
    const el = s.watched;
    if (!el || el.isConnected) return;
    s.watched = null;
    push({ ev: 'removed', el: desc(el), active: desc(document.activeElement) });
  }).observe(document.body, { childList: true, subtree: true });

  window.__navOpens = s;
  return {
    armed: 'hold Down through the home rows until the navigation opens, then run this again',
    route: location.hash || location.pathname,
    focus: desc(document.activeElement),
  };
})()
