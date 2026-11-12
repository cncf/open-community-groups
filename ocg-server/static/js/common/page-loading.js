import { closestElement } from "/static/js/common/dom.js";

// Paths ending in a file extension, which download instead of replacing the document.
const FILE_PATH_PATTERN = /\.[a-z0-9]+$/i;
// Root attribute that shows the page loading bar (see styles.src.css).
const PAGE_LOADING_ATTRIBUTE = "data-page-loading";
// Link attribute for hrefs that keep the document without showing it, such as a redirect to a download.
const PAGE_LOADING_IGNORE_ATTRIBUTE = "data-page-loading-ignore";
// Longest the bar stays when the document is never replaced, such as a cancelled load.
const PAGE_LOADING_TIMEOUT_MS = 10000;

let listenersBound = false;
let pageLoadingTimer = null;

/**
 * Shows the page loading bar for links and forms that replace the document. HTMX requests
 * cancel those events and show the bar through their request class instead.
 */
export const initializePageLoading = () => {
  if (listenersBound) {
    return;
  }
  listenersBound = true;

  // Listen on window, the last stop, so every other handler has had its chance to cancel.
  window.addEventListener("click", handleLinkClick);
  window.addEventListener("submit", handleFormSubmit);
  // A page restored from the back/forward cache still carries the state it left with.
  window.addEventListener("pageshow", clearPageLoading);
};

/** Clears the page loading bar and its fallback timer. */
export const clearPageLoading = () => {
  window.clearTimeout(pageLoadingTimer);
  pageLoadingTimer = null;
  document.documentElement.removeAttribute(PAGE_LOADING_ATTRIBUTE);
};

/**
 * Loads a URL in the current tab, showing the page loading bar when it replaces the document.
 * @param {string} url - URL to load.
 */
export const loadPage = (url) => {
  if (replacesDocument(new URL(url, window.location.href))) {
    showPageLoading();
  }
  window.location.assign(url);
};

/**
 * Shows the bar for a submitted form that replaces the document.
 * @param {SubmitEvent} event - Submit event.
 */
const handleFormSubmit = (event) => {
  const form = event.target;
  if (!event.defaultPrevented && form instanceof HTMLFormElement && opensInSameTab(form.target)) {
    showPageLoading();
  }
};

/**
 * Shows the bar for a followed link that replaces the document.
 * @param {MouseEvent} event - Click event.
 */
const handleLinkClick = (event) => {
  if (
    event.defaultPrevented ||
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey ||
    event.altKey
  ) {
    return;
  }

  const link = closestElement(event.target, "a[href]");
  if (
    !(link instanceof HTMLAnchorElement) ||
    link.hasAttribute("download") ||
    link.hasAttribute(PAGE_LOADING_IGNORE_ATTRIBUTE) ||
    !opensInSameTab(link.target)
  ) {
    return;
  }

  if (replacesDocument(link)) {
    showPageLoading();
  }
};

/**
 * Checks whether a link or form target keeps the navigation in the current tab.
 * @param {string} target - Browsing context name, empty when unset.
 * @returns {boolean} True when the current document is the one replaced.
 */
const opensInSameTab = (target) => target === "" || target === "_self";

/**
 * Checks whether loading a URL replaces the current document.
 * @param {URL|HTMLAnchorElement} url - Parsed URL, or the link that holds it.
 * @returns {boolean} False for other schemes, fragments of this page and file downloads.
 */
const replacesDocument = ({ href, pathname, protocol }) => {
  if (protocol !== "http:" && protocol !== "https:") {
    return false;
  }

  const [page] = href.split("#");
  const isPageFragment = href.includes("#") && page === window.location.href.split("#")[0];

  return !isPageFragment && !FILE_PATH_PATTERN.test(pathname);
};

/** Shows the page loading bar until the document is replaced or the fallback timer ends. */
const showPageLoading = () => {
  window.clearTimeout(pageLoadingTimer);
  document.documentElement.setAttribute(PAGE_LOADING_ATTRIBUTE, "");
  pageLoadingTimer = window.setTimeout(clearPageLoading, PAGE_LOADING_TIMEOUT_MS);
};
