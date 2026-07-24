import { getCommonAlertOptions, showErrorAlert, showSuccessAlert } from "/static/js/common/alerts.js";
import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

const ROOT_SELECTOR = "[data-group-badges]";
const READY_KEY = "groupBadgesReady";

const request = async (url, options) => {
  const response = await ocgFetch(url, options);
  if (!response.ok) {
    const message = (await response.text()).trim();
    throw new Error(message || "The badge change could not be saved.");
  }
  return response;
};

const setRefreshPane = (pane) => {
  const dashboard = document.getElementById("dashboard-content");
  if (pane && dashboard) {
    const url = new URL(dashboard.getAttribute("hx-get"), window.location.origin);
    url.searchParams.set("pane", pane);
    dashboard.setAttribute("hx-get", `${url.pathname}${url.search}`);
  }
};

const refresh = (pane = "") => {
  const dashboard = document.getElementById("dashboard-content");
  setRefreshPane(pane);
  window.htmx?.trigger(dashboard || document.body, "refresh-group-dashboard-table");
};

const setPane = (root, requestedPane, { focus = false } = {}) => {
  const buttons = [...root.querySelectorAll("[data-badge-pane-button]")];
  const pane = requestedPane;
  root.querySelectorAll("[data-content]").forEach((section) => {
    section.hidden = section.dataset.content !== pane;
  });
  buttons.forEach((button) => {
    const selected = button.dataset.badgePaneButton === pane;
    button.setAttribute("aria-selected", String(selected));
    button.tabIndex = selected ? 0 : -1;
    if (selected && focus) {
      button.focus();
    }
  });
  const select = root.querySelector("[data-badge-pane-select]");
  if (select) {
    select.value = pane;
  }
  return pane;
};

const moveTabFocus = (root, current, key) => {
  const buttons = [...root.querySelectorAll("[data-badge-pane-button]")];
  const currentIndex = buttons.indexOf(current);
  if (currentIndex < 0) {
    return;
  }
  let nextIndex;
  if (key === "Home") {
    nextIndex = 0;
  } else if (key === "End") {
    nextIndex = buttons.length - 1;
  } else if (key === "ArrowDown" || key === "ArrowRight") {
    nextIndex = (currentIndex + 1) % buttons.length;
  } else if (key === "ArrowUp" || key === "ArrowLeft") {
    nextIndex = (currentIndex - 1 + buttons.length) % buttons.length;
  } else {
    return;
  }
  setPane(root, buttons[nextIndex].dataset.badgePaneButton, { focus: true });
};

const revokeAward = async (button) => {
  if (button.disabled || button.dataset.revokePending === "true") {
    return;
  }
  button.dataset.revokePending = "true";
  const result = await Swal.fire({
    title: `Permanently revoke ${button.dataset.name}?`,
    html: "<p>This cannot be undone. The credential remains public, but it will permanently verify as revoked.</p>",
    input: "textarea",
    inputLabel: "Internal reason",
    inputPlaceholder: "Required; visible only to authorized group managers",
    inputAttributes: { maxlength: "1000" },
    showCancelButton: true,
    confirmButtonText: "Permanently revoke",
    focusCancel: true,
    preConfirm: (value) => {
      if (!value?.trim()) {
        Swal.showValidationMessage("Enter an internal revocation reason.");
        return false;
      }
      return value.trim();
    },
    ...getCommonAlertOptions(),
  });
  if (!result.isConfirmed) {
    delete button.dataset.revokePending;
    button.focus();
    return;
  }
  button.disabled = true;
  try {
    await request(button.dataset.endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ reason: result.value }),
    });
    showSuccessAlert("Credential permanently revoked.");
    refresh("awards");
  } catch (error) {
    button.disabled = false;
    delete button.dataset.revokePending;
    showErrorAlert(error.message, false, true);
  }
};

const prepareArtworkForm = (form) => {
  const field = form.querySelector('image-field[target="badge"]');
  const fileName = field?.value?.split("/").filter(Boolean).pop();
  if (!fileName) {
    showErrorAlert("Upload badge artwork before adding it to the gallery.");
    return false;
  }
  form.querySelector("[data-artwork-file-name]").value = fileName;
  return true;
};

export const initializeGroupBadges = (root) => {
  if (!markDatasetReady(root, READY_KEY)) {
    return;
  }
  const initialPane = root.dataset.initialPane || "definitions";
  setPane(root, initialPane);

  root.addEventListener("click", (event) => {
    const refreshOwner = event.target.closest?.("[data-badge-refresh-pane]");
    if (refreshOwner) {
      setRefreshPane(refreshOwner.dataset.badgeRefreshPane);
    }
    const paneButton = event.target.closest?.("[data-badge-pane-button]");
    if (paneButton) {
      setPane(root, paneButton.dataset.badgePaneButton);
      return;
    }
    const opener = event.target.closest?.("[data-badge-dialog-open]");
    if (opener) {
      document.getElementById(opener.dataset.badgeDialogOpen)?.showModal();
      return;
    }
    const closer = event.target.closest?.("[data-badge-dialog-close]");
    if (closer) {
      closer.closest("dialog")?.close();
      return;
    }
    const revoke = event.target.closest?.("[data-badge-revoke]");
    if (revoke) {
      revokeAward(revoke);
    }
  });
  root.addEventListener("keydown", (event) => {
    const paneButton = event.target.closest?.("[data-badge-pane-button]");
    if (!paneButton) {
      return;
    }
    if (["ArrowDown", "ArrowLeft", "ArrowRight", "ArrowUp", "End", "Home"].includes(event.key)) {
      event.preventDefault();
      moveTabFocus(root, paneButton, event.key);
    }
  });
  root.querySelector("[data-badge-pane-select]")?.addEventListener("change", (event) => {
    setPane(root, event.target.value);
  });
  root.addEventListener("submit", (event) => {
    const pane = event.target.dataset.badgeRefreshPane;
    if (pane) {
      setRefreshPane(pane);
    }
    if (event.target.matches("[data-artwork-form]") && !prepareArtworkForm(event.target)) {
      event.preventDefault();
      event.stopPropagation();
    }
  });
};

initializeOnReadyAndHtmxLoad((root) => {
  if (root.matches?.(ROOT_SELECTOR)) {
    initializeGroupBadges(root);
  }
  root.querySelectorAll?.(ROOT_SELECTOR).forEach(initializeGroupBadges);
});
