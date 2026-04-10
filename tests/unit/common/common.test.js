import { expect } from "@open-wc/testing";

import {
  computeUserInitials,
  convertDateTimeLocalToISO,
  convertTimestampToDateTimeLocal,
  convertTimestampToDateTimeLocalInTz,
  hideLoadingSpinner,
  isDashboardPath,
  isObjectEmpty,
  lockBodyScroll,
  scrollToDashboardTop,
  showLoadingSpinner,
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

    expect(convertTimestampToDateTimeLocalInTz(1735689600, "America/New_York")).to.equal(
      "2024-12-31T19:00",
    );
    expect(convertTimestampToDateTimeLocalInTz(1735689600, "")).to.equal("");

    expect(isObjectEmpty({ id: 10, title: "", tags: [], published: false })).to.equal(true);
    expect(isObjectEmpty({ id: 10, title: "OCG" })).to.equal(false);
  });
});
