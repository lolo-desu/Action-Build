(() => {
  'use strict';
  if (location.origin !== 'https://erp.sex') return;
  let viewport = null;
  let scheduled = false;
  function installStyle() {
    if (!document.head || document.getElementById('vrcrp-keyboard-layout')) return;
    const style = document.createElement('style');
    style.id = 'vrcrp-keyboard-layout';
    // The site's chat already uses a full-height flex layout. Supply only its
    // actual native viewport height, without restyling headers, tabs or editors.
    style.textContent = `
      html[data-vrcrp-chat="true"][data-vrcrp-viewport="true"] .h-dvh {
        height: var(--vrcrp-viewport-height) !important;
      }
      html[data-vrcrp-chat="true"][data-vrcrp-viewport="true"],
      html[data-vrcrp-chat="true"][data-vrcrp-viewport="true"] body {
        height: var(--vrcrp-viewport-height); overflow: hidden;
      }
    `;
    document.head.appendChild(style);
  }
  function update() {
    scheduled = false;
    const root = document.documentElement;
    if (!root) return;
    installStyle();
    const chat = /^\/matches\/[^/]+\/?$/.test(location.pathname);
    if (root.dataset.vrcrpChat !== String(chat)) root.dataset.vrcrpChat = String(chat);
    if (!viewport) return;
    root.dataset.vrcrpViewport = 'true';
    const value = `${viewport.height}px`;
    if (root.style.getPropertyValue('--vrcrp-viewport-height') !== value) root.style.setProperty('--vrcrp-viewport-height', value);
    if (root.dataset.vrcrpKeyboard !== String(viewport.keyboardVisible)) root.dataset.vrcrpKeyboard = String(viewport.keyboardVisible);
    // Resizing the native view relays out the chat's flex container. Only reveal
    // an editor that is still outside that viewport; preserve normal scrolling.
    const editor = document.activeElement;
    if (viewport.keyboardVisible && editor?.matches('input:not([type="hidden"]), textarea, [contenteditable]:not([contenteditable="false"])')) {
      const rect = editor.getBoundingClientRect();
      if (rect.bottom > viewport.height - 8 || rect.top < 0) editor.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
    }
  }
  function schedule() {
    if (!scheduled) { scheduled = true; requestAnimationFrame(update); }
  }
  window.__vrcrpSetViewport = value => {
    if (!value || !Number.isFinite(value.height) || value.height <= 0 || !Number.isFinite(value.width) || value.width <= 0) return;
    viewport = { height: value.height, keyboardVisible: value.keyboardVisible === true };
    // Native keyboard layout has already happened. Apply its height now even
    // when WebKit defers paint callbacks during a transition or cold launch.
    update();
  };
  document.addEventListener('focusin', schedule);
  window.addEventListener('resize', schedule);
  window.addEventListener('popstate', schedule);
  new MutationObserver(schedule).observe(document, { childList: true, subtree: true });
  schedule();
})();
