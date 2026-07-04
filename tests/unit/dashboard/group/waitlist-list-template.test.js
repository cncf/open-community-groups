import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/waitlist_list.html",
  );

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
    expect(template).to.include(
      "entry.user.name.as_deref() |assigned_or(entry.user.username)",
    );
    expect(template).to.include(
      "entry.user.company.as_deref() |assigned_or(\"-\")",
    );
    expect(template).to.include("{% if let Some(title) = &entry.user.title -%}");
  });

  it("uses the shared search convention for table filtering", async () => {
    // Load the waitlist list template before checking search markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify waitlist search follows the existing dashboard HTMX pattern.
    expect(template).to.include('id="waitlist-search-form"');
    expect(template).to.include(
      'hx-get="/dashboard/group/events/{{ event.event_id }}/waitlist"',
    );
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include('hx-target="#waitlist-content"');
    expect(template).to.include(
      '<label for="search_waitlist" class="sr-only">Search waitlist</label>',
    );
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('value="{{ ts_query|assigned_or("") }}"');
    expect(template).to.include('placeholder="Search waitlist"');
    expect(template).to.include('aria-label="Clear waitlist search"');
    expect(template).to.include(
      'pagination::range_display(offset = refresh_offset , count = waitlist.len() , total = total, label = "waitlist entry", plural_label = "waitlist entries")',
    );
    expect(template).to.include(
      "dashboard/placeholders/group_waitlist_no_results.html",
    );
    expect(template).to.include("{{ entry.waitlist_position }}");
    expect(template).not.to.include("{{ refresh_offset + loop.index }}");
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
    expect(template).to.include("Joined ↑");
    expect(template).to.include("Joined ↓");
    expect(template).to.include('<option value="name-asc"');
    expect(template).to.include('<option value="name-desc"');
    expect(template).to.include('<option value="created-at-asc"');
    expect(template).to.include('<option value="created-at-desc"');
    expect(template).to.not.include("dashboard::table_sort_menu");
    expect(template).to.not.include("dashboard::table_sort_option_button");
    expect(template).to.not.include("dashboard::table_sort_control");
    expect(template).to.include('class="px-3 xl:px-5 py-1.5"');
    expect(template).to.include(
      'class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5"',
    );
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-1.5 w-40"',
    );
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-[72px]"');
    expect(template).to.include('<span class="whitespace-nowrap">Entry</span>');
    expect(template).to.include('<span class="whitespace-nowrap">Joined</span>');
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
    expect(template).to.include(
      'dashboard::active_table_filter_badge("Position", "Present")',
    );
    expect(template).to.include(
      'dashboard::active_table_filter_badge("Position", "Missing")',
    );
    expect(template).to.not.include('dashboard::active_table_filter_badge("Sort"');
  });

  it("keeps waitlist responsive columns aligned with empty placeholders", async () => {
    // Load the waitlist list template before checking responsive table markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the table columns and placeholders keep matching responsive spans.
    expect(template).to.include(
      'class="hidden 2xl:table-cell px-3 xl:px-5 py-4 max-w-0"',
    );
    expect(template).to.include(
      '<td class="xl:hidden px-8 py-12 text-center" colspan="3">',
    );
    expect(template).to.include(
      '<td class="hidden xl:table-cell 2xl:hidden px-8 py-12 text-center" colspan="4">',
    );
    expect(template).to.include(
      '<td class="hidden 2xl:table-cell px-8 py-12 text-center" colspan="5">',
    );
  });

  it("preserves current filters for waitlist refreshes", async () => {
    // Load the waitlist list template before checking refresh markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify action-triggered refreshes reuse the handler-built filtered URL.
    expect(template).to.include('id="waitlist-refresh"');
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include(
      'hx-trigger="refresh-event-waitlist from:body"',
    );
    expect(template).not.to.include("refresh_limit");
  });

  it("renders row actions to invite waitlisted users", async () => {
    // Load the waitlist list template before checking invite action markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify waitlisted users get an action menu with an invitation action.
    expect(template).to.include("data-events-list-page");
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include(
      "can_manage_events && !event.canceled && !event.is_past() && !event.is_ticketed()",
    );
    expect(template).to.include(
      "Open waitlist actions for {{ entry.user.name.as_deref() |assigned_or(entry.user.username) }}",
    );
    expect(template).to.include(
      'data-event-id="waitlist-{{ entry.user.user_id }}"',
    );
    expect(template).to.include(
      'id="dropdown-actions-waitlist-{{ entry.user.user_id }}"',
    );
    expect(template).to.include("data-event-actions-dropdown");
    expect(template).to.include(
      'hx-post="/dashboard/group/events/{{ event.event_id }}/attendees/invite"',
    );
    expect(template).to.include(
      'name="user_id" value="{{ entry.user.user_id }}"',
    );
    expect(template).to.include("Invite user");
    expect(template).to.include('data-success-message="Invitation sent."');
    expect(template).to.include(
      'data-error-message="Something went wrong sending this invitation. Please try again later."',
    );
  });

  it("keeps waitlist actions disabled for unsupported invite states", async () => {
    // Load the waitlist list template before checking disabled invite states.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify unsupported invite states keep the waitlist action unavailable.
    expect(template).to.include('title="Your role cannot invite attendees."');
    expect(template).to.include(
      'title="Canceled events cannot invite attendees."',
    );
    expect(template).to.include('title="Past events cannot invite attendees."');
    expect(template).to.include(
      'title="Manual invitations are not available for ticketed events."',
    );
    expect(template).to.include(
      "Waitlist actions unavailable for {{ entry.user.name.as_deref() |assigned_or(entry.user.username) }}",
    );
  });
});
