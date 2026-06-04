import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import { initializeEventEnrollmentState } from "/static/js/dashboard/event/ticketing.js";
import "/static/js/dashboard/event/ticketing/ticket-types-editor.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

// Set input value for the test.
const setInputValue = async (
  container,
  selector,
  value,
  eventName = "input",
) => {
  const field = container.querySelector(selector);
  field.value = value;
  field.dispatchEvent(new Event(eventName, { bubbles: true, composed: true }));
  if ("updateComplete" in container) {
    await container.updateComplete;
  }
  return field;
};

// Mount ticket types ui for the test.
const mountTicketTypesUi = () => {
  const wrapper = document.createElement("ticket-types-editor");
  wrapper.id = "ticket-types-ui";
  wrapper.setAttribute("ticket-types", "[]");
  wrapper.dataset.disabled = "false";
  document.body.append(wrapper);
  return wrapper;
};

// Mount discount codes ui for the test.
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

    // Prepare the module under test.
    const currencyField = document.createElement("select");
    currencyField.id = "payment_currency_code";
    currencyField.innerHTML = `
      <option value="">Select currency</option>
      <option value="EUR">EUR</option>
      <option value="USD">USD</option>
    `;
    currencyField.value = "EUR";
    document.body.append(currencyField);

    // Prepare the module under test.
    const timezoneField = document.createElement("input");
    timezoneField.name = "timezone";
    timezoneField.value = "UTC";
    document.body.append(timezoneField);
  });

  it("renders ticket type summary rows and preserves hidden field serialization", async () => {
    // Prepare the UI root for persisted ticket summary rows.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify renders ticket type summary rows and preserves hidden field.
    expect(uiRoot.textContent).to.contain("General admission");
    expect(uiRoot.textContent).to.contain("25");
    expect(
      uiRoot.querySelector('input[name="ticket_types_present"]')?.value,
    ).to.equal("true");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][title]"]')?.value,
    ).to.equal("General admission");
    expect(
      uiRoot.querySelector(
        'input[name="ticket_types[0][price_windows][0][amount_minor]"]',
      )?.value,
    ).to.equal("3000");
    expect(uiRoot.hasConfiguredTicketTypes()).to.equal(true);
  });

  it("keeps seats and status in dedicated table cells on small layouts", async () => {
    // Prepare ui root for keeping seats and status in dedicated table cells.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Read the ticket row cells in the compact layout.
    const rowCells = uiRoot.querySelectorAll(
      '[data-ticketing-role="table-body"] tr td',
    );

    // Verify keeps seats and status in dedicated table cells on small layouts.
    expect(rowCells).to.have.length(4);
    expect(rowCells[1].className).to.not.contain("hidden");
    expect(rowCells[1].textContent).to.contain("25");
    expect(rowCells[2].className).to.not.contain("hidden");
    expect(rowCells[2].textContent).to.contain("Active");
    expect(rowCells[0].textContent).to.not.contain("25 seats");
  });

  it("adds ticket types through the modal and emits ticket-types-changed", async () => {
    // Prepare ui root for adding ticket types through the modal and emits.
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;
    const events = [];
    uiRoot.addEventListener("ticket-types-changed", (event) =>
      events.push(event.detail),
    );

    // Verify adds ticket types through the modal and emits.
    uiRoot._openTicketModal();
    await uiRoot.updateComplete;

    // Verify adds ticket types through the modal and emits ticket-types-changed.
    expect(
      uiRoot.querySelector('label[for="ticket-title-draft"]')?.textContent,
    ).to.contain("*");
    expect(
      uiRoot.querySelector('label[for="ticket-seats-draft"]')?.textContent,
    ).to.contain("*");
    expect(
      uiRoot.querySelector('label[for="ticket-price-1"]')?.textContent,
    ).to.contain("*");
    expect(uiRoot.querySelector("#ticket-price-1")?.max).to.equal("999999.99");

    // Verify adds ticket types through the modal and emits.
    await setInputValue(uiRoot, "#ticket-title-draft", "Early bird");
    await setInputValue(uiRoot, "#ticket-seats-draft", "40");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");

    // Verify adds ticket types through the modal.
    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Verify adds ticket types through the modal and emits ticket-types-changed.
    expect(uiRoot.textContent).to.contain("Early bird");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][title]"]')?.value,
    ).to.equal("Early bird");
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][seats_total]"]')?.value,
    ).to.equal("40");
    expect(
      uiRoot.querySelector(
        'input[name="ticket_types[0][price_windows][0][amount_minor]"]',
      )?.value,
    ).to.equal("1500");
    expect(events.at(-1)).to.deep.equal({ hasTicketTypes: true });
  });

  it("rejects ticket prices outside Stripe charge limits before saving", async () => {
    // Update the input before asserting it rejects ticket prices outside Stripe charge.
    document.getElementById("payment_currency_code").value = "USD";

    // Prepare ui root for rejects ticket prices outside Stripe charge limits.
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;

    // Verify rejects ticket prices outside Stripe charge limits.
    uiRoot._openTicketModal();
    await uiRoot.updateComplete;

    // Fill ticket title draft.
    await setInputValue(uiRoot, "#ticket-title-draft", "Tiny paid ticket");
    await setInputValue(uiRoot, "#ticket-seats-draft", "40");
    const priceInput = await setInputValue(uiRoot, "#ticket-price-1", "0.49");

    // Verify rejects ticket prices outside Stripe.
    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Verify rejects ticket prices outside Stripe charge limits before saving.
    expect(priceInput.validationMessage).to.equal(
      "Use 0 for free tickets, or at least 0.50 USD.",
    );
    expect(
      uiRoot.querySelector('input[name="ticket_types[0][title]"]'),
    ).to.equal(null);

    // Verify rejects ticket prices outside Stripe charge limits.
    await setInputValue(uiRoot, "#ticket-price-1", "1000000.00");
    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Verify rejects ticket prices outside Stripe charge limits before saving.
    expect(priceInput.validationMessage).to.equal(
      "Stripe allows up to 999999.99 USD.",
    );
  });

  it("uses explicit ticket type controller dependencies instead of global fields", async () => {
    // Update the input before asserting it uses explicit ticket type controller.
    document.getElementById("payment_currency_code").value = "USD";
    document.querySelector('[name="timezone"]').value = "UTC";

    // Prepare add button for using explicit ticket type controller dependencies.
    const addButton = document.createElement("button");
    document.body.append(addButton);

    // Prepare currency input for using explicit ticket type controller.
    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    // Prepare timezone input for using explicit ticket type controller.
    const timezoneInput = document.createElement("input");
    timezoneInput.value = "America/New_York";
    document.body.append(timezoneInput);

    // Prepare ui root for using explicit ticket type controller dependencies.
    const uiRoot = mountTicketTypesUi();
    uiRoot.configure({ addButton, currencyInput, timezoneInput });
    await uiRoot.updateComplete;

    // Verify uses explicit ticket type controller.
    addButton.click();
    await uiRoot.updateComplete;

    // Verify uses explicit ticket type controller dependencies instead of global.
    expect(uiRoot.textContent).to.contain("Price (EUR)");

    // Verify uses explicit ticket type controller dependencies.
    await setInputValue(
      uiRoot,
      "#ticket-title-draft",
      "Custom dependency ticket",
    );
    await setInputValue(uiRoot, "#ticket-seats-draft", "20");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");
    await setInputValue(uiRoot, "#ticket-starts-1", "2026-04-10T10:00");

    // Verify uses explicit ticket type controller.
    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Verify uses explicit ticket type controller dependencies instead of global.
    expect(
      uiRoot.querySelector(
        'input[name="ticket_types[0][price_windows][0][starts_at]"]',
      )?.value,
    ).to.equal("2026-04-10T14:00:00.000Z");

    // Update the input before asserting it uses explicit ticket type controller.
    currencyInput.value = "JPY";
    currencyInput.dispatchEvent(
      new Event("input", { bubbles: true, composed: true }),
    );
    await uiRoot.updateComplete;

    // Verify uses explicit ticket type controller.
    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Verify uses explicit ticket type controller dependencies instead of global.
    expect(uiRoot.textContent).to.contain("Price (JPY)");
  });

  it("reconfigures ticket type dependencies on repeated configure calls", async () => {
    // Prepare initial add button for reconfiguring ticket type dependencies.
    const initialAddButton = document.createElement("button");
    document.body.append(initialAddButton);

    // Prepare reconfigured add button for reconfiguring ticket type dependencies.
    const reconfiguredAddButton = document.createElement("button");
    document.body.append(reconfiguredAddButton);

    // Prepare currency input for reconfiguring ticket type dependencies.
    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    // Prepare timezone input for reconfiguring ticket type dependencies.
    const timezoneInput = document.createElement("input");
    timezoneInput.value = "America/New_York";
    document.body.append(timezoneInput);

    // Prepare ui root for reconfiguring ticket type dependencies on repeated.
    const uiRoot = mountTicketTypesUi();
    uiRoot.configure({ addButton: initialAddButton });
    await uiRoot.updateComplete;

    // Repeated configuration keeps ticket type dependencies current.
    uiRoot.configure({
      addButton: reconfiguredAddButton,
      currencyInput,
      timezoneInput,
    });
    await uiRoot.updateComplete;

    // Click the initial add button.
    initialAddButton.click();
    await uiRoot.updateComplete;
    expect(
      uiRoot.querySelector('[data-ticketing-role="ticket-modal"]')?.className,
    ).to.contain("hidden");

    // Click the reconfigured add button.
    reconfiguredAddButton.click();
    await uiRoot.updateComplete;
    expect(uiRoot.textContent).to.contain("Price (EUR)");

    // Ticket type dependencies stay current after another configuration.
    await setInputValue(uiRoot, "#ticket-title-draft", "Reconfigured ticket");
    await setInputValue(uiRoot, "#ticket-seats-draft", "20");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");
    await setInputValue(uiRoot, "#ticket-starts-1", "2026-04-10T10:00");

    // Ticket type dependencies update dependent fields.
    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Repeated configure calls keep ticket type dependencies current.
    expect(
      uiRoot.querySelector(
        'input[name="ticket_types[0][price_windows][0][starts_at]"]',
      )?.value,
    ).to.equal("2026-04-10T14:00:00.000Z");

    // Update the input before asserting it reconfigures ticket type dependencies.
    currencyInput.value = "JPY";
    currencyInput.dispatchEvent(
      new Event("input", { bubbles: true, composed: true }),
    );
    await uiRoot.updateComplete;

    // Reconfigured ticket type dependencies update field state.
    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Reconfigured ticket type dependencies update the dependent fields.
    expect(uiRoot.textContent).to.contain("Price (JPY)");
  });

  it("keeps free ticket prices as amount_minor 0 in hidden fields", async () => {
    // Prepare the UI root before saving a free ticket.
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;

    // Verify free tickets keep amount_minor 0 in hidden fields.
    uiRoot._openTicketModal();
    await uiRoot.updateComplete;

    // Fill ticket title draft.
    await setInputValue(uiRoot, "#ticket-title-draft", "Free entry");
    await setInputValue(uiRoot, "#ticket-seats-draft", "10");
    await setInputValue(uiRoot, "#ticket-price-1", "0");

    // Save the free ticket through the editor.
    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Verify keeps free ticket prices as amount_minor 0 in hidden fields.
    expect(uiRoot.textContent).to.contain("Free entry");
    expect(
      uiRoot.querySelector(
        'input[name="ticket_types[0][price_windows][0][amount_minor]"]',
      )?.value,
    ).to.equal("0");
  });

  it("renders scheduled ticket windows with compact dates", async () => {
    // Prepare ui root for rendering scheduled ticket windows with compact dates.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify renders scheduled ticket windows with compact dates.
    expect(uiRoot.textContent).to.contain("Early bird");
    expect(uiRoot.textContent).to.not.contain("until Apr 10");
    expect(uiRoot.textContent).to.not.contain("from Apr 11");
  });

  it("renders persisted ticket rows from the dataset and wires row actions", async () => {
    // Prepare ui root for rendering persisted ticket rows from the dataset.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Assert that the persisted ticket is rendered.
    expect(uiRoot.textContent).to.contain("General admission");

    // Verify renders persisted ticket rows.
    uiRoot.querySelector('[data-ticketing-action="edit-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Assert that editing opens the ticket modal.
    expect(
      uiRoot
        .querySelector('[data-ticketing-role="modal-title"]')
        ?.textContent?.trim(),
    ).to.equal("Edit ticket type");
  });

  it("parses ticket type JSON from the element attribute", async () => {
    // Prepare ui root for parses ticket type JSON from the element attribute.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Ticket type JSON is parsed from the element attribute.
    expect(uiRoot.textContent).to.contain("Attribute ticket");
  });

  it("rehydrates ticket rows when the attribute changes after mount", async () => {
    // Prepare ui root for rehydrates ticket rows when the attribute changes.
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;

    // Update fixture state before asserting the new state.
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

    // Ticket rows rehydrate when the attribute changes after mount.
    expect(uiRoot.textContent).to.contain("Late release ticket");
    expect(uiRoot.hasConfiguredTicketTypes()).to.equal(true);
  });

  it("keeps hidden ticket modal fields disabled so parent form validation ignores them", async () => {
    // Prepare form for keeping hidden ticket modal fields disabled so parent form.
    const form = document.createElement("form");
    const uiRoot = mountTicketTypesUi();
    form.append(uiRoot);
    document.body.append(form);

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify keeps hidden ticket modal fields disabled so parent form validation.
    expect(form.checkValidity()).to.equal(true);
    expect(uiRoot.querySelector("#ticket-title-draft")?.disabled).to.equal(
      true,
    );
    expect(uiRoot.querySelector("#ticket-seats-draft")?.disabled).to.equal(
      true,
    );
  });

  it("requires an event currency when ticket types are configured", async () => {
    // Keep a reference to the payment currency code element.
    const currencyField = document.getElementById("payment_currency_code");
    currencyField.value = "";

    // Prepare ui root for requiring an event currency when ticket types.
    const uiRoot = mountTicketTypesUi();
    initializeEventEnrollmentState();
    await uiRoot.updateComplete;

    // Verify requires an event currency when ticket types.
    uiRoot._openTicketModal();
    await uiRoot.updateComplete;

    // Fill ticket title draft.
    await setInputValue(uiRoot, "#ticket-title-draft", "Paid ticket");
    await setInputValue(uiRoot, "#ticket-seats-draft", "25");
    await setInputValue(uiRoot, "#ticket-price-1", "15.00");

    // Verify requires an event currency when ticket.
    uiRoot.querySelector('[data-ticketing-action="save-ticket"]')?.click();
    await uiRoot.updateComplete;

    // Verify requires an event currency when ticket types are configured.
    expect(currencyField.required).to.equal(true);
    expect(currencyField.validationMessage).to.equal(
      "Ticketed events require an event currency.",
    );
    expect(currencyField.checkValidity()).to.equal(false);

    // Update the input before asserting it requires an event currency when ticket types.
    currencyField.value = "USD";
    currencyField.dispatchEvent(
      new Event("change", { bubbles: true, composed: true }),
    );

    // Verify requires an event currency when ticket types are configured.
    expect(currencyField.validationMessage).to.equal("");
    expect(currencyField.checkValidity()).to.equal(true);
  });

  it("renders discount code rows and updates serialization after modal edits", async () => {
    // Prepare ui root for rendering discount code rows and updates serialization.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify renders discount code rows and updates serialization after modal edits.
    expect(uiRoot.textContent).to.contain("Early supporter");
    expect(uiRoot.textContent).to.contain("EARLY20");
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][percentage]"]')
        ?.value,
    ).to.equal("20");

    // Verify renders discount code rows and updates serialization.
    uiRoot._openDiscountModal(uiRoot._rows[0]._row_id);
    await uiRoot.updateComplete;

    // Fill discount title draft.
    await setInputValue(uiRoot, "#discount-title-draft", "Member perk");
    await setInputValue(uiRoot, "#discount-code-draft", "member10");
    await setInputValue(uiRoot, "#discount-percentage-draft", "10");

    // Verify renders discount code rows and updates.
    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    // Verify renders discount code rows and updates serialization after modal edits.
    expect(uiRoot.textContent).to.contain("Member perk");
    expect(uiRoot.textContent).to.contain("MEMBER10");
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][title]"]')?.value,
    ).to.equal("Member perk");
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][code]"]')?.value,
    ).to.equal("MEMBER10");
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][percentage]"]')
        ?.value,
    ).to.equal("10");
  });

  it("serializes discount availability override state explicitly", async () => {
    // Prepare ui root for serializes discount availability override state.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify serializes discount availability override state.
    uiRoot._openDiscountModal(uiRoot._rows[0]._row_id);
    await uiRoot.updateComplete;

    // Fill discount available draft.
    await setInputValue(uiRoot, "#discount-available-draft", "");

    // Verify serializes discount availability override.
    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    // Verify serializes discount availability override state explicitly.
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][available]"]'),
    ).to.equal(null);
    expect(
      uiRoot.querySelector(
        'input[name="discount_codes[0][available_override_active]"]',
      )?.value,
    ).to.equal("false");
  });

  it("preserves preloaded discount availability overrides marked dirty", async () => {
    // Prepare ui root for preserves preloaded discount availability overrides.
    const uiRoot = mountDiscountCodesUi();
    uiRoot.setAttribute(
      "discount-codes",
      JSON.stringify([
        {
          active: true,
          available: 12,
          available_dirty: true,
          available_override_active: true,
          code: "EARLY20",
          kind: "percentage",
          percentage: 20,
          title: "Early supporter",
          total_available: 50,
        },
      ]),
    );

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify preserves preloaded discount availability overrides marked dirty.
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][available]"]')?.value,
    ).to.equal("12");
    expect(
      uiRoot.querySelector(
        'input[name="discount_codes[0][available_override_active]"]',
      )?.value,
    ).to.equal("true");
  });

  it("adds and removes discount codes from the compact card list", async () => {
    // Prepare ui root for adding and removes discount codes from the compact card.
    const uiRoot = mountDiscountCodesUi();
    await uiRoot.updateComplete;

    // Verify adds and removes discount codes from the compact.
    uiRoot._openDiscountModal();
    await uiRoot.updateComplete;

    // Fill discount title draft.
    await setInputValue(uiRoot, "#discount-title-draft", "Sponsor invite");
    await setInputValue(uiRoot, "#discount-code-draft", "sponsor50");
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;
    await setInputValue(uiRoot, "#discount-amount-draft", "5.00");

    // Verify adds and removes discount codes.
    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    // Verify adds and removes discount codes from the compact card list.
    expect(uiRoot.textContent).to.contain("Sponsor invite");
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][amount_minor]"]')
        ?.value,
    ).to.equal("500");

    // Verify adds and removes discount codes from the compact.
    uiRoot._removeDiscountCode(uiRoot._rows[0]._row_id);
    await uiRoot.updateComplete;

    // Verify adds and removes discount codes from the compact card list.
    expect(uiRoot.textContent).to.contain("No discount codes yet.");
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][title]"]'),
    ).to.equal(null);
  });

  it("uses explicit discount controller dependencies instead of global fields", async () => {
    // Update the input before checking explicit discount dependencies.
    document.getElementById("payment_currency_code").value = "USD";

    // Prepare add button for using explicit discount controller dependencies.
    const addButton = document.createElement("button");
    document.body.append(addButton);

    // Prepare currency input for using explicit discount controller dependencies.
    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    // Prepare timezone input for using explicit discount controller dependencies.
    const timezoneInput = document.createElement("input");
    timezoneInput.value = "UTC";
    document.body.append(timezoneInput);

    // Prepare the UI root with explicit discount controller dependencies.
    const uiRoot = mountDiscountCodesUi();
    uiRoot.configure({ addButton, currencyInput, timezoneInput });
    await uiRoot.updateComplete;

    // Verify uses explicit discount controller.
    addButton.click();
    await uiRoot.updateComplete;
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    // Verify uses explicit discount controller dependencies instead of global fields.
    expect(
      uiRoot.querySelector('label[for="discount-title-draft"]')?.textContent,
    ).to.contain("*");
    expect(
      uiRoot.querySelector('label[for="discount-code-draft"]')?.textContent,
    ).to.contain("*");
    expect(
      uiRoot.querySelector('label[for="discount-amount-draft"]')?.textContent,
    ).to.contain("*");
    expect(uiRoot.textContent).to.contain("Amount (EUR)");

    // Update the input before checking the discount dependency value.
    currencyInput.value = "GBP";
    currencyInput.dispatchEvent(
      new Event("input", { bubbles: true, composed: true }),
    );
    await uiRoot.updateComplete;

    // Verify uses explicit discount controller dependencies instead of global fields.
    expect(uiRoot.textContent).to.contain("Amount (GBP)");

    // Update the input before checking the repeated discount dependency value.
    uiRoot.querySelector("#discount-kind-draft").value = "percentage";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    // Verify uses explicit discount controller dependencies instead of global fields.
    expect(
      uiRoot.querySelector('label[for="discount-percentage-draft"]')
        ?.textContent,
    ).to.contain("*");
  });

  it("reconfigures discount dependencies on repeated configure calls", async () => {
    // Prepare initial add button for reconfiguring discount dependencies.
    const initialAddButton = document.createElement("button");
    document.body.append(initialAddButton);

    // Prepare reconfigured add button for reconfiguring discount dependencies.
    const reconfiguredAddButton = document.createElement("button");
    document.body.append(reconfiguredAddButton);

    // Prepare currency input for reconfiguring discount dependencies on repeated.
    const currencyInput = document.createElement("input");
    currencyInput.value = "EUR";
    document.body.append(currencyInput);

    // Prepare timezone input for reconfiguring discount dependencies on repeated.
    const timezoneInput = document.createElement("input");
    timezoneInput.value = "UTC";
    document.body.append(timezoneInput);

    // Prepare ui root for reconfiguring discount dependencies on repeated.
    const uiRoot = mountDiscountCodesUi();
    uiRoot.configure({ addButton: initialAddButton });
    await uiRoot.updateComplete;

    // Repeated configuration keeps discount dependencies current.
    uiRoot.configure({
      addButton: reconfiguredAddButton,
      currencyInput,
      timezoneInput,
    });
    await uiRoot.updateComplete;

    // Click the initial add button.
    initialAddButton.click();
    await uiRoot.updateComplete;
    expect(
      uiRoot.querySelector('[data-ticketing-role="discount-modal"]')?.className,
    ).to.contain("hidden");

    // Click the reconfigured add button.
    reconfiguredAddButton.click();
    await uiRoot.updateComplete;
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;

    // Repeated configure calls keep discount dependencies current.
    expect(uiRoot.textContent).to.contain("Amount (EUR)");

    // Update the input before checking reconfigured discount dependencies.
    currencyInput.value = "GBP";
    currencyInput.dispatchEvent(
      new Event("input", { bubbles: true, composed: true }),
    );
    await uiRoot.updateComplete;

    // Reconfigured discount dependencies update the dependent fields.
    expect(uiRoot.textContent).to.contain("Amount (GBP)");
  });

  it("rejects zero fixed discount amounts in the editor", async () => {
    // Prepare ui root for rejects zero fixed discount amounts in the editor.
    const uiRoot = mountDiscountCodesUi();
    await uiRoot.updateComplete;

    // Verify rejects zero fixed discount amounts in the editor.
    uiRoot._openDiscountModal();
    await uiRoot.updateComplete;

    // Fill discount title draft.
    await setInputValue(uiRoot, "#discount-title-draft", "Free comp");
    await setInputValue(uiRoot, "#discount-code-draft", "FREE0");
    uiRoot.querySelector("#discount-kind-draft").value = "fixed_amount";
    uiRoot
      .querySelector("#discount-kind-draft")
      .dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    await uiRoot.updateComplete;
    await setInputValue(uiRoot, "#discount-amount-draft", "0");

    // Verify rejects zero fixed discount amounts.
    uiRoot.querySelector('[data-ticketing-action="save-discount"]')?.click();
    await uiRoot.updateComplete;

    // Verify rejects zero fixed discount amounts in the editor.
    expect(uiRoot.textContent).to.not.contain("Free comp");
    expect(
      uiRoot.querySelector('input[name="discount_codes[0][amount_minor]"]'),
    ).to.equal(null);
  });

  it("renders persisted discount rows from the dataset and wires row actions", async () => {
    // Prepare ui root for rendering persisted discount rows from the dataset.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Assert that the persisted discount is rendered.
    expect(uiRoot.textContent).to.contain("Early supporter");

    // Verify renders persisted discount rows.
    uiRoot.querySelector('[data-ticketing-action="edit-discount"]')?.click();
    await uiRoot.updateComplete;

    // Assert that editing opens the discount modal.
    expect(
      uiRoot
        .querySelector('[data-ticketing-role="modal-title"]')
        ?.textContent?.trim(),
    ).to.equal("Edit discount code");
  });

  it("parses discount code JSON from the element attribute", async () => {
    // Prepare ui root for parses discount code JSON from the element attribute.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Discount code JSON is parsed from the element attribute.
    expect(uiRoot.textContent).to.contain("Attribute code");
  });

  it("keeps hidden discount modal fields disabled so parent form validation ignores them", async () => {
    // Prepare form for keeping hidden discount modal fields disabled so parent.
    const form = document.createElement("form");
    const uiRoot = mountDiscountCodesUi();
    form.append(uiRoot);
    document.body.append(form);

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify keeps hidden discount modal fields disabled so parent form validation.
    expect(form.checkValidity()).to.equal(true);
    expect(uiRoot.querySelector("#discount-title-draft")?.disabled).to.equal(
      true,
    );
    expect(uiRoot.querySelector("#discount-code-draft")?.disabled).to.equal(
      true,
    );
  });

  it("preserves persisted remaining counts after discount row rerenders", async () => {
    // Prepare ui root for preserves persisted remaining counts after discount.
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

    // Wait for the component to finish rendering.
    await uiRoot.updateComplete;

    // Verify preserves persisted remaining counts after discount row rerenders.
    expect(uiRoot.textContent).to.contain("12 remaining");

    // Keep a reference to the payment currency code element.
    const currencyField = document.getElementById("payment_currency_code");
    currencyField.value = "USD";
    currencyField.dispatchEvent(
      new Event("input", { bubbles: true, composed: true }),
    );
    await uiRoot.updateComplete;

    // Verify preserves persisted remaining counts after discount row rerenders.
    expect(uiRoot.textContent).to.contain("12 remaining");
  });

  it("self-bootstraps ticketing editors from page controls after reconnecting", async () => {
    // Prepare ticket button for self-bootstraps ticketing editors from page.
    const ticketButton = document.createElement("button");
    ticketButton.id = "add-ticket-type-button";
    document.body.append(ticketButton);

    // Prepare discount button for self-bootstraps ticketing editors from page.
    const discountButton = document.createElement("button");
    discountButton.id = "add-discount-code-button";
    document.body.append(discountButton);

    // Prepare ticket types ui root for self-bootstraps ticketing editors.
    const ticketTypesUiRoot = mountTicketTypesUi();
    const discountCodesUiRoot = mountDiscountCodesUi();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    // Ticketing editors bootstrap from the page controls.
    ticketButton.click();
    discountButton.click();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    // Reconnected ticketing editors bootstrap from page controls.
    expect(
      ticketTypesUiRoot
        .querySelector('[data-ticketing-role="modal-title"]')
        ?.textContent?.trim(),
    ).to.equal("Add ticket type");
    expect(
      discountCodesUiRoot
        .querySelector('[data-ticketing-role="modal-title"]')
        ?.textContent?.trim(),
    ).to.equal("Add discount code");

    // Reconnected ticketing editors keep their page-control wiring.
    ticketTypesUiRoot._closeTicketModal();
    discountCodesUiRoot._closeDiscountModal();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    // Prepare fragment for self-bootstraps ticketing editors from page controls.
    const fragment = document.createElement("div");
    fragment.append(ticketTypesUiRoot, discountCodesUiRoot);
    document.body.append(fragment);
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    // Discount editors bootstrap from the page controls.
    ticketButton.click();
    discountButton.click();
    await ticketTypesUiRoot.updateComplete;
    await discountCodesUiRoot.updateComplete;

    // Reconnected discount editors bootstrap from page controls.
    expect(
      ticketTypesUiRoot
        .querySelector('[data-ticketing-role="modal-title"]')
        ?.textContent?.trim(),
    ).to.equal("Add ticket type");
    expect(
      discountCodesUiRoot
        .querySelector('[data-ticketing-role="modal-title"]')
        ?.textContent?.trim(),
    ).to.equal("Add discount code");
  });

  it("restores body scroll when a ticket editor disconnects with the modal open", async () => {
    // Prepare ticket button for restores body scroll when a ticket editor.
    const ticketButton = document.createElement("button");
    ticketButton.id = "add-ticket-type-button";
    document.body.append(ticketButton);

    // Prepare ui root for restores body scroll when a ticket editor disconnects.
    const uiRoot = mountTicketTypesUi();
    await uiRoot.updateComplete;

    // Click the ticket button.
    ticketButton.click();
    await uiRoot.updateComplete;

    // Assert the document.
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.body.style.overflow).to.equal("hidden");

    // Remove the editor while the modal is open.
    uiRoot.remove();

    // Assert the updated document.
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });
});
