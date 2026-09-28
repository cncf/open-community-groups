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
    expect(line).to.include('<span class="truncate" data-cohosts-full>Co-hosted with {{ names }}</span>');
    expect(line).to.include("icon-cohosts");
    expect(line).not.to.include("<a ");
  });

  it("prepares a reduced count and panel for credits with several co-hosts", async () => {
    // Load the shared co-hosts macros.
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/macros/cohosts.html"));
    const line = template.slice(
      template.indexOf("{% macro cohosts_line"),
      template.indexOf("{% endmacro cohosts_line"),
    );

    // Verify only multi co-host lines opt into fitting and carry the hidden count.
    expect(line).to.include("{% if cohosts.len() > 1 -%}data-cohosts-line{% endif -%}");
    expect(line).to.include(
      '<span class="hidden truncate" data-cohosts-summary aria-hidden="true"> Co-hosted with {{ cohosts.len() }} groups </span>',
    );

    // Verify the panel template lists every co-host with its square logo.
    expect(line).to.include("<template data-cohosts-panel-template>");
    expect(line).to.include("data-cohosts-panel");
    expect(line).to.include('text-stone-900"> Co-hosted with </div>');
    expect(line).to.include("{% for cohost in cohosts.iter() -%}");
    expect(line).to.include(
      '{{ ui::logo(logo_url = cohost.logo_url, classes = "size-9 shrink-0", size = 36) -}}',
    );
    expect(line).to.include(
      '<div class="truncate text-[0.65rem]/3 font-semibold uppercase tracking-wider text-stone-400"> {{ cohost.community_display_name }} </div>',
    );
    expect(line).to.include(
      '<div class="mt-0.5 truncate text-sm/5 font-semibold text-black">{{ cohost.name }}</div>',
    );
  });

  it("links co-host groups from the event page box under their own community", async () => {
    // Load the shared co-hosts macros.
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/macros/cohosts.html"));
    const box = template.slice(
      template.indexOf("{% macro cohosts_box"),
      template.indexOf("{% endmacro cohosts_box"),
    );

    // Verify each card links to the co-host group page with boosted navigation.
    expect(box).to.include(">Co-hosted with</div>");
    expect(box).to.include('href="/{{ cohost.community_name }}/group/{{ cohost.public_slug() }}"');
    expect(box).to.include('hx-boost="true"');
    expect(box).to.include('aria-label="Co-hosts"');
  });

  it("lays out co-hosts as a titled grid of equal square-logo cells", async () => {
    // Load the shared co-hosts macros.
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/macros/cohosts.html"));
    const box = template.slice(
      template.indexOf("{% macro cohosts_box"),
      template.indexOf("{% endmacro cohosts_box"),
    );

    // Verify the title matches the event date and location panels.
    expect(box).to.include(
      '<div class="mb-4 flex min-h-[25px] items-center justify-between"> <div class="text-base/3 font-semibold uppercase text-stone-400">Co-hosted with</div>',
    );

    // Verify co-hosts share one dashed box with responsive equal-width columns.
    expect(box).to.include('<div class="rounded-lg border border-dashed border-stone-200 bg-white p-4">');
    expect(box).to.include("grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4");

    // Verify each group shows its square logo with the community over the truncated name.
    expect(box).to.include(
      '{{ ui::logo(logo_url = cohost.logo_url, classes = "size-10 shrink-0", size = 40) -}}',
    );
    expect(box).to.include(
      '<span class="block truncate text-[0.65rem]/3 font-semibold uppercase tracking-wider text-stone-400"> {{ cohost.community_display_name }} </span>',
    );
    expect(box).to.include(
      '<span class="mt-0.5 block truncate text-sm/5 font-semibold text-black group-hover:text-primary-500"> {{ cohost.name|demoji }} </span>',
    );
  });

  it("renders the co-hosts box under the event date and location", async () => {
    // Load the public event page template.
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/event/page.html"));

    // Verify the box renders only with co-hosts as a full-width row after the location panel.
    const boxIndex = template.indexOf(
      '{% if !event.cohosts.is_empty() -%} <div class="md:col-span-2">{{ cohosts::cohosts_box(event.cohosts) -}}</div>',
    );
    expect(boxIndex).to.be.greaterThan(template.indexOf("{# End location -#}"));
    expect(boxIndex).to.be.lessThan(template.indexOf("{# Host -#}"));
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
    expect(normalizeWhitespace(exploreCard)).to.include(
      '<div class="mt-auto min-w-0">{{ cohosts::cohosts_line(event.cohosts) -}}</div>',
    );
    expect(normalizeWhitespace(exploreCard)).to.include(
      "{% if event.cohosts.is_empty() -%}line-clamp-2{% else -%}line-clamp-1{% endif -%}",
    );
    expect(normalizeWhitespace(groupCard)).to.include(
      "{% if cohosted_by_page_group -%} <span>Hosted by {{ event.group_name -}}</span>",
    );

    // Verify co-hosted card titles stay on one line.
    const oneLineTitle =
      "{% block title_line_clamp_classes -%} {% if event.cohosts.is_empty() -%} !line-clamp-2 {% else -%} !line-clamp-1 {% endif -%} {% endblock title_line_clamp_classes %}";
    expect(normalizeWhitespace(smallCard)).to.include(oneLineTitle);
    expect(normalizeWhitespace(exploreCard)).to.include(oneLineTitle);

    // Verify card text uses the full width instead of reserving ribbon space.
    expect(smallCard).not.to.include("top_row_classes");
    expect(exploreCard).not.to.include("top_row_classes");

    // Verify calendar popovers inherit the one-line rule with a smaller title.
    const calendarCard = normalizeWhitespace(
      await loadTemplate("/ocg-server/templates/site/explore/events/calendar_event_card.html"),
    );
    expect(calendarCard).not.to.include("title_line_clamp_classes");
    expect(calendarCard).to.include(
      "{% block title_classes -%} !text-[0.9rem]/[1.25rem] {% endblock title_classes %}",
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
