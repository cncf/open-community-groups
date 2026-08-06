import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/waitlist_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group waitlist list template", () => {
  it("renders waitlist identity cells as profile modal triggers", async () => {
    // Load the waitlist list template before checking profile trigger markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the waitlist identity area uses the shared profile trigger macro.
    expect(template).to.include(
      "dashboard::user_profile_modal_trigger(entry.user, self::user_initials(entry.user.name.as_deref() , entry.user.username.as_str()))",
    );
    expect(template).to.include("entry.user.name.as_deref() |assigned_or(entry.user.username)");
    expect(template).to.include('entry.user.company.as_deref() |assigned_or("-")');
    expect(template).to.include("{% if let Some(title) = &entry.user.title -%}");
  });

  it("uses the shared search convention for table filtering", async () => {
    // Load the waitlist list template before checking search markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify waitlist search follows the existing dashboard HTMX pattern.
    expect(template).to.include('id="waitlist-search-form"');
    expect(template).to.include('hx-get="/dashboard/group/events/{{ event.event_id }}/waitlist"');
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include('hx-target="#waitlist-content"');
    expect(template).to.include('<label for="search_waitlist" class="sr-only">Search waitlist</label>');
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('value="{{ ts_query|assigned_or("") }}"');
    expect(template).to.include('placeholder="Search waitlist"');
    expect(template).to.include('aria-label="Clear waitlist search"');
    expect(template).to.include(
      'pagination::range_display(offset = refresh_offset , count = waitlist.len() , total = total, label = "waitlist entry", plural_label = "waitlist entries")',
    );
    expect(template).to.include("dashboard/placeholders/group_waitlist_no_results.html");
    expect(template).to.include('<th scope="col" class="px-3 xl:px-5 py-1.5 w-44">Queue</th>');
    expect(template).to.include("{% if let Some(waitlist_position) = entry.waitlist_position -%}");
    expect(template).to.include("#{{ waitlist_position }}");
    expect(template).not.to.include("queue_label");
    expect(template).not.to.include("{{ refresh_offset + loop.index }}");
    expect(template.indexOf(">Queue</th>")).to.be.lessThan(template.indexOf(">Enrollment</th>"));
    expect(template.indexOf("#{{ waitlist_position }}")).to.be.lessThan(
      template.indexOf("{{ entry.ticket_title }}"),
    );
  });

  it("renders waitlist sort select and title filter controls", async () => {
    // Load the waitlist list template before checking table filter markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify sort and filter controls preserve current waitlist parameters.
    expect(template).to.include('name="sort" value="{{ sort }}"');
    expect(template).to.include('name="title" value="{{ title }}"');
    expect(template).to.include('name="ts_query" value="{{ ts_query }}"');
    expect(template).to.include('<label for="waitlist-sort"');
    expect(template).to.include('id="waitlist-sort"');
    expect(template).to.include('name="sort"');
    expect(template).to.include('hx-trigger="change"');
    expect(template).to.include("sm:w-[36rem]");
    expect(template).to.include("self-end sm:ms-auto");
    expect(template).to.include("Entry ↑");
    expect(template).to.include("Entry ↓");
    expect(template).to.include("Created ↑");
    expect(template).to.include("Created ↓");
    expect(template).to.include('<option value="name-asc"');
    expect(template).to.include('<option value="name-desc"');
    expect(template).to.include('<option value="created-at-asc"');
    expect(template).to.include('<option value="created-at-desc"');
    expect(template).to.not.include("dashboard::table_sort_menu");
    expect(template).to.not.include("dashboard::table_sort_option_button");
    expect(template).to.not.include("dashboard::table_sort_control");
    expect(template).to.include('class="px-3 xl:px-5 py-1.5"');
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5"');
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-1.5"');
    expect(template).to.include('class="hidden min-[1920px]:table-cell px-3 xl:px-5 py-1.5 w-40"');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-[72px]"');
    expect(template).to.include('<span class="whitespace-nowrap">Entry</span>');
    expect(template).to.include('<span class="whitespace-nowrap">Created</span>');
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "waitlist-position-filter", label = "Position", is_active = title.is_some())',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "All", name = "title", value = "", is_active = title.is_none() , is_clear_option = true)',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Present", name = "title", value = "present"',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Missing", name = "title", value = "missing"',
    );
    expect(template).to.include("Reset all");
    expect(template).to.not.include("Title present");
    expect(template).to.not.include("Title missing");
    expect(template).to.not.include("waitlist-entry-filter");
    expect(template).to.include('dashboard::active_table_filter_badge("Position", "Present")');
    expect(template).to.include('dashboard::active_table_filter_badge("Position", "Missing")');
    expect(template).to.not.include('dashboard::active_table_filter_badge("Sort"');
  });

  it("keeps waitlist responsive columns aligned with empty placeholders", async () => {
    // Load the waitlist list template before checking responsive table markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the table columns and placeholders keep matching responsive spans.
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-4 max-w-0"');
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-4"');
    expect(template).to.include(
      'class="hidden min-[1920px]:table-cell px-3 xl:px-5 py-4 whitespace-nowrap w-40"',
    );
    expect(template).to.include('<td class="xl:hidden px-8 py-12 text-center" colspan="3">');
    expect(template).to.include(
      '<td class="hidden xl:table-cell 2xl:hidden px-8 py-12 text-center" colspan="4">',
    );
    expect(template).to.include(
      '<td class="hidden 2xl:table-cell min-[1920px]:hidden px-8 py-12 text-center" colspan="5">',
    );
    expect(template).to.include(
      '<td class="hidden min-[1920px]:table-cell px-8 py-12 text-center" colspan="6">',
    );
  });

  it("preserves current filters for waitlist refreshes", async () => {
    // Load the waitlist list template before checking refresh markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify action-triggered refreshes reuse the handler-built filtered URL.
    expect(template).to.include('id="waitlist-refresh"');
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include('hx-trigger="refresh-event-waitlist from:body"');
    expect(template).not.to.include("refresh_limit");
  });

  it("explains disabled waitlist actions for unsupported offer states", async () => {
    // Load the waitlist list template before checking disabled offer states.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify every unsupported offer state explains why actions are unavailable.
    expect(template).to.include('title="Your role cannot manage waiting list offers."');
    expect(template).to.include('title="Canceled events have no available waiting list actions."');
    expect(template).to.include('title="Past events have no available waiting list actions."');
    expect(template).to.include('title="This waiting list offer is no longer active."');
    expect(template).to.include('title="No active waiting list offer to cancel."');
    expect(template).to.include(
      "Waitlist actions unavailable for {{ entry.user.name.as_deref() |assigned_or(entry.user.username) }}",
    );
  });

  it("renders waitlist queue and offer history states", async () => {
    // Load the waitlist template before checking queue and offer history.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify ticket tiers, queue positions, offer states, and deadlines remain visible.
    expect(template).to.include("{{ entry.ticket_title }}");
    expect(template).to.include("#{{ waitlist_position }}");
    expect(template).not.to.include("—");
    expect(template).to.include('waitlist_offer_status_badge(entry, event, "Offer pending", false, false)');
    expect(template).to.include(
      'waitlist_offer_status_badge(entry, event, "Checkout pending", false, false)',
    );
    expect(template).to.include('badges::status_badge(label = "Ticket claimed", published = true)');
    expect(template).to.include('waitlist_offer_status_badge(entry, event, "Offer expired", true, false)');
    expect(template).to.include('badges::status_badge(label = "Offer canceled", canceled = true)');
    expect(template).to.include('badges::status_badge(label = "Offer declined", canceled = true)');
    expect(template).not.to.include('waitlist_offer_status_badge(entry, event, "Ticket claimed"');
    expect(template).not.to.include('waitlist_offer_status_badge(entry, event, "Offer canceled"');
    expect(template).not.to.include('waitlist_offer_status_badge(entry, event, "Offer declined"');
    expect(template).to.include("badges::status_badge");
    expect(template).not.to.include("badges::invitation_badge");
    expect(template.indexOf("#{{ waitlist_position }}")).to.be.lessThan(
      template.indexOf('waitlist_offer_status_badge(entry, event, "Offer pending"'),
    );
    expect(template.indexOf('waitlist_offer_status_badge(entry, event, "Offer pending"')).to.be.lessThan(
      template.indexOf("{{ entry.ticket_title }}"),
    );

    // Active and expired offer details remain available with mouse or keyboard.
    expect(template).to.include("waitlist-offer-deadline-{{ entry.user.user_id }}");
    expect(template).to.include('aria-describedby="{{ waitlist_offer_tooltip_id }}"');
    expect(template).to.include("dashboard::tooltip_panel(");
    expect(template).to.include('title = "Ticket offer"');
    expect(template).to.include("-end-1 -top-1 size-2.5 rounded-full border-2 border-white");
    expect(template).to.include('<span class="block font-semibold text-stone-500">');
    expect(template).to.include('<span class="mt-0.5 block text-stone-900">');
    expect(template).to.include("group-hover/offer-deadline:visible");
    expect(template).to.include("group-focus-within/offer-deadline:visible");
    expect(template).to.include(
      'offer_expires_at.with_timezone(event.timezone).format("%b %d, %Y at %I:%M %p %Z")',
    );

    // Active offers use the shared table action-menu presentation.
    expect(template).to.include('data-event-id="waitlist-offer-{{ admission_offer_id }}"');
    expect(template).to.include(
      'aria-controls="dropdown-actions-waitlist-offer-{{ admission_offer_id }}"',
    );
    expect(template).to.include('aria-expanded="false"');
    expect(template).to.include('aria-label="Open waitlist actions for');
    expect(template).to.include("icon-vertical-dots");
    expect(template).to.include(
      'id="dropdown-actions-waitlist-offer-{{ admission_offer_id }}" data-event-actions-dropdown class="dropdown absolute end-0 top-8 z-10 hidden w-[220px] overflow-hidden rounded-lg border border-stone-200 bg-white py-1 shadow-lg"',
    );
    expect(template).to.include('id="cancel-waitlist-offer-{{ admission_offer_id }}"');
    expect(template).to.include('hx-trigger="confirmed"');
    expect(template).to.include('role="menuitem"');
    expect(template).to.include("<span>Cancel offer</span>");
    expect(template).not.to.include("Reissue offer");
  });
});
