import { expect } from "@open-wc/testing";

import { loadEventAnalyticsTab } from "/static/js/dashboard/group/event-analytics-tab.js";
import { initializeSectionTabs } from "/static/js/dashboard/group/page-form-state.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

/** Renders an event page fixture with the waitlist and analytics sections. */
const renderEventPageFixture = () => {
  document.body.innerHTML = `
    <div id="event-update-page">
      <select data-section-select>
        <option value="waitlist" selected>Waitlist</option>
        <option value="analytics">Analytics</option>
      </select>
      <ul>
        <li><button type="button" data-section="waitlist" data-active="true">Waitlist</button></li>
        <li><button type="button" data-section="analytics" data-active="false">Analytics</button></li>
      </ul>
      <div data-content="waitlist"></div>
      <div data-content="analytics" class="hidden">
        <div id="analytics-content"
             data-analytics-url="/dashboard/group/events/event-1/analytics"
             data-analytics-state="idle"
             aria-live="polite">
          <div id="analytics-loading">Loading analytics...</div>
          <div id="analytics-error" class="hidden" role="alert" tabindex="-1">
            <button type="button" data-analytics-retry>Retry</button>
          </div>
        </div>
      </div>
      <button type="button" data-section-next>Next</button>
    </div>
  `;

  const pageRoot = document.getElementById("event-update-page");
  initializeSectionTabs({
    root: pageRoot,
    onSectionChange: (sectionName) => {
      if (sectionName === "analytics") {
        loadEventAnalyticsTab(pageRoot);
      }
    },
  });

  return pageRoot;
};

describe("dashboard group event analytics tab", () => {
  const originalHtmx = window.htmx;
  let requests;

  beforeEach(() => {
    resetDom();
    requests = [];
    window.htmx = {
      ajax(verb, path, context) {
        requests.push({ context, path, verb });
        return Promise.resolve();
      },
    };
  });

  afterEach(() => {
    resetDom();
    if (originalHtmx) {
      window.htmx = originalHtmx;
    } else {
      delete window.htmx;
    }
  });

  it("does not request analytics before the tab is activated", () => {
    // Render the page without opening the analytics tab.
    const pageRoot = renderEventPageFixture();

    // Assert no request was sent and the tab stays idle.
    expect(requests).to.have.length(0);
    expect(pageRoot.querySelector("#analytics-content").dataset.analyticsState).to.equal("idle");
  });

  it("loads analytics when the desktop tab button is clicked", () => {
    // Render the page and click the analytics tab.
    const pageRoot = renderEventPageFixture();
    const content = pageRoot.querySelector("#analytics-content");
    pageRoot.querySelector('[data-section="analytics"]').click();

    // Assert one GET request targets the analytics content.
    expect(requests).to.have.length(1);
    expect(requests[0].verb).to.equal("GET");
    expect(requests[0].path).to.equal("/dashboard/group/events/event-1/analytics");
    expect(requests[0].context.target).to.equal(content);
    expect(requests[0].context.source).to.equal(content);
    expect(requests[0].context.swap).to.equal("innerHTML");
    expect(content.dataset.analyticsState).to.equal("loading");
    expect(content.getAttribute("aria-busy")).to.equal("true");
  });

  it("loads analytics from the compact section select", () => {
    // Render the page and choose analytics in the select.
    const pageRoot = renderEventPageFixture();
    const select = pageRoot.querySelector("[data-section-select]");
    select.value = "analytics";
    select.dispatchEvent(new Event("change", { bubbles: true }));

    // Assert one request was sent.
    expect(requests).to.have.length(1);
  });

  it("loads analytics from the Next button of the previous section", () => {
    // Render the page and move to the next section.
    const pageRoot = renderEventPageFixture();
    pageRoot.querySelector("[data-section-next]").click();

    // Assert the analytics section was activated and loaded.
    expect(pageRoot.querySelector('[data-content="analytics"]').classList.contains("hidden")).to.equal(false);
    expect(requests).to.have.length(1);
  });

  it("suppresses duplicate requests while loading and after loading", () => {
    // Render the page and activate the tab twice while loading.
    const pageRoot = renderEventPageFixture();
    const content = pageRoot.querySelector("#analytics-content");
    const analyticsButton = pageRoot.querySelector('[data-section="analytics"]');
    analyticsButton.click();
    analyticsButton.click();
    expect(requests).to.have.length(1);

    // Complete the swap and activate the tab again.
    content.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true }));
    pageRoot.querySelector('[data-section="waitlist"]').click();
    analyticsButton.click();

    // Assert the loaded tab is not requested again.
    expect(content.dataset.analyticsState).to.equal("loaded");
    expect(requests).to.have.length(1);
  });

  it("shows an error with Retry and loads again after a failure", () => {
    // Render the page and fail the first request.
    const pageRoot = renderEventPageFixture();
    const content = pageRoot.querySelector("#analytics-content");
    const error = pageRoot.querySelector("#analytics-error");
    pageRoot.querySelector('[data-section="analytics"]').click();
    content.dispatchEvent(new CustomEvent("htmx:responseError", { bubbles: true }));

    // Assert the error is shown, focused and the spinner hidden.
    expect(content.dataset.analyticsState).to.equal("error");
    expect(error.classList.contains("hidden")).to.equal(false);
    expect(pageRoot.querySelector("#analytics-loading").classList.contains("hidden")).to.equal(true);
    expect(document.activeElement).to.equal(error);
    expect(content.getAttribute("aria-busy")).to.equal("false");

    // Retry and complete the second request.
    pageRoot.querySelector("[data-analytics-retry]").click();
    expect(requests).to.have.length(2);
    expect(content.dataset.analyticsState).to.equal("loading");
    expect(error.classList.contains("hidden")).to.equal(true);
    content.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true }));

    // Assert the tab is loaded.
    expect(content.dataset.analyticsState).to.equal("loaded");
  });

  it("ignores stale responses after the tab loaded or was removed", () => {
    // Render the page and load the tab.
    const pageRoot = renderEventPageFixture();
    const content = pageRoot.querySelector("#analytics-content");
    pageRoot.querySelector('[data-section="analytics"]').click();
    content.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true }));

    // Dispatch a late failure for the loaded tab.
    content.dispatchEvent(new CustomEvent("htmx:sendError", { bubbles: true }));
    expect(content.dataset.analyticsState).to.equal("loaded");

    // Dispatch a failure for a request whose content was removed.
    const nextPageRoot = renderEventPageFixture();
    const nextContent = nextPageRoot.querySelector("#analytics-content");
    nextPageRoot.querySelector('[data-section="analytics"]').click();
    nextPageRoot.remove();
    nextContent.dispatchEvent(new CustomEvent("htmx:responseError", { bubbles: true }));

    // Assert the removed tab is left untouched.
    expect(nextContent.dataset.analyticsState).to.equal("loading");
  });
});
