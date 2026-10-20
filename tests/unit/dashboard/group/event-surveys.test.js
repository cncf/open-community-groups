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
        <form id="details-form" data-event-form>
          <input name="name" value="Event" />
        </form>
        <div data-content="attendees">
          <div id="attendees-content"></div>
        </div>
        <div data-content="surveys">
          <div id="surveys-content" data-event-surveys-root>
            <form id="event-survey-form" data-event-survey-form data-success-message="Saved." data-error-message="Failed.">
              <button id="event-survey-form-back" type="button">Back to surveys</button>
              <input id="event-survey-title" name="title" value="Session feedback" />
              <input id="event-survey-anonymous-toggle" type="checkbox" data-event-survey-toggle="event-survey-anonymous" checked ${anonymousLocked ? "disabled" : ""} />
              <input type="hidden" id="event-survey-anonymous" name="anonymous" value="true" />
              <input id="event-survey-opens-at" type="datetime-local" name="opens_at" value="" />
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
