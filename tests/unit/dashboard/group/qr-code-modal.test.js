import { expect } from "@open-wc/testing";

import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code-modal.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

describe("qr code modal", () => {
  const originalPrint = window.print;

  let swal;
  let printCalls;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    printCalls = [];
    window.print = () => {
      printCalls.push(true);
    };
  });

  afterEach(() => {
    resetDom();
    swal.restore();
    window.print = originalPrint;
  });

  const renderModalFixture = ({
    qrUrl = "",
    checkInUrl = "",
    eventName = "KubeCon Europe",
    groupName = "CNCF Madrid",
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
    renderModalFixture();
    initializeQrCodeModal();

    document.getElementById("open-event-qr-code-modal")?.click();

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Select an event before opening the QR code.");
    expect(document.getElementById("event-qr-code-modal")?.classList.contains("hidden")).to.equal(true);
  });

  it("populates the modal and enables printing after the qr image loads", () => {
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    const modal = document.getElementById("event-qr-code-modal");
    const image = document.getElementById("event-qr-code-image");
    const printButton = document.getElementById("print-event-qr-code");
    const link = document.getElementById("event-qr-code-link");

    document.getElementById("open-event-qr-code-modal")?.click();

    expect(modal?.classList.contains("hidden")).to.equal(false);
    expect(image?.getAttribute("src")).to.equal("https://example.com/qr.png");
    expect(image?.getAttribute("alt")).to.equal("KubeCon Europe check-in QR code");
    expect(document.getElementById("event-qr-code-name")?.textContent).to.equal("KubeCon Europe");
    expect(document.getElementById("event-qr-code-group-name")?.textContent).to.equal("CNCF Madrid");
    expect(document.getElementById("event-qr-code-start")?.textContent).to.equal("March 25, 2026");
    expect(link?.textContent).to.equal(`${window.location.origin}/events/kubecon/check-in`);
    expect(link?.getAttribute("href")).to.equal(`${window.location.origin}/events/kubecon/check-in`);
    expect(printButton?.disabled).to.equal(true);

    image?.dispatchEvent(new Event("load"));
    expect(printButton?.disabled).to.equal(false);
  });

  it("shows an error when the qr image fails to load", () => {
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    const image = document.getElementById("event-qr-code-image");
    const printButton = document.getElementById("print-event-qr-code");

    document.getElementById("open-event-qr-code-modal")?.click();
    image?.dispatchEvent(new Event("error"));

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Failed to load QR code. Please try again.");
    expect(printButton?.disabled).to.equal(true);
  });

  it("closes the modal from the close button and overlay", () => {
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    const modal = document.getElementById("event-qr-code-modal");
    document.getElementById("open-event-qr-code-modal")?.click();
    expect(modal?.classList.contains("hidden")).to.equal(false);

    document.getElementById("close-event-qr-code-modal")?.click();
    expect(modal?.classList.contains("hidden")).to.equal(true);

    document.getElementById("open-event-qr-code-modal")?.click();
    document.getElementById("overlay-event-qr-code-modal")?.click();
    expect(modal?.classList.contains("hidden")).to.equal(true);
  });

  it("passes the modal through to the qr print flow", () => {
    renderModalFixture({
      qrUrl: "https://example.com/qr.png",
      checkInUrl: "/events/kubecon/check-in",
    });
    initializeQrCodeModal();

    document.getElementById("open-event-qr-code-modal")?.click();
    document.getElementById("event-qr-code-image")?.dispatchEvent(new Event("load"));
    document.getElementById("print-event-qr-code")?.click();

    const printImage = document.getElementById("event-qr-code-image-print");
    expect(printImage).to.not.equal(null);

    printImage?.dispatchEvent(new Event("load"));

    expect(printCalls).to.have.length(1);
    expect(document.getElementById("qr-print-container")?.style.display).to.equal("flex");
  });
});
