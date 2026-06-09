import { expect } from "@open-wc/testing";

import "/static/js/common/modals/share-modal.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("share-modal", () => {
  const originalClipboardDescriptor = Object.getOwnPropertyDescriptor(
    navigator,
    "clipboard",
  );
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

    // Restore the original clipboard descriptor after copy tests.
    if (originalClipboardDescriptor) {
      Object.defineProperty(
        navigator,
        "clipboard",
        originalClipboardDescriptor,
      );
    } else {
      delete navigator.clipboard;
    }

    // Restore the original Sharer global after platform-share tests.
    if (originalSharer) {
      window.Sharer = originalSharer;
    } else {
      delete window.Sharer;
    }
  });

  it("normalizes relative urls and renders the share trigger", async () => {
    // Render the share-modal fixture.
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    // Normalized relative urls and renders the share trigger.
    expect(element._getFullUrl()).to.equal(
      `${window.location.origin}/groups/cncf`,
    );
    expect(element.textContent).to.include("Share");
  });

  it("renders the menu item trigger variant", async () => {
    // Render the share-modal fixture.
    const element = await mountLitComponent("share-modal", {
      triggerVariant: "menu-item",
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    // The rendered text shows the scenario data.
    expect(
      element.querySelector("button")?.classList.contains("w-full"),
    ).to.equal(true);
    expect(element.textContent).to.include("Share");
  });

  it("opens and closes the modal while updating body scroll state", async () => {
    // Render the share-modal fixture.
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    // Open the modal dialog.
    element._openModal();
    await element.updateComplete;

    // The open modal renders a dialog and disables body scrolling.
    expect(element._isOpen).to.equal(true);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.body.querySelector('[role="dialog"]')).to.not.equal(null);

    // Escape closes the modal and releases body scrolling.
    element._handleKeydown({
      key: "Escape",
      preventDefault() {},
    });
    await element.updateComplete;

    // The dialog is removed after Escape closes the modal.
    expect(element._isOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.querySelector('[role="dialog"]')).to.equal(null);
  });

  it("closes the containing event actions dropdown when opened from a menu item", async () => {
    // Build an open event-actions dropdown containing the share trigger.
    document.body.innerHTML = `
      <details data-event-actions-menu open>
        <summary>Actions</summary>
      </details>
    `;
    const dropdown = document.querySelector("[data-event-actions-menu]");
    const element = document.createElement("share-modal");
    element.triggerVariant = "menu-item";
    element.title = "Open Community Groups";
    element.url = "/groups/cncf";
    dropdown.append(element);
    await element.updateComplete;

    // Opening the share modal closes the surrounding actions dropdown.
    element.querySelector("button").click();
    await element.updateComplete;

    // The share dialog opens while the containing dropdown closes.
    expect(dropdown.open).to.equal(false);
    expect(element._isOpen).to.equal(true);
    expect(document.body.querySelector('[role="dialog"]')).to.not.equal(null);
  });

  it("copies the share url and shows a success alert", async () => {
    // Render the share-modal fixture.
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    // Copy the current share URL from the open modal.
    element._openModal();
    await element._handleCopyClick();
    await element.updateComplete;

    // Successful copy closes the modal and shows a success alert.
    expect(clipboardCalls).to.deep.equal([
      `${window.location.origin}/groups/cncf`,
    ]);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Link copied to clipboard!",
      icon: "success",
    });
    expect(element._isOpen).to.equal(false);
  });

  it("shows an error alert when copying fails", async () => {
    // Render the share-modal fixture.
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    // Mock clipboard failure for the copy action.
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText: async () => {
          throw new Error("clipboard blocked");
        },
      },
    });

    // Attempt to copy the current share URL from the open modal.
    element._openModal();
    await element._handleCopyClick();
    await element.updateComplete;

    // Failed copy keeps the modal open and shows an error alert.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Failed to copy link. Please try again.",
      icon: "error",
    });
    expect(element._isOpen).to.equal(true);
  });

  it("uses sharer.js when a platform button is clicked", async () => {
    // Render the share-modal fixture.
    const element = await mountLitComponent("share-modal", {
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    // Track Sharer construction and share calls.
    const sharerCalls = [];
    window.Sharer = class {
      constructor(button) {
        sharerCalls.push({ stage: "constructor", button });
      }

      // Record share invocations from the platform button.
      share() {
        sharerCalls.push({ stage: "share" });
      }
    };

    // Open the modal to render platform share buttons.
    element._openModal();
    await element.updateComplete;

    // Click the LinkedIn share button through the Sharer integration.
    const button = document.body.querySelector('[data-sharer="linkedin"]');
    element._handleShareClick({ currentTarget: button });
    await element.updateComplete;

    // Sharer receives the clicked button and closes the modal after sharing.
    expect(sharerCalls).to.have.length(2);
    expect(sharerCalls[0].button).to.equal(button);
    expect(sharerCalls[1]).to.deep.equal({ stage: "share" });
    expect(element._isOpen).to.equal(false);
  });
});
