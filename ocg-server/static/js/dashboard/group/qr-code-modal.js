import { toggleModalVisibility } from "/static/js/common/common.js";
import { showErrorAlert } from "/static/js/common/alerts.js";

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
const PRINT_CONTAINER_ID = "qr-print-container";
const PRINT_STYLES_ID = "qr-print-styles";
const PRINT_ROOT_SELECTOR = "[data-qr-print-root]";
const PRINT_ACTIONS_SELECTOR = "[data-qr-print-actions]";
const DEFAULT_ERROR_MESSAGE = "Unable to load the event QR code. Please try again.";

const resolveUrl = (url) => {
  try {
    return new URL(url, window.location.origin).toString();
  } catch {
    return url;
  }
};

const setLinkContent = (link, url) => {
  if (!link) {
    return;
  }

  if (url) {
    const resolved = resolveUrl(url);
    link.textContent = resolved;
    link.setAttribute("href", resolved);
  } else {
    link.textContent = "";
    link.removeAttribute("href");
  }
};

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

const ensurePrintStyles = () => {
  if (document.getElementById(PRINT_STYLES_ID)) {
    return;
  }

  const style = document.createElement("style");
  style.id = PRINT_STYLES_ID;
  style.textContent = `
    #${PRINT_CONTAINER_ID} {
      position: fixed;
      inset: 0;
      z-index: 10000;
      background: #f5f5f4;
      padding: 32px 24px;
      display: none;
      align-items: center;
      justify-content: center;
    }
    #${PRINT_CONTAINER_ID}.is-visible {
      display: flex;
    }
    #${PRINT_CONTAINER_ID} .qr-print-sheet {
      width: min(960px, 100vw);
      display: flex;
      justify-content: center;
    }
    @media print {
      @page {
        size: A4 landscape;
        margin: 0;
      }
      body > *:not(#${PRINT_CONTAINER_ID}) {
        display: none !important;
      }
      #${PRINT_CONTAINER_ID} {
        display: flex !important;
        padding: 0;
        background: #fff;
        align-items: center;
        justify-content: center;
      }
      #${PRINT_CONTAINER_ID} .qr-print-sheet {
        width: 10.5in;
        max-height: 7.75in;
        padding: 0.6in 0.75in;
        box-sizing: border-box;
        background: #fff;
      }
      #${PRINT_CONTAINER_ID} [data-qr-print-root] {
        width: 100%;
        max-width: none;
        box-shadow: none;
      }
      #${PRINT_CONTAINER_ID} #event-qr-code-print-area {
        display: flex;
        flex-direction: row;
        gap: 1.5in;
      }
      #${PRINT_CONTAINER_ID} [data-qr-print-actions],
      #${PRINT_CONTAINER_ID} button {
        display: none !important;
      }
    }
  `;
  document.head.appendChild(style);
};

const removePrintContainer = () => {
  const existing = document.getElementById(PRINT_CONTAINER_ID);
  if (existing && existing.parentNode) {
    existing.parentNode.removeChild(existing);
  }
};

const printQrCode = (modal) => {
  if (!modal) {
    showErrorAlert(DEFAULT_ERROR_MESSAGE, false);
    return;
  }

  const source = modal.querySelector(PRINT_ROOT_SELECTOR);
  if (!source) {
    showErrorAlert("Unable to prepare the QR code for printing.", false);
    return;
  }

  ensurePrintStyles();
  removePrintContainer();

  const clone = source.cloneNode(true);
  clone.querySelectorAll("button").forEach((button) => button.remove());
  clone.querySelectorAll(PRINT_ACTIONS_SELECTOR).forEach((node) => node.remove());

  const container = document.createElement("div");
  container.id = PRINT_CONTAINER_ID;
  container.classList.add("is-visible");

  const sheet = document.createElement("div");
  sheet.classList.add("qr-print-sheet");
  sheet.appendChild(clone);
  container.appendChild(sheet);
  container.style.display = "none";
  document.body.appendChild(container);

  const qrImage = container.querySelector(`#${IMAGE_ID}`);
  if (qrImage) {
    qrImage.id = `${IMAGE_ID}-print`;
    const printSrc = modal.dataset.qrUrl
      ? `${modal.dataset.qrUrl}?print=${Date.now()}`
      : qrImage.getAttribute("src");
    if (printSrc) {
      qrImage.setAttribute("src", printSrc);
    }
  }

  const cleanup = () => {
    container.removeAttribute("style");
    removePrintContainer();
  };

  const startPrint = () => {
    container.style.display = "flex";
    window.addEventListener(
      "afterprint",
      () => {
        cleanup();
      },
      { once: true },
    );
    window.print();
  };

  if (!qrImage) {
    startPrint();
    return;
  }

  const handleLoad = () => {
    qrImage.removeEventListener("load", handleLoad);
    qrImage.removeEventListener("error", handleError);
    startPrint();
  };

  const handleError = () => {
    qrImage.removeEventListener("load", handleLoad);
    qrImage.removeEventListener("error", handleError);
    cleanup();
    showErrorAlert("Unable to load the QR code for printing. Please try again.", false);
  };

  qrImage.addEventListener("load", handleLoad);
  qrImage.addEventListener("error", handleError);

  if (qrImage.complete && qrImage.naturalWidth > 0) {
    handleLoad();
  }
};

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
    printButton.addEventListener("click", () => printQrCode(modal));
  }
};
