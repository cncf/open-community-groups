import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/events_update.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group event update template", () => {
  it("keeps the existing read-only copy when registration answers lock question editing", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include("{% if event.registration_questions_locked -%}");
    expect(template).to.include(
      "Registration questions are read-only because attendees have submitted answers.",
    );
  });
});
