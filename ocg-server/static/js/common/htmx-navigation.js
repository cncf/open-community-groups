/**
 * Navigates to a URL using HTMX by creating a temporary boosted anchor.
 * @param {string} url URL to navigate to.
 * @returns {void}
 */
export const navigateWithHtmx = (url) => {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.setAttribute("hx-boost", "true");
  anchor.style.display = "none";

  document.body.appendChild(anchor);
  htmx.process(anchor);
  anchor.click();

  setTimeout(() => {
    if (document.body.contains(anchor)) {
      document.body.removeChild(anchor);
    }
  }, 100);
};
