import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/event/attend_button.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("event attendance button template", () => {
  it("keeps price-ineligible approval tickets disabled in cached markup", async () => {
    // Load the cached ticket controls used when availability refresh fails.
    const template = normalizeWhitespace(await loadTemplate());

    // Approval requests expose the same selectable contract as refreshed cards.
    expect(template).to.include("data-ticket-selectable=");
    expect(template).to.include("ticket_type.current_price.is_none()");
    expect(template).to.include(
      "ticket_type.current_price.is_some() && (event.attendee_approval_required || ticket_type.is_sellable_now()",
    );
    expect(template).to.include('data-attendance-role="ticket-type-indicator"');
    expect(template).to.include('data-attendance-role="ticket-type-description"');
    expect(template).to.include("group-has-[input:focus-visible]:ring-2");
  });
});
