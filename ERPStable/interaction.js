(() => {
  'use strict';
  if (location.origin !== 'https://erp.sex') return;
  const viewportValue = 'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
  const css = `
    html, body { touch-action: manipulation; }
    * { -webkit-user-select: none !important; user-select: none !important; -webkit-touch-callout: none !important; }
    #main, #main *, [role="dialog"], [role="dialog"] * {
      -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important;
    }
    #main .stage, #main .stage *, #main button, #main button *,
    #main [role="button"], #main [role="button"] *,
    #main svg, #main svg *, #main img, #main video, #main canvas,
    [role="dialog"] button, [role="dialog"] button *, [role="dialog"] [role="button"], [role="dialog"] [role="button"] * {
      -webkit-user-select: none !important; user-select: none !important; -webkit-touch-callout: none !important;
    }
    input, textarea, [contenteditable]:not([contenteditable="false"]),
    input *, textarea *, [contenteditable]:not([contenteditable="false"]) * {
      -webkit-user-select: text !important; user-select: text !important;
    }
  `;
  let queued = false;
  let lastThemeColor = null;
  function apply() {
    queued = false;
    if (!document.head) return;
    // The site's installed-app pull handler explicitly respects data-no-ptr.
    // UIKit owns the single refresh hint and performs an in-place refetch.
    document.documentElement.dataset.noPtr='true';
    let metas = [...document.querySelectorAll('meta[name="viewport" i]')];
    if (!metas.length) {
      const meta = document.createElement('meta');
      meta.name = 'viewport'; document.head.appendChild(meta); metas = [meta];
    }
    for (const meta of metas) {
      if (meta.content !== viewportValue) meta.content = viewportValue;
    }
    let style = document.getElementById('erp-stable-interactions');
    if (!style) {
      style = document.createElement('style');
      style.id = 'erp-stable-interactions'; document.head.appendChild(style);
    }
    if (style.textContent !== css) style.textContent = css;
    const color = document.querySelector('meta[name="theme-color"]')?.content;
    if (window === window.top && location.origin === 'https://erp.sex' &&
        /^#[0-9a-f]{6}$/i.test(color ?? '') && color !== lastThemeColor) {
      lastThemeColor = color;
      window.webkit?.messageHandlers?.erpNativeNotifications?.postMessage({ kind: 'appearance', color });
    }
  }
  new MutationObserver(() => {
    if (!queued) { queued = true; queueMicrotask(apply); }
  }).observe(document, { subtree: true, childList: true, attributes: true,
    attributeFilter: ['content', 'name'] });
  document.addEventListener('contextmenu', event => {
    const el = event.target instanceof Element ? event.target : event.target.parentElement;
    const editing = el?.closest('input, textarea, [contenteditable]:not([contenteditable="false"])');
    const reading = el?.closest('#main,[role="dialog"]') && !el.closest('.stage,button,[role="button"],svg,img,video,canvas');
    if (!editing && !reading) event.preventDefault();
  }, true);
  apply();
})();
