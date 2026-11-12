import { expect } from "@open-wc/testing";

import { navigateWithHtmx } from "/static/js/common/htmx-navigation.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

// Class HTMX keeps on an element while its request runs.
const REQUEST_CLASS = "htmx-request";

describe("htmx navigation", () => {
  let originalHtmx;

  beforeEach(() => {
    resetDom();
    originalHtmx = globalThis.htmx;
  });

  afterEach(() => {
    globalThis.htmx = originalHtmx;
    resetDom();
  });

  it("keeps the anchor while its request runs and removes it when the request ends", () => {
    // Navigate with an HTMX that starts the request.
    globalThis.htmx = stubHtmx({ startsRequest: true });
    navigateWithHtmx("/explore");

    // Verify the boosted anchor stays in the page, carrying the request class.
    const anchor = document.body.querySelector('a[hx-boost="true"]');
    expect(anchor.getAttribute("href")).to.equal("/explore");
    expect(anchor.classList.contains(REQUEST_CLASS)).to.equal(true);

    // Verify a request that ends without swapping the page removes the anchor.
    dispatchHtmxAfterRequest(anchor, { status: 500 });
    expect(anchor.isConnected).to.equal(false);
  });

  it("removes the anchor before HTMX saves a history snapshot", () => {
    // Navigate with an HTMX that starts the request.
    globalThis.htmx = stubHtmx({ startsRequest: true });
    navigateWithHtmx("/explore");
    const anchor = document.body.querySelector('a[hx-boost="true"]');

    // Save the page to history while the request is still running.
    document.body.dispatchEvent(new Event("htmx:beforeHistorySave", { bubbles: true }));

    // Verify the snapshot is taken from a page without the anchor.
    expect(anchor.isConnected).to.equal(false);
  });

  it("removes the anchor when no request starts", () => {
    // Navigate with an HTMX that drops the request.
    globalThis.htmx = stubHtmx({ startsRequest: false });
    navigateWithHtmx("/explore");

    // Verify no anchor is left behind.
    expect(document.body.querySelector("a")).to.equal(null);
  });
});

/**
 * Stubs HTMX so a processed link cancels its click and may start a request.
 * @param {{ startsRequest: boolean }} options - Whether the click starts a request.
 * @returns {object} HTMX stub with the API the navigation helper uses.
 */
const stubHtmx = ({ startsRequest }) => ({
  process: (element) => {
    element.addEventListener("click", (event) => {
      event.preventDefault();
      element.classList.toggle(REQUEST_CLASS, startsRequest);
    });
  },
});
