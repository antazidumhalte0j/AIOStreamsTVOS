// Tries other timings for the app's reset of the side navigation (BridgeScript, `__aioNavRedraws`),
// on the running page, without a build. Edit the numbers below, run it, then turn "Background from
// artwork" off just after scrolling to it and watch the sidebar. They last until the page reloads
// or the app restarts, which puts back the build's own (0, 0, 2).
//   inspect-memory.py eval scripts/probes/sidebar-tune.js
(() => {
  // How long after the setting changes it runs, in ms.
  const AFTER_MS = 0;
  // After a scroll, how long the page must have held still first, in ms.
  const STILL_MS = 0;
  // How many frames the navigation stays hidden (1 or more).
  const HIDE_FRAMES = 2;

  const r = window.__aioNavRedraws;
  if (!r) return { error: "this build has no reset (no window.__aioNavRedraws)" };
  if (!('hideFrames' in r)) return { error: 'this build has a reset that can\'t be tuned; build from the latest commit' };
  r.afterMs = AFTER_MS;
  r.stillMs = STILL_MS;
  r.hideFrames = HIDE_FRAMES;
  return { now: { ...r } };
})()
