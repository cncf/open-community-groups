import { expect } from "@open-wc/testing";

import { navigateWithHtmx } from "/static/js/common/htmx-navigation.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import {
  createXhr,
  dispatchHtmxAfterRequest,
  dispatchHtmxRequestError,
} from "/tests/unit/test-utils/htmx.js";

// Class HTMX keeps on an element while its request runs.
const REQUEST_CLASS = "htmx-request";

const nextMicrotask = () => new Promise((resolve) => queueMicrotask(resolve));

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

  it("keeps the anchor while its request runs and removes it when the request ends", async () => {
    // Navigate with an HTMX that starts the request.
    globalThis.htmx = stubHtmx({ startsRequest: true });
    navigateWithHtmx("/explore");

    // Verify the boosted anchor stays in the page, carrying the request class.
    const anchor = document.body.querySelector('a[hx-boost="true"]');
    expect(anchor.getAttribute("href")).to.equal("/explore");
    expect(anchor.classList.contains(REQUEST_CLASS)).to.equal(true);

    // Verify a request that ends without swapping the page removes the anchor.
    dispatchHtmxAfterRequest(anchor, { status: 500 });
    await nextMicrotask();
    expect(anchor.isConnected).to.equal(false);
  });

  ["htmx:sendError", "htmx:timeout"].forEach((type) => {
    it(`keeps the anchor connected until ${type} reaches the document`, async () => {
      // Navigate with an HTMX that starts the request.
      globalThis.htmx = stubHtmx({ startsRequest: true });
      navigateWithHtmx("/explore");
      const anchor = document.body.querySelector('a[hx-boost="true"]');
      const received = [];
      const recordError = (event) => received.push(event.detail.elt);
      document.addEventListener(type, recordError);

      try {
        // End the request the way HTMX does, with the error right after afterRequest.
        dispatchHtmxAfterRequest(anchor, { status: 0 });
        expect(anchor.isConnected).to.equal(true);
        dispatchHtmxRequestError(anchor, type, {
          boosted: true,
          target: document.body,
          xhr: createXhr({ status: 0 }),
        });

        // Verify the document heard the error and the anchor is gone after a microtask.
        expect(received).to.deep.equal([anchor]);
        await nextMicrotask();
        expect(anchor.isConnected).to.equal(false);
      } finally {
        document.removeEventListener(type, recordError);
      }
    });
  });

  it("leaves a swapped page untouched once the anchor left with the old page", async () => {
    // Navigate with an HTMX that starts the request.
    globalThis.htmx = stubHtmx({ startsRequest: true });
    navigateWithHtmx("/explore");
    const anchor = document.body.querySelector('a[hx-boost="true"]');

    // Swap the page, which removes the anchor, and end the request.
    document.body.innerHTML = '<main id="new-page"></main>';
    dispatchHtmxAfterRequest(anchor, { status: 200 });
    await nextMicrotask();

    // Verify the new page stays as swapped.
    expect(anchor.isConnected).to.equal(false);
    expect(document.body.innerHTML).to.equal('<main id="new-page"></main>');
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
