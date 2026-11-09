/**
 * Initializes header dropdown and nav loading behavior with HTMX awareness.
 */
import { closestElement, getElementById, isElementHidden, setElementHidden } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import {
  focusModal,
  lockBodyScroll,
  restoreModalFocus,
  trapModalFocus,
  unlockBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { bindSheetGestures } from "/static/js/common/modals/sheet-gestures.js";
import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";

let documentHandlersBound = false;
let lifecycleListenersBound = false;
let pendingHeaderNavLink = null;
let pendingHeaderNavLinkTimer = null;
let releaseUserSheetGestures = null;
let userSheetDropdown = null;
let userSheetOpen = false;
let userSheetPhoneQuery = null;
let userSheetTrigger = null;

const headerNavLinkSelector = "[data-header-nav-link]";
/** Wait before showing nav loading so quick HTMX requests can finish without flicker. */
const headerNavLinkPendingDelayMs = 120;
const userSheetCloseSelector = ".sheet-head button";
// Everything behind the scrim, so screen readers cannot walk there while the sheet is open.
const userSheetInertSelector =
  '#main-content, #dashboard-layout, footer[role="contentinfo"], #header a[aria-label$=" homepage"], ' +
  "div:has(> #header) ~ *";
const userSheetTriggerSelector = "#user-dropdown-button";

/**
 * Finds the header nav link that triggered an event.
 * @param {Event} event - Click or HTMX lifecycle event.
 * @returns {Element|null} Matching header nav link, if any.
 */
const getHeaderNavLinkFromEvent = (event) => {
  const source = event?.detail?.elt || event?.target;
  if (!(source instanceof Element)) {
    return null;
  }

  if (source.matches(headerNavLinkSelector)) {
    return source;
  }

  return source.closest(headerNavLinkSelector);
};

/**
 * Clears the pending loading state from the desktop header nav link.
 */
const clearHeaderNavLoading = () => {
  if (pendingHeaderNavLinkTimer) {
    window.clearTimeout(pendingHeaderNavLinkTimer);
    pendingHeaderNavLinkTimer = null;
  }

  if (!pendingHeaderNavLink) {
    return;
  }

  pendingHeaderNavLink.classList.remove("header-nav-link-pending");
  pendingHeaderNavLink.removeAttribute("aria-busy");
  pendingHeaderNavLink = null;
};

/**
 * Clears pending loading state from dropdown links with manual spinners.
 */
const clearHeaderDropdownLoading = () => {
  document.querySelectorAll(".header-dropdown-link-pending").forEach((link) => {
    link.classList.remove("header-dropdown-link-pending");
    link.removeAttribute("aria-busy");
  });
};

/**
 * Clears all header loading indicators.
 */
const clearHeaderLoading = () => {
  clearHeaderNavLoading();
  clearHeaderDropdownLoading();
};

/**
 * Restores header interactions after browser or HTMX history navigation. A first
 * pageshow restores nothing, and the sheet may already be open by then.
 * @param {Event} [event] - HTMX historyRestore or pageshow event.
 */
const restoreHeaderState = (event) => {
  if (event?.type !== "pageshow" || event.persisted) {
    resetUserSheet();
  }
  clearHeaderLoading();
  initUserDropdown();
};

/**
 * Clears the loading state for the matching HTMX header nav request.
 * @param {Event} event - HTMX lifecycle event.
 */
const clearHeaderNavLoadingFromHtmx = (event) => {
  const link = getHeaderNavLinkFromEvent(event);
  if (!link || link !== pendingHeaderNavLink) {
    return;
  }

  clearHeaderNavLoading();
};

/**
 * Queues a delayed loading state for a header nav link.
 * @param {Element} link - Header nav link.
 */
const queueHeaderNavLoading = (link) => {
  if (pendingHeaderNavLink === link) {
    return;
  }

  clearHeaderNavLoading();
  pendingHeaderNavLink = link;

  pendingHeaderNavLinkTimer = window.setTimeout(() => {
    if (pendingHeaderNavLink !== link) {
      return;
    }

    link.classList.add("header-nav-link-pending");
    link.setAttribute("aria-busy", "true");
    pendingHeaderNavLinkTimer = null;
  }, headerNavLinkPendingDelayMs);
};

/**
 * Shows a delayed loading state for header nav link clicks.
 * @param {MouseEvent} event - Click event.
 */
const startHeaderNavLoadingFromClick = (event) => {
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

  const link = getHeaderNavLinkFromEvent(event);
  if (!link) {
    return;
  }

  queueHeaderNavLoading(link);
};

/**
 * Shows a delayed loading state on boosted header nav links.
 * @param {Event} event - HTMX beforeRequest event.
 */
const startHeaderNavLoadingFromHtmx = (event) => {
  const link = getHeaderNavLinkFromEvent(event);
  if (!link) {
    return;
  }

  queueHeaderNavLoading(link);
};

/**
 * Returns the sheet's reachable controls. The shared modal targets skip anything
 * under a literal hidden class, which the Desktop version row carries.
 * @param {Element} dropdown - User dropdown.
 * @returns {HTMLElement[]} Rendered links and buttons.
 */
const getUserSheetFocusTargets = (dropdown) =>
  Array.from(dropdown.querySelectorAll("a[href], button:not([disabled])")).filter(
    (target) => target.getClientRects().length > 0,
  );

/**
 * Marks the sheet rows that lead to the current page. The menu is a shared section
 * that cannot know the page, so rows are matched by pathname and dashboard tab. A row
 * without a tab only matches a URL without one, so it never shadows the tab rows.
 * @param {Element} dropdown - User dropdown.
 */
const markCurrentUserSheetRow = (dropdown) => {
  const currentTab = new URLSearchParams(window.location.search).get("tab");

  getUserSheetFocusTargets(dropdown)
    .filter((target) => target.matches('a[role="menuitem"]'))
    .forEach((link) => {
      const url = new URL(link.href);
      const tab = url.searchParams.get("tab");
      if (url.pathname === window.location.pathname && tab === currentTab) {
        link.setAttribute("aria-current", "page");
      }
    });
};

/**
 * Shows or hides the user dropdown and exposes the result on its triggers.
 * @param {Element|null} dropdown - User dropdown.
 * @param {boolean} hidden - Whether the dropdown should be hidden.
 */
const setUserDropdownHidden = (dropdown, hidden) => {
  setElementHidden(dropdown, hidden);
  syncUserMenuExpanded();
};

/**
 * Mirrors the dropdown's visibility on every trigger, so a swapped, restored or
 * stale trigger never announces a state the menu is not in.
 */
const syncUserMenuExpanded = () => {
  const dropdown = getElementById(document, "user-dropdown");
  const expanded = String(Boolean(dropdown) && !isElementHidden(dropdown));
  document.querySelectorAll(userSheetTriggerSelector).forEach((trigger) => {
    trigger.setAttribute("aria-expanded", expanded);
  });
};

/**
 * Removes every sheet marker from the page, whatever module state says.
 */
const clearUserSheetMarkers = () => {
  document.querySelectorAll(userSheetInertSelector).forEach((element) => {
    element.inert = false;
  });
  syncUserMenuExpanded();
  document.querySelectorAll('#user-dropdown [aria-current="page"]').forEach((link) => {
    link.removeAttribute("aria-current");
  });
};

/**
 * Releases what the open sheet holds and leaves the dropdown as it is. Keyed on held
 * state, because a rotation past md must release even though the query is now false.
 */
const releaseUserSheet = () => {
  if (!userSheetOpen) {
    return;
  }

  userSheetDropdown = null;
  userSheetOpen = false;
  userSheetTrigger = null;
  releaseUserSheetGestures?.();
  releaseUserSheetGestures = null;
  userSheetPhoneQuery?.removeEventListener("change", handleUserSheetQueryChange);
  userSheetPhoneQuery = null;
  document.removeEventListener("htmx:beforeHistorySave", resetUserSheet);
  unlockBodyScroll();
  clearUserSheetMarkers();
};

/**
 * Leaves sheet mode when the phone query turns false. The dropdown stays open as
 * the anchored menu.
 * @param {MediaQueryListEvent} event - Query change event.
 */
const handleUserSheetQueryChange = (event) => {
  if (!event.matches) {
    releaseUserSheet();
  }
};

/**
 * Closes the sheet, or the dropdown left open by crossing into phone widths, and
 * returns focus to the trigger that opened it.
 */
const closeUserSheet = () => {
  const dropdown = getElementById(document, "user-dropdown");
  releaseUserSheet();
  setUserDropdownHidden(dropdown, true);
  restoreModalFocus(dropdown);
};

/**
 * Releases a sheet an HTMX swap removed and returns focus, which fell to the body
 * with it. The swap can replace the trigger as well, so its successor takes focus then.
 */
const releaseSwappedUserSheet = () => {
  const dropdown = userSheetDropdown;
  const trigger = userSheetTrigger;
  releaseUserSheet();
  restoreModalFocus(dropdown);
  if (!trigger.isConnected) {
    getElementById(document, trigger.id)?.focus();
  }
};

/**
 * Opens the dropdown as the phone account sheet.
 * @param {HTMLElement|null} trigger - Control that opened the sheet, if any.
 */
const openUserSheet = (trigger) => {
  const dropdown = getElementById(document, "user-dropdown");
  if (!dropdown || !trigger || userSheetOpen) {
    return;
  }

  userSheetDropdown = dropdown;
  userSheetOpen = true;
  userSheetTrigger = trigger;
  setUserDropdownHidden(dropdown, false);
  lockBodyScroll();
  document.querySelectorAll(userSheetInertSelector).forEach((element) => {
    element.inert = true;
  });
  markCurrentUserSheetRow(dropdown);
  focusModal(dropdown, trigger);
  releaseUserSheetGestures = bindSheetGestures(dropdown);
  userSheetPhoneQuery = window.matchMedia(PHONE_MEDIA_QUERY);
  userSheetPhoneQuery.addEventListener("change", handleUserSheetQueryChange);
  document.addEventListener("htmx:beforeHistorySave", resetUserSheet);
};

/**
 * Closes the sheet without moving focus, so open state never survives history.
 * Reads the DOM on phones, because a restored snapshot can show a sheet no flag knows of.
 */
const resetUserSheet = () => {
  if (!userSheetOpen && !isPhoneViewport()) {
    return;
  }

  releaseUserSheet();
  setUserDropdownHidden(getElementById(document, "user-dropdown"), true);
  clearUserSheetMarkers();
};

// Ensures global handlers close the dropdown on outside click or Escape.
const ensureDocumentHandlers = () => {
  if (documentHandlersBound) {
    return;
  }

  const handleDocumentClick = (event) => {
    const button = getElementById(document, "user-dropdown-button");
    const dropdown = getElementById(document, "user-dropdown");

    if (!button || !dropdown) {
      return;
    }

    const trigger = closestElement(event.target, userSheetTriggerSelector);
    const clickedDropdown = dropdown.contains(event.target);

    if (!trigger && !clickedDropdown) {
      // Hide if the click did not originate inside the dropdown or trigger.
      if (userSheetOpen) {
        closeUserSheet();
      } else {
        setUserDropdownHidden(dropdown, true);
      }
      return;
    }

    // The scrim is the dropdown itself, whose margins keep the anchored menu open.
    const clickedSheetClose =
      event.target === dropdown || Boolean(closestElement(event.target, userSheetCloseSelector));
    if (clickedSheetClose && (userSheetOpen || isPhoneViewport())) {
      closeUserSheet();
    }
  };

  const handleKeydown = (event) => {
    if (userSheetOpen && event.key === "Tab") {
      const dropdown = getElementById(document, "user-dropdown");
      trapModalFocus(event, dropdown, getUserSheetFocusTargets(dropdown));
      return;
    }

    if (!isEscapeEvent(event)) {
      return;
    }

    const button = getElementById(document, "user-dropdown-button");
    const dropdown = getElementById(document, "user-dropdown");

    if (!button || !dropdown || isElementHidden(dropdown)) {
      return;
    }

    if (userSheetOpen) {
      closeUserSheet();
      return;
    }

    setUserDropdownHidden(dropdown, true);
    button.focus();
  };

  document.addEventListener("click", handleDocumentClick);
  document.addEventListener("click", startHeaderNavLoadingFromClick);
  document.addEventListener("keydown", handleKeydown);

  documentHandlersBound = true;
};

/**
 * Determines if a swap should reset scroll for dashboard pages.
 * @param {Event} event - HTMX afterSwap event.
 * @returns {boolean} True when the swap targets dashboard content.
 */
const shouldResetDashboardScroll = (event) => {
  if (!event) {
    return false;
  }

  const swapTarget = event.detail?.target || event.target;
  if (!swapTarget) {
    return false;
  }

  const path = window.location?.pathname || "";
  if (!path.startsWith("/dashboard/")) {
    return false;
  }

  return swapTarget === document.body || swapTarget.id === "dashboard-content";
};

/**
 * Scrolls to the top after dashboard swaps.
 * @param {Event} event - HTMX afterSwap event.
 */
const scrollToTopOnDashboardSwap = (event) => {
  if (!shouldResetDashboardScroll(event) || typeof window.scrollTo !== "function") {
    return;
  }

  window.scrollTo({ top: 0, behavior: "auto" });
};

// Subscribes to HTMX lifecycle hooks once for history and swap events.
const bindLifecycleListeners = () => {
  if (lifecycleListenersBound) {
    return;
  }

  document.addEventListener("htmx:historyRestore", restoreHeaderState);
  document.addEventListener("htmx:beforeRequest", startHeaderNavLoadingFromHtmx);
  document.addEventListener("htmx:afterRequest", clearHeaderNavLoadingFromHtmx);
  document.addEventListener("htmx:afterSwap", initUserDropdown);
  document.addEventListener("htmx:afterSwap", scrollToTopOnDashboardSwap);
  // A swapped menu keeps the old menu's class until settling, so sync again then.
  document.addEventListener("htmx:afterSettle", syncUserMenuExpanded);
  window.addEventListener("pageshow", restoreHeaderState);

  lifecycleListenersBound = true;
};

// Toggles dropdown visibility when a trigger is clicked, as a sheet on phones.
const toggleDropdownVisibility = (event) => {
  const dropdown = getElementById(document, "user-dropdown");
  if (!dropdown) {
    return;
  }

  if (userSheetOpen) {
    closeUserSheet();
  } else if (isPhoneViewport()) {
    openUserSheet(closestElement(event.target, userSheetTriggerSelector));
  } else {
    setUserDropdownHidden(dropdown, !isElementHidden(dropdown));
  }
};

// Public initializer for the user dropdown interactions.
export const initUserDropdown = () => {
  ensureDocumentHandlers();
  bindLifecycleListeners();
  // Swapped, restored and bfcache triggers can carry a stale expanded state.
  syncUserMenuExpanded();

  const button = getElementById(document, "user-dropdown-button");
  const dropdown = getElementById(document, "user-dropdown");

  // A swap replaced the open sheet, so what it held has nothing left to close it. The new
  // node's class cannot tell, because HTMX keeps the old class on it until settling.
  if (userSheetOpen && !userSheetDropdown.isConnected) {
    releaseSwappedUserSheet();
  }

  if (!button || !dropdown) {
    return;
  }

  if (button.__ocgDropdownInitialized) {
    return;
  }

  button.addEventListener("click", toggleDropdownVisibility);
  button.__ocgDropdownInitialized = true;

  if (!dropdown.__ocgCloseOnLinkBound) {
    dropdown.addEventListener(
      "click",
      (event) => {
        const link = closestElement(event.target, "a");
        if (!link) {
          return;
        }
        // Close immediately unless the link shows a loading spinner.
        if (link.querySelector(".hx-spinner")) {
          if (link.getAttribute("hx-boost") === "false") {
            link.classList.add("header-dropdown-link-pending");
            link.setAttribute("aria-busy", "true");
          }
          return;
        }
        if (userSheetOpen) {
          closeUserSheet();
        } else {
          setUserDropdownHidden(dropdown, true);
        }
      },
      true,
    );
    dropdown.__ocgCloseOnLinkBound = true;
  }
};

initUserDropdown();
