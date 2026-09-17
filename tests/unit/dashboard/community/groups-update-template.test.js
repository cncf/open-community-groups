import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/community/groups_update.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard community group update template", () => {
  it("shows the group id beside the group details description", async () => {
    // Load the community group update template before checking the page title meta.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the group id is passed to the page title.
    expect(template).to.include(
      "{% let group_meta -%}(id: {{ group.group_id }}){%- endlet %}",
    );
    expect(template).to.include(
      'dashboard::page_title(title = "Group Details", docs_href = "/docs#/guides/community-dashboard?id=groups-portfolio", description = "Please update as many details about this group as possible.", meta = group_meta)',
    );
  });
});
