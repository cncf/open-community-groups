/** Resets the DOM and shared body/document styles between unit test cases. */
export const resetDom = () => {
  document.body.innerHTML = "";
  document.body.removeAttribute("style");
  delete document.body.dataset.modalOpenCount;
  delete document.body.dataset.modalOverflow;
  delete document.body.dataset.modalPaddingRight;
  document.documentElement.removeAttribute("style");
  document.head.querySelector("#qr-print-styles")?.remove();
  document.getElementById("qr-print-container")?.remove();
  delete window.__ocgPageViewTracker;
};

/** Updates the current browser path without triggering a full navigation. */
export const setLocationPath = (path) => {
  history.replaceState({}, "", path);
};

/** Captures window scroll requests and restores the original implementation. */
export const mockScrollTo = () => {
  const originalScrollTo = window.scrollTo;
  const calls = [];

  window.scrollTo = (options) => {
    calls.push(options);
  };

  return {
    calls,
    restore() {
      window.scrollTo = originalScrollTo;
    },
  };
};

/** Tracks document and window listeners so tests can remove them after each case. */
export const trackAddedEventListeners = () => {
  const originalWindowAddEventListener = window.addEventListener.bind(window);
  const originalDocumentAddEventListener = document.addEventListener.bind(document);
  const listenersToRemove = [];

  window.addEventListener = (type, listener, options) => {
    listenersToRemove.push(() => window.removeEventListener(type, listener, options));
    return originalWindowAddEventListener(type, listener, options);
  };

  document.addEventListener = (type, listener, options) => {
    listenersToRemove.push(() => document.removeEventListener(type, listener, options));
    return originalDocumentAddEventListener(type, listener, options);
  };

  return {
    restore() {
      window.addEventListener = originalWindowAddEventListener;
      document.addEventListener = originalDocumentAddEventListener;
      listenersToRemove.forEach((removeListener) => removeListener());
    },
  };
};
