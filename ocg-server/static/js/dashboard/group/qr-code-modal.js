import { toggleModalVisibility } from "/static/js/common/common.js";
import { showErrorAlert } from "/static/js/common/alerts.js";

const MODAL_ID = "event-qr-code-modal";
const OPEN_BUTTON_ID = "open-event-qr-code-modal";
const CLOSE_BUTTON_ID = "close-event-qr-code-modal";
const OVERLAY_ID = "overlay-event-qr-code-modal";
const PRINT_BUTTON_ID = "print-event-qr-code";
const DOWNLOAD_BUTTON_ID = "download-event-qr-code";
const IMAGE_ID = "event-qr-code-image";
const NAME_ID = "event-qr-code-name";
const LINK_ID = "event-qr-code-link";
const DATASET_KEY = "qrCodeModalReady";
const PRINT_CONTAINER_ID = "qr-print-container";
const PRINT_STYLES_ID = "qr-print-styles";
const DEFAULT_ERROR_MESSAGE = "Unable to load the event QR code. Please try again.";

const setLinkContent = (link, url) => {
  if (!link) {
    return;
  }

  if (url) {
    link.textContent = url;
    link.setAttribute("href", url);
  } else {
    link.textContent = "";
    link.removeAttribute("href");
  }
};

const updateModalContent = (modal, trigger, elements) => {
  if (!modal || !trigger) {
    showErrorAlert(DEFAULT_ERROR_MESSAGE, false);
    return false;
  }

  const qrUrl = trigger.getAttribute("data-qr-code-url");
  const checkInUrl = trigger.getAttribute("data-check-in-url");
  const eventName = trigger.getAttribute("data-event-name") || "Event";
  const eventSlug = trigger.getAttribute("data-event-slug") || "event";

  if (!qrUrl || !checkInUrl) {
    showErrorAlert("Select an event before opening the QR code.", false);
    return false;
  }

  if (elements.image) {
    const cacheBuster = Date.now();
    elements.image.setAttribute("src", `${qrUrl}?cb=${cacheBuster}`);
    elements.image.setAttribute("alt", `${eventName} check-in QR code`);
  }

  if (elements.name) {
    elements.name.textContent = eventName;
  }

  setLinkContent(elements.link, checkInUrl);

  modal.dataset.qrUrl = qrUrl;
  modal.dataset.checkInUrl = checkInUrl;
  modal.dataset.eventSlug = eventSlug;
  modal.dataset.eventName = eventName;

  return true;
};

const escapeHtml = (value = "") => {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
};

const downloadQrCode = async (modal) => {
  const qrUrl = modal?.dataset.qrUrl;
  if (!qrUrl) {
    showErrorAlert(DEFAULT_ERROR_MESSAGE, false);
    return;
  }

  try {
    const response = await fetch(`${qrUrl}?download=${Date.now()}`, {
      credentials: "include",
      cache: "no-store",
    });

    if (!response.ok) {
      throw new Error("Request failed");
    }

    const svgContent = await response.text();
    const blob = new Blob([svgContent], { type: "image/svg+xml" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    const fileSlug = modal.dataset.eventSlug || "event";

    anchor.href = url;
    anchor.download = `${fileSlug}-check-in-qr.svg`;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
  } catch {
    showErrorAlert("Failed to download the QR code. Please try again.", false);
  }
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
      padding: 40px 24px;
      display: none;
      align-items: center;
      justify-content: center;
    }
    #${PRINT_CONTAINER_ID}.is-visible {
      display: flex;
    }
    #${PRINT_CONTAINER_ID} .qr-print-sheet {
      width: min(640px, 90vw);
      background: #fff;
      border-radius: 20px;
      border: 1px solid #e7e5e4;
      padding: 40px 32px 48px;
      text-align: center;
      box-shadow: 0 30px 70px rgba(15, 23, 42, 0.08);
      display: flex;
      flex-direction: column;
      gap: 24px;
    }
    #${PRINT_CONTAINER_ID} h1 {
      font-size: 1.5rem;
      margin: 0;
      color: #1c1917;
    }
    #${PRINT_CONTAINER_ID} img {
      width: min(420px, 80vw);
      align-self: center;
    }
    @media print {
      body > *:not(#${PRINT_CONTAINER_ID}) {
        display: none !important;
      }
      #${PRINT_CONTAINER_ID} {
        display: flex !important;
        padding: 0;
        background: #fff;
      }
      #${PRINT_CONTAINER_ID} .qr-print-sheet {
        width: 100%;
        height: 100%;
        justify-content: center;
        border: none;
        border-radius: 0;
        box-shadow: none;
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

const renderPrintPreview = (modal) => {
  const qrUrl = modal?.dataset.qrUrl;
  const eventName = modal?.dataset.eventName || "Event check-in";

  if (!qrUrl) {
    showErrorAlert(DEFAULT_ERROR_MESSAGE, false);
    return;
  }

  ensurePrintStyles();
  removePrintContainer();

  const safeName = escapeHtml(eventName);
  const src = `${qrUrl}?print=${Date.now()}`;
  const container = document.createElement("div");
  container.id = PRINT_CONTAINER_ID;
  container.classList.add("is-visible");
  container.innerHTML = `
    <div class="qr-print-sheet">
      <h1>${safeName}</h1>
      <img src="${src}" alt="${safeName} check-in QR code" />
    </div>
  `;
  document.body.appendChild(container);

  const image = container.querySelector("img");

  const cleanup = () => {
    image?.removeEventListener("load", handleLoad);
    image?.removeEventListener("error", handleError);
    removePrintContainer();
  };

  const handleLoad = () => {
    image.removeEventListener("load", handleLoad);
    image.removeEventListener("error", handleError);
    setTimeout(() => {
      window.print();
    }, 50);
  };

  const handleError = () => {
    cleanup();
    showErrorAlert("Unable to load the QR code for printing. Please try again.", false);
  };

  if (!image) {
    cleanup();
    showErrorAlert("Unable to prepare the QR code for printing.", false);
    return;
  }

  image.addEventListener("load", handleLoad);
  image.addEventListener("error", handleError);

  if (image.complete && image.naturalWidth > 0) {
    handleLoad();
  }

  window.addEventListener(
    "afterprint",
    () => {
      cleanup();
    },
    { once: true },
  );
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
    link: document.getElementById(LINK_ID),
  };

  const openButton = document.getElementById(OPEN_BUTTON_ID);
  const closeButton = document.getElementById(CLOSE_BUTTON_ID);
  const overlay = document.getElementById(OVERLAY_ID);
  const printButton = document.getElementById(PRINT_BUTTON_ID);
  const downloadButton = document.getElementById(DOWNLOAD_BUTTON_ID);

  const toggleModal = () => toggleModalVisibility(MODAL_ID);

  if (openButton) {
    openButton.addEventListener("click", () => {
      if (updateModalContent(modal, openButton, elements)) {
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
    printButton.addEventListener("click", () => renderPrintPreview(modal));
  }

  if (downloadButton) {
    downloadButton.addEventListener("click", () => downloadQrCode(modal));
  }
};
