(() => {
  'use strict';
  const viewportValue = 'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
  const css = `
    html, body { touch-action: manipulation; }
    body { padding-left: env(safe-area-inset-left); padding-right: env(safe-area-inset-right); }
    .app-top { padding-top: max(0.75rem, env(safe-area-inset-top)) !important; }
    .app-bottom { padding-left: env(safe-area-inset-left); padding-right: env(safe-area-inset-right); }
    .h-dvh, .h-screen { height: var(--vrcrp-viewport-height, 100dvh) !important; }
    .min-h-screen { min-height: var(--vrcrp-viewport-height, 100dvh) !important; }
    html[data-vrcrp-chat="true"], html[data-vrcrp-chat="true"] body {
      height: var(--vrcrp-viewport-height, 100dvh); overflow: hidden;
    }
    * { -webkit-user-select: none !important; user-select: none !important; -webkit-touch-callout: none !important; }
    input, textarea, [contenteditable]:not([contenteditable="false"]),
    input *, textarea *, [contenteditable]:not([contenteditable="false"]) * {
      -webkit-user-select: text !important; user-select: text !important;
    }
    input, textarea, select, [contenteditable]:not([contenteditable="false"]) {
      font-size: max(16px, 1em) !important;
    }
  `;
  let queued = false;
  let lastThemeColor = null;
  function apply() {
    queued = false;
    if (!document.head) return;
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
    document.querySelectorAll('[autofocus]').forEach(el => el.removeAttribute('autofocus'));
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
    attributeFilter: ['content', 'name', 'autofocus'] });
  document.addEventListener('contextmenu', event => {
    const el = event.target instanceof Element ? event.target : event.target.parentElement;
    if (!el?.closest('input, textarea, [contenteditable]:not([contenteditable="false"])')) event.preventDefault();
  }, true);
  apply();
})();
