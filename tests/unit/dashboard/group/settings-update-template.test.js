import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/settings_update.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group settings update template", () => {
  it("shows the group id beside the group details description", async () => {
    // Load the group settings template before checking the page title id.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the group id is passed to the page title.
    expect(template).to.include(
      'dashboard::page_title(title = "Group Details", docs_href = "/docs#/guides/group-dashboard?id=settings-group-identity", description = "Information about the group.", id = group.group_id.to_string())',
    );
  });
});
