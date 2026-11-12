import { expect } from "@open-wc/testing";

import { resolveUserLoggedIn } from "/static/js/common/user-session.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

const MENU_BUTTON = '<button id="user-dropdown-button" data-logged-in="false"></button>';

/**
 * Checks whether a promise has settled once pending microtasks have run.
 * @param {Promise<unknown>} promise Promise under test.
 * @returns {Promise<boolean>} True when the promise settled.
 */
const hasSettled = (promise) =>
  Promise.race([promise.then(() => true), waitForMicrotask().then(() => false)]);

/**
 * Renders the wrapper that loads the user menu, optionally holding a menu already.
 * @param {string} [content=""] Markup inside the loader.
 * @returns {HTMLElement} Loader element.
 */
const renderLoader = (content = "") => {
  document.body.insertAdjacentHTML("beforeend", `<div hx-get="/section/user-menu">${content}</div>`);

  return document.body.lastElementChild;
};

describe("user session", () => {
  afterEach(() => {
    resetDom();
  });

  it("reads the login state from a menu rendered with the page", async () => {
    // Render a menu button for each login state in turn.
    for (const loggedIn of [true, false]) {
      document.body.innerHTML = `<button id="user-dropdown-button" data-logged-in="${loggedIn}"></button>`;

      // Verify the state resolves without waiting.
      expect(await resolveUserLoggedIn()).to.equal(loggedIn);
    }
  });

  it("cannot tell without a menu", async () => {
    expect(await resolveUserLoggedIn()).to.equal(null);
  });

  it("waits for a menu load that has not finished", async () => {
    // Ask before the loader's request has even started.
    const loader = renderLoader();
    const loggedIn = resolveUserLoggedIn();
    expect(await hasSettled(loggedIn)).to.equal(false);

    // Finish the load with the menu swapped in.
    loader.innerHTML = MENU_BUTTON;
    dispatchHtmxAfterRequest(loader);

    // Verify the answer comes from the loaded menu.
    expect(await loggedIn).to.equal(false);
  });

  it("ignores requests that bubble up from the menu while waiting", async () => {
    // Ask while a restored snapshot still shows the previous menu.
    const loader = renderLoader(MENU_BUTTON);
    const loggedIn = resolveUserLoggedIn();

    // Finish a request started inside the menu.
    dispatchHtmxAfterRequest(loader.firstElementChild);
    expect(await hasSettled(loggedIn)).to.equal(false);

    // Finish the loader's own request with a logged-in menu.
    loader.firstElementChild.dataset.loggedIn = "true";
    dispatchHtmxAfterRequest(loader);

    // Verify the fresh menu wins over the snapshot.
    expect(await loggedIn).to.equal(true);
  });

  it("answers at once after the load finished, and cannot tell when it failed", async () => {
    // Finish a load that swapped nothing in.
    const loader = renderLoader();
    dispatchHtmxAfterRequest(loader, { status: 500 });

    // Verify a failed load leaves the state unknown, without waiting.
    expect(await resolveUserLoggedIn()).to.equal(null);

    // Verify a finished load with a menu answers without waiting.
    loader.innerHTML = MENU_BUTTON;
    expect(await resolveUserLoggedIn()).to.equal(false);
  });
});
