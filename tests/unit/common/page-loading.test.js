import { expect } from "@open-wc/testing";

import { clearPageLoading, initializePageLoading, loadPage } from "/static/js/common/page-loading.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockWindowTimers } from "/tests/unit/test-utils/timers.js";

// Links whose click never replaces the document.
const IGNORED_LINKS = [
  { name: "a link that opens a new tab", html: '<a href="/explore" target="_blank">Explore</a>' },
  { name: "a download link", html: '<a href="/report" download>Report</a>' },
  {
    name: "a link that opts out",
    html: '<a href="/purchases/1/credit-notes/2" data-page-loading-ignore>Download credit note</a>',
  },
  { name: "a file link", html: '<a href="/event/calendar.ics">Add to calendar</a>' },
  { name: "a fragment of this page", html: '<a href="#main-content">Skip to main content</a>' },
  { name: "a link with another scheme", html: '<a href="mailto:team@example.test">Email</a>' },
];
// Root attribute that shows the page loading bar.
const PAGE_LOADING_ATTRIBUTE = "data-page-loading";
// Time after which the module stops waiting for the document to be replaced.
const PAGE_LOADING_TIMEOUT_MS = 10000;

describe("page loading", () => {
  let navigatedUrls;
  let timers;

  /**
   * Records a navigation and cancels it, so a loaded page never replaces the test page.
   * @param {NavigateEvent} event - Navigate event.
   */
  const recordNavigation = (event) => {
    event.preventDefault();
    navigatedUrls.push(event.destination.url);
  };

  before(() => {
    initializePageLoading();
    // Registered after the module, so it cancels each navigation once the module has seen it.
    window.addEventListener("click", cancelEvent);
    window.navigation.addEventListener("navigate", recordNavigation);
  });

  after(() => {
    window.removeEventListener("click", cancelEvent);
    window.navigation.removeEventListener("navigate", recordNavigation);
  });

  beforeEach(() => {
    resetDom();
    navigatedUrls = [];
    timers = mockWindowTimers();
  });

  afterEach(() => {
    clearPageLoading();
    timers.restore();
    resetDom();
  });

  it("shows the bar for a link that replaces the document", () => {
    // Render a plain link with nested content.
    document.body.innerHTML = '<a href="/explore"><span>Explore</span></a>';

    // Click the content inside the link.
    click(document.querySelector("span"));

    // Verify the root is marked.
    expect(isPageLoading()).to.equal(true);
  });

  IGNORED_LINKS.forEach(({ name, html }) => {
    it(`ignores ${name}`, () => {
      // Render the link and click it.
      document.body.innerHTML = html;
      click(document.querySelector("a"));

      // Verify the root stays unmarked.
      expect(isPageLoading()).to.equal(false);
    });
  });

  it("ignores cancelled and modified clicks", () => {
    // Render a link another handler takes over, as HTMX does for boosted links.
    document.body.innerHTML =
      '<a id="boosted" href="/explore">Explore</a><a id="plain" href="/stats">Stats</a>';
    const boostedLink = document.getElementById("boosted");
    boostedLink.addEventListener("click", cancelEvent);

    // Click the handled link, then open the plain one in another tab.
    click(boostedLink);
    click(document.getElementById("plain"), { ctrlKey: true });

    // Verify neither click marks the root.
    expect(isPageLoading()).to.equal(false);
  });

  it("shows the bar for a submitted form unless the submit is cancelled", () => {
    // Render a form another handler submits itself, and a native one.
    document.body.innerHTML =
      '<form id="handled" action="/search"></form><form id="native" action="/log-in"></form>';
    const handledForm = document.getElementById("handled");
    handledForm.addEventListener("submit", cancelEvent);

    // Verify the handled submit leaves the root unmarked.
    submit(handledForm);
    expect(isPageLoading()).to.equal(false);

    // Verify the native submit marks it.
    submit(document.getElementById("native"));
    expect(isPageLoading()).to.equal(true);
  });

  it("shows the bar while a script loads a page that replaces the document", () => {
    // Load a page from a script.
    loadPage("/explore?ts_query=cloud");

    // Verify the root is marked and the page is requested.
    expect(isPageLoading()).to.equal(true);
    expect(navigatedUrls).to.deep.equal([toAbsoluteUrl("/explore?ts_query=cloud")]);
  });

  it("loads fragments and files from a script without the bar", () => {
    // Load a fragment of this page and a file download from a script.
    loadPage("#main-content");
    loadPage("/event/calendar.ics");

    // Verify both are requested and the root stays unmarked.
    expect(isPageLoading()).to.equal(false);
    expect(navigatedUrls).to.deep.equal([
      toAbsoluteUrl("#main-content"),
      toAbsoluteUrl("/event/calendar.ics"),
    ]);
  });

  it("clears the bar when the page is restored or the document is never replaced", () => {
    // Show the bar, then restore the page from the back/forward cache.
    document.body.innerHTML = '<a href="/explore">Explore</a>';
    const link = document.querySelector("a");
    click(link);
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    // Verify the restored page shows no bar.
    expect(isPageLoading()).to.equal(false);

    // Show the bar again and let the navigation stall.
    click(link);
    timers.advance(PAGE_LOADING_TIMEOUT_MS - 1);
    expect(isPageLoading()).to.equal(true);
    timers.advance(1);

    // Verify the bar gives up.
    expect(isPageLoading()).to.equal(false);
  });
});

/**
 * Cancels an event, standing in for a handler that takes over its default action.
 * @param {Event} event - Event to cancel.
 */
const cancelEvent = (event) => event.preventDefault();

/**
 * Dispatches a primary-button click on an element.
 * @param {Element} element - Element to click.
 * @param {MouseEventInit} [init] - Extra event options, such as modifier keys.
 */
const click = (element, init = {}) => {
  element.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, ...init }));
};

/**
 * Reads whether the root is marked as loading a page.
 * @returns {boolean} True while the page loading bar shows.
 */
const isPageLoading = () => document.documentElement.hasAttribute(PAGE_LOADING_ATTRIBUTE);

/**
 * Dispatches a submit event on a form without submitting it.
 * @param {HTMLFormElement} form - Form to submit.
 */
const submit = (form) => {
  form.dispatchEvent(new SubmitEvent("submit", { bubbles: true, cancelable: true }));
};

/**
 * Resolves a URL against the test page, as the browser does before navigating.
 * @param {string} url - Relative or absolute URL.
 * @returns {string} Absolute URL.
 */
const toAbsoluteUrl = (url) => new URL(url, window.location.href).href;
