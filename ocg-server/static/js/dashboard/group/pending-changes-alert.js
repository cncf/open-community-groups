import { showConfirmAlert } from "/static/js/common/alerts.js";
import { getElementById, setElementHidden } from "/static/js/common/dom.js";

// Attribute marking tracked forms with unsaved changes, read by the deployment refresh guard.
const PENDING_CHANGES_DIRTY_ATTRIBUTE = "data-pending-changes-dirty";

/**
 * Serializes a form field value for deterministic snapshot comparisons.
 * @param {FormDataEntryValue} value Field value from FormData.
 * @returns {string} Serialized value.
 */
const serializeFormDataValue = (value) => {
  if (value instanceof File) {
    return `file:${value.name}:${value.size}:${value.lastModified}`;
  }
  return String(value ?? "");
};

/**
 * Builds a deterministic key for form data entry comparisons.
 * @param {string} name Field name.
 * @param {FormDataEntryValue} value Field value.
 * @returns {string} Deterministic entry key.
 */
const buildEntryKey = (name, value) => `${name}\u0000${serializeFormDataValue(value)}`;

/**
 * Collects successful form entries from a control.
 * @param {HTMLElement} control Form control element.
 * @returns {Array<[string, FormDataEntryValue]>} Successful entries.
 */
const collectControlEntries = (control) => {
  if (!(control instanceof HTMLElement)) {
    return [];
  }

  if ("disabled" in control && control.disabled) {
    return [];
  }

  if (!("name" in control) || !control.name) {
    return [];
  }

  if (control instanceof HTMLInputElement) {
    const type = (control.type || "").toLowerCase();
    if (type === "radio" || type === "checkbox") {
      return control.checked ? [[control.name, control.value]] : [];
    }
    if (type === "file") {
      const files = Array.from(control.files || []);
      return files.map((file) => [control.name, file]);
    }
    if (type === "submit" || type === "button" || type === "reset" || type === "image") {
      return [];
    }
    return [[control.name, control.value]];
  }

  if (control instanceof HTMLTextAreaElement) {
    return [[control.name, control.value]];
  }

  if (control instanceof HTMLSelectElement) {
    if (control.multiple) {
      return Array.from(control.selectedOptions).map((option) => [control.name, option.value]);
    }
    return [[control.name, control.value]];
  }

  return [];
};

/**
 * Collects entries from controls marked to be ignored in pending-changes snapshots.
 * @param {HTMLFormElement} form Form to scan.
 * @returns {Map<string, number>} Entry key -> occurrences.
 */
const collectIgnoredEntries = (form) => {
  const ignoredCounts = new Map();
  const ignoredContainers = form.querySelectorAll("[data-pending-changes-ignore]");

  ignoredContainers.forEach((container) => {
    container.querySelectorAll("input, select, textarea").forEach((control) => {
      collectControlEntries(control).forEach(([name, value]) => {
        const key = buildEntryKey(name, value);
        ignoredCounts.set(key, (ignoredCounts.get(key) || 0) + 1);
      });
    });
  });

  return ignoredCounts;
};

/**
 * Sets up pending changes visibility and optional cancel confirmation.
 * @param {Object} config Init configuration.
 * @param {string} config.alertId Alert element id.
 * @param {string[]} config.formIds Form ids included in the pending snapshot.
 * @param {string} [config.cancelButtonId] Cancel button id to guard.
 * @param {string} [config.confirmMessage] Confirmation text shown on cancel.
 * @param {string} [config.confirmText] Confirmation button label.
 * @param {Element|null} [config.guardRoot] Root delegating the confirmation to
 * matching triggers, including triggers rendered after initialization.
 * @param {string} [config.guardSelector] Selector of triggers guarded within
 * the guard root. Matching triggers need an id and an htmx `confirmed` trigger.
 * @returns {{hasPendingChanges: () => boolean, refresh: () => void}} API.
 */
export const initializePendingChangesAlert = ({
  alertId,
  formIds,
  cancelButtonId = "",
  confirmMessage = "",
  confirmText = "Leave",
  guardRoot = null,
  guardSelector = "",
}) => {
  const pendingChangesAlert = getElementById(document, alertId);
  const trackedForms = (formIds || []).map((formId) => getElementById(document, formId)).filter(Boolean);
  const cancelButton = cancelButtonId ? getElementById(document, cancelButtonId) : null;

  const tracker =
    pendingChangesAlert && trackedForms.length > 0
      ? trackFormChanges({
          forms: trackedForms,
          onCheck: (dirty) => setElementHidden(pendingChangesAlert, !dirty),
        })
      : null;
  const hasPendingChanges = () => tracker?.isDirty() ?? false;

  if (cancelButton && confirmMessage) {
    cancelButton.addEventListener("click", (event) => {
      if (!hasPendingChanges()) {
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      showConfirmAlert(confirmMessage, cancelButton.id, confirmText);
    });
  }

  if (guardRoot && guardSelector && confirmMessage) {
    // Capture the click before HTMX handles it on the trigger itself
    guardRoot.addEventListener(
      "click",
      (event) => {
        const trigger = event.target instanceof Element ? event.target.closest(guardSelector) : null;
        if (!trigger?.id || !guardRoot.contains(trigger) || !hasPendingChanges()) {
          return;
        }
        event.preventDefault();
        event.stopImmediatePropagation();
        showConfirmAlert(confirmMessage, trigger.id, confirmText);
      },
      { capture: true },
    );
  }

  return {
    hasPendingChanges,
    refresh: () => tracker?.refresh(),
  };
};

/**
 * Builds a stable snapshot for all tracked forms.
 * @param {HTMLFormElement[]} forms Tracked forms.
 * @returns {string} URL-like snapshot payload.
 */
export const buildFormsSnapshot = (forms) => {
  const entries = [];
  forms.forEach((form) => {
    const ignoredEntries = collectIgnoredEntries(form);
    const formData = new FormData(form);
    for (const [name, value] of formData.entries()) {
      const ignoredKey = buildEntryKey(name, value);
      const ignoredCount = ignoredEntries.get(ignoredKey) || 0;
      if (ignoredCount > 0) {
        ignoredEntries.set(ignoredKey, ignoredCount - 1);
        continue;
      }
      entries.push([`${form.id}:${name}`, serializeFormDataValue(value)]);
    }
  });

  entries.sort(([leftKey, leftValue], [rightKey, rightValue]) => {
    if (leftKey === rightKey) {
      return leftValue.localeCompare(rightValue);
    }
    return leftKey.localeCompare(rightKey);
  });

  return entries.map(([name, value]) => `${encodeURIComponent(name)}=${encodeURIComponent(value)}`).join("&");
};

/**
 * Tracker of the unsaved changes of one or more forms.
 * @typedef {object} FormChangesTracker
 * @property {() => void} destroy Stops watching the forms and drops the pending check.
 * @property {() => void} flush Runs the pending check right away.
 * @property {() => boolean} isDirty Returns the result of the last check.
 * @property {() => void} refresh Checks the forms right away.
 * @property {(baseline?: string) => void} setBaseline Takes a snapshot, the
 * current values by default, as the saved state and checks the forms.
 * @property {() => string} snapshot Returns the snapshot of the current values.
 */

/**
 * Tracks whether forms differ from their saved values. The baseline is taken
 * on the next animation frame, or once `ready` resolves. Later input, change,
 * click and field mutations schedule one check per animation frame, and dirty
 * forms are marked with the `data-pending-changes-dirty` attribute.
 * @param {object} config Tracker configuration.
 * @param {HTMLFormElement[]} config.forms Tracked forms.
 * @param {(dirty: boolean) => void} [config.onCheck] Called with the result of each check.
 * @param {() => void} [config.onCheckScheduled] Called when a check is scheduled.
 * @param {Promise<unknown>|null} [config.ready] Resolves once the forms render
 * the values the baseline is taken from.
 * @returns {FormChangesTracker} Tracker API.
 */
export const trackFormChanges = ({
  forms,
  onCheck = () => {},
  onCheckScheduled = () => {},
  ready = null,
}) => {
  let baseline = "";
  let baselineReady = false;
  let destroyed = false;
  let dirty = false;
  let frame = null;

  const snapshot = () => buildFormsSnapshot(forms);

  const cancel = () => {
    if (frame === null) {
      return;
    }
    cancelAnimationFrame(frame);
    frame = null;
  };

  const refresh = () => {
    cancel();
    if (destroyed || !baselineReady) {
      return;
    }
    dirty = snapshot() !== baseline;
    forms.forEach((form) => form.toggleAttribute(PENDING_CHANGES_DIRTY_ATTRIBUTE, dirty));
    onCheck(dirty);
  };

  const schedule = () => {
    if (destroyed || !baselineReady || frame !== null) {
      return;
    }
    onCheckScheduled();
    frame = requestAnimationFrame(() => {
      frame = null;
      refresh();
    });
  };

  const setBaseline = (value = snapshot()) => {
    if (destroyed) {
      return;
    }
    baseline = value;
    baselineReady = true;
    refresh();
  };

  // Watch the form fields, ignoring the dirty marker set by the checks
  const observer = new MutationObserver((mutations) => {
    if (mutations.some((mutation) => mutation.attributeName !== PENDING_CHANGES_DIRTY_ATTRIBUTE)) {
      schedule();
    }
  });
  forms.forEach((form) => {
    form.addEventListener("input", schedule, true);
    form.addEventListener("change", schedule, true);
    form.addEventListener("click", schedule, true);
    observer.observe(form, {
      attributes: true,
      characterData: true,
      childList: true,
      subtree: true,
    });
  });

  // Take the baseline once the forms render their values
  const takeBaseline = () => setBaseline();
  if (ready) {
    ready.then(takeBaseline);
  } else {
    requestAnimationFrame(takeBaseline);
  }

  return {
    destroy: () => {
      destroyed = true;
      cancel();
      observer.disconnect();
      forms.forEach((form) => {
        form.removeEventListener("input", schedule, true);
        form.removeEventListener("change", schedule, true);
        form.removeEventListener("click", schedule, true);
        form.removeAttribute(PENDING_CHANGES_DIRTY_ATTRIBUTE);
      });
    },
    flush: () => {
      if (frame !== null) {
        refresh();
      }
    },
    isDirty: () => dirty,
    refresh,
    setBaseline,
    snapshot,
  };
};
