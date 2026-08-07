import { expect } from "@open-wc/testing";

const loadTemplate = async (path) => {
  const response = await fetch(path);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("event card price templates", () => {
  it("hides free-only price badges across shared and calendar event cards", async () => {
    // Load both event card price entrypoints.
    const [cardsTemplate, calendarTemplate] = await Promise.all([
      loadTemplate("/ocg-server/templates/macros/cards.html"),
      loadTemplate("/ocg-server/templates/site/explore/events/calendar_event_card.html"),
    ]);

    // Verify free-only labels are filtered before card markup is rendered.
    expect(normalizeWhitespace(cardsTemplate)).to.include('{% if ticket_price_badge != "Free" -%}');
    expect(normalizeWhitespace(calendarTemplate)).to.include('{% if ticket_price_badge != "Free" -%}');
  });
});
