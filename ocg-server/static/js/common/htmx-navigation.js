// Class HTMX keeps on an element while its request runs (the default `requestClass`).
const REQUEST_CLASS = "htmx-request";

/**
 * Navigates to a URL using HTMX by creating a temporary boosted anchor. The anchor stays
 * while its request runs, because the page loading bar follows its request class.
 * @param {string} url URL to navigate to.
 * @returns {void}
 */
export const navigateWithHtmx = (url) => {
  const anchor = document.createElement("a");
  const listeners = new AbortController();
  const { signal } = listeners;
  const removeAnchor = () => {
    listeners.abort();
    anchor.remove();
  };

  anchor.href = url;
  anchor.setAttribute("hx-boost", "true");
  anchor.style.display = "none";
  // A body swap removes the anchor with the old page; this covers requests that fail.
  anchor.addEventListener("htmx:afterRequest", removeAnchor, { signal });
  // A snapshot saved while the request runs would bring the anchor back once restored.
  document.addEventListener("htmx:beforeHistorySave", removeAnchor, { signal });

  document.body.appendChild(anchor);
  htmx.process(anchor);
  anchor.click();

  // Remove the anchor when HTMX started no request for it.
  if (!anchor.classList.contains(REQUEST_CLASS)) {
    removeAnchor();
  }
};
