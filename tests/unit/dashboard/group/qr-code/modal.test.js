import { expect } from "@open-wc/testing";

import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code/modal.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockWindowPrint } from "/tests/unit/test-utils/print.js";

describe("qr code modal", () => {
  let printMock;
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    printMock = mockWindowPrint();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
    printMock.restore();
  });

  const renderModalFixture = ({
    qrUrl = "",
    checkInUrl = "",
    eventName = "KubeCon Europe",
    groupName = "Goup Madrid",
    eventStart = "March 25, 2026",
  } = {}) => {
    document.body.innerHTML = `
      <button
        id="open-event-qr-code-modal"
        type="button"
        data-qr-code-url="${qrUrl}"
        data-check-in-url="${checkInUrl}"
        data-event-name="${eventName}"
        data-group-name="${groupName}"
        data-event-start="${eventStart}"
      >
        Open
      </button>
      <div id="event-qr-code-modal" class="hidden">
        <div data-qr-print-root>
          <div data-qr-print-actions>Actions</div>
          <img id="event-qr-code-image" src="" />
          <div id="event-qr-code-name"></div>
          <div id="event-qr-code-group-name"></div>
          <div id="event-qr-code-start"></div>
          <a id="event-qr-code-link"></a>
        </div>
      </div>
      <button id="close-event-qr-code-modal" type="button">Close</button>
      <div id="overlay-event-qr-code-modal"></div>
      <button id="print-event-qr-code" type="button">Print</button>
    `;
  };

  it("shows an error when the trigger button is missing qr data", () => {
    // Render the modal without QR data on the trigger.
    renderModalFixture();
    initializeQrCodeModal();

    // Try to open the modal from the incomplete trigger.
    document.getElementById("open-event-qr-code-modal")?.click();

    // Verify the missing-data error keeps the modal closed.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Select an event before opening the QR code.",
    );
    expect(
      document
        .getElementById("event-qr-code-modal")
        ?.classList.contains("hidden"),
    ).to.equal(true);
  });

  it("populates the modal and enables printing after the qr image loads", () => {
    // Render the modal with event QR data.
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    // Read the modal fields that should receive the event data.
    const modal = document.getElementById("event-qr-code-modal");
    const image = document.getElementById("event-qr-code-image");
    const printButton = document.getElementById("print-event-qr-code");
    const link = document.getElementById("event-qr-code-link");

    // Open the modal before the QR image has loaded.
    document.getElementById("open-event-qr-code-modal")?.click();

    // Verify the modal is populated while printing is still disabled.
    expect(modal?.classList.contains("hidden")).to.equal(false);
    expect(image?.getAttribute("src")).to.equal("https://example.com/qr.png");
    expect(image?.getAttribute("alt")).to.equal(
      "KubeCon Europe check-in QR code",
    );
    expect(document.getElementById("event-qr-code-name")?.textContent).to.equal(
      "KubeCon Europe",
    );
    expect(
      document.getElementById("event-qr-code-group-name")?.textContent,
    ).to.equal("Goup Madrid");
    expect(
      document.getElementById("event-qr-code-start")?.textContent,
    ).to.equal("March 25, 2026");
    expect(link?.textContent).to.equal(
      `${window.location.origin}/events/kubecon/check-in`,
    );
    expect(link?.getAttribute("href")).to.equal(
      `${window.location.origin}/events/kubecon/check-in`,
    );
    expect(printButton?.disabled).to.equal(true);

    // Finish loading the QR image so printing becomes available.
    image?.dispatchEvent(new Event("load"));
    expect(printButton?.disabled).to.equal(false);
  });

  it("shows an error when the qr image fails to load", () => {
    // Render the modal with a QR image that will fail to load.
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    // Read the image and print button affected by the load error.
    const image = document.getElementById("event-qr-code-image");
    const printButton = document.getElementById("print-event-qr-code");

    // Open the modal and emit the QR image error.
    document.getElementById("open-event-qr-code-modal")?.click();
    image?.dispatchEvent(new Event("error"));

    // Verify the load error disables printing and shows feedback.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Failed to load QR code. Please try again.",
    );
    expect(printButton?.disabled).to.equal(true);
  });

  it("closes the modal from the close button and overlay", () => {
    // Render the modal with valid QR data for close interactions.
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    // Open the modal before testing each close control.
    const modal = document.getElementById("event-qr-code-modal");
    document.getElementById("open-event-qr-code-modal")?.click();
    expect(modal?.classList.contains("hidden")).to.equal(false);

    // Close the modal from the close button.
    document.getElementById("close-event-qr-code-modal")?.click();
    expect(modal?.classList.contains("hidden")).to.equal(true);

    // Reopen the modal and close it from the overlay.
    document.getElementById("open-event-qr-code-modal")?.click();
    document.getElementById("overlay-event-qr-code-modal")?.click();
    expect(modal?.classList.contains("hidden")).to.equal(true);
  });

  it("passes the modal through to the qr print flow", () => {
    // Render the modal with QR data for the print flow.
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    // Open the modal, load the QR image, and start printing.
    document.getElementById("open-event-qr-code-modal")?.click();
    document
      .getElementById("event-qr-code-image")
      ?.dispatchEvent(new Event("load"));
    document.getElementById("print-event-qr-code")?.click();

    // Read the copied print image that must load before printing.
    const printImage = document.getElementById("event-qr-code-image-print");
    expect(printImage).to.not.equal(null);

    // Finish loading the print image.
    printImage?.dispatchEvent(new Event("load"));

    // Verify the print flow receives the modal content.
    expect(printMock.calls).to.have.length(1);
    expect(
      document.getElementById("qr-print-container")?.style.display,
    ).to.equal("flex");
  });
});
