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

/**
 * Renders utility layout styles and a spacer that pushes later body content near the viewport bottom.
 * @param {number} distanceFromBottom - Space left between the spacer end and the viewport bottom.
 * @returns {void}
 */
export const renderViewportBottomLayout = (distanceFromBottom) => {
  document.body.style.margin = "0";
  document.body.insertAdjacentHTML(
    "afterbegin",
    `<style>
      .absolute { position: absolute; }
      .relative { position: relative; }
      .hidden { display: none; }
      .end-0 { inset-inline-end: 0; }
      .left-0 { left: 0; }
      .right-0 { right: 0; }
      .start-0 { inset-inline-start: 0; }
      .top-10 { top: 2.5rem; }
      .top-full { top: 100%; }
      .mt-1 { margin-top: 0.25rem; }
      .mt-2 { margin-top: 0.5rem; }
      .max-h-56 { max-height: 14rem; }
      .max-h-80 { max-height: 20rem; }
      .overflow-y-auto { overflow-y: auto; }
    </style>
    <div style="height: ${window.innerHeight - distanceFromBottom}px"></div>`,
  );
};
