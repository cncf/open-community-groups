import { initializeOnReadyAndHtmxLoad, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility, trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";

const MODAL_ID = "user-check-in-modal";
let activeRoot = null;

/**
 * Initializes the attendee credential modal.
 * @param {Document|Element} container Content root supplied by page load or HTMX.
 * @param {object} context Initialization context.
 * @param {boolean} context.historyRestore Whether the root came from the HTMX history cache.
 * @returns {void}
 */
export const initializeUserCheckIn = (container = document, { historyRestore = false } = {}) => {
  const root = container.matches?.("[data-user-check-in-root]")
    ? container
    : container.querySelector?.("[data-user-check-in-root]");
  if (!(root instanceof HTMLElement)) {
    return;
  }
  if (historyRestore) {
    activeRoot = null;
    delete root.dataset.userCheckInReady;
  }
  if (!markDatasetReady(root, "userCheckInReady")) {
    return;
  }

  const modal = root.querySelector(`#${MODAL_ID}`);
  if (!(modal instanceof HTMLElement)) {
    return;
  }

  root.addEventListener("click", (event) => {
    const trigger = event.target.closest?.("[data-user-check-in-open]");
    if (trigger instanceof HTMLElement) {
      populateUserCheckInModal(root, trigger);
      toggleModalVisibility(MODAL_ID, trigger);
      activeRoot = root;
      return;
    }

    if (event.target.closest?.("[data-user-check-in-close]") && !isElementHidden(modal)) {
      closeUserCheckInModal(root, modal);
      return;
    }

    if (event.target.closest?.("[data-user-check-in-qr-retry]")) {
      const image = root.querySelector("#user-check-in-qr-image");
      const eventName = root.querySelector("#user-check-in-event-name")?.textContent || "Event";
      if (image instanceof HTMLImageElement) {
        loadQrImage(root, eventName, image.dataset.qrCodeUrl || "");
      }
    }
  });
  root.addEventListener("keydown", (event) => {
    if (isEscapeEvent(event) && !isElementHidden(modal)) {
      closeUserCheckInModal(root, modal);
      return;
    }
    trapModalFocus(event, modal);
  });
};

/**
 * Populates the attendee credential modal from a selected event card.
 * @param {Element} root Check-in section root.
 * @param {HTMLElement} trigger Selected event card.
 * @returns {void}
 */
export const populateUserCheckInModal = (root, trigger) => {
  const eventDate = trigger.dataset.eventDate || "Date information unavailable";
  const eventName = trigger.dataset.eventName || "Event";
  const name = root.dataset.userName || root.dataset.username || "Attendee";
  const photoUrl = root.dataset.userPhotoUrl || "";
  const username = root.dataset.username || "";

  const date = root.querySelector("#user-check-in-date");
  const eventNameElement = root.querySelector("#user-check-in-event-name");
  const qrImage = root.querySelector("#user-check-in-qr-image");
  const photo = root.querySelector("#user-check-in-photo");
  const nameElement = root.querySelector("#user-check-in-name");
  const usernameElement = root.querySelector("#user-check-in-username");
  const ticket = root.querySelector("#user-check-in-ticket");

  if (date) date.textContent = eventDate;
  if (eventNameElement) eventNameElement.textContent = eventName;
  if (nameElement) nameElement.textContent = name;
  if (usernameElement) usernameElement.textContent = username ? `@${username}` : "";
  if (ticket) ticket.textContent = trigger.dataset.ticketTitle || "Ticket information unavailable";
  if (qrImage instanceof HTMLImageElement) loadQrImage(root, eventName, trigger.dataset.qrCodeUrl || "");
  if (photo) {
    photo.replaceChildren();
    if (photoUrl) {
      const image = document.createElement("img");
      image.alt = "";
      image.className = "size-full object-cover";
      image.src = photoUrl;
      photo.append(image);
    } else {
      photo.textContent = computeUserInitials(name, username) || "?";
    }
  }
};

/** Closes the active attendee credential modal and releases its scroll lock. */
const closeUserCheckInModal = (root, modal) => {
  if (!isElementHidden(modal)) toggleModalVisibility(MODAL_ID);
  if (activeRoot === root) activeRoot = null;
};

/** Loads a credential image with visible progress and recovery controls. */
const loadQrImage = (root, eventName, url) => {
  const image = root.querySelector("#user-check-in-qr-image");
  const retry = root.querySelector("[data-user-check-in-qr-retry]");
  const status = root.querySelector("[data-user-check-in-qr-status]");
  if (!(image instanceof HTMLImageElement)) return;

  image.classList.add("hidden");
  retry?.classList.add("hidden");
  if (status) {
    status.classList.remove("hidden");
    status.textContent = "Loading QR code…";
  }
  image.alt = `${eventName} attendee check-in QR code`;
  image.dataset.qrCodeUrl = url;
  image.onload = () => {
    image.classList.remove("hidden");
    status?.classList.add("hidden");
  };
  image.onerror = () => {
    image.classList.add("hidden");
    image.removeAttribute("src");
    if (status) status.textContent = "The QR code could not be loaded. Try again.";
    retry?.classList.remove("hidden");
  };
  image.removeAttribute("src");
  if (url) {
    image.src = url;
  } else {
    image.onerror();
  }
};

document.addEventListener("htmx:beforeCleanupElement", (event) => {
  if (activeRoot && (activeRoot === event.target || event.target?.contains?.(activeRoot))) {
    const modal = activeRoot.querySelector(`#${MODAL_ID}`);
    if (modal instanceof HTMLElement) closeUserCheckInModal(activeRoot, modal);
  }
});
window.addEventListener("pageshow", (event) => {
  if (!event.persisted || !activeRoot) return;
  const modal = activeRoot.querySelector(`#${MODAL_ID}`);
  if (modal instanceof HTMLElement) closeUserCheckInModal(activeRoot, modal);
});

initializeOnReadyAndHtmxLoad(initializeUserCheckIn);
