import { expect } from "@open-wc/testing";

const loadTemplate = async (path) => {
  const response = await fetch(path);

  expect(response.ok).to.equal(true);

  return response.text();
};

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
    expect(line).to.include("icon-groups");
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
});
