import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import { initializeTicketingWaitlistState } from "/static/js/dashboard/event/ticketing.js";
import "/static/js/dashboard/event/ticketing/ticket-types-editor.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const setInputValue = async (container, selector, value, eventName = "input") => {
  const field = container.querySelector(selector);
  field.value = value;
  field.dispatchEvent(new Event(eventName, { bubbles: true, composed: true }));
  if ("updateComplete" in container) {
    await container.updateComplete;
  }
  return field;
};

const mountTicketTypesUi = () => {
  const wrapper = document.createElement("ticket-types-editor");
  wrapper.id = "ticket-types-ui";
  wrapper.setAttribute("ticket-types", "[]");
  wrapper.dataset.disabled = "false";
  document.body.append(wrapper);
  return wrapper;
};

const mountDiscountCodesUi = () => {
  const wrapper = document.createElement("discount-codes-editor");
  wrapper.id = "discount-codes-ui";
  wrapper.setAttribute("discount-codes", "[]");
  wrapper.dataset.disabled = "false";
  document.body.append(wrapper);
  return wrapper;
};

describe("ticketing editors", () => {
  beforeEach(() => {
    resetDom();

    const currencyField = document.createElement("select");
    currencyField.id = "payment_currency_code";
    currencyField.innerHTML = `
      <option value="">Select currency</option>
      <option value="EUR">EUR</option>
      <option value="USD">USD</option>
    `;
    currencyField.value = "EUR";
    document.body.append(currencyField);

    const timezoneField = document.createElement("input");
    timezoneField.name = "timezone";
    timezoneField.value = "UTC";
    document.body.append(timezoneField);
  });

  it("renders ticket type summary rows and preserves hidden field serialization", async () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.setAttribute(
      "ticket-types",
      JSON.stringify([
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
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("General admission");
    expect(uiRoot.textContent).to.contain("25");
    expect(uiRoot.querySelector('input[name="ticket_types_present"]')?.value).to.equal("true");
    expect(uiRoot.querySelector('input[name="ticket_types[0][title]"]')?.value).to.equal("General admission");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][amount_minor]"]')?.value,
    ).to.equal("3000");
    expect(uiRoot.hasConfiguredTicketTypes()).to.equal(true);
  });

  it("keeps seats and status in dedicated table cells on small layouts", async () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.setAttribute(
      "ticket-types",
      JSON.stringify([
        {
          active: true,
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
      ]),
    );

    await uiRoot.updateComplete;

    const rowCells = uiRoot.querySelectorAll('[data-ticketing-role="table-body"] tr td');

    expect(rowCells).to.have.length(4);
    expect(rowCells[1].className).to.not.contain("hidden");
    expect(rowCells[1].textContent).to.contain("25");
    expect(rowCells[2].className).to.not.contain("hidden");
    expect(rowCells[2].textContent).to.contain("Active");
    expect(rowCells[0].textContent).to.not.contain("25 seats");
  });

  it("adds ticket types through the modal and emits ticket-types-changed", async () => {
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;
    const events = [];
    uiRoot.addEventListener("ticket-types-changed", (event) => events.push(event.detail));

    uiRoot._openTicketModal();
    await uiRoot.updateComplete;

    expect(uiRoot.querySelector('label[for="ticket-title-draft"]')?.textContent).to.contain("*");
    expect(uiRoot.querySelector('label[for="ticket-seats-draft"]')?.textContent).to.contain("*");
    expect(uiRoot.querySelector('label[for="ticket-price-1"]')?.textContent).to.contain("*");

    await setInputValue(uiRoot, "#ticket-title-draft", "Early bird");
    await setInputValue(uiRoot, "#ticket-seats-draft", "40");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

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
    uiRoot.configure({ addButton, currencyInput, timezoneInput });
    await uiRoot.updateComplete;

    addButton.click();
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Price (EUR)");

    await setInputValue(uiRoot, "#ticket-title-draft", "Custom dependency ticket");
    await setInputValue(uiRoot, "#ticket-seats-draft", "20");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");
    await setInputValue(uiRoot, "#ticket-starts-1", "2026-04-10T10:00");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    expect(
      uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][starts_at]"]')?.value,
    ).to.equal("2026-04-10T14:00:00.000Z");

    currencyInput.value = "JPY";
    currencyInput.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Price (JPY)");
  });

  it("reconfigures ticket type dependencies on repeated configure calls", async () => {
    const initialAddButton = document.createElement("button");
    document.body.append(initialAddButton);

    const reconfiguredAddButton = document.createElement("button");
    document.body.append(reconfiguredAddButton);

    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    const timezoneInput = document.createElement("input");
    timezoneInput.value = "America/New_York";
    document.body.append(timezoneInput);

    const uiRoot = mountTicketTypesUi();
    uiRoot.configure({ addButton: initialAddButton });
    await uiRoot.updateComplete;

    uiRoot.configure({
      addButton: reconfiguredAddButton,
      currencyInput,
      timezoneInput,
    });
    await uiRoot.updateComplete;

    initialAddButton.click();
    await uiRoot.updateComplete;
    expect(uiRoot.querySelector('[data-ticketing-role="ticket-modal"]')?.className).to.contain("hidden");

    reconfiguredAddButton.click();
    await uiRoot.updateComplete;
    expect(uiRoot.textContent).to.contain("Price (EUR)");

    await setInputValue(uiRoot, "#ticket-title-draft", "Reconfigured ticket");
    await setInputValue(uiRoot, "#ticket-seats-draft", "20");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");
    await setInputValue(uiRoot, "#ticket-starts-1", "2026-04-10T10:00");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    expect(
      uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][starts_at]"]')?.value,
    ).to.equal("2026-04-10T14:00:00.000Z");

    currencyInput.value = "JPY";
    currencyInput.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Price (JPY)");
  });

  it("keeps free ticket prices as amount_minor 0 in hidden fields", async () => {
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;

    uiRoot._openTicketModal();
    await uiRoot.updateComplete;

    await setInputValue(uiRoot, "#ticket-title-draft", "Free entry");
    await setInputValue(uiRoot, "#ticket-seats-draft", "10");
    await setInputValue(uiRoot, "#ticket-price-1", "0");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Free entry");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][price_windows][0][amount_minor]"]')?.value,
    ).to.equal("0");
  });

  it("renders scheduled ticket windows with compact dates", async () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.setAttribute(
      "ticket-types",
      JSON.stringify([
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
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Early bird");
    expect(uiRoot.textContent).to.not.contain("until Apr 10");
    expect(uiRoot.textContent).to.not.contain("from Apr 11");
  });

  it("renders persisted ticket rows from the dataset and wires row actions", async () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.setAttribute(
      "ticket-types",
      JSON.stringify([
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
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("General admission");

    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent?.trim()).to.equal(
      "Edit ticket type",
    );
  });

  it("parses ticket type JSON from the element attribute", async () => {
    const uiRoot = mountTicketTypesUi();
    uiRoot.setAttribute(
      "ticket-types",
      JSON.stringify([
        {
          active: true,
          seats_total: 25,
          title: "Attribute ticket",
          price_windows: [{ amount_minor: 2500, starts_at: "", ends_at: "" }],
        },
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Attribute ticket");
  });

  it("rehydrates ticket rows when the attribute changes after mount", async () => {
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;

    uiRoot.setAttribute(
      "ticket-types",
      JSON.stringify([
        {
          active: true,
          seats_total: 25,
          title: "Late release ticket",
          price_windows: [{ amount_minor: 2500, starts_at: "", ends_at: "" }],
        },
      ]),
    );
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Late release ticket");
    expect(uiRoot.hasConfiguredTicketTypes()).to.equal(true);
  });

  it("keeps hidden ticket modal fields disabled so parent form validation ignores them", async () => {
    const form = document.createElement("form");
    const uiRoot = mountTicketTypesUi();
    form.append(uiRoot);
    document.body.append(form);

    await uiRoot.updateComplete;

    expect(form.checkValidity()).to.equal(true);
    expect(uiRoot.querySelector("#ticket-title-draft")?.disabled).to.equal(true);
    expect(uiRoot.querySelector("#ticket-seats-draft")?.disabled).to.equal(true);
  });

  it("requires an event currency when ticket types are configured", async () => {
    const currencyField = document.getElementById("payment_currency_code");
    currencyField.value = "";

    const uiRoot = mountTicketTypesUi();
    initializeTicketingWaitlistState();
    await uiRoot.updateComplete;

    uiRoot._openTicketModal();
    await uiRoot.updateComplete;

    await setInputValue(uiRoot, "#ticket-title-draft", "Paid ticket");
    await setInputValue(uiRoot, "#ticket-seats-draft", "25");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");

    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    expect(currencyField.required).to.equal(true);
    expect(currencyField.validationMessage).to.equal("Ticketed events require an event currency.");
    expect(currencyField.checkValidity()).to.equal(false);

    currencyField.value = "USD";
    currencyField.dispatchEvent(new Event("change", { bubbles: true, composed: true }));

    expect(currencyField.validationMessage).to.equal("");
    expect(currencyField.checkValidity()).to.equal(true);
  });

  it("renders discount code rows and updates serialization after modal edits", async () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.setAttribute(
      "discount-codes",
      JSON.stringify([
        {
          active: true,
          code: "EARLY20",
          kind: "percentage",
          percentage: 20,
          title: "Early supporter",
          total_available: 50,
        },
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Early supporter");
    expect(uiRoot.textContent).to.contain("EARLY20");
    expect(uiRoot.querySelector('input[name="discount_codes[0][percentage]"]')?.value).to.equal("20");

    uiRoot._openDiscountModal(uiRoot._rows[0]._row_id);
    await uiRoot.updateComplete;

    await setInputValue(uiRoot, "#discount-title-draft", "Member perk");
    await setInputValue(uiRoot, "#discount-code-draft", "member10");
    await setInputValue(uiRoot, "#discount-percentage-draft", "10");

    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Member perk");
    expect(uiRoot.textContent).to.contain("MEMBER10");
    expect(uiRoot.querySelector('input[name="discount_codes[0][title]"]')?.value).to.equal("Member perk");
    expect(uiRoot.querySelector('input[name="discount_codes[0][code]"]')?.value).to.equal("MEMBER10");
    expect(uiRoot.querySelector('input[name="discount_codes[0][percentage]"]')?.value).to.equal("10");
  });

  it("serializes discount availability override state explicitly", async () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.setAttribute(
      "discount-codes",
      JSON.stringify([
        {
          active: true,
          available: 12,
          available_override_active: true,
          code: "EARLY20",
          kind: "percentage",
          percentage: 20,
          title: "Early supporter",
          total_available: 50,
        },
      ]),
    );

    await uiRoot.updateComplete;

    uiRoot._openDiscountModal(uiRoot._rows[0]._row_id);
    await uiRoot.updateComplete;

    await setInputValue(uiRoot, "#discount-available-draft", "");

    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.querySelector('input[name="discount_codes[0][available]"]')).to.equal(null);
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][available_override_active]"]')?.value,
    ).to.equal("false");
  });

  it("adds and removes discount codes from the compact card list", async () => {
    const uiRoot = mountDiscountCodesUi();
    await uiRoot.updateComplete;

    uiRoot._openDiscountModal();
    await uiRoot.updateComplete;

    await setInputValue(uiRoot, "#discount-title-draft", "Sponsor invite");
    await setInputValue(uiRoot, "#discount-code-draft", "sponsor50");
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;
    await setInputValue(uiRoot, "#discount-amount-draft", "5.00");

    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Sponsor invite");
    expect(uiRoot.querySelector('input[name="discount_codes[0][amount_minor]"]')?.value).to.equal("500");

    uiRoot._removeDiscountCode(uiRoot._rows[0]._row_id);
    await uiRoot.updateComplete;

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
    uiRoot.configure({ addButton, currencyInput, timezoneInput });
    await uiRoot.updateComplete;

    addButton.click();
    await uiRoot.updateComplete;
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    expect(uiRoot.querySelector('label[for="discount-title-draft"]')?.textContent).to.contain("*");
    expect(uiRoot.querySelector('label[for="discount-code-draft"]')?.textContent).to.contain("*");
    expect(uiRoot.querySelector('label[for="discount-amount-draft"]')?.textContent).to.contain("*");
    expect(uiRoot.textContent).to.contain("Amount (EUR)");

    currencyInput.value = "GBP";
    currencyInput.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Amount (GBP)");

    uiRoot.querySelector("#discount-kind-draft").value = "percentage";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    expect(uiRoot.querySelector('label[for="discount-percentage-draft"]')?.textContent).to.contain("*");
  });

  it("reconfigures discount dependencies on repeated configure calls", async () => {
    const initialAddButton = document.createElement("button");
    document.body.append(initialAddButton);

    const reconfiguredAddButton = document.createElement("button");
    document.body.append(reconfiguredAddButton);

    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    const timezoneInput = document.createElement("input");
    timezoneInput.value = "UTC";
    document.body.append(timezoneInput);

    const uiRoot = mountDiscountCodesUi();
    uiRoot.configure({ addButton: initialAddButton });
    await uiRoot.updateComplete;

    uiRoot.configure({
      addButton: reconfiguredAddButton,
      currencyInput,
      timezoneInput,
    });
    await uiRoot.updateComplete;

    initialAddButton.click();
    await uiRoot.updateComplete;
    expect(uiRoot.querySelector('[data-ticketing-role="discount-modal"]')?.className).to.contain("hidden");

    reconfiguredAddButton.click();
    await uiRoot.updateComplete;
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Amount (EUR)");

    currencyInput.value = "GBP";
    currencyInput.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Amount (GBP)");
  });

  it("rejects zero fixed discount amounts in the editor", async () => {
    const uiRoot = mountDiscountCodesUi();
    await uiRoot.updateComplete;

    uiRoot._openDiscountModal();
    await uiRoot.updateComplete;

    await setInputValue(uiRoot, "#discount-title-draft", "Free comp");
    await setInputValue(uiRoot, "#discount-code-draft", "FREE0");
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;
    await setInputValue(uiRoot, "#discount-amount-draft", "0");

    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.not.contain("Free comp");
    expect(uiRoot.querySelector('input[name="discount_codes[0][amount_minor]"]')).to.equal(null);
  });

  it("renders persisted discount rows from the dataset and wires row actions", async () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.setAttribute(
      "discount-codes",
      JSON.stringify([
        {
          active: true,
          code: "EARLY20",
          kind: "percentage",
          percentage: 20,
          title: "Early supporter",
          total_available: 50,
        },
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Early supporter");

    uiRoot.querySelector('[data-ticketing-action="edit-discount"]')?.click();
    await uiRoot.updateComplete;

    expect(uiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent?.trim()).to.equal(
      "Edit discount code",
    );
  });

  it("parses discount code JSON from the element attribute", async () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.setAttribute(
      "discount-codes",
      JSON.stringify([
        {
          active: true,
          code: "ATTR20",
          kind: "percentage",
          percentage: 20,
          title: "Attribute code",
        },
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("Attribute code");
  });

  it("keeps hidden discount modal fields disabled so parent form validation ignores them", async () => {
    const form = document.createElement("form");
    const uiRoot = mountDiscountCodesUi();
    form.append(uiRoot);
    document.body.append(form);

    await uiRoot.updateComplete;

    expect(form.checkValidity()).to.equal(true);
    expect(uiRoot.querySelector("#discount-title-draft")?.disabled).to.equal(true);
    expect(uiRoot.querySelector("#discount-code-draft")?.disabled).to.equal(true);
  });

  it("preserves persisted remaining counts after discount row rerenders", async () => {
    const uiRoot = mountDiscountCodesUi();
    uiRoot.setAttribute(
      "discount-codes",
      JSON.stringify([
        {
          active: true,
          available: 12,
          code: "EARLY20",
          kind: "percentage",
          percentage: 20,
          title: "Early supporter",
          total_available: 50,
        },
      ]),
    );

    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("12 remaining");

    const currencyField = document.getElementById("payment_currency_code");
    currencyField.value = "USD";
    currencyField.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    expect(uiRoot.textContent).to.contain("12 remaining");
  });

  it("self-bootstraps ticketing editors from page controls after reconnecting", async () => {
    const ticketButton = document.createElement("button");
    ticketButton.id = "add-ticket-type-button";
    document.body.append(ticketButton);

    const discountButton = document.createElement("button");
    discountButton.id = "add-discount-code-button";
    document.body.append(discountButton);

    const ticketTypesUiRoot = mountTicketTypesUi();
    const discountCodesUiRoot = mountDiscountCodesUi();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    ticketButton.click();
    discountButton.click();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    expect(ticketTypesUiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent?.trim()).to.equal(
      "Add ticket type",
    );
    expect(
      discountCodesUiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent?.trim(),
    ).to.equal("Add discount code");

    ticketTypesUiRoot._closeTicketModal();
    discountCodesUiRoot._closeDiscountModal();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    const fragment = document.createElement("div");
    fragment.append(ticketTypesUiRoot, discountCodesUiRoot);
    document.body.append(fragment);
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    ticketButton.click();
    discountButton.click();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    expect(ticketTypesUiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent?.trim()).to.equal(
      "Add ticket type",
    );
    expect(
      discountCodesUiRoot.querySelector('[data-ticketing-role="modal-title"]')?.textContent?.trim(),
    ).to.equal("Add discount code");
  });

  it("restores body scroll when a ticket editor disconnects with the modal open", async () => {
    const ticketButton = document.createElement("button");
    ticketButton.id = "add-ticket-type-button";
    document.body.append(ticketButton);

    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;

    ticketButton.click();
    await uiRoot.updateComplete;

    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.body.style.overflow).to.equal("hidden");

    uiRoot.remove();

    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });
});
