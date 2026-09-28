import { expect } from "@open-wc/testing";

/**
 * Fetches a template source file and returns its text.
 * @param {string} path - Template path served by the test runner.
 * @returns {Promise<string>} Template source.
 */
const loadTemplate = async (path) => {
  const response = await fetch(path);

  expect(response.ok).to.equal(true);

  return response.text();
};

/**
 * Collapses whitespace runs so template assertions ignore formatting.
 * @param {string} value - Template source.
 * @returns {string} Normalized source.
 */
const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("co-hosts templates", () => {
  it("credits co-hosts on cards with plain text instead of nested links", async () => {
    // Load the shared co-hosts macros.
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/macros/cohosts.html"));
    const line = template.slice(
      template.indexOf("{% macro cohosts_line"),
      template.indexOf("{% endmacro cohosts_line"),
    );

    // Verify the credit line keeps the full list in its title and renders no links.
    expect(line).to.include('title="Co-hosted with {{ names }}"');
    expect(line).to.include('<span class="truncate">Co-hosted with {{ names }}</span>');
    expect(line).to.include("icon-cohosts");
    expect(line).not.to.include("<a ");
  });

  it("links co-host groups from the event page box under their own community", async () => {
    // Load the shared co-hosts macros.
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/macros/cohosts.html"));
    const box = template.slice(
      template.indexOf("{% macro cohosts_box"),
      template.indexOf("{% endmacro cohosts_box"),
    );

    // Verify each card links to the co-host group page with boosted navigation.
    expect(box).to.include(">Co-hosts</div>");
    expect(box).to.include('href="/{{ cohost.community_name }}/group/{{ cohost.public_slug() }}"');
    expect(box).to.include('hx-boost="true"');
    expect(box).to.include('aria-label="Co-hosts"');
  });

  it("renders the co-hosts box above the event date and location", async () => {
    // Load the public event page template.
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/event/page.html"));

    // Verify the box renders only with co-hosts and before the date panel.
    const boxIndex = template.indexOf("{{ cohosts::cohosts_box(event.cohosts) -}}");
    expect(boxIndex).to.be.greaterThan(-1);
    expect(template).to.include("{% if !event.cohosts.is_empty() -%}");
    expect(boxIndex).to.be.lessThan(template.indexOf(">Event date</div>"));
  });

  it("credits co-hosts on shared, explore, and group page event cards", async () => {
    // Load every card entrypoint that shows co-host credit.
    const [smallCard, exploreCard, groupCard, groupPage] = await Promise.all([
      loadTemplate("/ocg-server/templates/common/event_card_small.html"),
      loadTemplate("/ocg-server/templates/site/explore/events/event_card.html"),
      loadTemplate("/ocg-server/templates/group/event_card.html"),
      loadTemplate("/ocg-server/templates/group/page.html"),
    ]);

    // Verify the credit line and the owner preheader on co-hosted group cards.
    expect(normalizeWhitespace(smallCard)).to.include("{{ cohosts::cohosts_line(event.cohosts) -}}");
    expect(normalizeWhitespace(exploreCard)).to.include("{{ cohosts::cohosts_line(event.cohosts) -}}");
    expect(normalizeWhitespace(groupCard)).to.include(
      "{% if cohosted_by_page_group -%} <span>Hosted by {{ event.group_name -}}</span>",
    );

    // Verify the next-event link uses the event's own community.
    expect(normalizeWhitespace(groupPage)).to.include(
      'href="/{{ next_event_card.event.community_name }}/group/{{ next_event_card.event.public_group_slug() }}/event/{{ next_event_card.event.slug }}"',
    );
  });

  it("colors dashboard co-hosting statuses with the shared status badge", async () => {
    // Load the group dashboard co-hosts list.
    const template = normalizeWhitespace(
      await loadTemplate("/ocg-server/templates/dashboard/group/cohosts_list.html"),
    );

    // Verify approved maps to green, pending to amber, and closed statuses to red.
    expect(template).to.include(
      "{% let is_approved = event.status == crate::types::event::EventCohostStatus::Approved -%}",
    );
    expect(template).to.include(
      "{% let is_pending = event.status == crate::types::event::EventCohostStatus::Pending -%}",
    );
    expect(template).to.include(
      "{{ badges::status_badge(label = event.status_label(), canceled = !is_approved && !is_pending, published = is_approved) -}}",
    );
    expect(template).not.to.include("bg-primary-50");
  });

  it("renders co-hosted event and owner group logos with the shared square logo", async () => {
    // Load the group dashboard co-hosts list.
    const template = normalizeWhitespace(
      await loadTemplate("/ocg-server/templates/dashboard/group/cohosts_list.html"),
    );

    // Verify both logos use the public page logo macro instead of round avatars.
    expect(template).to.include(
      '{{ ui::logo(logo_url = event.event_logo_url, classes = "size-10 shrink-0", size = 40) -}}',
    );
    expect(template).to.include(
      '{{ ui::logo(logo_url = event.owner_group_logo_url, classes = "size-9 shrink-0", size = 36) -}}',
    );
    expect(template).not.to.include("<logo-image");
  });

  it("caps the co-hosted event cell width so long names truncate", async () => {
    // Load the group dashboard co-hosts list.
    const template = normalizeWhitespace(
      await loadTemplate("/ocg-server/templates/dashboard/group/cohosts_list.html"),
    );

    // Verify the event cell is bounded like the events list name cell.
    expect(template).to.include(
      '<th scope="row" class="px-3 py-4 font-medium text-stone-900 min-w-[100px] max-w-[250px] xl:px-5">',
    );
    expect(template).to.include(
      '<div class="truncate" title="{{ event.event_name }}">{{ event.event_name }}</div>',
    );
  });
});
