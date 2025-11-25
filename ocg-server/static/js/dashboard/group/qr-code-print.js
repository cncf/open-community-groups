import { showErrorAlert } from "/static/js/common/alerts.js";

const PRINT_CONTAINER_ID = "qr-print-container";
const PRINT_STYLES_ID = "qr-print-styles";
const PRINT_ROOT_SELECTOR = "[data-qr-print-root]";
const PRINT_ACTIONS_SELECTOR = "[data-qr-print-actions]";

// A4 landscape dimensions: 11.69" x 8.27". Using 10.5" x 7.75" for safe printable
// area with standard 0.6" margins to avoid printer edge clipping
const PRINT_DIMENSIONS = {
  PAGE_WIDTH: "10.5in",
  PAGE_HEIGHT: "7.75in",
  PADDING_VERTICAL: "0.6in",
  PADDING_HORIZONTAL: "0.75in",
  CONTENT_GAP: "1.5in",
};

/**
 * Injects print-specific CSS styles into the document head if not already present.
 * These styles ensure the QR code prints correctly on A4 landscape paper.
 */
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
      align-items: center;
      justify-content: center;
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
        width: ${PRINT_DIMENSIONS.PAGE_WIDTH};
        max-height: ${PRINT_DIMENSIONS.PAGE_HEIGHT};
        padding: ${PRINT_DIMENSIONS.PADDING_VERTICAL} ${PRINT_DIMENSIONS.PADDING_HORIZONTAL};
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
        gap: ${PRINT_DIMENSIONS.CONTENT_GAP};
      }
      #${PRINT_CONTAINER_ID} [data-qr-print-actions],
      #${PRINT_CONTAINER_ID} button {
        display: none !important;
      }
    }
  `;
  document.head.appendChild(style);
};

/**
 * Removes the print container from the DOM if it exists.
 */
const removePrintContainer = () => {
  const existing = document.getElementById(PRINT_CONTAINER_ID);
  existing?.parentNode?.removeChild(existing);
};

/**
 * Prepares and triggers the browser print dialog for a QR code modal. Clones the modal
 * content, removes interactive elements, loads the QR image, and initiates printing.
 */
export const printQrCode = (modal, imageId, qrUrl) => {
  if (!modal) {
    showErrorAlert("Unable to load the event QR code. Please try again.", false);
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
  container.style.display = "none";

  const sheet = document.createElement("div");
  sheet.classList.add("qr-print-sheet");
  sheet.appendChild(clone);
  container.appendChild(sheet);
  document.body.appendChild(container);

  const qrImage = container.querySelector(`#${imageId}`);
  if (qrImage) {
    qrImage.id = `${imageId}-print`;
    const printSrc = qrUrl ? `${qrUrl}?print=${Date.now()}` : qrImage.getAttribute("src");
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
    window.addEventListener("afterprint", cleanup, { once: true });
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
