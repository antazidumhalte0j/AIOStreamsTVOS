// Tries the top tabs' fit (BridgeScript's `data-tabs-tight`) on the running page: centred as upstream
// has it if that fits, else the tabs centred between the ends, else the bar's spacing tightened, the
// tabs' names kept. Reports the page's width before and after. Stays until the page reloads.
// Run with: inspect-memory.py eval scripts/probes/top-tabs-fit.js
(() => {
  const html = document.documentElement;
  const TABS_ROW = "[data-ui='top-tabs'] .grid";
  const COMPACT = TABS_ROW + "[data-tabs-tight='compact']";
  const row = document.querySelector(TABS_ROW);
  if (!row) return { error: 'no top tabs on the page', nav: html.dataset.nav };
  const before = { scrollWidth: html.scrollWidth, innerWidth, scale: visualViewport && visualViewport.scale };
  let style = document.getElementById('aio-tabs-fit-test');
  if (!style) {
    style = document.createElement('style');
    style.id = 'aio-tabs-fit-test';
    document.head.appendChild(style);
  }
  style.textContent =
    TABS_ROW + '[data-tabs-tight]{grid-template-columns:auto minmax(0,1fr) auto!important}' +
    TABS_ROW + '[data-tabs-tight]>:nth-child(2){justify-self:center}' +
    COMPACT + '{padding-left:1.25rem!important;padding-right:1.25rem!important;column-gap:0.75rem!important}' +
    COMPACT + " [data-ui='nav-item']{padding-inline-end:0.875rem!important;gap:0.75rem!important}";
  const contentWidth = (el) => {
    let left = Infinity;
    let right = -Infinity;
    for (const child of el.children) {
      const r = child.getBoundingClientRect();
      if (!r.width) continue;
      left = Math.min(left, r.left);
      right = Math.max(right, r.right);
    }
    return right > left ? right - left : el.getBoundingClientRect().width;
  };
  // Measured at upstream's spacing.
  row.removeAttribute('data-tabs-tight');
  void html.offsetWidth;
  const [start, tabs, end] = row.children;
  const s = getComputedStyle(row);
  const room = row.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight);
  const gap = parseFloat(s.columnGap) || 0;
  const sizes = {
    room,
    gap,
    logo: Math.round(contentWidth(start)),
    tabs: Math.round(tabs.getBoundingClientRect().width),
    end: Math.round(end.getBoundingClientRect().width),
  };
  const mode =
    sizes.tabs + 2 * gap + 2 * Math.max(sizes.logo, sizes.end) <= room + 0.5
      ? 'centred'
      : sizes.logo + sizes.tabs + sizes.end + 2 * gap <= room + 0.5
        ? 'tight'
        : 'compact';
  if (mode === 'tight') row.setAttribute('data-tabs-tight', '');
  if (mode === 'compact') row.setAttribute('data-tabs-tight', 'compact');
  void html.offsetWidth;
  const tabsBox = tabs.getBoundingClientRect();
  const endBox = end.getBoundingClientRect();
  return {
    mode,
    sizes,
    before,
    after: {
      scrollWidth: html.scrollWidth,
      tabsWidth: Math.round(tabsBox.width),
      tabsRight: Math.round(tabsBox.right),
      endLeft: Math.round(endBox.left),
      endRight: Math.round(endBox.right),
      clear: Math.round(endBox.left - tabsBox.right),
    },
  };
})()
