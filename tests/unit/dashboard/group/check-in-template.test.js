import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/check_in_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group check-in template", () => {
  it("uses the dashboard content width", async () => {
    // Load the Check-In template before checking its page alignment.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the partial does not add a centered page-width constraint.
    expect(template).to.include(
      '<section class="relative min-w-0" data-group-check-in-root',
    );
    expect(template).not.to.include("container mx-auto");
    expect(template).not.to.include("max-w-7xl");
    expect(template).to.include("cards::check_in_event_card(event)");
    expect(template).not.to.include("status_before_title = true");
  });

  it("renders three event-card columns on extra-wide screens", async () => {
    // Load the Check-In template before checking its responsive grid.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the organizer grid grows from two to three columns at 2xl.
    expect(template).to.include("lg:grid-cols-2 2xl:grid-cols-3");
  });

  it("uses a labeled mini button to open each event scanner", async () => {
    // Load the Check-In template before checking its scanner action.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify cards contain a real compact action instead of an unlabeled QR icon.
    expect(template).to.include("data-group-check-in-card");
    expect(template).to.include(
      'class="btn-primary-outline btn-mini inline-flex items-center whitespace-nowrap focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-500"',
    );
    expect(template).to.include("<span>Scan attendees</span>");
    expect(template).to.include('<span class="sr-only">for {{ event.name }}</span>');
    expect(template).not.to.include("icon-qr-code bg-primary-500");
  });
});
