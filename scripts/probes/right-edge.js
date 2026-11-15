// What the page draws down its right edge, and how its layout boxes sit (a strip there with
// top tabs or a floating side rail). Run with: inspect-memory.py eval scripts/probes/right-edge.js
(() => {
  const box = (e) => {
    const b = e.getBoundingClientRect();
    return [Math.round(b.left), Math.round(b.top), Math.round(b.width), Math.round(b.height)];
  };
  const name = (e) =>
    e.tagName.toLowerCase() +
    (e.id ? '#' + e.id : '') +
    (e.dataset && e.dataset.ui ? '[ui=' + e.dataset.ui + ']' : '') +
    (e.dataset && e.dataset.page !== undefined ? '[page=' + e.dataset.page + ']' : '') +
    (typeof e.className === 'string' && e.className.trim()
      ? '.' + e.className.trim().split(/\s+/).slice(0, 6).join('.')
      : '');
  const under = (x, y) =>
    document
      .elementsFromPoint(x, y)
      .slice(0, 12)
      .map((e) => {
        const s = getComputedStyle(e);
        return {
          el: name(e),
          box: box(e),
          bg: s.backgroundColor,
          bgImage: s.backgroundImage.slice(0, 60),
          position: s.position,
        };
      });
  const html = document.documentElement;
  const css = getComputedStyle(html);
  const pick = (s) => document.querySelector(s) && box(document.querySelector(s));
  return {
    nav: html.dataset.nav,
    attrs: [...html.attributes].map((a) => a.name).filter((n) => n.startsWith('data-')),
    inner: [innerWidth, innerHeight],
    doc: [html.clientWidth, html.scrollWidth, document.body.clientWidth],
    scale: window.visualViewport && visualViewport.scale,
    topBar: css.getPropertyValue('--top-bar'),
    rightEdge: under(innerWidth - 15, innerHeight / 2),
    leftEdge: under(15, innerHeight / 2),
    main: pick('main'),
    page: pick('[data-page]'),
    background: pick("[data-ui='page-background']"),
    sidebar: pick("[data-ui='sidebar'], [data-ui='tv-rail'], aside"),
  };
})()
