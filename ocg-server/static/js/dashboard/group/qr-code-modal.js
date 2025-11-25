import { toggleModalVisibility } from "/static/js/common/common.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { setLinkContent } from "/static/js/common/url-utils.js";
import { printQrCode } from "/static/js/common/qr-code-print.js";

const MODAL_ID = "event-qr-code-modal";
const OPEN_BUTTON_ID = "open-event-qr-code-modal";
const CLOSE_BUTTON_ID = "close-event-qr-code-modal";
const OVERLAY_ID = "overlay-event-qr-code-modal";
const PRINT_BUTTON_ID = "print-event-qr-code";
const IMAGE_ID = "event-qr-code-image";
const NAME_ID = "event-qr-code-name";
const GROUP_ID = "event-qr-code-group-name";
const START_ID = "event-qr-code-start";
const LINK_ID = "event-qr-code-link";
const DATASET_KEY = "qrCodeModalReady";
const DEFAULT_ERROR_MESSAGE = "Unable to load the event QR code. Please try again.";

/**
 * Updates the modal content with event data from the trigger button's data attributes.
 * Loads the QR code image and populates event details.
 */
const updateModalContent = (modal, trigger, elements, printButton) => {
  if (!modal || !trigger) {
    showErrorAlert(DEFAULT_ERROR_MESSAGE, false);
    return false;
  }

  const qrUrl = trigger.getAttribute("data-qr-code-url");
  const checkInUrl = trigger.getAttribute("data-check-in-url");
  const eventName = trigger.getAttribute("data-event-name") || "Event";
  const eventSlug = trigger.getAttribute("data-event-slug") || "event";
  const groupName = trigger.getAttribute("data-group-name") || "Group";
  const eventStart = trigger.getAttribute("data-event-start") || "";

  if (!qrUrl || !checkInUrl) {
    showErrorAlert("Select an event before opening the QR code.", false);
    return false;
  }

  if (printButton) {
    printButton.disabled = true;
  }

  if (elements.image) {
    const cacheBuster = Date.now();
    elements.image.setAttribute("src", `${qrUrl}?cb=${cacheBuster}`);
    elements.image.setAttribute("alt", `${eventName} check-in QR code`);

    const handleImageLoad = () => {
      elements.image.removeEventListener("load", handleImageLoad);
      elements.image.removeEventListener("error", handleImageError);
      if (printButton) {
        printButton.disabled = false;
      }
    };

    const handleImageError = () => {
      elements.image.removeEventListener("load", handleImageLoad);
      elements.image.removeEventListener("error", handleImageError);
      showErrorAlert("Failed to load QR code. Please try again.", false);
      if (printButton) {
        printButton.disabled = true;
      }
    };

    elements.image.removeEventListener("load", handleImageLoad);
    elements.image.removeEventListener("error", handleImageError);
    elements.image.addEventListener("load", handleImageLoad);
    elements.image.addEventListener("error", handleImageError);

    if (elements.image.complete && elements.image.naturalWidth > 0) {
      handleImageLoad();
    }
  }

  if (elements.name) {
    elements.name.textContent = eventName;
  }

  if (elements.group) {
    elements.group.textContent = groupName;
  }

  if (elements.start) {
    elements.start.textContent = eventStart;
  }

  setLinkContent(elements.link, checkInUrl);

  modal.dataset.qrUrl = qrUrl;
  modal.dataset.checkInUrl = checkInUrl;
  modal.dataset.eventSlug = eventSlug;
  modal.dataset.eventName = eventName;
  modal.dataset.groupName = groupName;
  modal.dataset.eventStart = eventStart;

  return true;
};

/**
 * Initializes the QR code modal with event listeners for opening, closing, and
 * printing. Prevents duplicate initialization using a dataset flag.
 */
export const initializeQrCodeModal = () => {
  const modal = document.getElementById(MODAL_ID);
  if (!modal || modal.dataset[DATASET_KEY] === "true") {
    return;
  }

  modal.dataset[DATASET_KEY] = "true";

  const elements = {
    image: document.getElementById(IMAGE_ID),
    name: document.getElementById(NAME_ID),
    group: document.getElementById(GROUP_ID),
    start: document.getElementById(START_ID),
    link: document.getElementById(LINK_ID),
  };

  const openButton = document.getElementById(OPEN_BUTTON_ID);
  const closeButton = document.getElementById(CLOSE_BUTTON_ID);
  const overlay = document.getElementById(OVERLAY_ID);
  const printButton = document.getElementById(PRINT_BUTTON_ID);

  const toggleModal = () => toggleModalVisibility(MODAL_ID);

  if (openButton) {
    openButton.addEventListener("click", () => {
      if (updateModalContent(modal, openButton, elements, printButton)) {
        toggleModal();
      }
    });
  }

  if (closeButton) {
    closeButton.addEventListener("click", toggleModal);
  }

  if (overlay) {
    overlay.addEventListener("click", toggleModal);
  }

  if (printButton) {
    printButton.addEventListener("click", () => printQrCode(modal, IMAGE_ID, modal.dataset.qrUrl));
  }
};
