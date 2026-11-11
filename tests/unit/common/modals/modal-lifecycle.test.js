import { expect } from "@open-wc/testing";

import {
  bindModalControlClicks,
  bindModalDismissListeners,
  closeModalBodyScroll,
  focusBottomSheet,
  isModalOverlayTarget,
  openModalBodyScroll,
  resetRestoredModalState,
  toggleModalVisibility,
  trapBottomSheetFocus,
  trapModalFocus,
} from "/static/js/common/modals/modal-lifecycle.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

describe("modal lifecycle", () => {
  let media;

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    media?.restore();
    resetDom();
  });

  it("recognizes modal overlay targets", () => {
    // Build a modal overlay fixture.
    const overlay = document.createElement("div");
    overlay.className = "modal-overlay";

    // The helper identifies overlay targets.
    expect(isModalOverlayTarget(overlay)).to.equal(true);
    expect(isModalOverlayTarget(document.createElement("div"))).to.equal(false);
    expect(isModalOverlayTarget(null)).to.equal(false);
  });

  it("binds and removes document dismissal listeners", () => {
    // Track listener calls.
    let keydownCount = 0;
    let outsideClickCount = 0;

    // Bind the document-level modal dismissal listeners.
    const cleanup = bindModalDismissListeners({
      onKeydown: () => {
        keydownCount += 1;
      },
      onOutsideClick: () => {
        outsideClickCount += 1;
      },
    });

    // Dispatch events while listeners are active.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    document.dispatchEvent(new MouseEvent("mousedown"));

    // Remove listeners and verify later events are ignored.
    cleanup();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    document.dispatchEvent(new MouseEvent("mousedown"));

    expect(keydownCount).to.equal(1);
    expect(outsideClickCount).to.equal(1);
  });

  it("binds dismissal listeners to custom targets", () => {
    // Build a custom event target for owner-document scoped components.
    const target = document.createElement("section");
    let keydownCount = 0;

    // Bind the keydown listener to the custom target.
    const cleanup = bindModalDismissListeners({
      onKeydown: () => {
        keydownCount += 1;
      },
      target,
    });

    // Dispatch while bound, then verify cleanup removes the listener.
    target.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    cleanup();
    target.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));

    expect(keydownCount).to.equal(1);
  });

  it("binds modal control clicks and skips missing controls", () => {
    // Build two controls and include an absent one.
    const closeButton = document.createElement("button");
    const overlay = document.createElement("div");
    let clickCount = 0;

    // Bind the shared click handler to available controls only.
    bindModalControlClicks([closeButton, null, overlay], () => {
      clickCount += 1;
    });

    // Click each available control.
    closeButton.click();
    overlay.click();

    expect(clickCount).to.equal(2);
  });

  it("keeps skipping targets under a hidden class off phones", () => {
    // Build an open modal inside a panel that keeps the hidden class.
    const panel = document.createElement("main");
    panel.className = "hidden";
    panel.style.display = "block";
    const modal = document.createElement("div");
    modal.setAttribute("role", "dialog");
    modal.className = "hidden";
    const button = document.createElement("button");
    modal.append(button);
    panel.append(modal);
    document.body.append(panel);

    // The dialog itself takes focus, as it always has.
    media = stubMatchMedia();
    toggleModalVisibility(modal);
    expect(document.activeElement).to.equal(modal);
  });

  it("reaches targets a phone shows under a hidden class", () => {
    // Build an open modal inside a panel shown with phone:block.
    const panel = document.createElement("main");
    panel.className = "hidden";
    panel.style.display = "block";
    const modal = document.createElement("div");
    modal.setAttribute("role", "dialog");
    modal.className = "hidden";
    const button = document.createElement("button");
    const offscreen = document.createElement("button");
    offscreen.style.display = "none";
    modal.append(offscreen, button);
    panel.append(modal);
    document.body.append(panel);

    // The first rendered button takes focus, and the undisplayed one is skipped.
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
    toggleModalVisibility(modal);
    expect(document.activeElement).to.equal(button);
  });

  it("wraps forward and reverse keyboard focus within an open modal", () => {
    // Build an open modal with two keyboard focus targets.
    const modal = document.createElement("div");
    modal.innerHTML = `
      <button type="button" tabindex="-1">Backdrop</button>
      <button type="button">First</button>
      <input type="hidden" />
      <button type="button">Last</button>
    `;
    document.body.append(modal);
    const [, firstButton, lastButton] = modal.querySelectorAll("button");

    // Tab from the final target wraps to the first target.
    lastButton.focus();
    const forwardEvent = new KeyboardEvent("keydown", {
      cancelable: true,
      key: "Tab",
    });
    expect(trapModalFocus(forwardEvent, modal)).to.equal(true);
    expect(forwardEvent.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(firstButton);

    // Shift+Tab from the first target wraps to the final target.
    const backwardEvent = new KeyboardEvent("keydown", {
      cancelable: true,
      key: "Tab",
      shiftKey: true,
    });
    expect(trapModalFocus(backwardEvent, modal)).to.equal(true);
    expect(backwardEvent.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(lastButton);
  });

  describe("bottom sheet focus", () => {
    /**
     * Builds a sheet whose head renders a link before the close button.
     * @returns {{close: HTMLElement, last: HTMLElement, link: HTMLElement, panel: HTMLElement}} Fixture.
     */
    const renderSheet = () => {
      document.body.innerHTML = `
        <button id="opener" type="button">Open</button>
        <user-host id="host"><div id="host-control" role="button" tabindex="0">Chip</div></user-host>
        <div id="panel" class="sheet-panel" style="position: fixed">
          <a id="head-link" href="#profile">Profile</a>
          <button id="close" type="button"><div class="icon-close"></div></button>
          <button id="last" type="button">Copy</button>
        </div>
      `;

      return {
        close: document.getElementById("close"),
        last: document.getElementById("last"),
        link: document.getElementById("head-link"),
        panel: document.getElementById("panel"),
      };
    };

    /**
     * Presses Tab on the panel and reports whether the trap took it.
     * @param {HTMLElement} panel Sheet panel.
     * @returns {boolean} True when focus wrapped.
     */
    const pressTab = (panel) => {
      const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" });
      trapBottomSheetFocus(event, panel);
      return event.defaultPrevented;
    };

    it("enters at the close button and returns to the opener", () => {
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { close, panel } = renderSheet();
      const opener = document.getElementById("opener");

      // Nothing focuses the opener first, as on iOS after a tap.
      const restore = focusBottomSheet(panel, opener);
      expect(document.activeElement).to.equal(close);

      restore();
      expect(document.activeElement).to.equal(opener);
    });

    it("stops a closing mouse press from clearing the returned focus", () => {
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { panel } = renderSheet();
      const restore = focusBottomSheet(panel, document.getElementById("opener"));

      // A backdrop tap closes on mousedown.
      const press = new MouseEvent("mousedown", { bubbles: true, cancelable: true });
      document.addEventListener("mousedown", restore, { once: true });
      document.body.dispatchEvent(press);

      expect(press.defaultPrevented).to.equal(true);
    });

    it("returns to the control a host element renders", () => {
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { panel } = renderSheet();

      const restore = focusBottomSheet(panel, document.getElementById("host"));
      restore();

      expect(document.activeElement).to.equal(document.getElementById("host-control"));
    });

    it("leaves focus alone off phones and on missing panels", () => {
      media = stubMatchMedia();
      const { panel } = renderSheet();
      const opener = document.getElementById("opener");
      opener.focus();

      expect(focusBottomSheet(panel, opener)).to.equal(null);
      expect(focusBottomSheet(null, opener)).to.equal(null);
      expect(document.activeElement).to.equal(opener);
    });

    it("wraps Tab while the panel is a sheet and lets go when it stops being one", () => {
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { last, link, panel } = renderSheet();
      focusBottomSheet(panel, document.getElementById("opener"));
      last.focus();

      // Verify Tab wraps from the last target to the first.
      expect(pressTab(panel)).to.equal(true);
      expect(document.activeElement).to.equal(link);

      // Verify a rotation past phone widths ends the trap.
      media.setMatches(PHONE_MEDIA_QUERY, false);
      last.focus();
      expect(pressTab(panel)).to.equal(false);
      expect(document.activeElement).to.equal(last);
    });
  });

  it("locks body scroll only across modal open transitions", () => {
    // Open the modal twice and close it twice.
    let isOpen = false;
    isOpen = openModalBodyScroll(isOpen);
    isOpen = openModalBodyScroll(isOpen);
    isOpen = closeModalBodyScroll(isOpen);
    isOpen = closeModalBodyScroll(isOpen);

    // The helpers only lock and unlock on real state transitions.
    expect(isOpen).to.equal(false);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });

  it("hides declarative modals and clears scroll locks after history restore", () => {
    // Build a restored server-rendered modal fixture.
    const root = document.createElement("section");
    root.innerHTML = `
      <button data-modal-toggle="details-modal">Close</button>
      <div id="details-modal" aria-hidden="false"></div>
      <div id="custom-modal" data-restorable-modal aria-hidden="false"></div>
    `;
    root.dataset.modalToggle = "root-modal";
    document.body.append(root);
    const rootModal = document.createElement("div");
    rootModal.id = "root-modal";
    document.body.append(rootModal);
    document.body.dataset.modalOpenCount = "1";
    document.body.style.overflow = "hidden";

    // Reset modal state after a cached history snapshot is restored.
    resetRestoredModalState(root);

    // The restored modal is closed and body scrolling is available again.
    expect(document.getElementById("details-modal").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("details-modal").getAttribute("aria-hidden")).to.equal("true");
    expect(rootModal.classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("custom-modal").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("custom-modal").getAttribute("aria-hidden")).to.equal("true");
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal(undefined);
  });

  it("hides custom modals from a restored full page", () => {
    // Build a custom modal captured while open in the browser history cache.
    document.body.innerHTML = `
      <div id="custom-modal" data-restorable-modal aria-hidden="false"></div>
    `;
    document.body.dataset.modalOpenCount = "1";
    document.body.style.overflow = "hidden";

    // Reset the full document as the persisted pageshow handler does.
    resetRestoredModalState(document);

    // The custom modal and page scroll state are both reset.
    expect(document.getElementById("custom-modal").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("custom-modal").getAttribute("aria-hidden")).to.equal("true");
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal(undefined);
  });

  it("hides accessible dialogs without requiring a restoration marker", () => {
    // Build a modal that manages its own controls but uses the shared dialog contract.
    document.body.innerHTML = `
      <div id="managed-modal" role="dialog" aria-modal="true" aria-hidden="false"></div>
    `;

    // Reset the page before its dashboard content is replaced.
    resetRestoredModalState(document);

    // Accessible modal markup is enough for shared navigation cleanup.
    const modal = document.getElementById("managed-modal");
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
  });
});
