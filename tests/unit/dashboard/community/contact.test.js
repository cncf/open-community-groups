import { expect } from "@open-wc/testing";

import { buildFiltersKey, initializeCommunityContactForm } from "/static/js/dashboard/community/contact.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

const CATEGORY_ID = "00000000-0000-0000-0000-0000000000a1";
const CATEGORY_KEY = `filters%5Bgroup_category_ids%5D%5B%5D=${CATEGORY_ID}`;

describe("community contact", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/community",
    withHtmx: true,
    withSwal: true,
  });

  it("builds the filters key from hidden inputs in document order", () => {
    // Render filter inputs in document order
    const form = renderContactForm();
    addFilterValue(form, "categories", "filters[group_category_ids][]", CATEGORY_ID);
    addFilterValue(form, "roles", "filters[roles][]", "admin");

    // Verify the key matches the server canonical query
    expect(buildFiltersKey(form.querySelector("#community-contact-filters"))).to.equal(
      `${CATEGORY_KEY}&filters%5Broles%5D%5B%5D=admin`,
    );
  });

  it("enables sending for a current preview with recipients", () => {
    // Render and initialize the contact form
    const form = renderContactForm();
    initializeCommunityContactForm(form);

    // Verify the initial preview enables sending
    expect(submitButton(form).disabled).to.equal(false);
  });

  it("keeps sending disabled for read-only users", () => {
    // Render the contact form for a user who cannot send
    const form = renderContactForm({ canSend: false });
    initializeCommunityContactForm(form);

    // Verify sending stays disabled
    expect(submitButton(form).disabled).to.equal(true);
  });

  it("disables sending immediately when the filters change", () => {
    // Render and initialize the contact form
    const form = renderContactForm();
    initializeCommunityContactForm(form);

    // Change the category filter
    changeFilter(form, "categories", "filters[group_category_ids][]", CATEGORY_ID);

    // Verify sending is disabled and the preview is refreshed
    const recipients = form.querySelector("#community-contact-recipients");
    expect(submitButton(form).disabled).to.equal(true);
    expect(recipients.getAttribute("aria-busy")).to.equal("true");
    expect(env.current.htmx.triggerCalls).to.deep.equal([[recipients, "contact-filters-changed"]]);
  });

  it("re-enables sending only after a summary for the current filters", () => {
    // Render, initialize and change the filters
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    changeFilter(form, "categories", "filters[group_category_ids][]", CATEGORY_ID);

    // Swap in a superseded summary computed for the previous filters
    swapSummary(form, { filtersKey: "", peopleCount: 3 });
    expect(submitButton(form).disabled).to.equal(true);

    // Swap in the summary for the current filters
    swapSummary(form, { filtersKey: CATEGORY_KEY, peopleCount: 2 });
    expect(submitButton(form).disabled).to.equal(false);
    expect(form.querySelector("#community-contact-recipients").hasAttribute("aria-busy")).to.equal(false);
  });

  it("keeps sending disabled for an empty current summary", () => {
    // Render, initialize and change the filters
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    changeFilter(form, "categories", "filters[group_category_ids][]", CATEGORY_ID);

    // Swap in an empty summary for the current filters
    swapSummary(form, { filtersKey: CATEGORY_KEY, peopleCount: 0 });

    // Verify sending stays disabled
    expect(submitButton(form).disabled).to.equal(true);
  });

  it("keeps sending disabled and shows the error when the preview fails", () => {
    // Render, initialize and change the filters
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    changeFilter(form, "categories", "filters[group_category_ids][]", CATEGORY_ID);

    // Fail the preview request
    const recipients = form.querySelector("#community-contact-recipients");
    recipients.dispatchEvent(
      new CustomEvent("htmx:responseError", {
        bubbles: true,
        detail: { xhr: { responseText: "group category not found", status: 422 } },
      }),
    );

    // Verify the error is shown and sending stays disabled
    expect(recipients.querySelector('[role="alert"]').textContent).to.equal("group category not found");
    expect(submitButton(form).disabled).to.equal(true);
  });

  it("confirms with the previewed count before sending", async () => {
    // Render and initialize the contact form
    const form = renderContactForm({ peopleCount: 3 });
    initializeCommunityContactForm(form);

    // Submit the form
    form.requestSubmit();
    await waitForMicrotask();

    // Verify the confirmation uses the count and triggers the request
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0].text).to.equal("Send this email to 3 group team members?");
    expect(env.current.swal.calls[0].confirmButtonText).to.equal("Send");
    expect(env.current.htmx.triggerCalls).to.deep.equal([[form, "confirmed"]]);
  });

  it("sends nothing when the confirmation is cancelled", async () => {
    // Render and initialize the contact form
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    env.current.swal.setNextResult({ isConfirmed: false });

    // Submit and cancel the confirmation
    form.requestSubmit();
    await waitForMicrotask();

    // Verify nothing was sent and sending is enabled again
    expect(env.current.htmx.triggerCalls).to.have.length(0);
    expect(submitButton(form).disabled).to.equal(false);
  });

  it("sends nothing when the filters change while the dialog is open", async () => {
    // Render, initialize and hold the confirmation open
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    const dialog = holdConfirmation();

    // Submit, then change the filters before confirming
    form.requestSubmit();
    await waitForMicrotask();
    changeFilter(form, "categories", "filters[group_category_ids][]", CATEGORY_ID);
    dialog.resolve({ isConfirmed: true });
    await waitForMicrotask();

    // Verify only the preview refresh was triggered and the user was warned
    const triggered = env.current.htmx.triggerCalls.map(([, eventName]) => eventName);
    expect(triggered).to.deep.equal(["contact-filters-changed"]);
    expect(dialog.calls.at(-1).text).to.equal("Recipients changed, please review the updated count");
    dialog.restore();
  });

  it("opens one dialog and sends one request on a rapid double submit", async () => {
    // Render, initialize and hold the confirmation open
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    const dialog = holdConfirmation();

    // Submit twice before confirming
    form.requestSubmit();
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    dialog.resolve({ isConfirmed: true });
    await waitForMicrotask();

    // Verify one dialog and one request
    expect(dialog.calls).to.have.length(1);
    expect(env.current.htmx.triggerCalls).to.deep.equal([[form, "confirmed"]]);
    dialog.restore();
  });

  it("clears the message and keeps the filters after a successful send", () => {
    // Render and initialize the contact form with a selected filter
    const form = renderContactForm({ filtersKey: CATEGORY_KEY });
    addFilterValue(form, "categories", "filters[group_category_ids][]", CATEGORY_ID);
    initializeCommunityContactForm(form);
    form.querySelector("#community-contact-body").value = "Hello teams";

    // Complete the send request
    dispatchHtmxAfterRequest(form, { status: 204 });

    // Verify the message is cleared and the filters are kept
    expect(form.querySelector("#community-contact-subject").value).to.equal("");
    expect(form.querySelector("#community-contact-body").value).to.equal("");
    expect(buildFiltersKey(form.querySelector("#community-contact-filters"))).to.equal(CATEGORY_KEY);
    expect(env.current.swal.calls[0]).to.include({ text: "Email sent successfully.", icon: "success" });
  });

  it("keeps every field after a failed send", () => {
    // Render and initialize the contact form
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    form.querySelector("#community-contact-body").value = "Hello teams";

    // Fail the send request
    dispatchHtmxAfterRequest(form, {
      status: 422,
      responseText: "no group team members match the selected filters",
    });

    // Verify the message is kept
    expect(form.querySelector("#community-contact-subject").value).to.equal("Community");
    expect(form.querySelector("#community-contact-body").value).to.equal("Hello teams");
    expect(submitButton(form).disabled).to.equal(false);
  });

  it("ignores preview responses when handling the send result", () => {
    // Render and initialize the contact form
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    form.querySelector("#community-contact-body").value = "Hello teams";

    // Complete a preview request bubbling through the form
    dispatchHtmxAfterRequest(form.querySelector("#community-contact-recipients"), { status: 200 });

    // Verify the message is kept and no alert was shown
    expect(form.querySelector("#community-contact-body").value).to.equal("Hello teams");
    expect(env.current.swal.calls).to.have.length(0);
  });

  it("wires a form only once when initialized repeatedly", async () => {
    // Render and initialize the contact form twice
    const form = renderContactForm();
    initializeCommunityContactForm(form);
    initializeCommunityContactForm(form);

    // Submit the form
    form.requestSubmit();
    await waitForMicrotask();

    // Verify one dialog and one request
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.htmx.triggerCalls).to.deep.equal([[form, "confirmed"]]);
  });

  it("wires a form restored from an HTMX history snapshot", async () => {
    // Initialize the contact form, then restore its serialized markup
    initializeCommunityContactForm(renderContactForm());
    document.body.innerHTML = document.body.innerHTML;
    const restoredForm = document.getElementById("community-contact-form");
    initializeCommunityContactForm(restoredForm);

    // Submit the restored form
    const submitEvent = new Event("submit", { bubbles: true, cancelable: true });
    restoredForm.dispatchEvent(submitEvent);
    await waitForMicrotask();

    // Verify the submit was handled with a confirmation instead of navigating
    expect(submitEvent.defaultPrevented).to.equal(true);
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.htmx.triggerCalls).to.deep.equal([[restoredForm, "confirmed"]]);
  });
});

/**
 * Adds a selected hidden filter input to a picker fixture.
 * @param {HTMLFormElement} form Contact form fixture.
 * @param {string} picker Picker fixture identifier.
 * @param {string} name Hidden input name.
 * @param {string} value Hidden input value.
 * @returns {Element} Picker fixture.
 */
const addFilterValue = (form, picker, name, value) => {
  const element = form.querySelector(`[data-picker="${picker}"]`);
  const input = document.createElement("input");
  input.type = "hidden";
  input.name = name;
  input.value = value;
  element.append(input);
  return element;
};

/**
 * Selects a filter value and dispatches the picker change event.
 * @param {HTMLFormElement} form Contact form fixture.
 * @param {string} picker Picker fixture identifier.
 * @param {string} name Hidden input name.
 * @param {string} value Hidden input value.
 * @returns {void}
 */
const changeFilter = (form, picker, name, value) => {
  addFilterValue(form, picker, name, value).dispatchEvent(new Event("change", { bubbles: true }));
};

/**
 * Replaces the SweetAlert mock with one whose first dialog stays open until resolved.
 * @returns {{calls: object[], resolve: (result: object) => void, restore: () => void}} Dialog controls.
 */
const holdConfirmation = () => {
  const originalSwal = globalThis.Swal;
  const calls = [];
  let resolveFirst;
  globalThis.Swal = {
    fire: (options) => {
      calls.push(options);
      if (calls.length === 1) {
        return new Promise((resolve) => {
          resolveFirst = resolve;
        });
      }
      return Promise.resolve({ isConfirmed: false });
    },
  };
  return {
    calls,
    resolve: (result) => resolveFirst(result),
    restore: () => {
      globalThis.Swal = originalSwal;
    },
  };
};

/**
 * Renders the community contact form fixture.
 * @param {object} options Fixture options.
 * @param {boolean} [options.canSend] Whether the user can send.
 * @param {string} [options.filtersKey] Filters key of the rendered summary.
 * @param {number} [options.peopleCount] People in the rendered summary.
 * @returns {HTMLFormElement} Contact form.
 */
const renderContactForm = ({ canSend = true, filtersKey = "", peopleCount = 2 } = {}) => {
  document.body.innerHTML = `
    <form id="community-contact-form" data-can-send="${canSend}">
      <div id="community-contact-filters">
        <div data-picker="categories"></div>
        <div data-picker="roles"></div>
      </div>
      <div id="community-contact-recipients">
        ${summaryMarkup({ filtersKey, peopleCount })}
      </div>
      <input id="community-contact-subject" name="subject" value="Community" required>
      <textarea id="community-contact-body" name="body"></textarea>
      <button id="community-contact-submit" type="submit">Send email</button>
    </form>
  `;
  return document.getElementById("community-contact-form");
};

/**
 * Returns the send button of the contact form.
 * @param {HTMLFormElement} form Contact form fixture.
 * @returns {HTMLButtonElement} Send button.
 */
const submitButton = (form) => form.querySelector("#community-contact-submit");

/**
 * Builds the recipients summary markup rendered by the server.
 * @param {{filtersKey: string, peopleCount: number}} summary Summary data.
 * @returns {string} Summary markup.
 */
const summaryMarkup = ({ filtersKey, peopleCount }) => `
  <div id="community-contact-summary" data-people-count="${peopleCount}" data-filters-key="${filtersKey}"></div>
`;

/**
 * Swaps a new recipients summary into the container.
 * @param {HTMLFormElement} form Contact form fixture.
 * @param {{filtersKey: string, peopleCount: number}} summary Summary data.
 * @returns {void}
 */
const swapSummary = (form, summary) => {
  const recipients = form.querySelector("#community-contact-recipients");
  recipients.innerHTML = summaryMarkup(summary);
  recipients.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true }));
};
