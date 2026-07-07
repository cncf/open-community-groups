import { initializeOnReady } from "/static/js/common/dom.js";
import { toTrimmedString } from "/static/js/common/utils.js";

export const BROKEN_IMAGE_PLACEHOLDER_URL = "/static/images/icons/broken_image.svg";

const DEFAULT_BROKEN_IMAGE_PLACEHOLDER_BG_CLASS = "bg-stone-50";
const REMOVE_BROKEN_IMAGE_SELECTOR = "[data-ocg-remove-broken-images]";
const EMPTY_IMAGE_WRAPPER_SELECTOR = "img, video, iframe, object, embed";

/**
 * Checks if a failed image should be removed instead of replaced.
 * @param {HTMLImageElement} image Image element that emitted the event.
 * @returns {boolean} True when the image should be removed from the DOM.
 */
const shouldRemoveBrokenImage = (image) => Boolean(image.closest(REMOVE_BROKEN_IMAGE_SELECTOR));

/**
 * Checks whether a wrapper has content worth keeping after an image is removed.
 * @param {Element|null} element Possible wrapper around the failed image.
 * @returns {boolean} True when the wrapper has meaningful remaining content.
 */
const hasRemainingWrapperContent = (element) =>
  Boolean(element?.textContent?.trim() || element?.querySelector(EMPTY_IMAGE_WRAPPER_SELECTOR));

/**
 * Removes a failed image in content areas that opt out of placeholders.
 * @param {EventTarget|null} target Possible image element from an error event.
 * @returns {boolean} True when the image was removed.
 */
const removeBrokenImage = (target) => {
  if (!(target instanceof HTMLImageElement) || !shouldRemoveBrokenImage(target)) {
    return false;
  }

  const linkedImage = target.parentElement?.tagName === "A" ? target.parentElement : null;
  const paragraph = target.closest("p");

  target.remove();
  if (linkedImage && !hasRemainingWrapperContent(linkedImage)) {
    linkedImage.remove();
  }
  if (paragraph && !hasRemainingWrapperContent(paragraph)) {
    paragraph.remove();
  }

  return true;
};

/**
 * Checks if a failed image should keep an existing fallback.
 * @param {HTMLImageElement} image Image element that emitted the event.
 * @returns {boolean} True when the global fallback should not replace it.
 */
const shouldSkipBrokenImagePlaceholder = (image) => {
  if (image.closest("logo-image")) {
    return true;
  }

  const srcAttribute = image.getAttribute("src");
  if (srcAttribute !== null && srcAttribute.trim().length === 0) {
    return true;
  }

  const currentSource = image.currentSrc || image.src;
  if (!srcAttribute && !image.currentSrc) {
    return true;
  }

  return currentSource.endsWith(BROKEN_IMAGE_PLACEHOLDER_URL);
};

/**
 * Resolves the background color class used behind the broken-image icon.
 * @param {HTMLImageElement} image Image element that emitted the event.
 * @returns {string} Background class used by the placeholder container.
 */
const getBrokenImagePlaceholderBgClass = (image) =>
  toTrimmedString(image.dataset.ocgBrokenImageBgClass) || DEFAULT_BROKEN_IMAGE_PLACEHOLDER_BG_CLASS;

/**
 * Checks whether an element already creates a containing block.
 * @param {Element} element Parent element for the broken image.
 * @returns {boolean} True when the element is already positioned.
 */
const isPositionedElement = (element) => {
  const position = element.ownerDocument.defaultView?.getComputedStyle(element).position;
  return Boolean(position && position !== "static");
};

/**
 * Hides a failed image and overlays the shared broken-image icon.
 * @param {EventTarget|null} target Possible image element from an error event.
 * @returns {boolean} True when the placeholder was applied.
 */
export const applyBrokenImagePlaceholder = (target) => {
  if (!(target instanceof HTMLImageElement)) {
    return false;
  }

  if (removeBrokenImage(target)) {
    return false;
  }

  if (target.dataset.ocgBrokenImagePlaceholder === "true" || shouldSkipBrokenImagePlaceholder(target)) {
    return false;
  }

  target.dataset.ocgBrokenImagePlaceholder = "true";
  target.classList.add("invisible");
  if (target.parentElement && !isPositionedElement(target.parentElement)) {
    target.parentElement.dataset.ocgBrokenImageAddedRelative = "true";
    target.parentElement.classList.add("relative");
  }
  target.removeAttribute("srcset");
  target.src = BROKEN_IMAGE_PLACEHOLDER_URL;
  if (target.nextElementSibling?.dataset?.ocgBrokenImageIcon !== "true") {
    const placeholderContainer = document.createElement("span");
    const placeholderIcon = document.createElement("span");
    placeholderContainer.className = [
      "absolute",
      "inset-0",
      "flex",
      "items-center",
      "justify-center",
      getBrokenImagePlaceholderBgClass(target),
      "pointer-events-none",
    ].join(" ");
    placeholderIcon.className = ["svg-icon", "size-8", "icon-broken-image", "bg-stone-400"].join(" ");
    placeholderContainer.dataset.ocgBrokenImageIcon = "true";
    placeholderContainer.setAttribute("aria-hidden", "true");
    placeholderContainer.append(placeholderIcon);
    target.insertAdjacentElement("afterend", placeholderContainer);
  }

  return true;
};

/**
 * Removes fallback state when a previously broken image loads normally.
 * @param {EventTarget|null} target Possible image element from a load event.
 * @returns {boolean} True when fallback state was cleared.
 */
export const clearBrokenImagePlaceholder = (target) => {
  if (!(target instanceof HTMLImageElement)) {
    return false;
  }

  if (target.dataset.ocgBrokenImagePlaceholder !== "true") {
    return false;
  }

  const currentSource = target.currentSrc || target.src;
  if (currentSource.endsWith(BROKEN_IMAGE_PLACEHOLDER_URL)) {
    return false;
  }

  delete target.dataset.ocgBrokenImagePlaceholder;
  target.classList.remove("invisible");
  if (target.nextElementSibling?.dataset?.ocgBrokenImageIcon === "true") {
    target.nextElementSibling.remove();
  }
  if (!target.parentElement?.querySelector('[data-ocg-broken-image-placeholder="true"]')) {
    if (target.parentElement?.dataset.ocgBrokenImageAddedRelative === "true") {
      delete target.parentElement.dataset.ocgBrokenImageAddedRelative;
      target.parentElement.classList.remove("relative");
    }
  }

  return true;
};

/**
 * Applies placeholders to images that failed before listeners ran.
 * @param {ParentNode} root Root node to scan for image elements.
 * @returns {number} Number of placeholders applied.
 */
export const applyBrokenImagePlaceholders = (root = document) => {
  if (!root || typeof root.querySelectorAll !== "function") {
    return 0;
  }

  return [...root.querySelectorAll("img")].reduce((appliedCount, image) => {
    if (!image.complete || image.naturalWidth > 0) {
      return appliedCount;
    }

    if (removeBrokenImage(image)) {
      return appliedCount;
    }

    return applyBrokenImagePlaceholder(image) ? appliedCount + 1 : appliedCount;
  }, 0);
};

const applyBrokenImagePlaceholdersForDocument = () => {
  applyBrokenImagePlaceholders(document);
};

document.addEventListener(
  "error",
  (event) => {
    applyBrokenImagePlaceholder(event.target);
  },
  true,
);

document.addEventListener(
  "load",
  (event) => {
    clearBrokenImagePlaceholder(event.target);
  },
  true,
);

initializeOnReady(applyBrokenImagePlaceholdersForDocument);

window.addEventListener("load", applyBrokenImagePlaceholdersForDocument, { once: true });
