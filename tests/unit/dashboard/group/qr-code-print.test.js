import { expect } from "@open-wc/testing";

import { printQrCode } from "/static/js/dashboard/group/qr-code-print.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

describe("qr code print", () => {
  const originalPrint = window.print;

  let swal;
  let printCalls;

  beforeEach(() => {
    swal = mockSwal();
    printCalls = [];
    resetDom();

    window.print = () => {
      printCalls.push(true);
    };
  });

  afterEach(() => {
    resetDom();
    swal.restore();
    window.print = originalPrint;
  });

  it("shows an error when the modal is missing", () => {
    printQrCode(null, "qr-image", "/qr.png");

    expect(printCalls).to.have.length(0);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Unable to load the event QR code. Please try again.");
  });

  it("shows an error when the printable root is missing", () => {
    const modal = document.createElement("div");
    document.body.append(modal);

    printQrCode(modal, "qr-image", "/qr.png");

    expect(printCalls).to.have.length(0);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Unable to prepare the QR code for printing.");
  });

  it("prepares the printable container and prints when no image is present", () => {
    const modal = document.createElement("div");
    modal.innerHTML = `
      <div data-qr-print-root>
        <div data-qr-print-actions>Actions</div>
        <button type="button">Print</button>
        <div id="event-qr-code-print-area">Printable</div>
      </div>
    `;
    document.body.append(modal);

    printQrCode(modal, "qr-image", "/qr.png");

    const style = document.getElementById("qr-print-styles");
    const container = document.getElementById("qr-print-container");

    expect(style).to.not.equal(null);
    expect(container).to.not.equal(null);
    expect(container?.style.display).to.equal("flex");
    expect(container?.querySelector("button")).to.equal(null);
    expect(container?.querySelector("[data-qr-print-actions]")).to.equal(null);
    expect(printCalls).to.have.length(1);

    window.dispatchEvent(new Event("afterprint"));

    expect(document.getElementById("qr-print-container")).to.equal(null);
  });

  it("waits for the qr image to load before printing", () => {
    const modal = document.createElement("div");
    modal.innerHTML = `
      <div data-qr-print-root>
        <img id="qr-image" src="/qr.png" />
      </div>
    `;
    document.body.append(modal);

    printQrCode(modal, "qr-image", "https://example.com/qr.png");

    const printImage = document.getElementById("qr-image-print");

    expect(printImage).to.not.equal(null);
    expect(printImage?.getAttribute("src")).to.include("https://example.com/qr.png?print=");
    expect(printCalls).to.have.length(0);

    printImage?.dispatchEvent(new Event("load"));

    expect(printCalls).to.have.length(1);
    expect(document.getElementById("qr-print-container")?.style.display).to.equal("flex");
  });

  it("shows an error when the qr image fails to load", () => {
    const modal = document.createElement("div");
    modal.innerHTML = `
      <div data-qr-print-root>
        <img id="qr-image" src="/qr.png" />
      </div>
    `;
    document.body.append(modal);

    printQrCode(modal, "qr-image", "https://example.com/qr.png");

    document.getElementById("qr-image-print")?.dispatchEvent(new Event("error"));

    expect(printCalls).to.have.length(0);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Unable to load the QR code for printing. Please try again.");
    expect(document.getElementById("qr-print-container")).to.equal(null);
  });
});
