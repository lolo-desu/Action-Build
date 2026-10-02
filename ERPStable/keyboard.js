(() => {
  'use strict';
  if (location.origin !== 'https://erp.sex') return;
  let viewport = null;
  let scheduled = false;
  let messages = null, messageState = null;
  const resizeObserver = new ResizeObserver(() => update());
  function messagePane() {
    if (!/^\/matches\/[^/]+\/?$/.test(location.pathname)) return null;
    return document.querySelector('#main .card.relative.min-h-0.flex-1.overflow-y-auto') || document.querySelector('#main .messages');
  }
  function rememberMessages() {
    if (!messages) return;
    messageState = { top: messages.scrollTop, height: messages.clientHeight, content: messages.scrollHeight,
      bottom: messages.scrollHeight - messages.scrollTop - messages.clientHeight < 80 };
  }
  function observeMessages() {
    const pane = messagePane();
    if (pane === messages) return;
    if (messages) resizeObserver.unobserve(messages);
    messages = pane; messageState = null;
    if (pane) { pane.style.overflowAnchor = 'none'; rememberMessages(); resizeObserver.observe(pane); }
  }
  function preserveMessages() {
    if (!messages || !messageState) return;
    const resized = messages.clientHeight !== messageState.height;
    const grown = messages.scrollHeight !== messageState.content;
    if (resized || grown && messageState.bottom) {
      const top = messageState.bottom ? Math.max(0, messages.scrollHeight - messages.clientHeight) : messageState.top;
      if (Math.abs(messages.scrollTop - top) > .5) messages.scrollTop = top;
      // Update the site's own near-bottom flag after the layout change as well.
      rememberMessages(); messages.dispatchEvent(new Event('scroll'));
    } else rememberMessages();
  }
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
    observeMessages();
    const chat = /^\/matches\/[^/]+\/?$/.test(location.pathname);
    if (root.dataset.vrcrpChat !== String(chat)) root.dataset.vrcrpChat = String(chat);
    if (!viewport) return;
    root.dataset.vrcrpViewport = 'true';
    const value = `${viewport.height}px`;
    if (root.style.getPropertyValue('--vrcrp-viewport-height') !== value) root.style.setProperty('--vrcrp-viewport-height', value);
    if (root.dataset.vrcrpKeyboard !== String(viewport.keyboardVisible)) root.dataset.vrcrpKeyboard = String(viewport.keyboardVisible);
    preserveMessages();
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
  window.__vrcrpWillResizeViewport = () => { observeMessages(); if (messages && messageState && messages.clientHeight === messageState.height) rememberMessages(); };
  document.addEventListener('scroll', event => {
    if (event.target !== messages || !messageState) return;
    // WebKit can emit scroll while shrinking/clamping the pane. Keep the
    // pre-resize bottom policy until the new geometry has been applied.
    if (messages.clientHeight !== messageState.height) { update(); return; }
    rememberMessages();
  }, { capture: true, passive: true });
  document.addEventListener('load', event => { if (messages?.contains(event.target)) update(); }, true);
  document.addEventListener('focusin', schedule);
  window.addEventListener('resize', schedule);
  window.addEventListener('popstate', schedule);
  new MutationObserver(schedule).observe(document, { childList: true, subtree: true });
  schedule();
})();
