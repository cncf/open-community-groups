/**
 * Resolves a relative or absolute URL against the current origin. Returns an empty
 * string if the URL is invalid to avoid displaying potentially dangerous URLs.
 */
export const resolveUrl = (url) => {
  if (!url) {
    return "";
  }
  try {
    return new URL(url, window.location.origin).toString();
  } catch {
    return "";
  }
};

/**
 * Updates a link element's text content and href attribute with a resolved URL. If the
 * URL is invalid or empty, the link is cleared.
 */
export const setLinkContent = (link, url) => {
  if (!link) {
    return;
  }

  if (url) {
    const resolved = resolveUrl(url);
    if (resolved) {
      link.textContent = resolved;
      link.setAttribute("href", resolved);
      return;
    }
  }

  link.textContent = "";
  link.removeAttribute("href");
};
