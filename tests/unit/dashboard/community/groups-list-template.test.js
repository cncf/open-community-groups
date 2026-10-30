import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/community/groups_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

const getGroupRow = (template) =>
  template.slice(template.indexOf("{# Group row -#}"), template.indexOf("{# Location -#}"));

describe("dashboard community groups list template", () => {
  it("renders the group category before the group name", async () => {
    // Load and isolate the group row header.
    const groupRow = getGroupRow(normalizeWhitespace(await loadTemplate()));
    const categoryIndex = groupRow.indexOf("{{ group.category.name }}");
    const nameIndex = groupRow.indexOf("{# Group name -#}");

    // Verify the category context comes first and appears once in the row header.
    expect(categoryIndex).to.be.greaterThan(-1);
    expect(nameIndex).to.be.greaterThan(categoryIndex);
    expect(groupRow.split("{{ group.category.name }}")).to.have.length(2);
  });

  it("keeps the group dashboard button and the inactive badge", async () => {
    // Load and isolate the group row header.
    const groupRow = getGroupRow(normalizeWhitespace(await loadTemplate()));

    // Verify the name button keeps its contract and the inactive badge its label.
    expect(groupRow).to.include('data-select-group-id="{{ group.group_id }}"');
    expect(groupRow).to.include(
      'aria-label="Open group dashboard: {{ group.name }}">{{ group.name }}</button>',
    );
    expect(groupRow).to.include("{% if !group.active -%}");
    expect(groupRow).to.include('badge-warning inline-block">Inactive</span>');
  });

  it("keeps the location line inside the row header", async () => {
    // Load and isolate the group row header.
    const groupRow = getGroupRow(normalizeWhitespace(await loadTemplate()));

    // Verify the short location renders only when the group has one.
    expect(groupRow).to.include("{% if let Some(location) = &group.location(40) -%}");
    expect(groupRow).to.include("{{ location }}</div>");
  });
});
