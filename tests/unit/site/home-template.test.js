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
  it("keeps card badges beside a truncating location, so the footer stays on two lines", async () => {
    // Load the shared card footer.
    const cards = await loadTemplate("macros/cards.html");

    // Verify the location row never wraps the badges onto a line of their own.
    expect(cards).to.include('<div class="flex min-w-0 items-center gap-2">');
    expect(cards).to.not.include("phone:[&>.icon-text]:basis-36");
  });

  it("keeps the desktop Explore link on phones, with no hero search", async () => {
    // Load the home page.
    const page = await loadTemplate("site/home/page.html");

    // Verify the hero links to Explore on every device and carries no search form.
    expect(page).to.include(
      'class="btn-primary-anchor text-md lg:text-lg py-3 px-8 font-semibold">Explore groups and events</a>',
    );
    expect(page).to.not.include('role="search"');
  });

  it("renders the carousel and its position row only above three communities", async () => {
    // Load the home page.
    const page = await loadTemplate("site/home/page.html");

    // Verify the threshold and that the row directly follows its scroller.
    expect(page).to.include("{% let carousel = communities.len() > 3 -%}");
    expect(page).to.match(
      /{% endfor -%}\s*<\/div>\s*{% if carousel -%}[\s\S]*?<div class="not-phone:hidden"\s+aria-hidden="true"\s+data-snap-dots\s+data-snap-dots-max="24">/,
    );

    // Verify banners swipe in pages of three, and lists too long for one line of dots get a counter.
    expect(page).to.include("{% for communities_page in communities.chunks(3) -%}");
    expect(page).to.match(
      /data-snap-dots-max="24">\s*{% if communities\.len\(\) > 72 -%}\s*<span data-snap-counter><\/span>\s*{% endif -%}/,
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

  it("shows only the group name on phones", async () => {
    // Load both home cards.
    const cards = await Promise.all([
      loadTemplate("site/home/event_card.html"),
      loadTemplate("site/home/group_card.html"),
    ]);

    // Verify each card hides the community and its separator on phones,
    // leaving only the group name.
    for (const card of cards) {
      expect(card).to.include('class="hidden text-primary-500 sm:inline phone:hidden"');
      expect(card).to.include('class="px-1 hidden sm:inline phone:hidden"');
      expect(card).to.include('class="phone:min-w-0 phone:truncate"');
    }
  });
});
