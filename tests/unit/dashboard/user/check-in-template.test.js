import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/user/check_in_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user check-in template", () => {
  it("uses the dashboard content width", async () => {
    // Load the Check-In template before checking its page alignment.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the partial does not add a centered page-width constraint.
    expect(template).to.include(
      '<section class="relative min-w-0" data-user-check-in-root',
    );
    expect(template).not.to.include("container mx-auto");
    expect(template).not.to.include("max-w-7xl");
  });

  it("keeps medium dashboard cards stacked with shared status placement", async () => {
    // Load the Check-In template before checking responsive card presentation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify cards split only on wide screens and retain the shared card layout.
    expect(template).to.include("md:gap-8 2xl:grid-cols-2");
    expect(template).not.to.include("md:gap-8 lg:grid-cols-2");
    expect(template).to.include("cards::check_in_event_card(event)");
    expect(template).not.to.include("status_before_title");
  });
});
