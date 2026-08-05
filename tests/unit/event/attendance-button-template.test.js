import { expect } from "@open-wc/testing";

const loadTemplate = async (path = "/ocg-server/templates/event/attend_button.html") => {
  const response = await fetch(path);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("event attendance button template", () => {
  it("loads enrollment state from the enrollment endpoint", async () => {
    // Load the hidden checker that refreshes the current user's event state.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      'hx-get="/{{ event.community.name }}/event/{{ event.event_id }}/enrollment"',
    );
  });

  it("includes registration answers only when the event has questions", async () => {
    // Load the attend action that submits the optional answers payload.
    const template = normalizeWhitespace(await loadTemplate());

    // The hx-include guard matches the conditional hidden answers input.
    expect(template).to.include(
      '{% if !event.registration_questions.is_empty() -%} hx-include="#registration-answers-input-{{ attendance_instance }}" {% endif -%}',
    );
  });

  it("marks initially hidden attendance dialogs as hidden for assistive technology", async () => {
    // Load the server-rendered dialogs before JavaScript initializes them.
    const template = normalizeWhitespace(await loadTemplate());

    // Registration and ticket dialogs expose the same initial hidden state.
    expect(template).to.include(
      'data-attendance-role="registration-modal" role="dialog" aria-modal="true" aria-hidden="true"',
    );
    expect(template).to.include(
      'data-attendance-role="ticket-modal" role="dialog" aria-modal="true" aria-hidden="true"',
    );
  });

  it("keeps price-ineligible approval tickets disabled in cached markup", async () => {
    // Load the cached ticket controls used when availability refresh fails.
    const template = normalizeWhitespace(await loadTemplate());

    // Approval requests expose the same selectable contract as refreshed cards.
    expect(template).to.include("data-ticket-selectable=");
    expect(template).to.include(
      "ticket_type_selectable = !event.canceled && ticket_type.active && ticket_type.current_price.is_some()",
    );
    expect(template).to.include("{% if !ticket_type_selectable %}disabled{% endif %}");
    expect(template).to.include('data-attendance-role="ticket-type-indicator"');
    expect(template).to.include('data-attendance-role="ticket-type-description"');
    expect(template).to.include("group-has-[input:focus-visible]:ring-2");
  });

  it("keeps cached and refreshed ticket status copy consistent", async () => {
    // Load the server-rendered status labels used before availability hydration.
    const template = normalizeWhitespace(await loadTemplate());

    // The frontend payload cannot reproduce a price-window end timestamp.
    expect(template).to.include("Available now");
    expect(template).to.not.include("Available until");
  });

  it("shares initial control content and floating badge typography", async () => {
    // Load the primary control template and its attendance macros.
    const template = await loadTemplate();
    const macros = await loadTemplate("/ocg-server/templates/event/attendance_macros.html");

    // Signed-in and signed-out controls use one macro and the same badge size.
    expect(template.match(/attendance::initial_control_content/g)).to.have.length(2);
    expect(macros).to.include("text-[11px]");
    expect(macros).to.not.include("text-[12px]");
  });
});
