import { expect } from "@open-wc/testing";

import { applyBrokenImagePlaceholder } from "/static/js/common/media/broken-images.js";
import "/static/js/common/modals/images-gallery.js";
import { resetRestoredModalState } from "/static/js/common/modals/modal-lifecycle.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

const IMAGES = ["https://example.com/1.png", "https://example.com/2.png", "https://example.com/3.png"];

/**
 * Builds a touch event. Plain events keep the fixture independent of Touch support.
 * @param {string} type Event type.
 * @param {{x: number, y: number}[]} touches Fingers on the screen.
 * @param {{x: number, y: number}[]} changedTouches Fingers that changed.
 * @returns {Event} Touch-shaped event.
 */
const touchEvent = (type, touches, changedTouches = touches) => {
  const toTouch = ({ x, y }) => ({ clientX: x, clientY: y });
  return Object.assign(new Event(type, { bubbles: true }), {
    changedTouches: changedTouches.map(toTouch),
    touches: touches.map(toTouch),
  });
};

/**
 * Plays a one-finger swipe on the lightbox.
 * @param {Element} lightbox Lightbox root.
 * @param {number} deltaX Horizontal travel.
 * @param {number} deltaY Vertical travel.
 * @returns {void}
 */
const swipe = (lightbox, deltaX, deltaY = 0) => {
  const start = { x: 200, y: 200 };
  lightbox.dispatchEvent(touchEvent("touchstart", [start]));
  lightbox.dispatchEvent(
    touchEvent("touchend", [], [{ x: start.x + deltaX, y: start.y + deltaY }]),
  );
};

/**
 * Presses Tab on the document.
 * @param {{shiftKey?: boolean}} [options] Key modifiers.
 * @returns {KeyboardEvent} Dispatched event.
 */
const pressTab = ({ shiftKey = false } = {}) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab", shiftKey });
  document.dispatchEvent(event);
  return event;
};

/**
 * Reads the dialog attributes of the lightbox.
 * @param {Element} lightbox Lightbox root.
 * @returns {(string|null)[]} Role, modal state and name.
 */
const readDialogAttributes = (lightbox) =>
  ["role", "aria-modal", "aria-label"].map((name) => lightbox.getAttribute(name));

/**
 * Counts swipe listeners added to and removed from the lightbox.
 * @param {Element} lightbox Lightbox root.
 * @returns {{added: string[], removed: string[]}} Listener types.
 */
const trackSwipeListeners = (lightbox) => {
  const listeners = { added: [], removed: [] };
  const { addEventListener, removeEventListener } = lightbox;

  lightbox.addEventListener = function add(type, ...rest) {
    listeners.added.push(type);
    return addEventListener.call(this, type, ...rest);
  };
  lightbox.removeEventListener = function remove(type, ...rest) {
    listeners.removed.push(type);
    return removeEventListener.call(this, type, ...rest);
  };

  return listeners;
};

describe("images-gallery", () => {
  useMountedElementsCleanup("images-gallery");

  let media;
  let phoneStyle = null;

  /**
   * Renders a gallery and opens its lightbox.
   * @param {string[]} images Gallery images.
   * @returns {Promise<{element: HTMLElement, lightbox: Element}>} Fixture nodes.
   */
  const openLightbox = async (images = IMAGES) => {
    const element = await mountLitComponent("images-gallery", { images });
    const lightbox = element.querySelector(".modal");
    return { element, lightbox };
  };

  /**
   * Renders a gallery and opens its lightbox from the first tile.
   * @returns {Promise<object>} Fixture nodes.
   */
  const openFromTile = async () => {
    const { element, lightbox } = await openLightbox();
    const tile = element.querySelector("button");
    tile.click();
    await element.updateComplete;
    return {
      closeButton: lightbox.querySelector(".modal-close"),
      element,
      lightbox,
      nextButton: [...lightbox.querySelectorAll("button")].at(-1),
      tile,
    };
  };

  /**
   * Hides the closed lightbox as the phone stylesheet does, which unit pages do not load.
   * @returns {void}
   */
  const applyPhoneInvisible = () => {
    phoneStyle = document.createElement("style");
    phoneStyle.textContent = ".phone\\:invisible { visibility: hidden; }";
    document.head.append(phoneStyle);
  };

  beforeEach(() => {
    media = stubMatchMedia();
  });

  afterEach(() => {
    media?.restore();
    phoneStyle?.remove();
    phoneStyle = null;
  });

  it("opens the modal and navigates through the image carousel", async () => {
    // Render the images-gallery fixture.
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png", "https://example.com/2.png"],
      title: "Gallery",
    });

    // Open the modal at the first image and lock body scrolling.
    element._openModal(0);
    await element.updateComplete;

    // The modal opens on the first image and disables body scroll.
    expect(element._isModalOpen).to.equal(true);
    expect(element._currentIndex).to.equal(0);
    expect(document.body.style.overflow).to.equal("hidden");

    // ArrowRight advances to the next gallery image.
    element._handleKeydown({ key: "ArrowRight" });
    expect(element._currentIndex).to.equal(1);

    // ArrowLeft returns to the previous gallery image.
    element._handleKeydown({ key: "ArrowLeft" });
    expect(element._currentIndex).to.equal(0);
  });

  it("renders gallery images inside stable positioned containers", async () => {
    // Render the images-gallery fixture.
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png"],
      title: "Gallery",
    });

    // Read the inline images that should keep relative positioning.
    const thumbnailButton = [...element.querySelectorAll("button")].find(
      (button) => button.querySelector('img[alt="Gallery image 1"]'),
    );
    const thumbnailImage = thumbnailButton?.querySelector(
      'img[alt="Gallery image 1"]',
    );
    const mobileImage = [
      ...element.querySelectorAll('img[alt="Gallery image 1"]'),
    ].find((image) => image.parentElement?.classList.contains("md:hidden"));

    // Inline gallery image containers keep relative positioning.
    expect(thumbnailButton?.classList.contains("relative")).to.equal(true);
    expect(thumbnailButton?.classList.contains("overflow-hidden")).to.equal(true);
    expect(thumbnailButton?.classList.contains("bg-plate")).to.equal(true);
    expect(thumbnailButton?.classList.contains("hover:outline-primary-edge-soft")).to.equal(true);
    expect(thumbnailButton?.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(mobileImage?.parentElement?.classList.contains("relative")).to.equal(
      true,
    );
    expect(mobileImage?.parentElement?.classList.contains("overflow-hidden")).to.equal(true);
    expect(mobileImage?.parentElement?.classList.contains("bg-plate")).to.equal(true);

    // Phones show the button tile and drop the static one.
    expect(thumbnailButton?.parentElement?.classList.contains("phone:block")).to.equal(true);
    expect(mobileImage?.parentElement?.classList.contains("phone:hidden")).to.equal(true);

    // Broken thumbnails keep the white mat and clip the fallback inside it.
    applyBrokenImagePlaceholder(thumbnailImage);
    const thumbnailFallback = thumbnailImage?.nextElementSibling;
    expect(thumbnailFallback?.classList.contains("m-[5px]")).to.equal(true);
    expect(thumbnailFallback?.classList.contains("rounded-md")).to.equal(true);

    // Open the modal to inspect the fixed-position carousel image.
    element._openModal(0);
    await element.updateComplete;

    // Modal carousel images use absolute positioning instead.
    const modalImage = [
      ...element.querySelectorAll('img[alt="Gallery image 1"]'),
    ].find((image) => image.classList.contains("top-1/2"));
    expect(modalImage?.parentElement?.classList.contains("absolute")).to.equal(
      true,
    );
    expect(modalImage?.parentElement?.classList.contains("relative")).to.equal(
      false,
    );
  });

  it("closes the modal from escape and background clicks", async () => {
    // Render the images-gallery fixture.
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png"],
    });

    // Open the modal.
    element._openModal(0);
    await element.updateComplete;

    // Escape closes the modal and restores body scrolling.
    element._handleKeydown({ key: "Escape" });
    expect(element._isModalOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");

    // Reopen the modal and close it from a background click.
    element._openModal(0);
    element._handleModalBackgroundClick({
      target: {
        tagName: "DIV",
        parentElement: null,
      },
    });

    // Background clicks close the reopened modal.
    expect(element._isModalOpen).to.equal(false);
  });

  it("sizes phone tiles by the image count", async () => {
    // Several images leave the next tile peeking in.
    const element = await mountLitComponent("images-gallery", { images: IMAGES });
    const tile = element.querySelector("button").parentElement;
    expect(tile.classList.contains("phone:w-[calc(100%-3.5rem)]")).to.equal(true);
    expect(tile.classList.contains("phone:w-full")).to.equal(false);

    // A single image fills the row.
    const single = await mountLitComponent("images-gallery", { images: IMAGES.slice(0, 1) });
    const singleTile = single.querySelector("button").parentElement;
    expect(singleTile.classList.contains("phone:w-full")).to.equal(true);
    expect(singleTile.classList.contains("phone:w-[calc(100%-3.5rem)]")).to.equal(false);
  });

  it("deepens the scrim and narrows the title for phone lightboxes", async () => {
    const element = await mountLitComponent("images-gallery", { images: IMAGES });

    // The page behind a full-width image and under the title must stay quiet.
    const overlay = element.querySelector(".modal-overlay");
    expect(overlay?.classList.contains("phone:opacity-[0.85]")).to.equal(true);

    // The 200px minimum would run the title into the close button at 320px.
    const title = element.querySelector(".modal-content")?.firstElementChild;
    expect(title?.classList.contains("phone:min-w-0")).to.equal(true);
  });

  it("renders the position row after the list only for several images", async () => {
    // The row follows the list, so snap-dots.js can find its scroller.
    const element = await mountLitComponent("images-gallery", { images: IMAGES });
    const row = element.querySelector("[data-snap-dots]");
    expect(row?.previousElementSibling?.classList.contains("phone:snap-x")).to.equal(true);
    expect(row?.classList.contains("not-phone:hidden")).to.equal(true);
    expect(row?.getAttribute("aria-hidden")).to.equal("true");
    expect(row?.dataset.snapDotsMax).to.equal("10");
    expect(row?.querySelector("[data-snap-counter]")?.textContent).to.equal("");

    // A single photo has no position to show.
    const single = await mountLitComponent("images-gallery", { images: IMAGES.slice(0, 1) });
    expect(single.querySelector("[data-snap-dots]")).to.equal(null);
  });

  it("swipes between images on phones", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openLightbox();
    element._openModal(0);

    // A swipe left moves forward, and a swipe right moves back.
    swipe(lightbox, -48);
    expect(element._currentIndex).to.equal(1);
    swipe(lightbox, 48);
    expect(element._currentIndex).to.equal(0);

    // Navigation wraps as the arrows do.
    swipe(lightbox, 60);
    expect(element._currentIndex).to.equal(2);
  });

  it("ignores short and mostly vertical swipes", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openLightbox();
    element._openModal(0);

    // Below the minimum distance.
    swipe(lightbox, -47);
    expect(element._currentIndex).to.equal(0);

    // Exactly 1.5 times the vertical travel is not more than it.
    swipe(lightbox, -60, 40);
    expect(element._currentIndex).to.equal(0);

    // Just past the ratio counts.
    swipe(lightbox, -61, 40);
    expect(element._currentIndex).to.equal(1);

    // A touchend with no touchstart does nothing.
    lightbox.dispatchEvent(touchEvent("touchend", [], [{ x: 0, y: 0 }]));
    expect(element._currentIndex).to.equal(1);
  });

  it("cancels the swipe when a second finger lands", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openLightbox();
    element._openModal(0);

    // Start with one finger, then pinch with a second.
    const first = { x: 200, y: 200 };
    const second = { x: 100, y: 200 };
    lightbox.dispatchEvent(touchEvent("touchstart", [first]));
    lightbox.dispatchEvent(touchEvent("touchstart", [first, second], [second]));

    // Neither finger lifting counts as a swipe.
    lightbox.dispatchEvent(touchEvent("touchend", [second], [{ x: 20, y: 200 }]));
    lightbox.dispatchEvent(touchEvent("touchend", [], [{ x: 20, y: 200 }]));
    expect(element._currentIndex).to.equal(0);

    // The next single-finger swipe works again.
    swipe(lightbox, -100);
    expect(element._currentIndex).to.equal(1);
  });

  it("binds no swipe for a single image or off phones", async () => {
    // A single image never binds, even on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const single = await openLightbox(IMAGES.slice(0, 1));
    const singleListeners = trackSwipeListeners(single.lightbox);
    single.element._openModal(0);
    swipe(single.lightbox, -100);
    expect(singleListeners.added).to.deep.equal([]);
    expect(single.element._currentIndex).to.equal(0);

    // A false query never binds either.
    media.setMatches(PHONE_MEDIA_QUERY, false);
    const { element, lightbox } = await openLightbox();
    const listeners = trackSwipeListeners(lightbox);
    element._openModal(0);
    swipe(lightbox, -100);
    expect(listeners.added).to.deep.equal([]);
    expect(element._currentIndex).to.equal(0);
  });

  it("removes swipe listeners on close and disconnect", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openLightbox();
    const listeners = trackSwipeListeners(lightbox);
    element._openModal(0);
    expect(listeners.added).to.deep.equal(["touchstart", "touchend"]);

    // Closing removes both listeners, and a swipe no longer navigates.
    element._closeModal();
    expect(listeners.removed).to.deep.equal(["touchstart", "touchend"]);
    swipe(lightbox, -100);
    expect(element._currentIndex).to.equal(0);

    // Reopening binds once, without doubling a swipe.
    element._openModal(0);
    element._openModal(0);
    swipe(lightbox, -100);
    expect(element._currentIndex).to.equal(1);

    // Disconnecting releases the open lightbox too.
    element.remove();
    expect(listeners.added).to.have.length(listeners.removed.length);
    swipe(lightbox, -100);
    expect(element._currentIndex).to.equal(1);
  });

  it("stops swiping when the query turns false", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openLightbox();
    const listeners = trackSwipeListeners(lightbox);
    element._openModal(0);

    // Rotating past 768px removes the listeners while the lightbox stays open.
    media.setMatches(PHONE_MEDIA_QUERY, false);
    expect(listeners.removed).to.deep.equal(["touchstart", "touchend"]);
    swipe(lightbox, -100);
    expect(element._currentIndex).to.equal(0);
    expect(element._isModalOpen).to.equal(true);

    // The arrows keep working, and close releases the listeners.
    element._navigateCarousel("next");
    expect(element._currentIndex).to.equal(1);
    element._closeModal();
    expect(element._removeSwipeListeners).to.equal(null);
  });

  it("opens as a named dialog on phones and closes back to the tile", async () => {
    // Open the lightbox from a tile.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { closeButton, element, lightbox, tile } = await openFromTile();

    // Verify the semantics and the focus entry.
    expect(readDialogAttributes(lightbox)).to.deep.equal(["dialog", "true", "Gallery"]);
    expect(document.activeElement).to.equal(closeButton);

    // Verify a close removes all of it and hands focus back.
    closeButton.click();
    await element.updateComplete;
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
    expect(document.activeElement).to.equal(tile);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
  });

  it("names the dialog after the gallery title", async () => {
    // Open a gallery with its own title.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const element = await mountLitComponent("images-gallery", { images: IMAGES, title: "Summit photos" });
    element.querySelector("button").click();

    // Verify the name follows the title.
    expect(element.querySelector(".modal").getAttribute("aria-label")).to.equal("Summit photos");
  });

  it("returns focus to the tile on Escape", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, tile } = await openFromTile();

    // Close from the keyboard.
    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));

    // Verify the lightbox closed and focus went back.
    expect(element._isModalOpen).to.equal(false);
    expect(document.activeElement).to.equal(tile);
  });

  it("keeps Tab inside the lightbox on phones", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { closeButton, nextButton } = await openFromTile();

    // Verify Shift+Tab wraps from the first control to the last.
    expect(pressTab({ shiftKey: true }).defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(nextButton);

    // Verify Tab wraps from the last control to the first.
    expect(pressTab().defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(closeButton);

    // Verify focus knocked out of the lightbox comes back.
    document.activeElement.blur();
    expect(pressTab().defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(closeButton);
  });

  it("keeps the tile focused after a backdrop tap closes on mousedown", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox, tile } = await openFromTile();

    // Press the backdrop, which closes during the mousedown.
    const press = new MouseEvent("mousedown", { bubbles: true, cancelable: true });
    lightbox.querySelector(".modal-overlay").dispatchEvent(press);

    // Verify the default action, which would clear focus, is stopped.
    expect(element._isModalOpen).to.equal(false);
    expect(press.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(tile);
  });

  it("drops the dialog on rotation and still returns focus on close", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { closeButton, element, lightbox, nextButton, tile } = await openFromTile();

    // Rotate past the phone width.
    media.setMatches(PHONE_MEDIA_QUERY, false);

    // Verify the lightbox stays open as the plain one, holding only the query listener.
    expect(element._isModalOpen).to.equal(true);
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);

    // Verify Tab is free again.
    nextButton.focus();
    expect(pressTab().defaultPrevented).to.equal(false);

    // Verify the close of a lightbox opened on a phone still hands focus back.
    closeButton.click();
    expect(document.activeElement).to.equal(tile);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
  });

  it("binds the dialog and swipe again when rotated back", async () => {
    // Open the lightbox on a phone, then rotate out and back.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { closeButton, element, lightbox, nextButton, tile } = await openFromTile();
    media.setMatches(PHONE_MEDIA_QUERY, false);
    media.setMatches(PHONE_MEDIA_QUERY, true);

    // Verify the semantics, the trap and the swipe are back, with one listener of each.
    expect(readDialogAttributes(lightbox)).to.deep.equal(["dialog", "true", "Gallery"]);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);
    nextButton.focus();
    expect(pressTab().defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(closeButton);
    swipe(lightbox, -100);
    expect(element._currentIndex).to.equal(1);

    // Verify a second round trip stays the same, and the close releases all of it.
    media.setMatches(PHONE_MEDIA_QUERY, false);
    media.setMatches(PHONE_MEDIA_QUERY, true);
    swipe(lightbox, -100);
    expect(element._currentIndex).to.equal(2);
    closeButton.click();
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    expect(document.activeElement).to.equal(tile);
  });

  it("closes before a history snapshot after a round trip, but not as the plain lightbox", async () => {
    // Open the lightbox on a phone and rotate out.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element } = await openFromTile();
    media.setMatches(PHONE_MEDIA_QUERY, false);

    // Verify the plain lightbox keeps its desktop behaviour.
    document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave"));
    expect(element._isModalOpen).to.equal(true);

    // Verify the dialog closes again once it is back.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave"));
    expect(element._isModalOpen).to.equal(false);
  });

  it("keeps focus on a lightbox control through a rotation", async () => {
    // Move to Next, then rotate out and back.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { nextButton } = await openFromTile();
    nextButton.focus();
    media.setMatches(PHONE_MEDIA_QUERY, false);
    media.setMatches(PHONE_MEDIA_QUERY, true);

    // Verify focus did not jump to Close.
    expect(document.activeElement).to.equal(nextButton);
  });

  it("brings focus back into the dialog when it left while rotated", async () => {
    // Rotate out, and let focus reach the page behind the plain lightbox.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { closeButton, tile } = await openFromTile();
    media.setMatches(PHONE_MEDIA_QUERY, false);
    tile.focus();

    // Rotate back and verify a modal dialog holds focus again.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    expect(document.activeElement).to.equal(closeButton);
  });

  it("binds no swipe for a single image on the way back", async () => {
    // Open a single image on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openLightbox(IMAGES.slice(0, 1));
    const listeners = trackSwipeListeners(lightbox);
    element._openModal(0);

    // Verify the round trip restores the dialog only.
    media.setMatches(PHONE_MEDIA_QUERY, false);
    media.setMatches(PHONE_MEDIA_QUERY, true);
    expect(readDialogAttributes(lightbox)).to.deep.equal(["dialog", "true", "Gallery"]);
    expect(listeners.added).to.deep.equal([]);
  });

  it("releases the query listener on disconnect while rotated", async () => {
    // Open the lightbox on a phone and rotate out.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openFromTile();
    media.setMatches(PHONE_MEDIA_QUERY, false);

    // Remove the gallery, then rotate back.
    element.remove();
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    media.setMatches(PHONE_MEDIA_QUERY, true);

    // Verify nothing came back.
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
  });

  it("takes the closed lightbox out of reach on phones with one token", async () => {
    // Render the closed lightbox.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    applyPhoneInvisible();
    const { element, lightbox } = await openLightbox();

    // Verify the closed controls cannot take focus.
    expect(lightbox.classList.contains("phone:invisible")).to.equal(true);
    const closeButton = lightbox.querySelector(".modal-close");
    closeButton.focus();
    expect(document.activeElement).not.to.equal(closeButton);

    // Verify the open lightbox drops the token and takes focus once it renders.
    element.querySelector("button").click();
    await element.updateComplete;
    expect(lightbox.classList.contains("phone:invisible")).to.equal(false);
    expect(document.activeElement).to.equal(closeButton);

    // Verify a close brings it back.
    closeButton.click();
    await element.updateComplete;
    expect(lightbox.classList.contains("phone:invisible")).to.equal(true);
  });

  it("does not move focus for a lightbox closed before it rendered", async () => {
    // Open and close in the same task.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openLightbox();
    const tile = element.querySelector("button");
    tile.focus();
    element._openModal(0, tile);
    element._closeModal();
    await element.updateComplete;

    // Verify focus stays on the tile and nothing is held.
    expect(document.activeElement).to.equal(tile);
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
  });

  it("closes before a history snapshot", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openFromTile();

    // Save the page to history.
    document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave"));

    // Verify no open state reaches the snapshot.
    expect(element._isModalOpen).to.equal(false);
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
  });

  it("recovers from the shared restore of the back-forward cache", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { closeButton, element, lightbox, tile } = await openFromTile();

    // A first page show changes nothing.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: false }));
    expect(element._isModalOpen).to.equal(true);

    // Restore the page: the shared reset runs first, as it was bound at load.
    resetRestoredModalState(document);
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));
    await element.updateComplete;

    // Verify the lightbox is closed and carries nothing from the reset.
    expect(element._isModalOpen).to.equal(false);
    expect(lightbox.classList.contains("hidden")).to.equal(false);
    expect(lightbox.classList.contains("opacity-0")).to.equal(true);
    expect(lightbox.hasAttribute("aria-hidden")).to.equal(false);

    // Verify it opens again.
    tile.click();
    await element.updateComplete;
    expect(lightbox.classList.contains("opacity-0")).to.equal(false);
    expect(document.activeElement).to.equal(closeButton);
  });

  it("releases the dialog on disconnect", async () => {
    // Open the lightbox on a phone.
    media.setMatches(PHONE_MEDIA_QUERY, true);
    const { element, lightbox } = await openFromTile();

    // Remove the gallery while it is open.
    element.remove();

    // Verify nothing stays held.
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    expect(element._restoreLightboxFocus).to.equal(null);
    expect(element._removePhoneQueryListener).to.equal(null);
  });

  it("leaves the lightbox as it is off phones", async () => {
    // Open the lightbox from a focused tile.
    media.setMatches(PHONE_MEDIA_QUERY, false);
    const { element, lightbox } = await openLightbox();
    const tile = element.querySelector("button");
    tile.focus();
    tile.click();
    await element.updateComplete;

    // Verify no attribute, focus move, trap or listener is added.
    expect(readDialogAttributes(lightbox)).to.deep.equal([null, null, null]);
    expect(document.activeElement).to.equal(tile);
    expect(pressTab().defaultPrevented).to.equal(false);
    expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);

    // Verify a backdrop press keeps its default action.
    const press = new MouseEvent("mousedown", { bubbles: true, cancelable: true });
    lightbox.querySelector(".modal-overlay").dispatchEvent(press);
    expect(element._isModalOpen).to.equal(false);
    expect(press.defaultPrevented).to.equal(false);
  });

  it("gives the tile and the lightbox controls a focus ring at every width", async () => {
    const element = await mountLitComponent("images-gallery", { images: IMAGES });

    // The light ring reads on the dark overlay, and the tile outline is not a focus indicator.
    const controls = [element.querySelector("button"), ...element.querySelectorAll(".modal button")];
    expect(controls).to.have.length(4);
    controls.forEach((control) => {
      expect(control.classList.contains("focus-visible:ring-2")).to.equal(true);
      expect(control.classList.contains("focus-visible:ring-primary-halo")).to.equal(true);
      expect(control.classList.contains("phone:focus-visible:ring-2")).to.equal(false);
    });

    // Verify the lightbox controls drop the global outline so only the ring shows.
    controls.slice(1).forEach((control) => {
      expect(control.classList.contains("focus-visible:outline-none")).to.equal(true);
    });
  });

  it("paints the prev and next icons stone-900 inside the ink viewer", async () => {
    const element = await mountLitComponent("images-gallery", { images: IMAGES });

    // The viewer is a light island, and the arrow icons sit on their stone-200 pills.
    expect(element.querySelector(".modal-container")?.classList.contains("ink")).to.equal(true);
    const icons = [element.querySelector(".icon-prev"), element.querySelector(".icon-next")];
    icons.forEach((icon) => {
      expect(icon?.classList.contains("bg-stone-900")).to.equal(true);
      expect(icon?.classList.contains("bg-stone-950")).to.equal(false);
      expect(icon?.parentElement?.classList.contains("bg-stone-200/75")).to.equal(true);
    });
  });
});
