import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/events_update.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group event update template", () => {
  it("keeps the existing read-only copy when registration answers lock question editing", async () => {
    // Load the event update template before checking locked question copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the rendered registration question fields.
    expect(template).to.include("{% if event.registration_questions_locked -%}");
    expect(template).to.include(
      "Registration questions are read-only because attendees have submitted answers.",
    );
  });

  it("passes past-event state to online event and session details", async () => {
    // Load the event update template before checking the component contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the online and session details components receive past-event state.
    expect(template).to.include("{% if event.is_past() %}event-past{% endif %}");
  });
});
