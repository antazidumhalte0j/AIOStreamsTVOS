// Tries one way of getting WebKit to draw the side navigation where it's laid out again, while
// it's drawn too far down the screen (after "Background from artwork" is turned off on a scrolled
// page). Each run tries the next way, and says which; watch the TV after each run.
//   inspect-memory.py eval scripts/probes/sidebar-reset.js
(() => {
  const aside = document.querySelector("[data-ui='sidebar']");
  if (!aside) return { error: 'no sidebar on this page' };
  const ways = [
    ['hidden for two frames (display: none), then shown', (done) => {
      aside.style.display = 'none';
      void aside.offsetHeight;
      requestAnimationFrame(() => requestAnimationFrame(() => {
        aside.style.display = '';
        done();
      }));
    }],
    ['laid out as absolute for two frames, then fixed again', (done) => {
      aside.style.setProperty('position', 'absolute', 'important');
      void aside.offsetHeight;
      requestAnimationFrame(() => requestAnimationFrame(() => {
        aside.style.removeProperty('position');
        done();
      }));
    }],
    ['given a layer of its own (translateZ(0)); stays until the next run', (done) => {
      aside.style.transform = 'translateZ(0)';
      done();
    }],
    ['page scrolled to the top for two frames, then back', (done) => {
      aside.style.transform = '';
      const y = scrollY;
      scrollTo({ top: 0, behavior: 'instant' });
      requestAnimationFrame(() => requestAnimationFrame(() => {
        scrollTo({ top: y, behavior: 'instant' });
        done();
      }));
    }],
  ];
  const step = (window.__sidebarReset || 0) % ways.length;
  window.__sidebarReset = step + 1;
  const [what, run] = ways[step];
  run(() => {});
  return {
    tried: `${step + 1} of ${ways.length}: ${what}`,
    next: step + 1 < ways.length ? 'run again for the next way' : 'that was the last; the next run starts over',
    scrollY: Math.round(scrollY),
    sidebar: (() => {
      const b = aside.getBoundingClientRect();
      return [Math.round(b.left), Math.round(b.top), Math.round(b.width), Math.round(b.height)];
    })(),
  };
})()
