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

/**
 * Returns the class attribute of a button in the membership template.
 * @param {string} template - Membership template source.
 * @param {string} id - Button id.
 * @returns {string} Class attribute value.
 */
const getButtonClasses = (template, id) => {
  const button = template.slice(template.indexOf(`id="${id}"`));

  return button.match(/class="([^"]*)"/)[1];
};

describe("group page template", () => {
  it("fills Join and sign-in on phones and leaves the others outlined", async () => {
    // Load the membership buttons.
    const template = await loadTemplate("group/membership_button.html");

    // Verify every button takes the phone size and none sets a display JS could override.
    for (const id of ["loading-btn", "signin-btn", "join-btn", "leave-btn"]) {
      const classes = getButtonClasses(template, id);
      expect(classes).to.include("phone:h-11 phone:w-full phone:px-5 phone:text-sm");
      expect(classes).to.not.include("phone:flex");
    }

    // Verify only the main actions are filled.
    expect(getButtonClasses(template, "signin-btn")).to.include("phone:enabled:btn-fill");
    expect(getButtonClasses(template, "join-btn")).to.include("phone:enabled:btn-fill");
    expect(getButtonClasses(template, "leave-btn")).to.not.include("btn-fill");
    expect(getButtonClasses(template, "loading-btn")).to.not.include("btn-fill");
  });

  it("swaps the actions menu for a phone-only Share pill", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify the menu leaves phones and the pill never reaches desktop.
    expect(page).to.include('class="order-last static shrink-0 sm:relative phone:hidden"');
    expect(page).to.include('<share-modal class="not-phone:hidden" trigger-variant="pill"');
  });

  it("adds a phone See all pill beside each events title", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify each pill keeps the desktop block's list and its own name.
    for (const [link, name] of [
      ["upcoming_events_link", "See all upcoming events"],
      ["past_events_link", "See all past events"],
    ]) {
      expect(page).to.match(
        new RegExp(
          `<a href="{{ self\\.${link}\\(\\) }}"\\s+hx-boost="true"\\s+hx-target="body"\\s+` +
            `aria-label="${name}"\\s+class="btn-secondary-anchor pill-link not-phone:hidden">See all</a>`,
        ),
      );
    }

    // Verify phones drop the bottom links and cap both lists at three cards.
    expect(page.match(/md:hidden md:mt-0 phone:hidden/g)).to.have.length(2);
    expect(page.match(/phone:\[&>:nth-child\(n\+4\)\]:hidden/g)).to.have.length(2);
  });

  it("hides the Location card on phones only without a map", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify the card depends on both coordinates and stays on desktop.
    expect(page).to.include("{% let has_map = group.latitude.is_some() && group.longitude.is_some() -%}");
    expect(page).to.match(
      /<div class="border border-stone-200 rounded-lg flex flex-col bg-white\s+{% if !has_map %}phone:hidden{% endif %}">\s+{# Location details/,
    );
  });

  it("keeps multi-day dates on one line until they stack", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify the row takes Event's narrow gap, which a 390px phone needs.
    expect(page).to.include(
      'class="flex items-start gap-8 phone:gap-4 phone:max-[375px]:flex-col phone:max-[375px]:gap-2"',
    );
  });

  it("gives the multi-day labels the eyebrow's contrast", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify both labels leave the panel's stone-400, which fails on white.
    for (const label of ["From", "To"]) {
      expect(page).to.include(
        `<div class="text-xs uppercase font-medium mb-0.5 phone:text-stone-500">${label}</div>`,
      );
    }
  });

  it("closes the page with the tags, after every other section", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify Tags follows the gallery and nothing else comes after it.
    const tagsIndex = page.indexOf("{# Tags -#}");
    expect(tagsIndex).to.be.greaterThan(page.indexOf("{# End photo gallery -#}"));
    expect(page.slice(page.indexOf("{# End tags -#}"))).not.to.include("section-strip");
  });

  it("turns every section title into a phone heading", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify the plain titles, including Gallery, carry the strip.
    for (const title of [
      "About this group",
      "Parent group",
      "Subgroups",
      "Tags",
      "Organizers",
      "Sponsors",
      "Gallery",
    ]) {
      expect(page).to.match(new RegExp(`section-strip phone:-mx-3">\\s+${title}\\s+</div>`));
    }

    // Verify the two rows with a nested title use the nested modifier.
    for (const title of ["Upcoming Events", "Past Events"]) {
      expect(page).to.match(
        new RegExp(`section-strip phone:-mx-3">\\s+<div class="[^"]* section-strip-title">${title}</div>`),
      );
    }
  });

  it("wraps the description in read more with the text's own line height", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify the body carries the line height that sizes its three-line clip.
    expect(page).to.match(
      /<div class="read-more">\s+<div class="[^"]*read-more-body phone:text-\[15px\]\/6[^"]*"\s+data-ocg-remove-broken-images>{{ description\|md_to_html\|safe }}<\/div>\s+{{ ui::read_more_toggle\(\) -}}/,
    );
  });

  it("lays the phone social links out as a horizontal scroll strip", async () => {
    // Load the group page.
    const page = await loadTemplate("group/page.html");

    // Verify the links sit in one swipeable row with a hidden scrollbar and an edge fade.
    expect(page).to.include(
      'class="flex flex-wrap gap-2 phone:flex-nowrap phone:overflow-x-auto phone:pb-1 phone:[scrollbar-width:none] phone:[&>*]:shrink-0 phone:[mask-image:linear-gradient(to_right,#000_85%,transparent)] phone:[-webkit-mask-image:linear-gradient(to_right,#000_85%,transparent)]"',
    );
  });

  it("gives every social link a 44px phone target", async () => {
    // Load the shared link macro and the group's extra links.
    const macro = await loadTemplate("macros/social.html");
    const networks = await loadTemplate("group/social_networks.html");

    // Verify both macro branches and the extra links match.
    expect(macro).to.include("size-[40px] p-2 phone:size-11");
    expect(macro).to.include("size-[40px] sm:size-[30px] p-1.5 phone:size-11");
    expect(macro).to.include("size-4 phone:size-5");
    expect(networks).to.include("flex items-center justify-center phone:size-11");
    expect(networks).to.include("icon-link phone:size-5");
  });
});
