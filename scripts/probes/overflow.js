// What sticks out past the page's right edge, making it wider than its 1280 and WebKit shrink it to
// fit (a strip down the right with top tabs). Only what isn't clipped by a box it's in counts, as
// only that widens the page. Run with: inspect-memory.py eval scripts/probes/overflow.js
(() => {
  const html = document.documentElement;
  const edge = html.clientWidth;
  const name = (e) =>
    e.tagName.toLowerCase() +
    (e.id ? '#' + e.id : '') +
    (e.dataset && e.dataset.ui ? '[ui=' + e.dataset.ui + ']' : '') +
    (typeof e.className === 'string' && e.className.trim()
      ? '.' + e.className.trim().split(/\s+/).slice(0, 8).join('.')
      : '');
  const clips = (e) => {
    const s = getComputedStyle(e);
    return s.overflowX !== 'visible' || s.contain.includes('paint');
  };
  const clipped = (e) => {
    for (let p = e.parentElement; p && p !== document.body; p = p.parentElement) if (clips(p)) return true;
    return false;
  };
  const out = [];
  for (const e of document.body.querySelectorAll('*')) {
    const s = getComputedStyle(e);
    if (s.display === 'none' || s.position === 'fixed') continue;
    const b = e.getBoundingClientRect();
    if (b.right <= edge + 0.5 || b.width === 0) continue;
    if (clipped(e)) continue;
    // The outermost one: its parent doesn't stick out as far.
    const parent = e.parentElement && e.parentElement.getBoundingClientRect();
    out.push({
      el: name(e),
      right: Math.round(b.right),
      left: Math.round(b.left),
      width: Math.round(b.width),
      parentRight: parent ? Math.round(parent.right) : null,
      margin: s.marginLeft + ' / ' + s.marginRight,
      widthCss: s.width,
    });
  }
  out.sort((a, b) => b.right - a.right);
  return { edge, scrollWidth: html.scrollWidth, nav: html.dataset.nav, count: out.length, widest: out.slice(0, 15) };
})()
