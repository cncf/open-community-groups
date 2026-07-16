import { expect } from "@open-wc/testing";

import {
  convertDateTimeLocalToISO,
  convertDateToDateTimeLocalInTz,
  convertTimestampToDateTimeLocal,
  convertTimestampToDateTimeLocalInTz,
  resolveEventTimezone,
  toDateTimeLocalInTimezone,
  toUtcIsoInTimezone,
} from "/static/js/common/datetime.js";
import { isDashboardPath, scrollToDashboardTop } from "/static/js/common/dashboard-path.js";
import {
  applyBrokenImagePlaceholder,
  applyBrokenImagePlaceholders,
  BROKEN_IMAGE_PLACEHOLDER_URL,
  clearBrokenImagePlaceholder,
} from "/static/js/common/media/broken-images.js";
import { hideLoadingSpinner, showLoadingSpinner } from "/static/js/common/loading-spinner.js";
import {
  lockBodyScroll,
  resetBodyScrollLock,
  toggleModalVisibility,
  unlockBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
import { isObjectEmpty } from "/static/js/common/utils.js";
import { resetDom, setLocationPath, mockScrollTo } from "/tests/unit/test-utils/dom.js";

describe("common utilities", () => {
  const originalPath = window.location.pathname;

  let scrollToMock;

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
    scrollToMock?.restore();
    setLocationPath(originalPath);
  });

  it("toggles the loading spinner class by element id", () => {
    // Create the loading target.
    const element = document.createElement("div");
    element.id = "content";
    document.body.append(element);

    // Show the loading state.
    showLoadingSpinner("content");
    expect(element.classList.contains("is-loading")).to.equal(true);

    // Hide the loading state.
    hideLoadingSpinner("content");
    expect(element.classList.contains("is-loading")).to.equal(false);
  });

  it("replaces broken images with the shared placeholder", () => {
    // Create the image fixture.
    const container = document.createElement("div");
    const image = document.createElement("img");
    image.src = "https://example.com/missing.png";
    image.srcset = "https://example.com/missing-2x.png 2x";
    container.append(image);
    document.body.append(container);

    // Assert the error event.
    image.dispatchEvent(new Event("error"));

    // The broken image now uses the shared placeholder.
    expect(image.src.endsWith(BROKEN_IMAGE_PLACEHOLDER_URL)).to.equal(true);
    expect(image.getAttribute("srcset")).to.equal(null);
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal("true");
    expect(image.classList.contains("invisible")).to.equal(true);
    expect(image.parentElement?.classList.contains("relative")).to.equal(true);
    expect(image.nextElementSibling?.dataset.ocgBrokenImageIcon).to.equal("true");
    expect(image.nextElementSibling?.classList.contains("absolute") ?? false).to.equal(true);
    expect(image.nextElementSibling?.classList.contains("inset-0") ?? false).to.equal(true);
    expect(image.nextElementSibling?.classList.contains("bg-stone-50") ?? false).to.equal(true);
    const icon = image.nextElementSibling?.querySelector(".svg-icon");
    expect(icon?.classList.contains("icon-broken-image") ?? false).to.equal(true);
    expect(icon?.classList.contains("bg-stone-400") ?? false).to.equal(true);
    expect(applyBrokenImagePlaceholder(image)).to.equal(false);
  });

  it("uses a custom broken image placeholder background when provided", () => {
    // Create the image fixture.
    const container = document.createElement("div");
    const image = document.createElement("img");
    image.src = "https://example.com/missing.png";
    image.dataset.ocgBrokenImageBgClass = "bg-stone-950";
    container.append(image);
    document.body.append(container);

    // Assert the error event.
    image.dispatchEvent(new Event("error"));

    // The visual state matches the scenario.
    expect(image.nextElementSibling?.classList.contains("bg-stone-950") ?? false).to.equal(true);
    expect(image.nextElementSibling?.classList.contains("bg-stone-50") ?? false).to.equal(false);
  });

  it("removes broken images inside opted-in content areas", () => {
    // Create the opted-in markdown fixture.
    const description = document.createElement("div");
    const paragraph = document.createElement("p");
    const image = document.createElement("img");
    description.dataset.ocgRemoveBrokenImages = "";
    image.src = "https://example.com/missing.png";
    paragraph.append(image);
    description.append(paragraph);
    document.body.append(description);

    // Assert the error event.
    image.dispatchEvent(new Event("error"));

    // The failed image and empty paragraph are removed.
    expect(description.querySelector("img")).to.equal(null);
    expect(description.querySelector("p")).to.equal(null);
  });

  it("removes opted-in images that failed before the error listener ran", () => {
    // Create the completed failed image fixture.
    const description = document.createElement("div");
    const image = document.createElement("img");
    description.dataset.ocgRemoveBrokenImages = "";
    image.src = "https://example.com/missing-before-listener.png";
    Object.defineProperty(image, "complete", {
      configurable: true,
      value: true,
    });
    Object.defineProperty(image, "naturalWidth", {
      configurable: true,
      value: 0,
    });
    description.append(image);
    document.body.append(description);

    // Scan for failed images after the page is ready.
    expect(applyBrokenImagePlaceholders(document)).to.equal(0);

    // The failed image is removed instead of replaced with a placeholder.
    expect(description.querySelector("img")).to.equal(null);
    expect(description.querySelector("[data-ocg-broken-image-icon]")).to.equal(null);
  });

  it("does not add relative to parents that are already positioned", () => {
    // Create the image fixture.
    const container = document.createElement("div");
    const image = document.createElement("img");
    container.style.position = "absolute";
    image.src = "https://example.com/missing.png";
    container.append(image);
    document.body.append(container);

    // Assert the error event.
    image.dispatchEvent(new Event("error"));

    // Positioned parents are left unchanged.
    expect(getComputedStyle(container).position).to.equal("absolute");
    expect(container.classList.contains("relative")).to.equal(false);
    expect(container.dataset.ocgBrokenImageAddedRelative).to.equal(undefined);
    expect(image.nextElementSibling?.classList.contains("absolute") ?? false).to.equal(true);
  });

  it("replaces images that failed before the error listener ran", () => {
    // Create the image fixture.
    const container = document.createElement("div");
    const image = document.createElement("img");
    image.src = "https://example.com/missing-before-listener.png";
    Object.defineProperty(image, "complete", {
      configurable: true,
      value: true,
    });
    Object.defineProperty(image, "naturalWidth", {
      configurable: true,
      value: 0,
    });
    container.append(image);
    document.body.append(container);

    // Replaces images that failed before the error listener ran.
    expect(applyBrokenImagePlaceholders(document)).to.equal(1);

    // The broken image now uses the shared placeholder.
    expect(image.src.endsWith(BROKEN_IMAGE_PLACEHOLDER_URL)).to.equal(true);
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal("true");
    expect(image.nextElementSibling?.dataset.ocgBrokenImageIcon).to.equal("true");
  });

  it("keeps initials avatar images on their component fallback path", () => {
    // Create the logo-image fixture element.
    const avatar = document.createElement("logo-image");
    const image = document.createElement("img");
    image.src = "https://example.com/avatar.png";
    avatar.append(image);
    document.body.append(avatar);

    // Assert the error event.
    image.dispatchEvent(new Event("error"));

    // The image fallback is left untouched.
    expect(image.src).to.equal("https://example.com/avatar.png");
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal(undefined);
  });

  it("ignores empty image sources until a real source fails", () => {
    // Create the img fixture element.
    const image = document.createElement("img");
    image.setAttribute("src", "");
    Object.defineProperty(image, "currentSrc", {
      configurable: true,
      value: "https://example.com/current-page",
    });
    document.body.append(image);

    // Assert the error event.
    image.dispatchEvent(new Event("error"));

    // The image fallback is left untouched.
    expect(image.getAttribute("src")).to.equal("");
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal(undefined);
  });

  it("clears broken image state when a later source loads", () => {
    // Create the image fixture.
    const container = document.createElement("div");
    const image = document.createElement("img");
    image.src = "https://example.com/missing.png";
    container.append(image);
    document.body.append(container);

    // Assert the error event.
    image.dispatchEvent(new Event("error"));
    image.src = "https://example.com/recovered.png";
    image.dispatchEvent(new Event("load"));

    // The image fallback is left untouched.
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal(undefined);
    expect(image.classList.contains("invisible")).to.equal(false);
    expect(image.parentElement?.classList.contains("relative")).to.equal(false);
    expect(image.nextElementSibling?.dataset.ocgBrokenImageIcon).to.equal(undefined);
    expect(clearBrokenImagePlaceholder(image)).to.equal(false);
  });

  it("detects dashboard paths and scrolls only on dashboard pages", () => {
    // Mock page scrolling.
    scrollToMock = mockScrollTo();

    // Non-dashboard paths do not trigger dashboard scrolling.
    setLocationPath("/communities/cncf");
    expect(isDashboardPath()).to.equal(false);
    scrollToDashboardTop();
    expect(scrollToMock.calls).to.deep.equal([]);

    // Dashboard paths trigger a scroll to the top of the dashboard.
    setLocationPath("/dashboard/groups");
    expect(isDashboardPath()).to.equal(true);
    scrollToDashboardTop();
    expect(scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });

  it("locks body scroll and manages focus when toggling a modal", () => {
    // Create the modal fixture.
    const trigger = document.createElement("button");
    trigger.textContent = "Open";
    const modal = document.createElement("div");
    modal.id = "test-modal";
    modal.className = "hidden";
    modal.innerHTML = '<button id="modal-close">Close</button>';
    document.body.append(trigger, modal);
    trigger.focus();

    // Opening the modal locks body scroll and increments the lock count.
    toggleModalVisibility("test-modal", trigger);
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(modal.getAttribute("aria-hidden")).to.equal("false");
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.activeElement).to.equal(document.getElementById("modal-close"));

    // Closing the modal releases body scroll, clears the count, and restores focus.
    toggleModalVisibility("test-modal");
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.activeElement).to.equal(trigger);
  });

  it("tracks nested lock counts before unlocking body scroll", () => {
    // Nested locks keep body scrolling disabled and count both locks.
    lockBodyScroll();
    lockBodyScroll();
    expect(document.body.dataset.modalOpenCount).to.equal("2");
    expect(document.body.style.overflow).to.equal("hidden");

    // Releasing one lock keeps body scrolling disabled.
    unlockBodyScroll();
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.body.style.overflow).to.equal("hidden");

    // Releasing the final lock restores body scrolling.
    unlockBodyScroll();
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });

  it("resets body scroll locks from restored page snapshots", () => {
    // Simulate a cached page snapshot with an active modal lock.
    document.body.dataset.modalOpenCount = "1";
    document.body.dataset.modalOverflow = "";
    document.body.dataset.modalPaddingRight = "";
    document.body.style.overflow = "hidden";
    document.body.style.paddingRight = "15px";

    // Reset the restored modal lock state.
    resetBodyScrollLock();

    // Body scroll state returns to the snapshot baseline.
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.style.paddingRight).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal(undefined);
  });

  it("formats initials, datetimes, and empty-object checks", () => {
    // Initials are derived from names with fallback text.
    expect(computeUserInitials("Open Community", "ocg")).to.equal("OC");
    expect(computeUserInitials("Single", "ocg", 1)).to.equal("S");
    expect(computeUserInitials("", "ocg")).to.equal("O");

    // Datetime-local strings serialize and blank values stay empty.
    expect(convertDateTimeLocalToISO("2025-08-23T15:00")).to.equal("2025-08-23T15:00:00");
    expect(convertDateTimeLocalToISO("")).to.equal(null);

    // Unix timestamps convert only from numeric values.
    expect(convertTimestampToDateTimeLocal(1735689600)).to.equal("2025-01-01T00:00");
    expect(convertTimestampToDateTimeLocal("1735689600")).to.equal("");

    // Timezone conversion applies offsets and ignores missing timezones.
    expect(convertTimestampToDateTimeLocalInTz(1735689600, "America/New_York")).to.equal("2024-12-31T19:00");
    expect(convertTimestampToDateTimeLocalInTz(1735689600, "")).to.equal("");

    // Object emptiness ignores blank values but keeps filled ones.
    expect(isObjectEmpty({ id: 10, title: "", tags: [], published: false })).to.equal(true);
    expect(isObjectEmpty({ id: 10, title: "OCG" })).to.equal(false);
  });

  it("resolves event timezones from explicit fields and the document fallback", () => {
    // Create the input fixture.
    const timezoneField = document.createElement("input");
    timezoneField.name = "timezone";
    timezoneField.value = "  Europe/Madrid  ";
    document.body.append(timezoneField);

    // Timezone fields are trimmed and reused as fallback.
    expect(resolveEventTimezone(timezoneField)).to.equal("Europe/Madrid");
    expect(resolveEventTimezone()).to.equal("Europe/Madrid");
    expect(resolveEventTimezone(null)).to.equal("");
  });

  it("formats datetime-local values in a timezone-aware way", () => {
    // Date values format in the requested timezone.
    expect(convertDateToDateTimeLocalInTz(new Date("2025-01-01T00:00:00.000Z"), "America/New_York")).to.equal(
      "2024-12-31T19:00",
    );
    expect(convertDateToDateTimeLocalInTz(new Date("invalid"), "America/New_York")).to.equal("");

    // Date values format in the requested timezone.
    expect(toDateTimeLocalInTimezone("2025-01-01T00:00:00.000Z", "America/New_York")).to.equal(
      "2024-12-31T19:00",
    );
    expect(toDateTimeLocalInTimezone("2025-01-01T00:00:00.000Z", "")).to.equal("2025-01-01T00:00");
    expect(toDateTimeLocalInTimezone("not-a-date", "America/New_York")).to.equal("");
  });

  it("converts datetime-local values back to UTC ISO strings", () => {
    // Local datetime values convert back to UTC.
    expect(toUtcIsoInTimezone("2026-04-10T10:00", "America/New_York")).to.equal("2026-04-10T14:00:00.000Z");

    // Empty or invalid timezone values preserve fallback behavior.
    expect(toUtcIsoInTimezone(" 2026-04-10T10:00 ", "")).to.equal("2026-04-10T10:00");
    expect(toUtcIsoInTimezone("invalid", "America/New_York")).to.equal("invalid");
    expect(toUtcIsoInTimezone("", "America/New_York")).to.equal(null);
  });
});
