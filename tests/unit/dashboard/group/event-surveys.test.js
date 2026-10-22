import { expect } from "@open-wc/testing";

import { getEventPageFormIds } from "/static/js/dashboard/group/event-page/context.js";
import {
  UNSAVED_SURVEY_CHANGES_MESSAGE,
  hasUnsavedSurveyChanges,
  initializeEventSurveys,
  normalizeEventSurveyDateParameters,
} from "/static/js/dashboard/group/event-surveys.js";
import { waitForAnimationFrames, waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

/**
 * Renders an event update page fixture with a survey form loaded in its tab.
 * @param {object} [options] Fixture options.
 * @param {boolean} [options.anonymousLocked=false] Renders the anonymous toggle read-only.
 */
const renderSurveyPage = async ({ anonymousLocked = false } = {}) => {
  document.body.innerHTML = `
    <div id="dashboard-content">
      <div id="event-update-page" data-event-page="update">
        <button id="update-event-button" type="button">Save</button>
        <button id="surveys-tab" type="button" data-section="surveys" data-active="true">Surveys</button>
        <form id="details-form" data-event-form>
          <input name="name" value="Event" />
        </form>
        <div data-content="attendees">
          <div id="attendees-content"></div>
        </div>
        <div data-content="surveys">
          <div id="surveys-content" data-event-surveys-root>
            <form id="event-survey-form" data-event-survey-form data-event-timezone="UTC" data-success-message="Saved." data-error-message="Failed.">
              <button id="event-survey-form-back" type="button">Back to surveys</button>
              <input id="event-survey-title" name="title" value="Session feedback" />
              <input id="event-survey-anonymous-toggle" type="checkbox" data-event-survey-toggle="event-survey-anonymous" checked ${anonymousLocked ? "disabled" : ""} />
              <input type="hidden" id="event-survey-anonymous" name="anonymous" value="true" />
              <input id="event-survey-opens-at" type="datetime-local" name="opens_at" value="" />
              <input id="event-survey-closes-at" type="datetime-local" name="closes_at" value="2020-01-01T10:00" />
              <div data-pending-changes-ignore>
                <input id="event-survey-question-draft" name="question_draft" value="" />
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  `;

  const pageRoot = document.getElementById("event-update-page");
  initializeEventSurveys(pageRoot);
  await waitForMicrotask();

  return {
    form: document.getElementById("event-survey-form"),
    pageRoot,
    title: document.getElementById("event-survey-title"),
  };
};

/** Edits the survey title so the form has unsaved changes. */
const editTitle = (title, value = "Updated feedback") => {
  title.value = value;
  title.dispatchEvent(new Event("input", { bubbles: true }));
};

/** Dispatches an `htmx:confirm` event the way HTMX does before a request. */
const dispatchHtmxConfirm = (elt, target) => {
  const issueRequestCalls = [];
  const event = new CustomEvent("htmx:confirm", {
    bubbles: true,
    cancelable: true,
    detail: {
      elt,
      issueRequest: (skipConfirmation) => issueRequestCalls.push(skipConfirmation),
      target,
    },
  });
  elt.dispatchEvent(event);

  return { event, issueRequestCalls };
};

/** Dispatches an HTMX request lifecycle event for the survey form. */
const dispatchFormRequestEvent = (form, type, xhr = {}) => {
  form.dispatchEvent(new CustomEvent(type, { bubbles: true, detail: { elt: form, xhr } }));
};

/** Dispatches a browser `beforeunload` event and returns it. */
const dispatchBeforeUnload = () => {
  const event = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(event);
  return event;
};

describe("event surveys", () => {
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
  });

  it("keeps the survey form out of the event forms", async () => {
    // Render the page with the survey form loaded
    const { pageRoot } = await renderSurveyPage();

    // Verify only the event form joins the event payload and pending changes
    expect(getEventPageFormIds(pageRoot)).to.deep.equal(["details-form"]);
  });

  it("normalizes survey dates before the request is sent", async () => {
    // Render the page and prepare the request parameters of the form
    const { form } = await renderSurveyPage();
    const parameters = { closes_at: "", opens_at: "2099-05-10T09:00", title: "Session feedback" };

    // Dispatch the request configuration of the survey form
    form.dispatchEvent(
      new CustomEvent("htmx:configRequest", { bubbles: true, detail: { elt: form, parameters } }),
    );

    // Verify dates use the server format and blank dates stay blank
    expect(parameters).to.deep.equal({
      closes_at: "",
      opens_at: "2099-05-10T09:00:00",
      title: "Session feedback",
    });
  });

  it("normalizes every survey date field", () => {
    const parameters = { closes_at: "2099-05-20T18:30", opens_at: "2099-05-10T09:00" };

    normalizeEventSurveyDateParameters(parameters);

    expect(parameters).to.deep.equal({
      closes_at: "2099-05-20T18:30:00",
      opens_at: "2099-05-10T09:00:00",
    });
  });

  it("rejects a closing date before the opening date", async () => {
    // Render the page and set dates that close before they open
    await renderSurveyPage();
    const opensAt = document.getElementById("event-survey-opens-at");
    const closesAt = document.getElementById("event-survey-closes-at");
    opensAt.value = "2099-05-10T09:00";
    closesAt.value = "2099-05-10T08:00";
    closesAt.dispatchEvent(new Event("input", { bubbles: true }));

    // Verify the closing date is flagged
    expect(closesAt.validationMessage).to.equal("Closing date must be after the opening date.");

    // Move the opening date earlier
    opensAt.value = "2099-05-09T09:00";
    opensAt.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify the closing date is accepted
    expect(closesAt.validity.valid).to.equal(true);
  });

  it("rejects a changed closing date in the past", async () => {
    // Render the page and change the stored past closing date
    await renderSurveyPage();
    const closesAt = document.getElementById("event-survey-closes-at");
    closesAt.value = "2021-01-01T10:00";
    closesAt.dispatchEvent(new Event("input", { bubbles: true }));

    // Verify the past closing date is flagged
    expect(closesAt.validationMessage).to.equal("Closing date must be in the future.");

    // Restore the stored closing date
    closesAt.value = "2020-01-01T10:00";
    closesAt.dispatchEvent(new Event("input", { bubbles: true }));

    // Verify the unchanged closing date is accepted
    expect(closesAt.validity.valid).to.equal(true);
  });

  it("binds the anonymous toggle to its hidden input", async () => {
    // Render the page with the survey form loaded
    await renderSurveyPage();
    const toggle = document.getElementById("event-survey-anonymous-toggle");

    // Turn anonymity off
    toggle.checked = false;
    toggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify the submitted value follows the toggle and marks the form dirty
    expect(document.getElementById("event-survey-anonymous").value).to.equal("false");
    expect(hasUnsavedSurveyChanges()).to.equal(true);
  });

  it("submits the current anonymity of a read-only anonymous toggle", async () => {
    // Render the page with the anonymous toggle locked on
    const { form } = await renderSurveyPage({ anonymousLocked: true });

    // Verify the hidden input keeps submitting anonymity without dirtying the form
    expect(document.getElementById("event-survey-anonymous-toggle").disabled).to.equal(true);
    expect(new FormData(form).get("anonymous")).to.equal("true");
    expect(hasUnsavedSurveyChanges()).to.equal(false);
  });

  it("warns on browser navigation only while the form is dirty", async () => {
    // Render the page and edit the survey
    const { title } = await renderSurveyPage();
    expect(dispatchBeforeUnload().defaultPrevented).to.equal(false);
    editTitle(title);

    // Verify browser navigation is guarded while dirty
    expect(hasUnsavedSurveyChanges()).to.equal(true);
    expect(dispatchBeforeUnload().defaultPrevented).to.equal(true);

    // Restore the original value and verify the guard is released
    editTitle(title, "Session feedback");
    expect(hasUnsavedSurveyChanges()).to.equal(false);
    expect(dispatchBeforeUnload().defaultPrevented).to.equal(false);
  });

  it("marks the survey form dirty until the edits are saved", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);
    await waitForAnimationFrames();

    // Verify the form is marked dirty for the deployment refresh guard
    expect(form.hasAttribute("data-pending-changes-dirty")).to.equal(true);

    // Save the form and verify the mark is removed
    dispatchFormRequestEvent(form, "htmx:beforeRequest");
    dispatchFormRequestEvent(form, "htmx:beforeOnLoad", { status: 204 });
    expect(form.hasAttribute("data-pending-changes-dirty")).to.equal(false);
  });

  it("asks before the event Save replaces the dashboard content", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);

    // Dispatch the confirmation of the event Save request
    const { event, issueRequestCalls } = dispatchHtmxConfirm(
      document.getElementById("update-event-button"),
      document.getElementById("dashboard-content"),
    );
    await waitForMicrotask();

    // Verify the request was held, confirmed and then issued
    expect(event.defaultPrevented).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(UNSAVED_SURVEY_CHANGES_MESSAGE);
    expect(swal.calls[0].confirmButtonText).to.equal("Discard changes");
    expect(swal.calls[0].cancelButtonText).to.equal("Keep editing");
    expect(issueRequestCalls).to.deep.equal([true]);

    // Verify the edits are released once the swap removes the form
    form.remove();
    expect(hasUnsavedSurveyChanges()).to.equal(false);
    expect(dispatchBeforeUnload().defaultPrevented).to.equal(false);
  });

  it("asks before a request issued in the same frame as an edit", async () => {
    // Render the page and edit the survey without waiting for a frame
    const { title } = await renderSurveyPage();
    editTitle(title);

    // Dispatch the Back link confirmation right away
    const { event } = dispatchHtmxConfirm(
      document.getElementById("event-survey-form-back"),
      document.getElementById("surveys-content"),
    );
    await waitForMicrotask();

    // Verify the pending edit was checked before deciding
    expect(event.defaultPrevented).to.equal(true);
    expect(swal.calls).to.have.length(1);
  });

  it("does not ask before the Back link swaps a clean form", async () => {
    // Render the page without editing the survey
    await renderSurveyPage();

    // Dispatch the confirmation of the Back link request
    const { event } = dispatchHtmxConfirm(
      document.getElementById("event-survey-form-back"),
      document.getElementById("surveys-content"),
    );

    // Verify the request was not held
    expect(event.defaultPrevented).to.equal(false);
    expect(swal.calls).to.have.length(0);
  });

  it("does not hold confirmations without a swap target", async () => {
    // Render the page and edit the survey
    const { title } = await renderSurveyPage();
    editTitle(title);

    // Dispatch a confirmation without a target
    const { event } = dispatchHtmxConfirm(document.getElementById("update-event-button"), null);

    // Verify the request was not held
    expect(event.defaultPrevented).to.equal(false);
    expect(swal.calls).to.have.length(0);
  });

  it("ignores fields excluded from pending changes", async () => {
    // Render the page and edit a field inside an ignored container
    await renderSurveyPage();
    const draft = document.getElementById("event-survey-question-draft");
    draft.value = "Draft question";
    draft.dispatchEvent(new Event("input", { bubbles: true }));
    await waitForAnimationFrames();

    // Verify the form stays clean
    expect(hasUnsavedSurveyChanges()).to.equal(false);
  });

  it("keeps the edits guarded when a confirmed request is not sent", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);

    // Confirm the event Save, whose request validation then cancels
    const save = dispatchHtmxConfirm(
      document.getElementById("update-event-button"),
      document.getElementById("dashboard-content"),
    );
    await waitForMicrotask();
    expect(save.issueRequestCalls).to.deep.equal([true]);

    // Verify the form is still dirty and the Back link asks again
    expect(form.isConnected).to.equal(true);
    expect(hasUnsavedSurveyChanges()).to.equal(true);
    const back = dispatchHtmxConfirm(
      document.getElementById("event-survey-form-back"),
      document.getElementById("surveys-content"),
    );
    await waitForMicrotask();
    expect(back.event.defaultPrevented).to.equal(true);
    expect(swal.calls).to.have.length(2);
  });

  it("keeps the edits when dashboard menu navigation is not confirmed", async () => {
    // Render the page, edit the survey and reject the confirmation
    const { title } = await renderSurveyPage();
    editTitle(title);
    swal.setNextResult({ isConfirmed: false });
    const menuLink = document.createElement("a");
    document.body.append(menuLink);

    // Dispatch the confirmation of a dashboard menu request targeting the body
    const { event, issueRequestCalls } = dispatchHtmxConfirm(menuLink, document.body);
    await waitForMicrotask();

    // Verify the request was dropped and the edits are still guarded
    expect(event.defaultPrevented).to.equal(true);
    expect(issueRequestCalls).to.deep.equal([]);
    expect(hasUnsavedSurveyChanges()).to.equal(true);
    expect(title.value).to.equal("Updated feedback");
  });

  it("asks before the Back link swaps the surveys tab", async () => {
    // Render the page and edit the survey
    const { title } = await renderSurveyPage();
    editTitle(title);

    // Dispatch the confirmation of the Back link request
    const { event, issueRequestCalls } = dispatchHtmxConfirm(
      document.getElementById("event-survey-form-back"),
      document.getElementById("surveys-content"),
    );
    await waitForMicrotask();

    // Verify the swap waited for the confirmation
    expect(event.defaultPrevented).to.equal(true);
    expect(issueRequestCalls).to.deep.equal([true]);
  });

  it("lets the form submit and requests that keep it on the page run", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);

    // Dispatch the form submission and an attendees tab request
    const submission = dispatchHtmxConfirm(form, form);
    const attendees = dispatchHtmxConfirm(
      document.getElementById("update-event-button"),
      document.getElementById("attendees-content"),
    );

    // Verify neither request was held
    expect(submission.event.defaultPrevented).to.equal(false);
    expect(attendees.event.defaultPrevented).to.equal(false);
    expect(swal.calls).to.have.length(0);
  });

  it("keeps the edits when the section changes", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);

    // Switch to another section, which only hides the surveys tab
    document.querySelector('[data-content="surveys"]').classList.add("hidden");
    const attendees = dispatchHtmxConfirm(
      document.getElementById("update-event-button"),
      document.getElementById("attendees-content"),
    );

    // Verify the form and its edits survive without a prompt
    expect(attendees.event.defaultPrevented).to.equal(false);
    expect(form.isConnected).to.equal(true);
    expect(title.value).to.equal("Updated feedback");
    expect(hasUnsavedSurveyChanges()).to.equal(true);
  });

  it("cleans up once the dirty form is removed", async () => {
    // Render the page, edit the survey and remove the form
    const { form, title } = await renderSurveyPage();
    editTitle(title);
    form.remove();

    // Verify neither browser navigation nor requests are guarded anymore
    expect(dispatchBeforeUnload().defaultPrevented).to.equal(false);
    expect(hasUnsavedSurveyChanges()).to.equal(false);
    const { event } = dispatchHtmxConfirm(document.getElementById("update-event-button"), document.body);
    expect(event.defaultPrevented).to.equal(false);
    expect(swal.calls).to.have.length(0);
  });

  it("clears unsaved changes once the form is saved", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);

    // Submit the form and dispatch its successful response
    dispatchFormRequestEvent(form, "htmx:beforeRequest");
    dispatchFormRequestEvent(form, "htmx:beforeOnLoad", { status: 204 });

    // Verify the refresh that follows is not held
    expect(hasUnsavedSurveyChanges()).to.equal(false);
    const { event } = dispatchHtmxConfirm(
      document.getElementById("update-event-button"),
      document.getElementById("surveys-content"),
    );
    expect(event.defaultPrevented).to.equal(false);
  });

  it("keeps edits made while the save runs unsaved", async () => {
    // Render the page, edit the survey and submit it
    const { form, title } = await renderSurveyPage();
    editTitle(title);
    dispatchFormRequestEvent(form, "htmx:beforeRequest");

    // Edit the survey again before the save responds
    editTitle(title, "Edited while saving");
    dispatchFormRequestEvent(form, "htmx:beforeOnLoad", { status: 204 });

    // Verify the later edit stays guarded against the refresh that follows
    expect(hasUnsavedSurveyChanges()).to.equal(true);
    const { event } = dispatchHtmxConfirm(
      document.getElementById("update-event-button"),
      document.getElementById("surveys-content"),
    );
    await waitForMicrotask();
    expect(event.defaultPrevented).to.equal(true);
    expect(swal.calls).to.have.length(1);

    // Verify the saved values are the new baseline
    editTitle(title, "Updated feedback");
    expect(hasUnsavedSurveyChanges()).to.equal(false);
  });

  it("keeps unsaved changes when a new version intercepts the save", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);
    await waitForAnimationFrames();

    // Submit the form and dispatch the new-version intercept
    dispatchFormRequestEvent(form, "htmx:beforeRequest");
    dispatchFormRequestEvent(form, "htmx:beforeOnLoad", { status: 204, "HX-Refresh": "true" });

    // Verify the edits stay guarded for the deployment refresh check
    expect(hasUnsavedSurveyChanges()).to.equal(true);
    expect(form.hasAttribute("data-pending-changes-dirty")).to.equal(true);
  });

  it("keeps unsaved changes after a rejected save", async () => {
    // Render the page and edit the survey
    const { form, title } = await renderSurveyPage();
    editTitle(title);

    // Submit the form and dispatch its rejected response
    dispatchFormRequestEvent(form, "htmx:beforeRequest");
    dispatchFormRequestEvent(form, "htmx:beforeOnLoad", { status: 422 });
    form.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: { elt: form, xhr: { status: 422, responseText: "the survey changed" } },
      }),
    );

    // Verify the edits stay guarded and the rejection is reported
    expect(hasUnsavedSurveyChanges()).to.equal(true);
    expect(title.value).to.equal("Updated feedback");
    expect(swal.calls).to.have.length(1);
  });

  it("keeps survey dates of requests from other elements unchanged", async () => {
    // Render the page and prepare a request issued by the tab root
    await renderSurveyPage();
    const root = document.getElementById("surveys-content");
    const parameters = { opens_at: "2099-05-10T09:00" };

    // Dispatch the request configuration of the root
    root.dispatchEvent(
      new CustomEvent("htmx:configRequest", { bubbles: true, detail: { elt: root, parameters } }),
    );

    // Verify the parameters were left as sent
    expect(parameters).to.deep.equal({ opens_at: "2099-05-10T09:00" });
  });

  it("returns to the list when the active surveys tab is clicked", async () => {
    // Render the page with a survey form open and listen for list refreshes
    await renderSurveyPage();
    const refreshes = [];
    document.body.addEventListener("refresh-event-surveys", (event) => refreshes.push(event));

    // Click the active surveys tab
    document.getElementById("surveys-tab").click();

    // Verify the list is requested
    expect(refreshes).to.have.length(1);
  });

  it("keeps the surveys tab content when the tab is not active or shows the list", async () => {
    // Render the page and listen for list refreshes
    await renderSurveyPage();
    const refreshes = [];
    document.body.addEventListener("refresh-event-surveys", (event) => refreshes.push(event));
    const tab = document.getElementById("surveys-tab");

    // Click the surveys tab while another section is active
    tab.setAttribute("data-active", "false");
    tab.click();

    // Click the active surveys tab while the list is shown
    tab.setAttribute("data-active", "true");
    document.getElementById("surveys-content").innerHTML = "<p data-event-surveys-count>1 of 10 surveys</p>";
    tab.click();

    // Verify no list refresh was requested
    expect(refreshes).to.have.length(0);
  });

  it("registers each surveys tab once", async () => {
    // Render the page and initialize it a second time
    const { pageRoot, title } = await renderSurveyPage();
    initializeEventSurveys(pageRoot);
    editTitle(title);

    // Dispatch the confirmation of the Back link request
    dispatchHtmxConfirm(
      document.getElementById("event-survey-form-back"),
      document.getElementById("surveys-content"),
    );
    await waitForMicrotask();

    // Verify only one confirmation was shown
    expect(swal.calls).to.have.length(1);
  });

  it("tracks a survey form swapped into the tab", async () => {
    // Render the page and swap a new survey form into the tab
    await renderSurveyPage();
    const root = document.getElementById("surveys-content");
    root.innerHTML = `
      <form id="event-survey-form" data-event-survey-form>
        <input id="swapped-title" name="title" value="New survey" />
      </form>
    `;
    root.firstElementChild.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
    await waitForMicrotask();

    // Edit the swapped form
    editTitle(document.getElementById("swapped-title"));

    // Verify the swapped form is tracked
    expect(hasUnsavedSurveyChanges()).to.equal(true);
  });
});

/**
 * Renders the Individual view of a survey with two respondent rows and the
 * empty response modal, and initializes the surveys tab.
 */
const renderResponsesPage = () => {
  document.body.innerHTML = `
    <div id="event-update-page">
      <div id="surveys-content" data-event-surveys-root>
        <table aria-label="Survey respondents">
          <tbody>
            <tr id="respondent-row-1" tabindex="0" data-event-survey-respondent="1"><th>Jane</th></tr>
            <tr id="respondent-row-2" tabindex="0" data-event-survey-respondent="2"><th>John</th></tr>
          </tbody>
        </table>
        <div id="event-survey-response-modal" role="dialog" aria-modal="true" aria-hidden="true" class="hidden">
          <div id="response-overlay" data-event-survey-response-close class="modal-overlay"></div>
          <div id="event-survey-response-modal-content"></div>
        </div>
      </div>
    </div>
  `;
  initializeEventSurveys(document.getElementById("event-update-page"));

  return {
    content: document.getElementById("event-survey-response-modal-content"),
    modal: document.getElementById("event-survey-response-modal"),
    row: document.getElementById("respondent-row-1"),
  };
};

/**
 * Swaps the responses of a respondent into the modal content, as HTMX does
 * once a respondent row or a navigation button loads them.
 * @param {HTMLElement} content Modal content container.
 * @param {HTMLElement} trigger Element that requested the responses.
 * @param {{hasNext?: boolean, hasPrevious?: boolean}} [options] Available neighbors.
 */
const swapResponse = (content, trigger, { hasNext = true, hasPrevious = true } = {}) => {
  content.innerHTML = `
    <button id="response-close-icon" type="button" data-event-survey-response-close>Close icon</button>
    <button id="response-previous" type="button" data-event-survey-response-nav="previous" ${hasPrevious ? "" : "disabled"}>Previous</button>
    <button id="response-next" type="button" data-event-survey-response-nav="next" ${hasNext ? "" : "disabled"}>Next</button>
    <button id="response-close" type="button" data-event-survey-response-close>Close</button>
  `;
  content.dispatchEvent(
    new CustomEvent("htmx:afterSwap", {
      bubbles: true,
      detail: { requestConfig: { elt: trigger }, target: content },
    }),
  );
};

/**
 * Dispatches the `htmx:beforeSwap` event HTMX sends before swapping a response
 * into a target.
 * @param {Element} elt Element that issued the request.
 * @param {Element} target Swap target.
 * @param {{shouldSwap?: boolean}} [options] Whether the response is swapped.
 */
const dispatchBeforeSwap = (elt, target, { shouldSwap = true } = {}) => {
  elt.dispatchEvent(
    new CustomEvent("htmx:beforeSwap", {
      bubbles: true,
      detail: { requestConfig: { elt }, shouldSwap, target },
    }),
  );
};

describe("event survey response modal", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("opens once a respondent's responses load and restores focus on close", () => {
    // Render the Individual view and load the first respondent
    const { content, modal, row } = renderResponsesPage();
    row.focus();
    swapResponse(content, row);

    // Verify the modal opens with focus inside it and the page scroll locked
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(modal.getAttribute("aria-hidden")).to.equal("false");
    expect(modal.contains(document.activeElement)).to.equal(true);
    expect(document.body.style.overflow).to.equal("hidden");

    // Close the modal from its close button
    document.getElementById("response-close").click();

    // Verify the modal closes and focus returns to the respondent row
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
    expect(document.activeElement).to.equal(row);
    expect(document.body.style.overflow).to.equal("");
  });

  it("closes from its overlay and on Escape", () => {
    // Render the Individual view and open the modal
    const { content, modal, row } = renderResponsesPage();
    swapResponse(content, row);

    // Close the modal from its overlay
    document.getElementById("response-overlay").click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    // Open the modal again and press Escape inside it
    swapResponse(content, row);
    document
      .getElementById("response-next")
      .dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));

    // Verify the modal closes
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("keeps Tab and Escape working after a click on plain text moves focus to the body", () => {
    // Render the Individual view, open the modal and move focus to the body
    const { content, modal, row } = renderResponsesPage();
    swapResponse(content, row);
    document.activeElement?.blur();
    expect(document.activeElement).to.equal(document.body);

    // Press Tab on the body
    const tab = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" });
    document.body.dispatchEvent(tab);

    // Verify focus moves back into the modal
    expect(tab.defaultPrevented).to.equal(true);
    expect(modal.contains(document.activeElement)).to.equal(true);

    // Move focus to the body again and press Escape
    document.activeElement?.blur();
    document.body.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));

    // Verify the modal closes
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("keeps focus on the navigation direction while moving between respondents", () => {
    // Render the Individual view and open the modal
    const { content, modal, row } = renderResponsesPage();
    swapResponse(content, row);

    // Load the next respondent from the Next button
    swapResponse(content, document.getElementById("response-next"));

    // Verify the modal stays open with focus on the new Next button
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.activeElement?.id).to.equal("response-next");

    // Load the last respondent, which has no next one
    swapResponse(content, document.getElementById("response-next"), { hasNext: false });

    // Verify focus falls back to the Close button
    expect(document.activeElement?.id).to.equal("response-close");

    // Close the modal
    document.getElementById("response-close").click();
  });

  it("keeps Tab navigation inside the open modal", () => {
    // Render the Individual view and open the modal
    const { content, row } = renderResponsesPage();
    swapResponse(content, row);
    const close = document.getElementById("response-close");
    close.focus();

    // Press Tab on the last control of the modal
    const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" });
    close.dispatchEvent(event);

    // Verify focus wraps to the first control of the modal
    expect(event.defaultPrevented).to.equal(true);
    expect(document.activeElement?.id).to.equal("response-close-icon");

    // Close the modal
    close.click();
  });

  it("closes before a respondents search swap removes it", () => {
    // Render the Individual view and open the modal
    const { content, modal, row } = renderResponsesPage();
    const root = document.getElementById("surveys-content");
    swapResponse(content, row);
    expect(document.body.dataset.modalOpenCount).to.equal("1");

    // Land a respondents search that replaces the whole view
    dispatchBeforeSwap(root, root);

    // Verify the modal closes and releases the page scroll lock
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });

  it("closes before a swap requested outside the surveys tab removes it", () => {
    // Render the Individual view and open the modal
    const { content, modal, row } = renderResponsesPage();
    swapResponse(content, row);

    // Land a request from outside the tab that replaces the whole body
    dispatchBeforeSwap(document.body, document.body);

    // Verify the modal closes and releases the page scroll lock
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });

  it("stays open for swaps that do not remove it", () => {
    // Render the Individual view and open the modal
    const { content, modal, row } = renderResponsesPage();
    const root = document.getElementById("surveys-content");
    swapResponse(content, row);

    // Land a failed search, a swap into the modal and a swap elsewhere
    dispatchBeforeSwap(root, root, { shouldSwap: false });
    dispatchBeforeSwap(document.getElementById("response-next"), content);
    dispatchBeforeSwap(row, document.getElementById("respondent-row-2"));

    // Verify the modal stays open with the page scroll locked
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.body.style.overflow).to.equal("hidden");

    // Close the modal
    document.getElementById("response-close").click();
  });

  it("ignores swaps into other targets", () => {
    // Render the Individual view
    const { modal } = renderResponsesPage();
    const root = document.getElementById("surveys-content");

    // Swap content into the surveys tab instead of the modal
    root.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true, detail: { target: root } }));

    // Verify the modal stays closed
    expect(modal.classList.contains("hidden")).to.equal(true);
  });
});

/**
 * Renders the Summary view of a survey with one free-text question preview
 * and the empty answers modal, and initializes the surveys tab.
 */
const renderResultsPage = () => {
  document.body.innerHTML = `
    <div id="event-update-page">
      <div id="surveys-content" data-event-surveys-root>
        <section>
          <button id="text-answers-open" type="button" data-event-survey-text-answers-open>View all 12 answers</button>
        </section>
        <div id="event-survey-text-answers-modal" role="dialog" aria-modal="true" aria-hidden="true" class="hidden">
          <div id="text-answers-overlay" data-event-survey-text-answers-close class="modal-overlay"></div>
          <div id="event-survey-text-answers-modal-content"></div>
        </div>
      </div>
    </div>
  `;
  initializeEventSurveys(document.getElementById("event-update-page"));

  return {
    content: document.getElementById("event-survey-text-answers-modal-content"),
    modal: document.getElementById("event-survey-text-answers-modal"),
    opener: document.getElementById("text-answers-open"),
  };
};

/**
 * Swaps a page of free-text answers into the modal content, as HTMX does once
 * the opener, the search or a navigation button loads them.
 * @param {HTMLElement} content Modal content container.
 * @param {HTMLElement} trigger Element that requested the answers.
 * @param {{hasNext?: boolean}} [options] Whether a next page exists.
 * @returns {CustomEvent} Dispatched `htmx:beforeSwap` event.
 */
const swapTextAnswers = (content, trigger, { hasNext = true } = {}) => {
  // Let the modal decide whether the response is still wanted
  const beforeSwap = new CustomEvent("htmx:beforeSwap", {
    bubbles: true,
    detail: { requestConfig: { elt: trigger }, shouldSwap: true, target: content },
  });
  content.dispatchEvent(beforeSwap);
  if (!beforeSwap.detail.shouldSwap) {
    return beforeSwap;
  }

  // Swap the answers and report it
  content.innerHTML = `
    <button id="text-answers-close-icon" type="button" data-event-survey-text-answers-close>Close icon</button>
    <form id="text-answers-search-form">
      <input id="event-survey-text-answers-search" name="ts_query" />
      <button id="text-answers-clear" type="button">Clear answer search</button>
    </form>
    <button id="text-answers-previous" type="button" data-event-survey-text-answers-nav="previous">Previous</button>
    <button id="text-answers-next" type="button" data-event-survey-text-answers-nav="next" ${hasNext ? "" : "disabled"}>Next</button>
    <button id="text-answers-close" type="button" data-event-survey-text-answers-close>Close</button>
  `;
  content.dispatchEvent(
    new CustomEvent("htmx:afterSwap", {
      bubbles: true,
      detail: { requestConfig: { elt: trigger }, target: content },
    }),
  );
  return beforeSwap;
};

describe("event survey text answers modal", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("opens on the search box once the answers load and restores focus on close", () => {
    // Render the Summary view and load the answers from the opener
    const { content, modal, opener } = renderResultsPage();
    opener.focus();
    swapTextAnswers(content, opener);

    // Verify the modal opens on its search box with the page scroll locked
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(modal.getAttribute("aria-hidden")).to.equal("false");
    expect(document.activeElement?.id).to.equal("event-survey-text-answers-search");
    expect(document.body.style.overflow).to.equal("hidden");

    // Close the modal from its overlay
    document.getElementById("text-answers-overlay").click();

    // Verify the modal closes and focus returns to the opener
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
    expect(document.activeElement).to.equal(opener);
    expect(document.body.style.overflow).to.equal("");
  });

  it("keeps focus on the navigation direction while moving between pages", () => {
    // Render the Summary view and open the modal
    const { content, modal, opener } = renderResultsPage();
    swapTextAnswers(content, opener);

    // Load the next page from the Next button
    swapTextAnswers(content, document.getElementById("text-answers-next"));

    // Verify the modal stays open with focus on the new Next button
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.activeElement?.id).to.equal("text-answers-next");

    // Load the last page, which has no next one
    swapTextAnswers(content, document.getElementById("text-answers-next"), { hasNext: false });

    // Verify focus falls back to the Close button and Escape closes the modal
    expect(document.activeElement?.id).to.equal("text-answers-close");
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("moves focus to the search box when clearing the search removes the focused control", () => {
    // Render the Summary view and open the modal
    const { content, modal, opener } = renderResultsPage();
    swapTextAnswers(content, opener);

    // Clear the search from its clear button, which the new answers replace
    const clear = document.getElementById("text-answers-clear");
    clear.focus();
    swapTextAnswers(content, clear);

    // Verify focus lands on the search box instead of the page body
    expect(content.contains(clear)).to.equal(false);
    expect(document.activeElement?.id).to.equal("event-survey-text-answers-search");

    // Verify Tab stays trapped inside the modal
    const close = document.getElementById("text-answers-close");
    close.focus();
    const tab = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" });
    close.dispatchEvent(tab);
    expect(tab.defaultPrevented).to.equal(true);
    expect(modal.contains(document.activeElement)).to.equal(true);

    // Verify Escape still closes the modal
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("drops answers requested from inside the modal after it was closed", () => {
    // Render the Summary view, open the modal and close it while a search runs
    const { content, modal, opener } = renderResultsPage();
    swapTextAnswers(content, opener);
    const searchForm = document.getElementById("text-answers-search-form");
    document.getElementById("text-answers-close").click();

    // Deliver the search results after the modal was closed
    const beforeSwap = swapTextAnswers(content, searchForm);

    // Verify the stale results are dropped and the modal stays closed
    expect(beforeSwap.detail.shouldSwap).to.equal(false);
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(content.contains(searchForm)).to.equal(true);

    // Verify the opener still loads the answers into the closed modal
    expect(swapTextAnswers(content, opener).detail.shouldSwap).to.equal(true);
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Close the modal
    document.getElementById("text-answers-close").click();
  });
});
