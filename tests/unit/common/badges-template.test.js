import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/badges.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("badge macros template", () => {
  it("uses the compact uppercase badge foundation for dashboard badge variants", async () => {
    // Load the badge macros template and isolate the invitation badge variants.
    const template = normalizeWhitespace(await loadTemplate());
    const invitationBadge = template.slice(
      template.indexOf("{% macro invitation_badge"),
      template.indexOf("{% endmacro invitation_badge"),
    );

    // Verify shared badge styles and invitation state borders stay consistent.
    expect(template).to.include(
      'class="custom-badge inline-block max-w-full truncate px-2.5 py-0.5 text-stone-900',
    );
    expect(invitationBadge.match(/<span class="custom-badge bg-/g)).to.have.lengthOf(3);
    expect(invitationBadge).to.include(
      "{% if with_border %}border-green-800{% else %}border-transparent{% endif %}",
    );
    expect(invitationBadge).to.include(
      "{% if with_border %}border-red-800{% else %}border-transparent{% endif %}",
    );
    expect(invitationBadge).to.include(
      "{% if with_border %}border-yellow-800{% else %}border-transparent{% endif %}",
    );
  });
});
