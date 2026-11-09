import { showErrorAlert } from "/static/js/common/alerts.js";
import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { isSuccessfulXHR } from "/static/js/common/utils.js";

const ROOT_SELECTOR = "[data-group-badges]";
const READY_KEY = "groupBadgesReady";

/** Initialize badge dashboard interactions within a rendered root. */
export const initializeGroupBadges = (root) => {
  if (!markDatasetReady(root, READY_KEY)) {
    return;
  }
  root.querySelectorAll("[data-artwork-form]").forEach(syncArtworkFileName);

  root.addEventListener("htmx:beforeOnLoad", closeDialogOnSuccess);
  root.addEventListener("click", (event) => {
    const opener = event.target.closest?.("[data-badge-dialog-open]");
    if (opener) {
      document.getElementById(opener.dataset.badgeDialogOpen)?.showModal();
      return;
    }
    const closer = event.target.closest?.("[data-badge-dialog-close]");
    if (closer) {
      closer.closest("dialog")?.close();
    }
  });
  root.addEventListener("image-change", (event) => {
    const artworkForm = event.target.closest?.("[data-artwork-form]");
    if (artworkForm) {
      syncArtworkFileName(artworkForm);
    }
  });
  root.addEventListener("submit", (event) => {
    if (event.target.matches("[data-artwork-form]")) {
      syncArtworkFileName(event.target);
      if (!prepareArtworkForm(event.target)) {
        event.preventDefault();
        event.stopPropagation();
      }
    }
  });
};

/** Closes a badge dialog once its form succeeds so the success alert renders outside it. */
const closeDialogOnSuccess = (event) => {
  const dialog = event.target.closest?.("dialog[open]");
  if (dialog && isSuccessfulXHR(event.detail?.xhr)) {
    dialog.close();
  }
};

/** Validate that uploaded artwork is available before submission. */
const prepareArtworkForm = (form) => {
  const field = form.querySelector('image-field[target="badge"]');
  const fileName = field?.value?.split("/").filter(Boolean).pop();
  if (!fileName) {
    showErrorAlert("Upload badge artwork before adding it to the gallery.");
    return false;
  }
  return true;
};

/** Synchronize the uploaded artwork filename with its form field. */
const syncArtworkFileName = (form) => {
  const field = form.querySelector('image-field[target="badge"]');
  const fileName = field?.value?.split("/").filter(Boolean).pop() || "";
  const fileNameInput = form.querySelector("[data-artwork-file-name]");
  if (!fileNameInput) {
    return;
  }
  fileNameInput.value = fileName;
};

initializeOnReadyAndHtmxLoad((root) => {
  if (root.matches?.(ROOT_SELECTOR)) {
    initializeGroupBadges(root);
  }
  root.querySelectorAll?.(ROOT_SELECTOR).forEach(initializeGroupBadges);
});
