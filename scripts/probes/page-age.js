// How long ago the page loaded, to tell whether something (a setting, the page's process ending)
// reloaded it. Run it before and after; a smaller "secondsSinceLoad" after means it reloaded.
//   inspect-memory.py eval scripts/probes/page-age.js
(() => {
  const nav = performance.getEntriesByType('navigation')[0];
  return {
    secondsSinceLoad: Math.round(performance.now() / 1000),
    loadedAt: new Date(performance.timeOrigin).toISOString(),
    type: nav ? nav.type : 'unknown',
    path: location.hash,
    scrollY: Math.round(scrollY),
  };
})()
