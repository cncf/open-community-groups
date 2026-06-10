import { expect } from "@open-wc/testing";

import { printQrCode } from "/static/js/dashboard/group/qr-code/print.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockWindowPrint } from "/tests/unit/test-utils/print.js";

describe("qr code print", () => {
  let printMock;
  let swal;

  beforeEach(() => {
    swal = mockSwal();
    resetDom();
    printMock = mockWindowPrint();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
    printMock.restore();
  });

  it("shows an error when the modal is missing", () => {
    // Call print qr code.
    printQrCode(null, "qr-image", "/qr.png");

    // Assert the captured calls.
    expect(printMock.calls).to.have.length(0);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Unable to load the event QR code. Please try again.",
    );
  });

  it("shows an error when the printable root is missing", () => {
    // Prepare modal for showing an error when the printable root is missing.
    const modal = document.createElement("div");
    document.body.append(modal);

    // Call print qr code.
    printQrCode(modal, "qr-image", "/qr.png");

    // Assert the captured calls.
    expect(printMock.calls).to.have.length(0);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Unable to prepare the QR code for printing.",
    );
  });

  it("prepares the printable container and prints when no image is present", () => {
    // Prepare modal for preparing the printable container and prints when no.
    const modal = document.createElement("div");
    modal.innerHTML = `
      <div data-qr-print-root>
        <div data-qr-print-actions>Actions</div>
        <button type="button">Print</button>
        <div id="event-qr-code-print-area">Printable</div>
      </div>
    `;
    document.body.append(modal);

    // The printable container is prepared before printing.
    printQrCode(modal, "qr-image", "/qr.png");

    // Keep a reference to the QR print styles element.
    const style = document.getElementById("qr-print-styles");
    const container = document.getElementById("qr-print-container");

    // Printing works after preparing a container without an image.
    expect(style).to.not.equal(null);
    expect(container).to.not.equal(null);
    expect(container?.style.display).to.equal("flex");
    expect(container?.querySelector("button")).to.equal(null);
    expect(container?.querySelector("[data-qr-print-actions]")).to.equal(null);
    expect(printMock.calls).to.have.length(1);

    // Dispatch the afterprint event.
    window.dispatchEvent(new Event("afterprint"));

    // The temporary print container is cleaned up after printing.
    expect(document.getElementById("qr-print-container")).to.equal(null);
  });

  it("waits for the qr image to load before printing", () => {
    // Prepare modal for waiting for the qr image to load before printing.
    const modal = document.createElement("div");
    modal.innerHTML = `
      <div data-qr-print-root>
        <img id="qr-image" src="/qr.png" />
      </div>
    `;
    document.body.append(modal);

    // Call print qr code.
    printQrCode(modal, "qr-image", "https://example.com/qr.png");

    // Keep a reference to the QR image print element.
    const printImage = document.getElementById("qr-image-print");

    // Assert the print image state.
    expect(printImage).to.not.equal(null);
    expect(printImage?.getAttribute("src")).to.include(
      "https://example.com/qr.png?print=",
    );
    expect(printMock.calls).to.have.length(0);

    // Dispatch the load event.
    printImage?.dispatchEvent(new Event("load"));

    // Verify waits for the qr image to load before printing.
    expect(printMock.calls).to.have.length(1);
    expect(
      document.getElementById("qr-print-container")?.style.display,
    ).to.equal("flex");
  });

  it("shows an error when the qr image fails to load", () => {
    // Prepare modal for showing an error when the qr image fails to load.
    const modal = document.createElement("div");
    modal.innerHTML = `
      <div data-qr-print-root>
        <img id="qr-image" src="/qr.png" />
      </div>
    `;
    document.body.append(modal);

    // Call print qr code.
    printQrCode(modal, "qr-image", "https://example.com/qr.png");

    // Dispatch the error event.
    document
      .getElementById("qr-image-print")
      ?.dispatchEvent(new Event("error"));

    // Assert the captured calls.
    expect(printMock.calls).to.have.length(0);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Unable to load the QR code for printing. Please try again.",
    );
    expect(document.getElementById("qr-print-container")).to.equal(null);
  });
});
