import { expect, waitUntil } from "@open-wc/testing";

import "/static/js/common/modals/share-modal.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

/** Close watcher double that records its instances. */
class FakeCloseWatcher extends EventTarget {
  static instances = [];

  destroyCount = 0;

  constructor() {
    super();
    FakeCloseWatcher.instances.push(this);
  }

  destroy() {
    this.destroyCount += 1;
  }
}

/**
 * Replaces matchMedia with a fixed answer for the phone query.
 * @param {boolean} matches Phone query state.
 * @returns {void}
 */
const mockPhoneQuery = (matches) => {
  window.matchMedia = (text) => ({
    addEventListener() {},
    matches: text === PHONE_MEDIA_QUERY && matches,
    removeEventListener() {},
  });
};

/**
 * Installs navigator.share and navigator.canShare doubles.
 * @param {{canShare?: boolean, share?: () => Promise<void>}} [options] Double behaviour.
 * @returns {{calls: object[], canShareCalls: object[]}} Recorded calls.
 */
const mockNativeShare = ({ canShare = true, share = async () => {} } = {}) => {
  const calls = [];
  const canShareCalls = [];

  Object.defineProperty(navigator, "canShare", {
    configurable: true,
    value: (data) => {
      canShareCalls.push(data);
      return canShare;
    },
  });
  Object.defineProperty(navigator, "share", {
    configurable: true,
    value: (data) => {
      calls.push(data);
      return share();
    },
  });

  return { calls, canShareCalls };
};

describe("share-modal", () => {
  const originalCanShareDescriptor = Object.getOwnPropertyDescriptor(navigator, "canShare");
  const originalClipboardDescriptor = Object.getOwnPropertyDescriptor(
    navigator,
    "clipboard",
  );
  const originalCloseWatcher = window.CloseWatcher;
  const originalMatchMedia = window.matchMedia;
  const originalShareDescriptor = Object.getOwnPropertyDescriptor(navigator, "share");
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
    window.matchMedia = originalMatchMedia;
    document.getElementById("sheet-panel-fixture")?.remove();

    // Restore the native share API after system share tests.
    if (originalCanShareDescriptor) {
      Object.defineProperty(navigator, "canShare", originalCanShareDescriptor);
    } else {
      delete navigator.canShare;
    }
    if (originalShareDescriptor) {
      Object.defineProperty(navigator, "share", originalShareDescriptor);
    } else {
      delete navigator.share;
    }

    // Restore the original CloseWatcher after sheet tests.
    if (originalCloseWatcher) {
      window.CloseWatcher = originalCloseWatcher;
    } else {
      delete window.CloseWatcher;
    }

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

  it("renders the compact icon trigger variant", async () => {
    const element = await mountLitComponent("share-modal", {
      triggerLabel: "Share Speaker badge credential",
      triggerVariant: "icon",
      title: "Speaker badge",
      url: "/badges/credentials/speaker",
    });

    const button = element.querySelector("button");

    expect(button?.classList.contains("btn-tertiary")).to.equal(true);
    expect(button?.getAttribute("aria-label")).to.equal(
      "Share Speaker badge credential",
    );
    expect(button?.getAttribute("title")).to.equal("Share Speaker badge credential");
    expect(button?.querySelector(".icon-share")?.classList.contains("size-3.5")).to.equal(true);
  });

  it("renders the pill and action variants as labelled 44px buttons", async () => {
    const pill = await mountLitComponent("share-modal", {
      triggerVariant: "pill",
      title: "Open Community Groups",
      url: "/groups/cncf",
    });
    const action = await mountLitComponent("share-modal", {
      triggerVariant: "action",
      title: "Open Community Groups",
      url: "/groups/cncf",
    });

    const pillButton = pill.querySelector("button");
    const actionButton = action.querySelector("button");

    // Both are real outlined buttons with a visible label.
    for (const button of [pillButton, actionButton]) {
      expect(button?.tagName).to.equal("BUTTON");
      expect(button?.classList.contains("btn-primary-outline")).to.equal(true);
      expect(button?.classList.contains("phone:h-11")).to.equal(true);
      expect(button?.getAttribute("aria-label")).to.equal("Share");
      expect(button?.querySelector(".icon-share")).to.not.equal(null);
      expect(button?.textContent.trim()).to.equal("Share");
    }

    // Only the action fills its row and shrinks at narrow widths.
    expect(actionButton?.classList.contains("phone:w-full")).to.equal(true);
    expect(actionButton?.classList.contains("phone:max-[360px]:px-2.5")).to.equal(true);
    expect(pillButton?.classList.contains("phone:w-full")).to.equal(false);
  });

  for (const triggerVariant of ["pill", "action"]) {
    describe(`${triggerVariant} system share`, () => {
      const mountTrigger = () =>
        mountLitComponent("share-modal", {
          triggerVariant,
          title: "Open Community Groups",
          url: "/groups/cncf",
        });

      it("calls navigator.share from the tap and leaves the modal closed on success", async () => {
        mockPhoneQuery(true);
        const { calls, canShareCalls } = mockNativeShare();
        const element = await mountTrigger();
        const shareData = {
          title: "Open Community Groups",
          url: `${window.location.origin}/groups/cncf`,
        };

        // The share call runs synchronously inside the click, to keep the user gesture.
        element.querySelector("button").click();
        expect(calls).to.deep.equal([shareData]);
        expect(canShareCalls).to.deep.equal([shareData]);

        // Success does nothing else.
        await element.updateComplete;
        await Promise.resolve();
        expect(element._isOpen).to.equal(false);
        expect(element._isSharing).to.equal(false);
        expect(document.body.querySelector('[role="dialog"]')).to.equal(null);
      });

      it("does nothing when the person cancels", async () => {
        mockPhoneQuery(true);
        mockNativeShare({
          share: async () => {
            throw new DOMException("Share canceled", "AbortError");
          },
        });
        const element = await mountTrigger();

        await element._handleNativeShare();

        // Cancelling keeps the page as it was, and a later tap works.
        expect(element._isOpen).to.equal(false);
        expect(element._isSharing).to.equal(false);
        expect(document.body.querySelector('[role="dialog"]')).to.equal(null);
      });

      it("opens the modal after any other rejection", async () => {
        mockPhoneQuery(true);
        mockNativeShare({
          share: async () => {
            throw new DOMException("Share failed", "NotAllowedError");
          },
        });
        const element = await mountTrigger();

        await element._handleNativeShare();

        // The modal is the fallback.
        expect(element._isOpen).to.equal(true);
        expect(document.body.querySelector('[role="dialog"]')).to.not.equal(null);
      });

      it("ignores a second tap while the system sheet is open", async () => {
        mockPhoneQuery(true);
        let finishShare;
        const { calls } = mockNativeShare({
          share: () =>
            new Promise((resolve) => {
              finishShare = resolve;
            }),
        });
        const element = await mountTrigger();

        // Tap twice while the first share is pending.
        const firstShare = element._handleNativeShare();
        await element._handleNativeShare();
        expect(calls).to.have.length(1);

        // A later tap shares again once the first one settles.
        finishShare();
        await firstShare;
        element._handleNativeShare();
        expect(calls).to.have.length(2);
        finishShare();
      });

      it("opens no modal when the host left the page during a failed share", async () => {
        mockPhoneQuery(true);
        let failShare;
        mockNativeShare({
          share: () =>
            new Promise((_, reject) => {
              failShare = reject;
            }),
        });
        const element = await mountTrigger();

        // Remove the host while the system sheet is open.
        const share = element._handleNativeShare();
        element.remove();
        failShare(new DOMException("Share failed", "NotAllowedError"));
        await share;

        // Nothing mounts on a page the trigger no longer belongs to.
        expect(element._isOpen).to.equal(false);
        expect(document.body.querySelector('[role="dialog"]')).to.equal(null);
      });

      it("opens the modal straight away without support", async () => {
        mockPhoneQuery(true);
        const { calls } = mockNativeShare({ canShare: false });
        const element = await mountTrigger();

        element.querySelector("button").click();
        await element.updateComplete;

        // canShare said no, so the system sheet never runs.
        expect(calls).to.have.length(0);
        expect(element._isOpen).to.equal(true);
      });

      it("opens the modal when the browser has no canShare", async () => {
        mockPhoneQuery(true);
        const { calls } = mockNativeShare();
        Object.defineProperty(navigator, "canShare", { configurable: true, value: undefined });
        const element = await mountTrigger();

        element.querySelector("button").click();
        await element.updateComplete;

        // Verify the modal stays the fallback.
        expect(calls).to.have.length(0);
        expect(element._isOpen).to.equal(true);
      });

      it("opens the modal under a false phone query, without asking the share API", async () => {
        mockPhoneQuery(false);
        const { calls, canShareCalls } = mockNativeShare();
        const element = await mountTrigger();

        element.querySelector("button").click();
        await element.updateComplete;

        // Desktop Safari has the API, so the query comes first.
        expect(calls).to.have.length(0);
        expect(canShareCalls).to.have.length(0);
        expect(element._isOpen).to.equal(true);
      });
    });
  }

  for (const triggerVariant of ["button", "icon", "menu-item"]) {
    it(`keeps the modal handler on the ${triggerVariant} variant`, async () => {
      mockPhoneQuery(true);
      const { calls, canShareCalls } = mockNativeShare();
      const element = await mountLitComponent("share-modal", {
        triggerVariant,
        title: "Open Community Groups",
        url: "/groups/cncf",
      });

      element.querySelector("button").click();
      await element.updateComplete;

      // Existing triggers open the modal even where system share is available.
      expect(calls).to.have.length(0);
      expect(canShareCalls).to.have.length(0);
      expect(element._isOpen).to.equal(true);
      expect(document.body.querySelector('[role="dialog"]')).to.not.equal(null);
    });
  }

  describe("bottom sheet", () => {
    /**
     * Mounts the modal with a laid-out sheet panel and the close watcher double.
     * @returns {Promise<HTMLElement>} Share modal element.
     */
    const mountSheetFixture = async () => {
      FakeCloseWatcher.instances = [];
      window.CloseWatcher = FakeCloseWatcher;

      // The test page has no compiled CSS, so the fixture lays the panel out.
      const style = document.createElement("style");
      style.id = "sheet-panel-fixture";
      style.textContent = ".sheet-panel { position: fixed; }";
      document.head.append(style);

      return mountLitComponent("share-modal", {
        title: "Open Community Groups",
        url: "/groups/cncf",
      });
    };

    it("marks the panel, title row and body as a sheet", async () => {
      const element = await mountLitComponent("share-modal", {
        title: "Open Community Groups",
        url: "/groups/cncf",
      });

      element._openModal();

      // Verify the primitives sit beside the desktop modal classes.
      const panel = document.body.querySelector(".modal-card");
      expect(panel?.classList.contains("sheet-panel")).to.equal(true);
      expect(panel?.querySelector(".sheet-head.sheet-grab #share-modal-title")).to.not.equal(null);
      expect(panel?.querySelector(".modal-body")?.classList.contains("sheet-body")).to.equal(true);
    });

    it("binds gestures once the panel is rendered and releases them on close", async () => {
      mockPhoneQuery(true);
      const element = await mountSheetFixture();

      // Open the sheet through the phone path.
      element._openModal();
      const panel = document.body.querySelector(".sheet-panel");
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      expect(FakeCloseWatcher.instances).to.have.length(1);

      // A close request goes through the real close button.
      FakeCloseWatcher.instances[0].dispatchEvent(new Event("close"));
      await element.updateComplete;

      // Verify the modal closed and the watcher is gone.
      expect(element._isOpen).to.equal(false);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(document.body.querySelector('[role="dialog"]')).to.equal(null);
    });

    it("releases gestures when the host disconnects while open", async () => {
      mockPhoneQuery(true);
      const element = await mountSheetFixture();

      element._openModal();
      element.remove();

      // Verify nothing outlives the host.
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(element._removeSheetGestures).to.equal(null);
    });

    it("adds no gestures under a false phone query", async () => {
      mockPhoneQuery(false);
      const element = await mountSheetFixture();

      element._openModal();

      // Verify the modal opens exactly as it does on desktop.
      expect(document.body.querySelector(".sheet-panel").hasAttribute("data-sheet-drag")).to.equal(false);
      expect(FakeCloseWatcher.instances).to.have.length(0);
    });

    describe("focus", () => {
      /**
       * Presses a key on the document.
       * @param {string} key Key name.
       * @param {boolean} [shiftKey=false] Whether Shift is held.
       * @returns {void}
       */
      const press = (key, shiftKey = false) => {
        document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key, shiftKey }));
      };

      it("moves focus in and returns it to the tapped trigger, which never held it", async () => {
        mockPhoneQuery(true);
        const element = await mountSheetFixture();
        const trigger = element.querySelector("button");
        trigger.dispatchEvent(new MouseEvent("click", { bubbles: true }));
        const close = document.body.querySelector(".sheet-panel button:has(> .icon-close)");
        expect(document.activeElement).to.equal(close);

        close.click();

        expect(document.activeElement).to.equal(trigger);
      });

      it("wraps Tab inside the sheet", async () => {
        mockPhoneQuery(true);
        const element = await mountSheetFixture();
        element._openModal();
        const panel = document.body.querySelector(".sheet-panel");
        const close = panel.querySelector("button:has(> .icon-close)");

        // Shift-Tab from the first target wraps to the last.
        press("Tab", true);
        expect(panel.contains(document.activeElement)).to.equal(true);
        expect(document.activeElement).to.not.equal(close);

        // Tab from the last target wraps to the first.
        press("Tab");
        expect(document.activeElement).to.equal(close);
      });

      it("returns focus to the trigger after a native share falls back to the modal", async () => {
        mockPhoneQuery(true);
        mockNativeShare({ share: () => Promise.reject(new DOMException("Blocked", "NotAllowedError")) });
        const element = await mountSheetFixture();
        element.triggerVariant = "pill";
        await element.updateComplete;
        const trigger = element.querySelector("button");

        trigger.click();
        await waitUntil(() => document.body.querySelector(".sheet-panel"));
        document.body.querySelector(".sheet-panel button:has(> .icon-close)").click();

        expect(document.activeElement).to.equal(trigger);
      });

      it("leaves focus and Tab alone under a false phone query", async () => {
        mockPhoneQuery(false);
        const element = await mountSheetFixture();
        const trigger = element.querySelector("button");
        trigger.focus();

        // Open from the trigger.
        trigger.click();
        expect(document.activeElement).to.equal(trigger);

        // Tab is not trapped: focus starts outside the panel and stays there.
        press("Tab");
        expect(document.activeElement).to.equal(trigger);

        // A close does not move focus.
        trigger.blur();
        press("Escape");
        expect(document.activeElement).to.not.equal(trigger);
      });
    });

    describe("back-forward cache", () => {
      /** Builds a pageshow event for a restored page. */
      const restoredPageShow = () => {
        const event = new Event("pageshow");
        Object.defineProperty(event, "persisted", { value: true });
        return event;
      };

      it("closes on a restore, so the next tap shows the sheet", async () => {
        mockPhoneQuery(true);
        const element = await mountSheetFixture();
        element._openModal();

        // The shared restore hides the dialog before or after this listener.
        document.body.querySelector('[role="dialog"]').classList.add("hidden");
        window.dispatchEvent(restoredPageShow());

        // Verify nothing is left armed.
        expect(element._isOpen).to.equal(false);
        expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
        expect(document.body.querySelector('[role="dialog"]')).to.equal(null);

        // Verify the next open shows a fresh dialog.
        element._openModal();
        expect(document.body.querySelector('[role="dialog"]').classList.contains("hidden")).to.equal(false);
      });

      it("keeps the modal open on a restore under a false phone query", async () => {
        mockPhoneQuery(false);
        const element = await mountSheetFixture();
        element._openModal();

        window.dispatchEvent(restoredPageShow());

        // Verify only phones change.
        expect(element._isOpen).to.equal(true);
      });
    });
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
    const copyButton = document.body.querySelector('[aria-label="Copy link"]');
    expect(copyButton?.classList.contains("rounded-full")).to.equal(true);
    expect(copyButton?.classList.contains("hover:bg-stone-200")).to.equal(true);
    expect(copyButton?.querySelector(".icon-copy")?.classList.contains("size-4")).to.equal(true);

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
