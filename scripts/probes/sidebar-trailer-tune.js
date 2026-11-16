// Tries the side navigation's reset after a scroll while a trailer plays behind a title page (the
// sidebar drawn partway down the screen), on the running page, without a build: the same as
// BridgeScript's, installed by hand. Edit the numbers below and run it; running it again replaces
// the last one. It lasts until the page reloads or the app restarts.
//   inspect-memory.py eval scripts/probes/sidebar-trailer-tune.js
// Then, on a title page with its trailer playing, scroll down and watch the sidebar. Run it once
// more to see how many resets ran (`resets` in the last one's report, printed before it's replaced).
(() => {
  // How many frames the navigation stays hidden (1 or more). At 1 it's shown again before WebKit
  // draws a frame, so it may never be seen hidden.
  const HIDE_FRAMES = 1;
  // How long the page must hold still after a scroll before the reset, in ms.
  const SETTLE_MS = 0;
  // Off (false), it only reports, to see whether the sidebar shifts without it.
  const ON = true;

  const NAV_SIDE = '[data-ui="tv-rail"], [data-ui="sidebar"], [data-ui="corner-menu"]';
  const html = document.documentElement;
  const last = window.__sidebarTrailerTune;
  const before = last && { resets: last.resets, last: last.last };
  if (last) {
    removeEventListener('scroll', last.onScroll, true);
    clearTimeout(last.settling);
  }
  const state = { resets: 0, last: 'none yet', settling: 0, onScroll: null };
  const reset = () => {
    if (scrollY <= 0 || !html.hasAttribute('data-video-hole')) return;
    const navs = [...document.querySelectorAll(NAV_SIDE)].filter(
      (el) => !el.parentElement?.closest(NAV_SIDE) && getComputedStyle(el).position === 'fixed'
    );
    if (!navs.length) {
      state.last = 'skipped: no fixed navigation';
      return;
    }
    state.resets += 1;
    state.last = `hid ${navs.map((el) => el.dataset.ui).join(', ')} at scrollY ${Math.round(scrollY)}`;
    const focused = document.activeElement;
    const hadFocus = navs.some((el) => el.contains(focused));
    for (const el of navs) el.style.setProperty('display', 'none', 'important');
    void html.offsetHeight;
    let frames = Math.max(1, HIDE_FRAMES);
    const frame = () => {
      if (--frames > 0) return requestAnimationFrame(frame);
      for (const el of navs) el.style.removeProperty('display');
      if (hadFocus && focused?.isConnected) focused.focus({ preventScroll: true });
    };
    requestAnimationFrame(frame);
  };
  state.onScroll = () => {
    if (!ON || !html.hasAttribute('data-video-hole')) return;
    clearTimeout(state.settling);
    state.settling = setTimeout(reset, SETTLE_MS);
  };
  addEventListener('scroll', state.onScroll, { capture: true, passive: true });
  window.__sidebarTrailerTune = state;
  return {
    installed: { hideFrames: HIDE_FRAMES, settleMs: SETTLE_MS, on: ON },
    trailerNow: html.hasAttribute('data-video-hole'),
    previous: before,
  };
})()
