import { initializeMatchingRoots, initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";

const APPLE_MAPS_DIRECTIONS_URL = "https://maps.apple.com/directions";
const APPLE_MAPS_HOSTNAME = "maps.apple.com";
const DIRECTIONS_LINK_SELECTOR = "[data-directions-link]";
const IPHONE_USER_AGENT = /\biPhone\b/;

/**
 * Builds the Apple Maps form of a Google Maps directions URL.
 * @param {string} href Google Maps directions URL.
 * @returns {string|null} Apple Maps URL, or null when there is no destination.
 */
export const buildAppleMapsUrl = (href) => {
  const destination = new URL(href).searchParams.get("destination");
  if (!destination) {
    return null;
  }

  // Apple's examples keep commas literal in both coordinates and addresses.
  return `${APPLE_MAPS_DIRECTIONS_URL}?destination=${encodeURIComponent(destination).replaceAll("%2C", ",")}`;
};

/**
 * Keeps the Google Maps link everywhere but on iPhones, where it opens Apple
 * Maps instead. Adds nothing on any other device.
 * @param {string} [userAgent=navigator.userAgent] Browser user agent.
 * @returns {void}
 */
export const initializeDirectionsLinks = (userAgent = navigator.userAgent) => {
  if (!IPHONE_USER_AGENT.test(userAgent)) {
    return;
  }

  const phoneQuery = window.matchMedia(PHONE_MEDIA_QUERY);
  const swapLinks = (root = document) => {
    if (phoneQuery.matches) {
      initializeMatchingRoots(root, DIRECTIONS_LINK_SELECTOR, swapDirectionsLink);
    }
  };

  // A page loaded in landscape still swaps once rotated into the phone layout.
  phoneQuery.addEventListener("change", () => swapLinks());
  initializeOnReadyAndHtmxLoad(swapLinks);
};

/**
 * Points one directions link at Apple Maps, unless it already does.
 * @param {HTMLAnchorElement} link Directions link.
 * @returns {void}
 */
const swapDirectionsLink = (link) => {
  if (new URL(link.href).hostname === APPLE_MAPS_HOSTNAME) {
    return;
  }

  const appleMapsUrl = buildAppleMapsUrl(link.href);
  if (appleMapsUrl) {
    link.href = appleMapsUrl;
  }
};

initializeDirectionsLinks();
