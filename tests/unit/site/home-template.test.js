import { expect } from "@open-wc/testing";

/**
 * Loads a server template source as text.
 * @param {string} path - Template path relative to the templates folder.
 * @returns {Promise<string>} Template source.
 */
const loadTemplate = async (path) => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("site home template", () => {
  it("keeps the phone search form off desktop and free of community filters", async () => {
    // Load the home page and isolate the search form.
    const page = await loadTemplate("site/home/page.html");
    const form = page.slice(page.indexOf("<form"), page.indexOf("</form>"));

    // Verify the form is phone-only and drops empty values, which Explore rejects.
    expect(form).to.include('class="relative not-phone:hidden"');
    expect(form).to.include('action="/explore"');
    expect(form).to.include('hx-ext="no-empty-vals"');
    expect(form).to.include('name="ts_query"');
    expect(form).to.include('aria-label="Search events"');

    // Verify the form sends the entity but never a community.
    expect(form).to.include('name="entity" value="events"');
    expect(form).to.not.include("community");
  });

  it("lets card badges wrap below a location that would be cut short", async () => {
    // Load the shared card footer.
    const cards = await loadTemplate("macros/cards.html");

    // Verify the location holds a minimum width, so the badges wrap first.
    expect(cards).to.include(
      '<div class="flex min-w-0 items-center gap-2 phone:flex-wrap phone:gap-y-1 phone:[&>.icon-text]:basis-32">',
    );
  });

  it("swaps the Explore link for the pill on phones only", async () => {
    // Load the home page.
    const page = await loadTemplate("site/home/page.html");

    // Verify the desktop link stays and only phones drop it.
    expect(page).to.match(/class="btn-primary-anchor [^"]* phone:hidden">Explore groups and events/);
  });

  it("renders the carousel and its position row only above three communities", async () => {
    // Load the home page.
    const page = await loadTemplate("site/home/page.html");

    // Verify the threshold and that the row directly follows its scroller.
    expect(page).to.include("{% let carousel = communities.len() > 3 -%}");
    expect(page).to.match(
      /{% endfor -%}\s*<\/div>\s*{% if carousel -%}[\s\S]*?<div class="not-phone:hidden"\s+aria-hidden="true"\s+data-snap-dots\s+data-snap-dots-max="24">/,
    );

    // Verify lists too long for one line of dots get a counter instead.
    expect(page).to.match(
      /data-snap-dots-max="24">\s*{% if communities\.len\(\) > 24 -%}\s*<span data-snap-counter><\/span>\s*{% endif -%}/,
    );

    // Verify the page loads the module that fills the row.
    expect(page).to.include('<script type="module" src="/static/js/common/snap-dots.js"></script>');
  });

  it("gives each listing a phone See all with a descriptive name", async () => {
    // Load the home page and the shared events list macro.
    const page = await loadTemplate("site/home/page.html");
    const macros = await loadTemplate("macros/ui.html");

    // Verify the pill is phone-only in both headings.
    const pill = 'class="btn-secondary-anchor pill-link not-phone:hidden">See all</a>';
    expect(page).to.include(pill);
    expect(macros).to.include(pill);
    expect(macros).to.include('aria-label="See all {{ title }}"');
    expect(page).to.include('aria-label="See all latest groups added"');
  });

  it("shows the community on its own line on phones", async () => {
    // Load both home cards.
    const cards = await Promise.all([
      loadTemplate("site/home/event_card.html"),
      loadTemplate("site/home/group_card.html"),
    ]);

    // Verify each card shows the name and hides only the dot.
    for (const card of cards) {
      expect(card).to.include(
        'class="hidden text-primary-500 sm:inline phone:block phone:truncate"',
      );
      expect(card).to.include('class="px-1 hidden sm:inline phone:hidden"');
    }
  });
});
