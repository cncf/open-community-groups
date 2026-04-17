import { expect } from "@open-wc/testing";

import { initializeDiscountCodesController } from "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import { initializeTicketingWaitlistState } from "/static/js/dashboard/event/ticketing.js";
import { initializeTicketTypesController } from "/static/js/dashboard/event/ticketing/ticket-types-editor.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const setInputValue = async (container, selector, value, eventName = "input") => {
  const field = container.querySelector(selector);
  field.value = value;
  field.dispatchEvent(new Event(eventName, { bubbles: true, composed: true }));
  return field;
};

const mountTicketTypesUi = ({ bodyRows = "" } = {}) => {
  const wrapper = document.createElement("div");
  wrapper.id = "ticket-types-ui";
  wrapper.dataset.ticketTypes = "[]";
  wrapper.dataset.disabled = "false";
  wrapper.innerHTML = `
    <div data-ticketing-role="hidden-fields"></div>
    <div data-ticketing-role="table-wrapper">
      <table>
        <tbody data-ticketing-role="empty-state">
          <tr><td>No ticket tiers yet. Configured ticket tiers will appear here.</td></tr>
        </tbody>
        <tbody data-ticketing-role="table-body">${bodyRows}</tbody>
      </table>
    </div>
    <div data-ticketing-role="ticket-modal" class="hidden">
      <div data-ticketing-action="close-modal"></div>
      <h3 data-ticketing-role="modal-title"></h3>
      <input id="ticket-title-draft" data-ticket-modal-field data-ticket-field="title" required />
      <input id="ticket-seats-draft" data-ticket-modal-field data-ticket-field="seats_total" required />
      <textarea id="ticket-description-draft" data-ticket-field="description"></textarea>
      <input type="checkbox" data-ticket-field="active" />
      <button type="button" data-ticketing-action="add-price-window"></button>
      <div data-ticketing-role="price-windows-list"></div>
      <button type="button" data-ticketing-action="close-modal"></button>
      <button type="button" data-ticketing-action="save-ticket">
        <span data-ticketing-role="save-label"></span>
      </button>
    </div>
  `;
  document.body.append(wrapper);
  return wrapper;
};

const mountDiscountCodesUi = ({ bodyRows = "" } = {}) => {
  const wrapper = document.createElement("div");
  wrapper.id = "discount-codes-ui";
  wrapper.dataset.discountCodes = "[]";
  wrapper.dataset.disabled = "false";
  wrapper.innerHTML = `
    <div data-ticketing-role="hidden-fields"></div>
    <div data-ticketing-role="table-wrapper">
      <table>
        <tbody data-ticketing-role="empty-state">
          <tr><td>No discount codes yet. Configured discount codes will appear here.</td></tr>
        </tbody>
        <tbody data-ticketing-role="table-body">${bodyRows}</tbody>
      </table>
    </div>
    <div data-ticketing-role="discount-modal" class="hidden">
      <div data-ticketing-action="close-modal"></div>
      <h3 data-ticketing-role="modal-title"></h3>
      <input id="discount-title-draft" data-discount-modal-field data-discount-field="title" required />
      <input id="discount-code-draft" data-discount-modal-field data-discount-field="code" required />
      <input type="checkbox" data-discount-field="active" />
      <select id="discount-kind-draft" data-discount-field="kind">
        <option value="percentage">Percentage</option>
        <option value="fixed_amount">Fixed amount</option>
      </select>
      <div data-ticketing-role="discount-value-field"></div>
      <input id="discount-total-draft" data-discount-field="total_available" />
      <input id="discount-available-draft" data-discount-field="available" />
      <input id="discount-starts-draft" data-discount-field="starts_at" />
      <input id="discount-ends-draft" data-discount-field="ends_at" />
      <button type="button" data-ticketing-action="close-modal"></button>
      <button type="button" data-ticketing-action="save-discount">
        <span data-ticketing-role="save-label"></span>
      </button>
    </div>
  `;
  document.body.append(wrapper);
  return wrapper;
};

describe("ticketing editors", () => {
  beforeEach(() => {
    resetDom();

    const currencyField = document.createElement("select");
    currencyField.id = "payment_currency_code";
    currencyField.value = "EUR";
    document.body.append(currencyField);

    const timezoneField = document.createElement("input");
    timezoneField.name = "timezone";
    timezoneField.value = "UTC";
    document.body.append(timezoneField);
  });

  it("renders ticket type summary rows and preserves hidden field serialization", () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.dataset.ticketTypes = JSON.stringify([
      {
        active: true,
        description: "Main conference ticket",
        seats_total: 25,
        title: "General admission",
        price_windows: [
          {
            amount_minor: 3000,
            starts_at: "",
            ends_at: "",
          },
        ],
      },
    ]);

    const controller = initializeTicketTypesController({ addButtonId: "", rootId: "ticket-types-ui" });

    expect(uiRoot.textContent).to.contain("General admission");
    expect(uiRoot.textContent).to.contain("25");
    expect(uiRoot.textContent).to.contain("Always available");
    expect(uiRoot.querySelector('input[name="ticket_types_present"]')?.value).to.equal("true");
    expect(uiRoot.querySelector('input[name="ticket_types[0][title]"]')?.value).to.equal("General admission");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][amount_minor]"]')?.value,
    ).to.equal("3000");
    expect(controller.hasConfiguredTicketTypes()).to.equal(true);
  });

  it("adds ticket types through the modal and emits ticket-types-changed", async () => {
    const uiRoot = mountTicketTypesUi();
    const controller = initializeTicketTypesController({ addButtonId: "", rootId: "ticket-types-ui" });
    const events = [];
    uiRoot.addEventListener("ticket-types-changed", (event) => events.push(event.detail));

    controller._openTicketModal();

    await setInputValue(uiRoot, "#ticket-title-draft", "Early bird");
    await setInputValue(uiRoot, "#ticket-seats-draft", "40");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();

    expect(uiRoot.textContent).to.contain("Early bird");
    expect(uiRoot.querySelector('input[name="ticket_types[0][title]"]')?.value).to.equal("Early bird");
    expect(uiRoot.querySelector('input[name="ticket_types[0][seats_total]"]')?.value).to.equal("40");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][amount_minor]"]')?.value,
    ).to.equal("1500");
    expect(events.at(-1)).to.deep.equal({ hasTicketTypes: true });
  });

  it("uses explicit ticket type controller dependencies instead of global fields", async () => {
    document.getElementById("payment_currency_code").value = "USD";
    document.querySelector('[name="timezone"]').value = "UTC";

    const addButton = document.createElement("button");
    document.body.append(addButton);

    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    const timezoneInput = document.createElement("input");
    timezoneInput.value = "America/New_York";
    document.body.append(timezoneInput);

    const uiRoot = mountTicketTypesUi();
    initializeTicketTypesController({
      addButton,
      currencyInput,
      root: uiRoot,
      timezoneInput,
    });

    addButton.click();

    expect(uiRoot.textContent).to.contain("Price (EUR)");

    await setInputValue(uiRoot, "#ticket-title-draft", "Custom dependency ticket");
    await setInputValue(uiRoot, "#ticket-seats-draft", "20");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");
    await setInputValue(uiRoot, "#ticket-starts-1", "2026-04-10T10:00");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();

    expect(uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][starts_at]"]')?.value).to.equal(
      "2026-04-10T14:00:00.000Z",
    );

    currencyInput.value = "JPY";
    currencyInput.dispatchEvent(new Event("input", { bubbles: true, composed: true }));

    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();

    expect(uiRoot.textContent).to.contain("Price (JPY)");
  });

  it("keeps free ticket prices as amount_minor 0 in hidden fields", async () => {
    const uiRoot = mountTicketTypesUi();
    const controller = initializeTicketTypesController({ addButtonId: "", rootId: "ticket-types-ui" });

    controller._openTicketModal();

    await setInputValue(uiRoot, "#ticket-title-draft", "Free entry");
    await setInputValue(uiRoot, "#ticket-seats-draft", "10");
    await setInputValue(uiRoot, "#ticket-price-1", "0");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();

    expect(uiRoot.textContent).to.contain("Free entry");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][amount_minor]"]')?.value,
    ).to.equal("0");
  });

  it("renders scheduled ticket windows with compact dates", () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.dataset.ticketTypes = JSON.stringify([
      {
        active: true,
        seats_total: 40,
        title: "Early bird",
        price_windows: [
          {
            amount_minor: 1500,
            ends_at: "2026-04-10T23:59:00.000Z",
            starts_at: "",
          },
          {
            amount_minor: 2500,
            ends_at: "",
            starts_at: "2026-04-11T00:00:00.000Z",
          },
        ],
      },
    ]);

    initializeTicketTypesController({ addButtonId: "", rootId: "ticket-types-ui" });

    expect(uiRoot.textContent).to.contain("until Apr 10");
    expect(uiRoot.textContent).to.contain("from Apr 11");
  });

  it("renders persisted ticket rows from the dataset and wires row actions", () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.dataset.ticketTypes = JSON.stringify([
      {
        active: true,
        description: "Main conference ticket",
        seats_total: 25,
        title: "General admission",
        price_windows: [
          {
            amount_minor: 3000,
            starts_at: "",
            ends_at: "",
          },
        ],
      },
    ]);

    initializeTicketTypesController({ addButtonId: "", rootId: "ticket-types-ui" });

    expect(uiRoot.textContent).to.contain("General admission");

    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();

    expect(uiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent).to.equal(
      "Edit ticket type",
    );
  });

  it("keeps hidden ticket modal fields disabled so parent form validation ignores them", () => {
    const form = document.createElement("form");
    const uiRoot = mountTicketTypesUi();
    form.append(uiRoot);
    document.body.append(form);

    initializeTicketTypesController({ addButtonId: "", rootId: "ticket-types-ui" });

    expect(form.checkValidity()).to.equal(true);
    expect(uiRoot.querySelector("#ticket-title-draft")?.disabled).to.equal(true);
    expect(uiRoot.querySelector("#ticket-seats-draft")?.disabled).to.equal(true);
  });

  it("renders discount code rows and updates serialization after modal edits", async () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.dataset.discountCodes = JSON.stringify([
      {
        active: true,
        code: "EARLY20",
        kind: "percentage",
        percentage: 20,
        title: "Early supporter",
        total_available: 50,
      },
    ]);

    const controller = initializeDiscountCodesController({ addButtonId: "", rootId: "discount-codes-ui" });

    expect(uiRoot.textContent).to.contain("Early supporter");
    expect(uiRoot.textContent).to.contain("EARLY20");
    expect(uiRoot.querySelector('input[name="discount_codes[0][percentage]"]')?.value).to.equal("20");

    controller._openDiscountModal(controller._rows[0]._row_id);

    await setInputValue(uiRoot, "#discount-title-draft", "Member perk");
    await setInputValue(uiRoot, "#discount-code-draft", "member10");
    await setInputValue(uiRoot, "#discount-percentage-draft", "10");

    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();

    expect(uiRoot.textContent).to.contain("Member perk");
    expect(uiRoot.textContent).to.contain("MEMBER10");
    expect(uiRoot.querySelector('input[name="discount_codes[0][title]"]')?.value).to.equal("Member perk");
    expect(uiRoot.querySelector('input[name="discount_codes[0][code]"]')?.value).to.equal("MEMBER10");
    expect(uiRoot.querySelector('input[name="discount_codes[0][percentage]"]')?.value).to.equal("10");
  });

  it("adds and removes discount codes from the compact card list", async () => {
    const uiRoot = mountDiscountCodesUi();
    const controller = initializeDiscountCodesController({ addButtonId: "", rootId: "discount-codes-ui" });

    controller._openDiscountModal();

    await setInputValue(uiRoot, "#discount-title-draft", "Sponsor invite");
    await setInputValue(uiRoot, "#discount-code-draft", "sponsor50");
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await setInputValue(uiRoot, "#discount-amount-draft", "5.00");

    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();

    expect(uiRoot.textContent).to.contain("Sponsor invite");
    expect(uiRoot.querySelector('input[name="discount_codes[0][amount_minor]"]')?.value).to.equal("500");

    controller._removeDiscountCode(controller._rows[0]._row_id);

    expect(uiRoot.textContent).to.contain("No discount codes yet.");
    expect(uiRoot.querySelector('input[name="discount_codes[0][title]"]')).to.equal(null);
  });

  it("uses explicit discount controller dependencies instead of global fields", async () => {
    document.getElementById("payment_currency_code").value = "USD";

    const addButton = document.createElement("button");
    document.body.append(addButton);

    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    const timezoneInput = document.createElement("input");
    timezoneInput.value = "UTC";
    document.body.append(timezoneInput);

    const uiRoot = mountDiscountCodesUi();
    initializeDiscountCodesController({
      addButton,
      currencyInput,
      root: uiRoot,
      timezoneInput,
    });

    addButton.click();
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));

    expect(uiRoot.textContent).to.contain("Amount (EUR)");

    currencyInput.value = "GBP";
    currencyInput.dispatchEvent(new Event("input", { bubbles: true, composed: true }));

    expect(uiRoot.textContent).to.contain("Amount (GBP)");
  });

  it("keeps zero fixed discount amounts as amount_minor 0 in hidden fields", async () => {
    const uiRoot = mountDiscountCodesUi();
    const controller = initializeDiscountCodesController({ addButtonId: "", rootId: "discount-codes-ui" });

    controller._openDiscountModal();

    await setInputValue(uiRoot, "#discount-title-draft", "Free comp");
    await setInputValue(uiRoot, "#discount-code-draft", "FREE0");
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await setInputValue(uiRoot, "#discount-amount-draft", "0");

    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();

    expect(uiRoot.textContent).to.contain("Free comp");
    expect(uiRoot.querySelector('input[name="discount_codes[0][amount_minor]"]')?.value).to.equal("0");
  });

  it("renders persisted discount rows from the dataset and wires row actions", () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.dataset.discountCodes = JSON.stringify([
      {
        active: true,
        code: "EARLY20",
        kind: "percentage",
        percentage: 20,
        title: "Early supporter",
        total_available: 50,
      },
    ]);

    initializeDiscountCodesController({ addButtonId: "", rootId: "discount-codes-ui" });

    expect(uiRoot.textContent).to.contain("Early supporter");

    uiRoot.querySelector('[data-ticketing-action="edit-discount"]')?.click();

    expect(uiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent).to.equal(
      "Edit discount code",
    );
  });

  it("keeps hidden discount modal fields disabled so parent form validation ignores them", () => {
    const form = document.createElement("form");
    const uiRoot = mountDiscountCodesUi();
    form.append(uiRoot);
    document.body.append(form);

    initializeDiscountCodesController({ addButtonId: "", rootId: "discount-codes-ui" });

    expect(form.checkValidity()).to.equal(true);
    expect(uiRoot.querySelector("#discount-title-draft")?.disabled).to.equal(true);
    expect(uiRoot.querySelector("#discount-code-draft")?.disabled).to.equal(true);
  });

  it("preserves persisted remaining counts after discount row rerenders", () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.dataset.discountCodes = JSON.stringify([
      {
        active: true,
        available: 12,
        code: "EARLY20",
        kind: "percentage",
        percentage: 20,
        title: "Early supporter",
        total_available: 50,
      },
    ]);

    initializeDiscountCodesController({ addButtonId: "", rootId: "discount-codes-ui" });

    expect(uiRoot.textContent).to.contain("12 remaining");

    const currencyField = document.getElementById("payment_currency_code");
    currencyField.value = "USD";
    currencyField.dispatchEvent(new Event("input", { bubbles: true, composed: true }));

    expect(uiRoot.textContent).to.contain("12 remaining");
  });

  it("destroys ticketing controllers when HTMX cleans up the fragment", () => {
    const ticketTypesUiRoot = mountTicketTypesUi();
    const discountCodesUiRoot = mountDiscountCodesUi();
    const fragment = document.createElement("div");

    fragment.append(ticketTypesUiRoot, discountCodesUiRoot);
    document.body.append(fragment);

    initializeTicketingWaitlistState();

    discountCodesUiRoot._discountCodesController._openDiscountModal();

    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(ticketTypesUiRoot._ticketTypesController).to.exist;
    expect(discountCodesUiRoot._discountCodesController).to.exist;

    fragment.dispatchEvent(new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }));

    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(ticketTypesUiRoot._ticketTypesController).to.equal(undefined);
    expect(discountCodesUiRoot._discountCodesController).to.equal(undefined);
  });
});
