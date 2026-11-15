// With the side navigation drawn too far down the screen, scrolls the page to the top for two frames
// and back, as opening another page resets the scroll. Watch the TV as it runs.
//   inspect-memory.py eval scripts/probes/sidebar-scroll-reset.js
(() => {
  const y = scrollY;
  scrollTo({ top: 0, behavior: 'instant' });
  requestAnimationFrame(() => requestAnimationFrame(() => scrollTo({ top: y, behavior: 'instant' })));
  return { scrolledFrom: Math.round(y), andBackTo: Math.round(y) };
})()
