/** Resets the DOM and shared body/document styles between unit test cases. */
export const resetDom = () => {
  document.body.innerHTML = "";
  document.body.removeAttribute("style");
  delete document.body.dataset.modalOpenCount;
  delete document.body.dataset.modalOverflow;
  delete document.body.dataset.modalPaddingRight;
  document.documentElement.removeAttribute("style");
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
