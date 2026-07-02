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
    expect(template).to.include(
      "macro table_sort_control(label, ascending_value, descending_value, is_ascending, is_descending, disabled = false)",
    );
    expect(template).to.include("macro table_filter_option_button");
    expect(template).to.include("is_clear_option = false");
    expect(template).to.include("is_clear_option && clear_value.is_empty()");
    expect(template).to.include("icon-caret-up");
    expect(template).to.include("icon-caret-down");
    expect(template).to.include("bg-stone-300");
    expect(template).to.include(
      'class="inline-flex h-7 w-7 flex-col overflow-hidden rounded-md border border-stone-200 bg-white"',
    );
    expect(template).to.include('class="h-px w-full bg-stone-200"');
    expect(template).to.include("h-1/2 w-full");
    expect(template).to.include("disabled:cursor-not-allowed disabled:opacity-50");
    expect(template).to.include('disabled aria-disabled="true"');
    expect(template).to.include('aria-label="Sort {{ label }} ascending"');
    expect(template).to.include('aria-label="Sort {{ label }} descending"');
    expect(template).to.include("aria-pressed=");

    // Verify table filters use the filled caret treatment.
    expect(template).to.include(
      'macro table_filter_menu(id, label, is_active, extra_classes = "", dropdown_classes = "start-0")',
    );
    expect(template).to.include("{{ dropdown_classes }} top-full");
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
