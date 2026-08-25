import { expect } from "@open-wc/testing";

const loadTemplate = async (path) => {
  const response = await fetch(path);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("event card templates", () => {
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

  it("places check-in status beneath the compact event title", async () => {
    // Load the shared cards template before checking Check-In card presentation.
    const template = normalizeWhitespace(
      await loadTemplate("/ocg-server/templates/macros/cards.html"),
    );

    // Verify compact title typography precedes the caller-provided status.
    expect(template).to.include(
      "text-[0.85rem]/[1.05rem] text-stone-900 md:text-[0.9rem]/[1.1rem]",
    );
    expect(template).not.to.include("group-hover:text-primary-600");
    expect(template).to.include(
      '{{ event.name }} </span> <span class="mt-auto flex min-h-[17px] flex-wrap items-end gap-2">{{ caller() }}</span>',
    );
    expect(template).not.to.include("status_before_title");
  });
});
