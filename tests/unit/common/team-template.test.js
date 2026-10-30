import { expect } from "@open-wc/testing";

const TEAM_LIST_TEMPLATES = ["dashboard/community/team_list.html", "dashboard/group/team_list.html"];

const loadTemplate = async (path) => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

const getRoleCell = (template) =>
  template.slice(template.indexOf("{# Role -#}"), template.indexOf("{# End role -#}"));

describe("team templates", () => {
  it("renders the member identity cell from plain values", async () => {
    // Load the team macros template.
    const template = normalizeWhitespace(await loadTemplate("macros/team.html"));

    // Verify the macro takes plain values and escapes them itself.
    expect(template).to.include(
      "{% macro member_identity_cell(photo_url, name, username, placeholder, accepted) -%}",
    );
    expect(template).to.include('{% if let Some(url) = photo_url %}image-url="{{ url }}"{% endif %}');
    expect(template).to.include("{{ name.as_deref()|assigned_or(username) }}");
    expect(template).to.include("{% if name.is_some() -%}");
    expect(template).not.to.include("|safe");
  });

  it("keeps the pending badge in the identity cell", async () => {
    // Load the team macros template.
    const template = normalizeWhitespace(await loadTemplate("macros/team.html"));

    // Verify pending members still get the invitation badge next to the name.
    expect(template).to.include(
      '{% if !accepted -%} {{ badges::invitation_badge(label = "Invitation sent", extra_styles = Some(',
    );
  });

  for (const path of TEAM_LIST_TEMPLATES) {
    it(`passes member values to the identity cell in ${path}`, async () => {
      // Load the team list template.
      const template = normalizeWhitespace(await loadTemplate(path));

      // Verify the caller passes plain member fields instead of captured markup.
      expect(template).to.include("{{ team::member_identity_cell(photo_url = member.photo_url,");
      expect(template).to.include("name = member.name,");
      expect(template).to.include("username = member.username,");
      expect(template).to.include(
        "placeholder = self::user_initials(member.name.as_deref(), member.username.as_str()),",
      );
      expect(template).to.include("accepted = member.accepted) -}}");
      expect(template).not.to.include("member_image_attr");
      expect(template).not.to.include("member_display_name");
      expect(template).not.to.include("|safe");
    });

    it(`renders the pending badge in the role cell in ${path}`, async () => {
      // Load and isolate the role cell.
      const roleCell = getRoleCell(normalizeWhitespace(await loadTemplate(path)));

      // Verify pending members also get the invitation badge under the role.
      expect(roleCell).to.include(
        '{% if !member.accepted -%} {{ badges::invitation_badge(label = "Invitation sent"',
      );
      expect(roleCell).to.include("data-team-role-select");
    });
  }
});
