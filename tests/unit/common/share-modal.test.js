import { expect } from "@open-wc/testing";

import "/static/js/common/share-modal.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("share-modal", () => {
  const originalClipboardDescriptor = Object.getOwnPropertyDescriptor(navigator, "clipboard");
  const originalSharer = window.Sharer;

  useMountedElementsCleanup("share-modal");

  let swal;
  let clipboardCalls;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    clipboardCalls = [];

    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText: async (value) => {
          clipboardCalls.push(value);
        },
      },
    });
  });

  afterEach(() => {
    swal.restore();

    if (originalClipboardDescriptor) {
      Object.defineProperty(navigator, "clipboard", originalClipboardDescriptor);
    } else {
      delete navigator.clipboard;
    }

    if (originalSharer) {
      window.Sharer = originalSharer;
    } else {
      delete window.Sharer;
    }
  });

  it("normalizes relative urls and renders the share trigger", async () => {
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    expect(element._getFullUrl()).to.equal(`${window.location.origin}/groups/cncf`);
    expect(element.textContent).to.include("Share");
  });

  it("opens and closes the modal while updating body scroll state", async () => {
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    element._openModal();
    await element.updateComplete;

    expect(element._isOpen).to.equal(true);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(element.querySelector('[role="dialog"]')).to.not.equal(null);

    element._handleKeydown({
      key: "Escape",
      preventDefault() {},
    });
    await element.updateComplete;

    expect(element._isOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");
    expect(element.querySelector('[role="dialog"]')).to.equal(null);
  });

  it("copies the share url and shows a success alert", async () => {
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    element._openModal();
    await element._handleCopyClick();
    await element.updateComplete;

    expect(clipboardCalls).to.deep.equal([`${window.location.origin}/groups/cncf`]);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({ text: "Link copied to clipboard!", icon: "success" });
    expect(element._isOpen).to.equal(false);
  });

  it("shows an error alert when copying fails", async () => {
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText: async () => {
          throw new Error("clipboard blocked");
        },
      },
    });

    element._openModal();
    await element._handleCopyClick();
    await element.updateComplete;

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({ text: "Failed to copy link. Please try again.", icon: "error" });
    expect(element._isOpen).to.equal(true);
  });

  it("uses sharer.js when a platform button is clicked", async () => {
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    const sharerCalls = [];
    window.Sharer = class {
      constructor(button) {
        sharerCalls.push({ stage: "constructor", button });
      }

      share() {
        sharerCalls.push({ stage: "share" });
      }
    };

    element._openModal();
    await element.updateComplete;

    const button = element.querySelector('[data-sharer="linkedin"]');
    element._handleShareClick({ currentTarget: button });
    await element.updateComplete;

    expect(sharerCalls).to.have.length(2);
    expect(sharerCalls[0].button).to.equal(button);
    expect(sharerCalls[1]).to.deep.equal({ stage: "share" });
    expect(element._isOpen).to.equal(false);
  });
});
