import { expect } from "@open-wc/testing";

import {
  computeUserInitials,
  convertDateTimeLocalToISO,
  convertDateToDateTimeLocalInTz,
  convertTimestampToDateTimeLocal,
  convertTimestampToDateTimeLocalInTz,
  applyBrokenImagePlaceholder,
  applyBrokenImagePlaceholders,
  BROKEN_IMAGE_PLACEHOLDER_URL,
  clearBrokenImagePlaceholder,
  hideLoadingSpinner,
  isDashboardPath,
  isObjectEmpty,
  lockBodyScroll,
  resolveEventTimezone,
  scrollToDashboardTop,
  showLoadingSpinner,
  toDateTimeLocalInTimezone,
  toUtcIsoInTimezone,
  toggleModalVisibility,
  unlockBodyScroll,
} from "/static/js/common/common.js";
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
    const element = document.createElement("div");
    element.id = "content";
    document.body.append(element);

    showLoadingSpinner("content");
    expect(element.classList.contains("is-loading")).to.equal(true);

    hideLoadingSpinner("content");
    expect(element.classList.contains("is-loading")).to.equal(false);
  });

  it("replaces broken images with the shared placeholder", () => {
    const container = document.createElement("div");
    const image = document.createElement("img");
    image.src = "https://example.com/missing.png";
    image.srcset = "https://example.com/missing-2x.png 2x";
    container.append(image);
    document.body.append(container);

    image.dispatchEvent(new Event("error"));

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

  it("replaces images that failed before the error listener ran", () => {
    const container = document.createElement("div");
    const image = document.createElement("img");
    image.src = "https://example.com/missing-before-listener.png";
    Object.defineProperty(image, "complete", { configurable: true, value: true });
    Object.defineProperty(image, "naturalWidth", { configurable: true, value: 0 });
    container.append(image);
    document.body.append(container);

    expect(applyBrokenImagePlaceholders(document)).to.equal(1);

    expect(image.src.endsWith(BROKEN_IMAGE_PLACEHOLDER_URL)).to.equal(true);
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal("true");
    expect(image.nextElementSibling?.dataset.ocgBrokenImageIcon).to.equal("true");
  });

  it("keeps initials avatar images on their component fallback path", () => {
    const avatar = document.createElement("logo-image");
    const image = document.createElement("img");
    image.src = "https://example.com/avatar.png";
    avatar.append(image);
    document.body.append(avatar);

    image.dispatchEvent(new Event("error"));

    expect(image.src).to.equal("https://example.com/avatar.png");
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal(undefined);
  });

  it("ignores empty image sources until a real source fails", () => {
    const image = document.createElement("img");
    image.setAttribute("src", "");
    Object.defineProperty(image, "currentSrc", {
      configurable: true,
      value: "https://example.com/current-page",
    });
    document.body.append(image);

    image.dispatchEvent(new Event("error"));

    expect(image.getAttribute("src")).to.equal("");
    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal(undefined);
  });

  it("clears broken image state when a later source loads", () => {
    const container = document.createElement("div");
    const image = document.createElement("img");
    image.src = "https://example.com/missing.png";
    container.append(image);
    document.body.append(container);

    image.dispatchEvent(new Event("error"));
    image.src = "https://example.com/recovered.png";
    image.dispatchEvent(new Event("load"));

    expect(image.dataset.ocgBrokenImagePlaceholder).to.equal(undefined);
    expect(image.classList.contains("invisible")).to.equal(false);
    expect(image.parentElement?.classList.contains("relative")).to.equal(false);
    expect(image.nextElementSibling?.dataset.ocgBrokenImageIcon).to.equal(undefined);
    expect(clearBrokenImagePlaceholder(image)).to.equal(false);
  });

  it("detects dashboard paths and scrolls only on dashboard pages", () => {
    scrollToMock = mockScrollTo();

    setLocationPath("/communities/cncf");
    expect(isDashboardPath()).to.equal(false);
    scrollToDashboardTop();
    expect(scrollToMock.calls).to.deep.equal([]);

    setLocationPath("/dashboard/groups");
    expect(isDashboardPath()).to.equal(true);
    scrollToDashboardTop();
    expect(scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });

  it("locks and unlocks body scroll when toggling a modal", () => {
    const modal = document.createElement("div");
    modal.id = "test-modal";
    modal.className = "hidden";
    document.body.append(modal);

    toggleModalVisibility("test-modal");
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");

    toggleModalVisibility("test-modal");
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });

  it("tracks nested lock counts before unlocking body scroll", () => {
    lockBodyScroll();
    lockBodyScroll();
    expect(document.body.dataset.modalOpenCount).to.equal("2");
    expect(document.body.style.overflow).to.equal("hidden");

    unlockBodyScroll();
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.body.style.overflow).to.equal("hidden");

    unlockBodyScroll();
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });

  it("formats initials, datetimes, and empty-object checks", () => {
    expect(computeUserInitials("Open Community", "ocg")).to.equal("OC");
    expect(computeUserInitials("Single", "ocg", 1)).to.equal("S");
    expect(computeUserInitials("", "ocg")).to.equal("O");

    expect(convertDateTimeLocalToISO("2025-08-23T15:00")).to.equal("2025-08-23T15:00:00");
    expect(convertDateTimeLocalToISO("")).to.equal(null);

    expect(convertTimestampToDateTimeLocal(1735689600)).to.equal("2025-01-01T00:00");
    expect(convertTimestampToDateTimeLocal("1735689600")).to.equal("");

    expect(convertTimestampToDateTimeLocalInTz(1735689600, "America/New_York")).to.equal("2024-12-31T19:00");
    expect(convertTimestampToDateTimeLocalInTz(1735689600, "")).to.equal("");

    expect(isObjectEmpty({ id: 10, title: "", tags: [], published: false })).to.equal(true);
    expect(isObjectEmpty({ id: 10, title: "OCG" })).to.equal(false);
  });

  it("resolves event timezones from explicit fields and the document fallback", () => {
    const timezoneField = document.createElement("input");
    timezoneField.name = "timezone";
    timezoneField.value = "  Europe/Madrid  ";
    document.body.append(timezoneField);

    expect(resolveEventTimezone(timezoneField)).to.equal("Europe/Madrid");
    expect(resolveEventTimezone()).to.equal("Europe/Madrid");
    expect(resolveEventTimezone(null)).to.equal("");
  });

  it("formats datetime-local values in a timezone-aware way", () => {
    expect(convertDateToDateTimeLocalInTz(new Date("2025-01-01T00:00:00.000Z"), "America/New_York")).to.equal(
      "2024-12-31T19:00",
    );
    expect(convertDateToDateTimeLocalInTz(new Date("invalid"), "America/New_York")).to.equal("");

    expect(toDateTimeLocalInTimezone("2025-01-01T00:00:00.000Z", "America/New_York")).to.equal(
      "2024-12-31T19:00",
    );
    expect(toDateTimeLocalInTimezone("2025-01-01T00:00:00.000Z", "")).to.equal("2025-01-01T00:00");
    expect(toDateTimeLocalInTimezone("not-a-date", "America/New_York")).to.equal("");
  });

  it("converts datetime-local values back to UTC ISO strings", () => {
    expect(toUtcIsoInTimezone("2026-04-10T10:00", "America/New_York")).to.equal("2026-04-10T14:00:00.000Z");
    expect(toUtcIsoInTimezone(" 2026-04-10T10:00 ", "")).to.equal("2026-04-10T10:00");
    expect(toUtcIsoInTimezone("invalid", "America/New_York")).to.equal("invalid");
    expect(toUtcIsoInTimezone("", "America/New_York")).to.equal(null);
  });
});
