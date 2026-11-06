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
 * Returns the body of a macro, up to its closing tag.
 * @param {string} source - Macro file source.
 * @param {string} name - Macro name.
 * @returns {string} Macro body.
 */
const getMacro = (source, name) =>
  source.slice(source.indexOf(`{% macro ${name}(`), source.indexOf(`endmacro ${name}`));

describe("site explore templates", () => {
  it("keeps the entity switch on phones, with the values of desktop's switch", async () => {
    // Load the switch macro.
    const macros = await loadTemplate("macros/explore.html");
    const entitySwitch = getMacro(macros, "entity_switch");

    // Verify the group and its toggle state.
    expect(entitySwitch).to.include('role="group"');
    expect(entitySwitch).to.include('aria-label="Show"');
    expect(entitySwitch).to.include('aria-pressed="true"');
    expect(entitySwitch).to.include('aria-pressed="false"');

    // Verify it sends what entity_radio sends, with no id that would duplicate the drawer's.
    expect(entitySwitch).to.include("{{ entity_vals(community = community, ts_query = ts_query) }}");
    expect(entitySwitch).to.not.include(" id=");

    // Verify both sides share the full width.
    expect(entitySwitch).to.include('aria-label="Show" class="grid grid-cols-2"');

    // Verify the shell keeps it off desktop and hides the drawer's copy on phones.
    const shell = await loadTemplate("site/explore/entity_section_base.html");
    const row = shell.slice(shell.indexOf("{# Phone title and entity switch -#}"));
    expect(row).to.match(/<div class="flex flex-col [^"]*not-phone:hidden[^"]*">\s*<h1[^>]*>Explore<\/h1>/);
    expect(shell).to.include('styles = Some("phone:hidden")');
  });

  it("renders chips and the active filter state only on phones", async () => {
    // Load the macros.
    const macros = await loadTemplate("macros/explore.html");
    const row = getMacro(macros, "applied_filters");
    const count = getMacro(macros, "active_filters_count");
    const dot = getMacro(macros, "active_filters_dot");
    const chip = getMacro(macros, "applied_filter_chip");

    // Verify the row is skipped when empty and never reaches desktop.
    expect(row).to.include("{% if !chips.is_empty() -%}");
    expect(row).to.include('aria-label="Applied filters"');
    expect(row).to.include("not-phone:hidden");

    // Verify Reset is served by the delegated reset, and the toggle waits for page controls.
    expect(row).to.match(/class="reset-filters [^"]*">\s*Reset/);
    expect(row).to.include('id="applied-filters"');
    expect(row).to.match(
      /data-applied-filters-toggle\s+aria-controls="applied-filters"\s+aria-expanded="false"\s+hidden/,
    );

    // Verify the chip names the filter and carries what its removal needs.
    expect(chip).to.include('aria-label="Remove filter {{ label }}"');
    expect(chip).to.include('data-applied-filter="{{ name }}"');
    expect(chip).to.include('data-applied-filter-value="{{ value }}"');

    // Verify Type and Group labels keep their desktop casing.
    expect(chip).to.include('{% if *name != "kind" && *name != "group" %}');

    // Verify both state nodes stay off desktop.
    expect(count).to.include("not-phone:hidden");
    expect(dot).to.include("not-phone:hidden");
  });

  it("keeps the phone status region outside the swapped section", async () => {
    // Load the page shell.
    const page = await loadTemplate("site/explore/page.html");

    // Verify a section swap cannot replace the live region.
    const sectionEnd = page.indexOf("{# End entity section -#}");
    expect(page.indexOf('id="explore-filter-status"')).to.be.greaterThan(sectionEnd);
    expect(page).to.include('role="status"');
  });

  it("offers Reset filters from the empty state on Events and Groups", async () => {
    // Load the alert and both result lists.
    const [feedback, events, groups] = await Promise.all([
      loadTemplate("macros/feedback.html"),
      loadTemplate("site/explore/events/results.html"),
      loadTemplate("site/explore/groups/results.html"),
    ]);
    const alert = getMacro(feedback, "alert");

    // Verify the button is optional, phone-only and served by the delegated reset.
    expect(alert).to.include("{% if with_reset -%}");
    expect(alert).to.match(/class="reset-filters [^"]*not-phone:hidden"/);

    // Verify only the filtered list state of Events passes it.
    expect(events.match(/with_reset = true/g)).to.have.length(1);
    const filtered = events.slice(events.indexOf("{# List view -#}"));
    expect(filtered.slice(filtered.indexOf("no-results-filtered"))).to.include("with_reset = true");

    // Verify the Groups list passes it directly, and its map does not.
    expect(groups.match(/with_reset = true/g)).to.have.length(1);
    expect(groups.slice(groups.indexOf("{# List view -#}"))).to.include("with_reset = true");
  });

  it("leaves phones with a rounded Prev and Next pair", async () => {
    // Load the pager and split it by button.
    const pagination = await loadTemplate("macros/pagination.html");
    const section = (name, next) =>
      pagination.slice(pagination.indexOf(`{# ${name} button -#}`), pagination.indexOf(`{# ${next} -#}`));

    // Verify both ends drop in their link and disabled branches.
    expect(section("First", "End first button").match(/phone:hidden/g)).to.have.length(2);
    expect(section("Last", "End last button").match(/phone:hidden/g)).to.have.length(2);

    // Verify the pair rounds its outer ends in both branches.
    expect(section("Prev", "End prev button").match(/phone:rounded-s-full phone:border-s/g)).to.have.length(
      2,
    );
    expect(section("Next", "End next button").match(/phone:rounded-e-full phone:border-e/g)).to.have.length(
      2,
    );

    // Verify the white ground sits on the group, not on links that turn azure on focus.
    expect(pagination).to.include('class="inline-flex phone:rounded-full phone:bg-white" role="group"');
    expect(section("Next", "End next button")).to.not.include("phone:bg-white");
  });

  it("keeps the community on its own line of phone cards", async () => {
    // Load both cards.
    const [eventCard, groupCard] = await Promise.all([
      loadTemplate("site/explore/events/event_card.html"),
      loadTemplate("site/explore/groups/group_card.html"),
    ]);

    // Verify the community shows, and the separators and category do not.
    const community = 'phone:block phone:truncate"';
    expect(eventCard).to.include(community);
    expect(groupCard).to.include(community);
    expect(eventCard.match(/class="px-1 hidden sm:inline phone:hidden"/g)).to.have.length(2);
    expect(groupCard.match(/class="px-1 hidden sm:inline phone:hidden"/g)).to.have.length(1);
    expect(eventCard).to.include('class="hidden sm:inline phone:hidden">{{ event.group_category_name }}');
  });
});
