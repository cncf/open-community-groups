import { showConfirmAlert } from "/static/js/common/alerts.js";

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
 * Builds a stable snapshot for all tracked forms.
 * @param {HTMLFormElement[]} forms Tracked forms.
 * @returns {string} URL-like snapshot payload.
 */
const buildFormsSnapshot = (forms) => {
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
 * Sets up pending changes visibility and optional cancel confirmation.
 * @param {Object} config Init configuration.
 * @param {string} config.alertId Alert element id.
 * @param {string[]} config.formIds Form ids included in the pending snapshot.
 * @param {string} [config.cancelButtonId] Cancel button id to guard.
 * @param {string} [config.confirmMessage] Confirmation text shown on cancel.
 * @param {string} [config.confirmText] Confirmation button label.
 * @returns {{hasPendingChanges: () => boolean, refresh: () => void}} API.
 */
export const initializePendingChangesAlert = ({
  alertId,
  formIds,
  cancelButtonId = "",
  confirmMessage = "",
  confirmText = "Leave",
}) => {
  const pendingChangesAlert = document.getElementById(alertId);
  const trackedForms = (formIds || []).map((formId) => document.getElementById(formId)).filter(Boolean);
  const cancelButton = cancelButtonId ? document.getElementById(cancelButtonId) : null;

  let initialFormSnapshot = "";
  let hasPendingChanges = false;
  let pendingChangesReady = false;
  let pendingChangesAnimationFrame = null;

  const setPendingChangesState = (dirty) => {
    hasPendingChanges = dirty;
    if (pendingChangesAlert) {
      pendingChangesAlert.classList.toggle("hidden", !dirty);
    }
  };

  const refreshPendingChangesState = () => {
    if (!pendingChangesReady) {
      return;
    }
    const currentSnapshot = buildFormsSnapshot(trackedForms);
    setPendingChangesState(currentSnapshot !== initialFormSnapshot);
  };

  const schedulePendingChangesRefresh = () => {
    if (pendingChangesAnimationFrame) {
      return;
    }
    pendingChangesAnimationFrame = requestAnimationFrame(() => {
      pendingChangesAnimationFrame = null;
      refreshPendingChangesState();
    });
  };

  if (pendingChangesAlert && trackedForms.length > 0) {
    const handleTrackedEvent = (event) => {
      if (event.target instanceof Node) {
        schedulePendingChangesRefresh();
      }
    };

    trackedForms.forEach((form) => {
      form.addEventListener("input", handleTrackedEvent, true);
      form.addEventListener("change", handleTrackedEvent, true);
      form.addEventListener("click", handleTrackedEvent, true);
    });

    const observer = new MutationObserver((mutations) => {
      const shouldRefresh = mutations.some((mutation) =>
        trackedForms.some((form) => form.contains(mutation.target)),
      );
      if (shouldRefresh) {
        schedulePendingChangesRefresh();
      }
    });

    trackedForms.forEach((form) => {
      observer.observe(form, {
        childList: true,
        subtree: true,
        attributes: true,
        characterData: true,
      });
    });

    requestAnimationFrame(() => {
      initialFormSnapshot = buildFormsSnapshot(trackedForms);
      pendingChangesReady = true;
      refreshPendingChangesState();
    });
  }

  if (cancelButton && confirmMessage) {
    cancelButton.addEventListener("click", (event) => {
      if (!hasPendingChanges) {
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      showConfirmAlert(confirmMessage, cancelButton.id, confirmText);
    });
  }

  return {
    hasPendingChanges: () => hasPendingChanges,
    refresh: refreshPendingChangesState,
  };
};
