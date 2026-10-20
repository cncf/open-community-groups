import { expect } from "@open-wc/testing";

/**
 * Loads a server template as text.
 * @param {string} path Template path under the templates folder.
 * @returns {Promise<string>} Template text with collapsed whitespace.
 */
const loadTemplate = async (path) => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return (await response.text()).replace(/\s+/g, " ").trim();
};

describe("event organizers section template", () => {
  it("hides the organizers section when no organizer has a full name", async () => {
    // Load the organizers section of the event page template
    const template = await loadTemplate("event/page.html");
    const sectionStart = template.indexOf("{# Organizers section -#}");
    const sectionEnd = template.indexOf("{# End organizers section -#}");
    const section = template.slice(sectionStart, sectionEnd);

    // Verify the heading and grid only show once the section contains an organizer chip
    expect(sectionStart).to.be.greaterThan(-1);
    expect(sectionEnd).to.be.greaterThan(sectionStart);
    expect(section).to.match(
      /^\{# Organizers section -#\} \{% if !event\.organizers\.is_empty\(\) -%\} <div class="hidden has-\[user-chip\]:block"> <div class="uppercase text-lg lg:text-2xl tracking-wide font-bold leading-10 pb-8 lg:pt-2 lg:pb-14"> Organizers <\/div>/,
    );
    expect(section).to.include(
      "<div class=\"grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4\"> {% for organizer in event.organizers -%} {% if organizer.name.is_some() -%} <user-chip user='{{ organizer|json }}' display-modal></user-chip> {% endif -%} {% endfor -%} </div>",
    );
  });
});
