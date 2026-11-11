/**
 * Opens marked new-tab links through a placeholder tab painted in the current color theme.
 *
 * A browser shows its own blank page in a new tab until the destination's first response
 * paints. That page is white whatever the color theme is, so it flashes in dark mode. For plain
 * primary clicks on `a[data-themed-new-tab]`, this module opens the tab itself, paints it with
 * the opener's theme tokens and a spinner, and sends it to the link's URL. Modified clicks, other
 * mouse buttons and a blocked tab keep the native link, so `target` and `rel` stay on the anchor.
 *
 * The placeholder is built with DOM and CSSOM calls only, never `document.write`. The tab then
 * still holds its initial `about:blank` document, whose navigation replaces the history entry,
 * so Back never returns to the placeholder, and no inline style or script is needed.
 */
import { closestElement } from "/static/js/common/dom.js";

export const THEMED_NEW_TAB_ATTRIBUTE = "data-themed-new-tab";

const LINK_SELECTOR = `a[${THEMED_NEW_TAB_ATTRIBUTE}][href]`;
// Text of the placeholder, also its document title.
const PLACEHOLDER_LABEL = "Opening…";
const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";
// Time of one spinner turn.
const SPIN_DURATION_MS = 800;

let listenersBound = false;

/**
 * Binds the delegated click listener once.
 * @returns {void}
 */
export const initThemedNewTabs = () => {
  if (listenersBound) {
    return;
  }

  document.addEventListener("click", handleClick);
  listenersBound = true;
};

/**
 * Opens a link in a new tab that shows the themed placeholder until the destination paints.
 *
 * The new tab never keeps a reference to this page, like `rel="noopener"`, and the navigation
 * sends no referrer when the link carries `rel="noreferrer"`.
 * @param {HTMLAnchorElement} link - Link to follow.
 * @returns {boolean} False when the browser blocked the tab, so the caller keeps the native link.
 */
export const openThemedTab = (link) => {
  const tab = window.open("", "_blank");
  if (!tab) {
    return false;
  }

  tab.opener = null;
  try {
    paintPlaceholder(tab.document);
  } catch {
    // The placeholder is optional: the tab still goes to the link.
  }
  followLink(tab.document, link);
  return true;
};

/**
 * Sends the tab to the link through an anchor of its own document, so the browser applies the
 * link's referrer rule to the navigation.
 * @param {Document} tabDocument - Document of the new tab.
 * @param {HTMLAnchorElement} link - Link to follow.
 * @returns {void}
 */
const followLink = (tabDocument, link) => {
  const anchor = tabDocument.createElement("a");
  anchor.href = link.href;
  anchor.hidden = true;
  if (link.relList.contains("noreferrer")) {
    anchor.rel = "noreferrer";
  }
  tabDocument.body.append(anchor);
  anchor.click();
};

/**
 * Follows a plain primary click on a marked link through the themed tab.
 * @param {MouseEvent} event - Document click event.
 * @returns {void}
 */
const handleClick = (event) => {
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

  const link = closestElement(event.target, LINK_SELECTOR);
  if (link && openThemedTab(link)) {
    event.preventDefault();
  }
};

/**
 * Paints the placeholder: the opener's surface, a spinner and a status line.
 * @param {Document} tabDocument - Document of the new tab.
 * @returns {void}
 */
const paintPlaceholder = (tabDocument) => {
  const root = document.documentElement;
  const tokens = window.getComputedStyle(root);
  const readToken = (name) => tokens.getPropertyValue(name).trim();

  // Match the opener's language, color scheme and surface before anything else shows.
  tabDocument.title = PLACEHOLDER_LABEL;
  tabDocument.documentElement.lang = root.lang;
  tabDocument.documentElement.style.colorScheme = tokens.colorScheme;
  Object.assign(tabDocument.body.style, {
    alignItems: "center",
    backgroundColor: readToken("--color-surface"),
    color: readToken("--color-stone-600"),
    display: "flex",
    flexDirection: "column",
    fontFamily: window.getComputedStyle(document.body).fontFamily,
    fontSize: "14px",
    gap: "16px",
    height: "100vh",
    justifyContent: "center",
    margin: "0",
  });

  // Draw the spinner ring and the status line.
  const spinner = tabDocument.createElement("div");
  spinner.setAttribute("aria-hidden", "true");
  Object.assign(spinner.style, {
    border: `3px solid ${readToken("--color-stone-200")}`,
    borderRadius: "50%",
    borderTopColor: readToken("--color-primary-fg"),
    height: "32px",
    width: "32px",
  });
  const status = tabDocument.createElement("p");
  status.setAttribute("role", "status");
  status.style.margin = "0";
  status.textContent = PLACEHOLDER_LABEL;
  tabDocument.body.append(spinner, status);

  // Turn the ring unless the viewer asked for reduced motion.
  if (!window.matchMedia(REDUCED_MOTION_QUERY).matches) {
    spinner.animate([{ transform: "rotate(0deg)" }, { transform: "rotate(360deg)" }], {
      duration: SPIN_DURATION_MS,
      iterations: Infinity,
    });
  }
};

initThemedNewTabs();
