import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/dashboard.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard macros template", () => {
  it("passes the curated dashboard user payload to profile modal triggers", async () => {
    // Load the dashboard macros template before checking profile trigger data.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the shared macro uses the backend-curated dashboard user object.
    expect(template).to.include("data-user-profile-modal");
    expect(template).to.include("data-user-profile='{{ user|json }}'");
    expect(template).not.to.include("data-user-profile-username");
  });

  it("uses paired chevrons for table sorting and a filled filter caret", async () => {
    // Load the dashboard macros template before checking table control icons.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify sort state is carried by the paired chevrons, not a selected pill.
    expect(template).to.include("macro table_sort_button");
    expect(template).to.include("icon-caret-up");
    expect(template).to.include("icon-caret-down");
    expect(template).to.include("bg-stone-300");
    expect(template).to.include(
      'class="inline-flex size-7 items-center justify-center rounded-md transition-colors hover:bg-white hover:text-stone-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-500"',
    );

    // Verify table filters use the filled caret treatment.
    expect(template).to.include("icon-caret-down-filled");
    expect(template).to.include("icon-caret-down-filled bg-current");
    expect(template).not.to.include("bg-primary-500 {% else -%} bg-current");
    expect(template).not.to.include(
      "bg-primary-50 text-primary-700 ring-1 ring-primary-200",
    );
    expect(template).not.to.include(
      "bg-primary-50 text-stone-900 ring-1 ring-primary-200",
    );
  });
});
