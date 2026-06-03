const FLOATING_AD_BANNER_SELECTOR = '[data-ad-banner="floating"]';
const AD_BANNER_CLOSE_SELECTOR = "[data-ad-banner-close]";
const BANNER_HIDDEN_TRANSLATE_CLASS = "translate-y-[150%]";
const BANNER_VISIBLE_TRANSLATE_CLASS = "translate-y-0";
export const AD_BANNER_STORAGE_KEY_PREFIX = "ocg:ad-banner:hidden";

/**
 * Builds the localStorage key for a banner image and destination.
 * @param {string} imageUrl - Advertisement banner image URL.
 * @param {string} linkUrl - Advertisement banner destination URL.
 * @returns {string} Storage key scoped to the banner content.
 */
export const getAdBannerStorageKey = (imageUrl, linkUrl) =>
  [AD_BANNER_STORAGE_KEY_PREFIX, encodeURIComponent(imageUrl), encodeURIComponent(linkUrl)].join(":");

/**
 * Checks if the current banner content has already been closed.
 * @param {string} imageUrl - Advertisement banner image URL.
 * @param {string} linkUrl - Advertisement banner destination URL.
 * @returns {boolean} True when the banner should stay hidden.
 */
export const isAdBannerClosed = (imageUrl, linkUrl) => {
  try {
    return localStorage.getItem(getAdBannerStorageKey(imageUrl, linkUrl)) === "true";
  } catch (_error) {
    return false;
  }
};

/**
 * Hides the banner and resets its animation state for future renders.
 * @param {HTMLElement} banner - Floating advertisement banner element.
 */
const hideAdBanner = (banner) => {
  banner.classList.remove(BANNER_VISIBLE_TRANSLATE_CLASS);
  banner.classList.add(BANNER_HIDDEN_TRANSLATE_CLASS);
  banner.setAttribute("hidden", "");
};

/**
 * Persists that the current banner content has been closed.
 * @param {string} imageUrl - Advertisement banner image URL.
 * @param {string} linkUrl - Advertisement banner destination URL.
 */
const saveClosedAdBanner = (imageUrl, linkUrl) => {
  try {
    localStorage.setItem(getAdBannerStorageKey(imageUrl, linkUrl), "true");
  } catch (_error) {
    return;
  }
};

/**
 * Initializes one floating advertisement banner element.
 * @param {HTMLElement} banner - Floating advertisement banner element.
 */
const initializeFloatingAdBanner = (banner) => {
  if (banner.dataset.adBannerInitialized === "true") {
    return;
  }

  banner.dataset.adBannerInitialized = "true";
  const imageUrl = (banner.dataset.adBannerImageUrl || "").trim();
  const linkUrl = (banner.dataset.adBannerLinkUrl || "").trim();
  if (isAdBannerClosed(imageUrl, linkUrl)) {
    hideAdBanner(banner);
    return;
  }

  banner.removeAttribute("hidden");
  const image = banner.querySelector("img");
  const closeButton = banner.querySelector(AD_BANNER_CLOSE_SELECTOR);

  /**
   * Slides the banner into view after its image is ready.
   */
  const markLoaded = () => {
    banner.classList.remove(BANNER_HIDDEN_TRANSLATE_CLASS);
    banner.classList.add(BANNER_VISIBLE_TRANSLATE_CLASS);
  };

  /**
   * Hides the banner when the configured image cannot be loaded.
   */
  const handleImageError = () => hideAdBanner(banner);

  /**
   * Closes the banner and remembers the current image/link combination.
   */
  const handleClose = () => {
    saveClosedAdBanner(imageUrl, linkUrl);
    hideAdBanner(banner);
  };

  if (image instanceof HTMLImageElement) {
    image.addEventListener("load", markLoaded, { once: true });
    image.addEventListener("error", handleImageError, { once: true });
    if (image.complete && image.naturalWidth > 0) {
      markLoaded();
    }
  } else {
    markLoaded();
  }

  closeButton?.addEventListener("click", handleClose);
};

/**
 * Initializes floating advertisement banners in a document or HTMX fragment.
 * @param {ParentNode} root - Root node where banner elements should be found.
 */
export const initializeFloatingAdBanners = (root = document) => {
  if (root instanceof Element && root.matches(FLOATING_AD_BANNER_SELECTOR)) {
    initializeFloatingAdBanner(root);
  }
  root.querySelectorAll(FLOATING_AD_BANNER_SELECTOR).forEach(initializeFloatingAdBanner);
};

/**
 * Initializes banners after the first page load.
 */
const handleDocumentReady = () => initializeFloatingAdBanners(document);

/**
 * Initializes banners inside HTMX-loaded fragments.
 * @param {Event} event - HTMX load event.
 */
const handleHtmxLoad = (event) => initializeFloatingAdBanners(event.target);

document.addEventListener("DOMContentLoaded", handleDocumentReady);
document.addEventListener("htmx:load", handleHtmxLoad);
