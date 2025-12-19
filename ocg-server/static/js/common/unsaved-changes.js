/**
 * Unsaved changes warning module for forms and navigation.
 * Auto-wires all forms and intercepts navigation/logout for dirty forms.
 * @module unsaved-changes
 */

import { navigateWithHtmx } from "/static/js/common/common.js";
import { showConfirmDialog } from "/static/js/common/alerts.js";

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const FORM_SELECTOR = "form";
const LOGOUT_PATH = "/log-out";

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

const formSnapshots = new WeakMap();
const dirtyForms = new Set();
const scheduledChecks = new WeakMap();

let bypassNextNavigation = false;
let promptInFlight = null;
let pendingNavigation = null;

// -----------------------------------------------------------------------------
// Alert helpers
// -----------------------------------------------------------------------------

/**
 * Shows a confirmation dialog for unsaved changes.
 * @param {Object} options - Alert options.
 * @param {string} options.title - Title for the dialog.
 * @param {string} options.message - Body copy for the dialog.
 * @param {string} options.confirmText - Confirm button label.
 * @param {Function} onConfirm - Navigation callback to execute on confirm.
 */
const showUnsavedChangesDialog = ({ title, message, confirmText }, onConfirm) => {
  pendingNavigation = onConfirm;

  if (promptInFlight) {
    return;
  }

  promptInFlight = showConfirmDialog({
    title,
    message,
    confirmText,
    cancelText: "Stay",
  })
    .then((confirmed) => {
      if (!confirmed) {
        pendingNavigation = null;
        return;
      }

      const nextNavigation = pendingNavigation;
      pendingNavigation = null;
      if (typeof nextNavigation === "function") {
        nextNavigation();
      }
    })
    .finally(() => {
      promptInFlight = null;
    });
};

/**
 * Builds dialog copy for navigation or logout warnings.
 * @param {boolean} isLogout - True when warning about logout.
 * @returns {{title: string, message: string, confirmText: string}}
 */
const buildWarningCopy = (isLogout) => {
  if (isLogout) {
    return {
      title: "Unsaved Changes",
      message: "You have unsaved changes. Logging out will discard them.",
      confirmText: "Log out",
    };
  }

  return {
    title: "Unsaved Changes",
    message: "You have unsaved changes. Leaving this page will discard them.",
    confirmText: "Leave",
  };
};

// -----------------------------------------------------------------------------
// Form tracking
// -----------------------------------------------------------------------------

/**
 * Determines whether a form field should be tracked.
 * @param {HTMLElement} field - Field element.
 * @returns {boolean} True if field should be tracked.
 */
const isTrackableField = (field) => {
  if (
    !(
      field instanceof HTMLInputElement ||
      field instanceof HTMLSelectElement ||
      field instanceof HTMLTextAreaElement
    )
  ) {
    return false;
  }

  if (field.disabled) {
    return false;
  }

  if (field instanceof HTMLInputElement) {
    const ignoredTypes = ["submit", "reset", "button", "image"];
    return !ignoredTypes.includes(field.type);
  }

  return true;
};

/**
 * Builds a serialized snapshot for a field.
 * @param {HTMLElement} field - Field element.
 * @returns {Object} Snapshot of field state.
 */
const serializeField = (field) => {
  const base = {
    name: field.name ?? "",
    id: field.id ?? "",
    type: field.type ?? field.tagName.toLowerCase(),
  };

  if (field instanceof HTMLInputElement) {
    if (field.type === "checkbox" || field.type === "radio") {
      return { ...base, checked: field.checked, value: field.value };
    }

    if (field.type === "file") {
      const files = Array.from(field.files ?? []).map((file) => file.name);
      return { ...base, files };
    }

    return { ...base, value: field.value };
  }

  if (field instanceof HTMLSelectElement) {
    if (field.multiple) {
      const values = Array.from(field.selectedOptions).map((option) => option.value);
      return { ...base, multiple: true, value: values };
    }

    return { ...base, value: field.value };
  }

  return { ...base, value: field.value };
};

/**
 * Serializes form state into a stable string for comparison.
 * @param {HTMLFormElement} form - Form element.
 * @returns {string} Serialized snapshot.
 */
const serializeForm = (form) => {
  const fields = Array.from(form.elements ?? []).filter(isTrackableField);
  const snapshot = fields.map((field) => serializeField(field));
  return JSON.stringify(snapshot);
};

/**
 * Marks a form as clean using its current snapshot.
 * @param {HTMLFormElement} form - Form element.
 */
const markFormClean = (form) => {
  formSnapshots.set(form, serializeForm(form));
  dirtyForms.delete(form);
};

/**
 * Updates dirty state for a form based on current snapshot.
 * @param {HTMLFormElement} form - Form element.
 */
const updateDirtyState = (form) => {
  const baseline = formSnapshots.get(form);
  const current = serializeForm(form);

  if (baseline === current) {
    dirtyForms.delete(form);
    return;
  }

  dirtyForms.add(form);
};

/**
 * Schedules a dirty check for a form on the next frame.
 * @param {HTMLFormElement} form - Form element.
 */
const scheduleDirtyCheck = (form) => {
  if (scheduledChecks.get(form)) {
    return;
  }

  scheduledChecks.set(form, true);

  const runCheck = () => {
    scheduledChecks.delete(form);
    updateDirtyState(form);
  };

  if (typeof requestAnimationFrame === "function") {
    requestAnimationFrame(runCheck);
  } else {
    setTimeout(runCheck, 0);
  }
};

/**
 * Determines whether any tracked form is dirty.
 * @returns {boolean} True if any dirty form exists.
 */
const hasDirtyForms = () => {
  dirtyForms.forEach((form) => {
    if (!document.contains(form)) {
      dirtyForms.delete(form);
      formSnapshots.delete(form);
    }
  });

  return dirtyForms.size > 0;
};

/**
 * Wires unsaved change tracking to a form.
 * @param {HTMLFormElement} form - Form element.
 */
const wireForm = (form) => {
  if (form.dataset.unsavedReady === "true") {
    return;
  }

  form.dataset.unsavedReady = "true";
  markFormClean(form);

  const handleFieldEvent = (event) => {
    if (!isTrackableField(event.target)) {
      return;
    }
    scheduleDirtyCheck(form);
  };

  form.addEventListener("input", handleFieldEvent);
  form.addEventListener("change", handleFieldEvent);

  form.addEventListener("reset", () => {
    if (typeof requestAnimationFrame === "function") {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => markFormClean(form));
      });
    } else {
      setTimeout(() => markFormClean(form), 0);
    }
  });

  form.addEventListener("submit", (event) => {
    if (!event.defaultPrevented) {
      markFormClean(form);
    }
  });

  form.addEventListener("htmx:afterRequest", (event) => {
    const xhr = event.detail?.xhr;
    if (xhr && xhr.status >= 200 && xhr.status < 300) {
      markFormClean(form);
    }
  });
};

// -----------------------------------------------------------------------------
// Navigation guards
// -----------------------------------------------------------------------------

/**
 * Detects if a click should be ignored for navigation checks.
 * @param {MouseEvent} event - Click event.
 * @param {HTMLAnchorElement} anchor - Anchor element.
 * @returns {boolean} True if click should be ignored.
 */
const shouldIgnoreClick = (event, anchor) => {
  if (event.defaultPrevented) {
    return true;
  }

  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
    return true;
  }

  if (anchor.hasAttribute("download")) {
    return true;
  }

  const target = anchor.getAttribute("target");
  if (target && target !== "_self") {
    return true;
  }

  const rawHref = anchor.getAttribute("href") ?? "";
  if (!rawHref || rawHref.startsWith("#")) {
    return true;
  }

  if (rawHref.startsWith("mailto:") || rawHref.startsWith("tel:")) {
    return true;
  }

  if (rawHref.startsWith("javascript:")) {
    return true;
  }

  const url = new URL(anchor.href, window.location.href);
  const samePage =
    url.origin === window.location.origin &&
    url.pathname === window.location.pathname &&
    url.search === window.location.search;
  if (samePage) {
    return true;
  }

  return false;
};

/**
 * Determines whether an anchor is handled by HTMX.
 * @param {HTMLAnchorElement} anchor - Anchor element.
 * @returns {boolean} True if anchor triggers HTMX.
 */
const isHtmxAnchor = (anchor) => {
  const boostValue = anchor.getAttribute("hx-boost") ?? anchor.getAttribute("data-hx-boost") ?? "";
  if (boostValue && boostValue.toLowerCase() === "false") {
    return false;
  }

  const htmxAttributes = [
    "hx-boost",
    "data-hx-boost",
    "hx-get",
    "data-hx-get",
    "hx-post",
    "data-hx-post",
    "hx-put",
    "data-hx-put",
    "hx-patch",
    "data-hx-patch",
    "hx-delete",
    "data-hx-delete",
  ];

  return htmxAttributes.some((attribute) => anchor.hasAttribute(attribute));
};

/**
 * Determines whether a URL matches the logout path.
 * @param {string} url - URL to check.
 * @returns {boolean} True if logout path.
 */
const isLogoutUrl = (url) => {
  if (!url) {
    return false;
  }
  const resolved = new URL(url, window.location.href);
  return resolved.pathname === LOGOUT_PATH;
};

/**
 * Checks if an HTMX request represents navigation.
 * @param {Event} event - HTMX event.
 * @returns {boolean} True if request is navigation.
 */
const isHtmxNavigationRequest = (event) => {
  const detail = event.detail ?? {};
  const requestConfig = detail.requestConfig ?? {};
  const element = detail.elt ?? event.target;

  if (element instanceof HTMLFormElement) {
    return false;
  }

  const verb = (requestConfig.verb ?? detail.verb ?? "").toString().toLowerCase();
  if (verb && verb !== "get") {
    return false;
  }

  const anchor = element?.closest?.("a");
  const boosted = Boolean(requestConfig.boosted ?? detail.boosted);
  const hasBoost = anchor?.getAttribute("hx-boost") === "true" || anchor?.dataset?.hxBoost === "true";
  const target = requestConfig.target ?? detail.target ?? anchor?.getAttribute("hx-target");
  const targetIsBody = target === "body" || target === document.body;

  return boosted || hasBoost || targetIsBody;
};

/**
 * Builds a navigation function from an HTMX event.
 * @param {Event} event - HTMX event.
 * @returns {{path: string, navigate: Function}} Navigation info and callback.
 */
const buildHtmxNavigation = (event) => {
  const detail = event.detail ?? {};
  const element = detail.elt ?? event.target;
  const anchor = element?.closest?.("a");
  const path = detail.path ?? detail.requestConfig?.path ?? anchor?.href ?? "";

  const navigate = () => {
    bypassNextNavigation = true;

    if (anchor && typeof anchor.click === "function") {
      anchor.click();
      return;
    }

    if (path) {
      navigateWithHtmx(path);
    }
  };

  return { path, navigate };
};

/**
 * Handles HTMX navigation checks.
 * @param {Event} event - HTMX before request event.
 */
const handleHtmxBeforeRequest = (event) => {
  if (bypassNextNavigation) {
    bypassNextNavigation = false;
    return;
  }

  if (!hasDirtyForms()) {
    return;
  }

  if (!isHtmxNavigationRequest(event)) {
    return;
  }

  event.preventDefault();

  const { path, navigate } = buildHtmxNavigation(event);
  const warningCopy = buildWarningCopy(isLogoutUrl(path));

  showUnsavedChangesDialog(warningCopy, navigate);
};

/**
 * Handles standard anchor navigation checks.
 * @param {MouseEvent} event - Click event.
 */
const handleDocumentClick = (event) => {
  const anchor = event.target.closest?.("a");
  if (!anchor) {
    return;
  }

  if (shouldIgnoreClick(event, anchor)) {
    return;
  }

  if (isHtmxAnchor(anchor)) {
    return;
  }

  if (!hasDirtyForms()) {
    return;
  }

  event.preventDefault();

  const warningCopy = buildWarningCopy(isLogoutUrl(anchor.href));
  showUnsavedChangesDialog(warningCopy, () => {
    window.location.assign(anchor.href);
  });
};

/**
 * Handles browser-level unload navigation warnings.
 * @param {BeforeUnloadEvent} event - Before unload event.
 */
const handleBeforeUnload = (event) => {
  if (!hasDirtyForms()) {
    return;
  }

  event.preventDefault();
  event.returnValue = "";
};

// -----------------------------------------------------------------------------
// Initialization
// -----------------------------------------------------------------------------

/**
 * Initializes unsaved changes tracking and navigation guards.
 */
const init = () => {
  document.querySelectorAll(FORM_SELECTOR).forEach(wireForm);

  if (window.htmx && typeof htmx.onLoad === "function") {
    htmx.onLoad((element) => {
      if (!element) {
        return;
      }
      if (element instanceof HTMLFormElement) {
        wireForm(element);
      }
      element.querySelectorAll?.(FORM_SELECTOR).forEach(wireForm);
    });
  }

  document.body?.addEventListener("htmx:beforeRequest", handleHtmxBeforeRequest);
  document.addEventListener("click", handleDocumentClick, true);
  window.addEventListener("beforeunload", handleBeforeUnload);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
