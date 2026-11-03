import { expect } from "../../../fixtures.js";

import { queryE2eDatabaseRows } from "../../../database.js";
import {
  buildE2eUrl,
  futureDate,
  navigateToPath,
  routeNextRequestWithQuery,
  selectTimezone,
  waitForActionResponse,
  waitForActionResponses,
} from "../../../utils.js";
import { fillMarkdownEditor } from "../../form-helpers.js";
import { TEST_EVENT_CATEGORY_IDS, TEST_EVENT_IDS } from "../../../seed.js";

/** Opens the event editor payments section and waits until its tab is active. */
export const openPaymentsSection = async (page) => {
  const paymentsSectionButton = page.locator('button[data-section="payments"]');

  await paymentsSectionButton.scrollIntoViewIfNeeded();
  await expect(paymentsSectionButton).toBeVisible();

  if ((await paymentsSectionButton.getAttribute("data-active")) === "true") {
    return;
  }

  await paymentsSectionButton.click();
  await expect(paymentsSectionButton).toHaveAttribute("data-active", "true");
};

// Seeded event names opened by the shared section openers.
const CFS_EVENT_NAME = "Event With Active CFS";
const DASHBOARD_WAITLIST_EVENT_NAME = "Dashboard Waitlist Table Lab";
const EVENT_EDITOR_UPDATE_PATH = /\/dashboard\/group\/events\/[^/]+\/update$/;
const GROUP_EVENTS_PAGE_LIMIT = 100;

/**
 * Builds the matcher for the GET that loads the event update editor.
 * @param {string} [eventId] - Event id expected in the editor URL; any event when omitted.
 * @returns {object} Response matcher.
 */
const getEventEditorLoadMatcher = (eventId) => ({
  method: "GET",
  pathname: eventId ? `/dashboard/group/events/${eventId}/update` : EVENT_EDITOR_UPDATE_PATH,
  status: 200,
});

/**
 * Waits for the event update editor after a successful create or save.
 * When `action` is provided, the follow-up GET and editor-element replacement
 * are armed before the action runs so an already-open editor cannot satisfy the wait.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {() => Promise<unknown>|unknown} [action] - Click or submit that triggers save.
 * @param {{
 *   eventId?: string,
 *   method?: string,
 *   params?: Record<string, string|null|true>,
 *   pathname?: string|RegExp,
 *   status?: number|number[],
 *   urlEndsWith?: string,
 *   urlIncludes?: string
 * }} [request] - Mutation request matcher; `eventId` pins the follow-up editor GET.
 * @returns {Promise<string>} Created or saved event id.
 */
export const waitForEventEditorAfterSave = async (page, action, request = {}) => {
  const editor = page.locator('[data-event-page="update"]');
  const previousEditor = typeof action === "function" ? await editor.elementHandle() : null;
  const { eventId, ...actionRequest } = request;

  if (previousEditor) {
    await previousEditor.evaluate((element) => {
      element.setAttribute("data-editor-generation", "pre-save");
    });
  }

  if (typeof action === "function") {
    if (actionRequest.method) {
      await waitForActionResponses(page, action, [actionRequest, getEventEditorLoadMatcher(eventId)]);
    } else {
      await waitForActionResponse(page, action, getEventEditorLoadMatcher(eventId));
    }
  }

  const reloadedEditor = previousEditor
    ? page.locator('[data-event-page="update"]:not([data-editor-generation="pre-save"])')
    : editor;
  await expect(reloadedEditor).toHaveAttribute("data-event-page-ready", "true");
  const saveUrl = await reloadedEditor.locator("#update-event-button").getAttribute("hx-put");
  expect(saveUrl).toBeTruthy();
  const match = saveUrl?.match(/\/events\/([^/?]+)\/update/);
  expect(match).not.toBeNull();
  return match?.[1] ?? "";
};

/**
 * Opens the group events tab page containing an event and returns its row.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} eventName - Event name to locate.
 * @param {{ eventsTab?: "upcoming"|"past", limit?: number }} [options] - Events list paging options.
 * @returns {Promise<import("@playwright/test").Locator>} Event row locator.
 */
export const openGroupEventsTabWithEvent = async (
  page,
  eventName,
  { eventsTab = "upcoming", limit = GROUP_EVENTS_PAGE_LIMIT } = {},
) => {
  const offsetParam = `${eventsTab}_offset`;
  const content = page.locator(`#${eventsTab}-content`);
  let offset = 0;

  while (true) {
    await navigateToPath(
      page,
      `/dashboard/group?tab=events&events_tab=${eventsTab}&limit=${limit}&${offsetParam}=${offset}`,
    );
    await expect(page.locator("#dashboard-content").getByText("Events", { exact: true })).toBeVisible();
    await expect(content).toBeVisible();

    const eventRow = content.locator("tr", { hasText: eventName }).first();
    if ((await eventRow.count()) > 0) {
      await expect(eventRow).toBeVisible();
      return eventRow;
    }

    const resultRows = await content.locator("tbody tr").count();
    const nextLink = content.locator(".pagination").getByRole("link", { name: "Next" });
    if (resultRows === 0 || (await nextLink.count()) === 0) {
      break;
    }

    const href = await nextLink.first().getAttribute("href");
    const nextOffset = href
      ? Number(new URL(href, buildE2eUrl("/")).searchParams.get(offsetParam))
      : Number.NaN;
    offset = Number.isFinite(nextOffset) ? nextOffset : offset + limit;
  }

  throw new Error(`Event "${eventName}" was not found in ${eventsTab} events.`);
};

/**
 * Opens the event update form by row action and waits for HTMX content.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} eventName - Event name to locate.
 * @param {string} [eventId] - Event ID expected in the editor request URL.
 * @param {{ eventsTab?: "upcoming"|"past", limit?: number }} [options] - Events list paging options.
 */
export const openEventUpdateFormByName = async (page, eventName, eventId, options = {}) => {
  const eventRow = await openGroupEventsTabWithEvent(page, eventName, options);
  const editButton = eventRow.locator('td button[aria-label^="Edit event:"]:visible');
  await expect(editButton).toBeVisible();

  await waitForActionResponse(page, () => editButton.click(), getEventEditorLoadMatcher(eventId));
  await expect(page.locator('[data-event-page="update"]')).toHaveAttribute("data-event-page-ready", "true");
};

/**
 * Opens one event editor section from the currently loaded event editor.
 * Clicks the sidebar tab when it is visible and falls back to the compact
 * section select that replaces it on narrow viewports.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} eventId - Event id whose section request should load.
 * @param {string} section - Section data attribute.
 * @param {string} contentSelector - Section content selector.
 * @param {{ query?: string, tableName?: string }} [options] - Optional query override and table wait.
 * @returns {Promise<import("@playwright/test").Locator>} Section content locator.
 */
export const openCurrentEventEditorSection = async (
  page,
  eventId,
  section,
  contentSelector,
  { query = "", tableName } = {},
) => {
  const sectionPath = `/dashboard/group/events/${eventId}/${section}`;
  const sectionTab = page.locator(`button[data-section="${section}"]`);
  if (query !== "") {
    await routeNextRequestWithQuery(page, sectionPath, query);
  }

  const openSection = async () => {
    if (await sectionTab.isVisible()) {
      await sectionTab.click();
      return;
    }

    await page.locator('[data-event-page="update"] [data-section-select]').selectOption(section);
  };
  await waitForActionResponse(page, openSection, {
    method: "GET",
    pathname: sectionPath,
    status: 200,
  });

  const content = page.locator(contentSelector);
  if (tableName) {
    await expect(content.getByRole("table", { name: tableName })).toBeVisible();
  }

  return content;
};

/**
 * Opens the submissions section of the seeded CFS event.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} [query] - Optional query override for the first submissions request.
 * @returns {Promise<import("@playwright/test").Locator>} Submissions content locator.
 */
export const openCfsEventSubmissionsTab = (page, query = "") =>
  openEventSection(page, {
    contentSelector: "#submissions-content",
    eventId: TEST_EVENT_IDS.alpha.cfsSummit,
    eventName: CFS_EVENT_NAME,
    query,
    section: "submissions",
  });

/**
 * Opens the waitlist section of the seeded dashboard waitlist event.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} [query] - Optional query override for the first waitlist request.
 * @returns {Promise<import("@playwright/test").Locator>} Waitlist content locator.
 */
export const openDashboardWaitlist = (page, query = "") =>
  openEventSection(page, {
    contentSelector: "#waitlist-content",
    eventId: TEST_EVENT_IDS.alpha.dashboardWaitlist,
    eventName: DASHBOARD_WAITLIST_EVENT_NAME,
    query,
    section: "waitlist",
  });

/**
 * Opens an event editor from the group events list and loads one of its sections.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{
 *   contentSelector: string,
 *   eventId: string,
 *   eventName: string,
 *   eventsTab?: "upcoming"|"past",
 *   query?: string,
 *   section: string,
 *   tableName?: string
 * }} options - Event to open, section to load and optional query override and table wait.
 * @returns {Promise<import("@playwright/test").Locator>} Section content locator.
 */
export const openEventSection = async (
  page,
  { contentSelector, eventId, eventName, eventsTab = "upcoming", query = "", section, tableName },
) => {
  await openEventUpdateFormByName(page, eventName, eventId, { eventsTab });

  return openCurrentEventEditorSection(page, eventId, section, contentSelector, { query, tableName });
};

/** Adds a discount code through the ticketing modal and saves it. */
export const addDiscountCode = async (page, values) => {
  await page.locator("#add-discount-code-button").click();

  const modal = page.locator('[data-ticketing-role="discount-modal"]');
  await expect(modal).toBeVisible();
  await expect(
    modal.getByText("Leave blank to allow unlimited redemptions.", {
      exact: true,
    }),
  ).toBeVisible();
  await expect(
    modal.getByText("Optional manual override. Leave blank to let OCG track remaining uses automatically.", {
      exact: true,
    }),
  ).toBeVisible();
  await expect(modal.locator("#discount-available-draft")).toHaveAttribute(
    "placeholder",
    "Automatically tracked",
  );
  await modal.locator("#discount-title-draft").fill(values.title);
  await modal.locator("#discount-code-draft").fill(values.code);

  const activeCheckbox = modal.locator('[data-discount-field="active"]');
  if (!(await activeCheckbox.isChecked())) {
    await activeCheckbox.check({ force: true });
  }

  await modal.locator("#discount-kind-draft").selectOption(values.kind);

  if (values.kind === "fixed_amount" && values.amount) {
    await modal.locator("#discount-amount-draft").fill(values.amount);
  }

  if (values.kind === "percentage" && values.percentage) {
    await modal.locator("#discount-percentage-draft").fill(values.percentage);
  }

  if (values.totalAvailable) {
    await modal.locator("#discount-total-draft").fill(values.totalAvailable);
  }

  if (values.available) {
    await modal.locator("#discount-available-draft").fill(values.available);
  }

  if (values.startsAt) {
    await modal.locator("#discount-starts-draft").fill(values.startsAt);
  }

  if (values.endsAt) {
    await modal.locator("#discount-ends-draft").fill(values.endsAt);
  }

  await modal.locator('[data-ticketing-action="save-discount"]').click();
  await expect(modal).toBeHidden();
};

/** Sets whether a persisted discount code can be redeemed. */
export const setDiscountCodeActive = async (page, code, active) => {
  const discountRow = page
    .locator('#discount-codes-ui [data-ticketing-role="table-body"] tr')
    .filter({ hasText: code });
  await discountRow.locator('[data-ticketing-action="edit-discount"]').click();

  const modal = page.locator('[data-ticketing-role="discount-modal"]');
  await expect(modal).toBeVisible();
  await modal.locator('[data-discount-field="active"]').setChecked(active, {
    force: true,
  });
  await modal.locator('[data-ticketing-action="save-discount"]').click();
  await expect(modal).toBeHidden();
};

/**
 * Creates a published event that requires organizer approval for attendees through the editor
 * and reopens it from the events list. Specs that do not cover event creation should use
 * `setupApprovalRequiredEvent` from `data-graphs/events.js` instead.
 * @param {import("@playwright/test").Page} page - Organizer page with the owning group selected.
 * @param {string} eventName - Name of the new event.
 * @returns {Promise<{ eventId: string }>} Created event identifier.
 */
export const createApprovalRequiredEvent = async (page, eventName) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
  await dashboardContent.getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();

  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
  await page.locator("#description_short").fill("A temporary approval-required event from the e2e suite.");
  await fillMarkdownEditor(
    page,
    "description",
    "A temporary approval-required event for invitation request coverage.",
  );
  await page.locator("#toggle_attendee_approval_required").check({ force: true });

  await page.locator('button[data-section="date-venue"]').click();
  await expect(page.locator('button[data-section="date-venue"]')).toHaveAttribute("data-active", "true");
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill(futureDate({ days: 220, hour: 10 }));
  await page.locator("#ends_at").fill(futureDate({ days: 220, hour: 12 }));
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-invitation-requests");

  const visibleAddEventButton = page.locator("#pending-changes-alert:not(.hidden) #add-event-button");
  await expect(visibleAddEventButton).toBeVisible();

  await waitForActionResponse(page, () => visibleAddEventButton.click(), {
    method: "POST",
    urlIncludes: "/dashboard/group/events/add",
    status: 201,
  });
  const eventId = await waitForEventEditorAfterSave(page);

  const publishResponse = await page.request.put(buildE2eUrl(`/dashboard/group/events/${eventId}/publish`));
  expect(publishResponse.ok()).toBeTruthy();

  const eventRow = await openGroupEventsTabWithEvent(page, eventName);

  await waitForActionResponse(page, () => eventRow.locator('td button[aria-label^="Edit event:"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${eventId}/update`,
  });

  return { eventId: eventId ?? "" };
};

/**
 * Asserts a visible search dropdown stays next to its input and inside the viewport.
 *
 * Only pass `above` when the dropdown is known to be taller than the room left
 * below its input, otherwise the side it opens on depends on the seeded data.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {import("@playwright/test").Locator} input - Search input the dropdown opens from.
 * @param {import("@playwright/test").Locator} dropdown - Search dropdown panel.
 * @param {{ above?: boolean }} [options] - Whether the dropdown must open above its input.
 * @returns {Promise<void>}
 */
export const expectSearchDropdownInViewport = async (page, input, dropdown, { above = false } = {}) => {
  await expect(dropdown).toBeVisible();
  const { height: viewportHeight } = page.viewportSize();
  const inputBox = await input.boundingBox();
  const dropdownBox = await dropdown.boundingBox();
  const dropdownBottom = dropdownBox.y + dropdownBox.height;
  const opensAbove = dropdownBottom <= inputBox.y;
  const opensBelow = dropdownBox.y >= inputBox.y + inputBox.height;

  expect(dropdownBox.height).toBeGreaterThan(0);
  expect(dropdownBox.y).toBeGreaterThanOrEqual(0);
  expect(dropdownBottom).toBeLessThanOrEqual(viewportHeight);
  expect(above ? opensAbove : opensAbove || opensBelow).toBe(true);
};

/**
 * Scrolls an element so its bottom edge lines up with the viewport bottom.
 * @param {import("@playwright/test").Locator} locator - Element to scroll into place.
 * @returns {Promise<void>}
 */
export const scrollToViewportBottom = async (locator) => {
  await locator.evaluate((element) => element.scrollIntoView({ block: "end" }));
};

/**
 * Lists the labels of an event from the database, sorted by name.
 * @param {string} eventId - Event identifier.
 * @returns {{ color: string, id: string, name: string }[]} Event labels.
 */
export const listEventLabels = (eventId) =>
  queryE2eDatabaseRows(`
    select event_label_id, name, color
    from event_label
    where event_id = '${eventId}'
    order by name
  `).map(([id, name, color]) => ({ color, id, name }));

/**
 * Lists the sessions of an event with their label names from the database.
 * @param {string} eventId - Event identifier.
 * @returns {{ labels: string[], name: string }[]} Sessions sorted by name, labels sorted by name.
 */
export const listSessionLabels = (eventId) =>
  queryE2eDatabaseRows(`
    select s.name, coalesce(array_to_json(array_agg(el.name order by el.name) filter (where el.name is not null)), '[]')
    from session s
    left join session_label sl on sl.session_id = s.session_id
    left join event_label el on el.event_label_id = sl.event_label_id
    where s.event_id = '${eventId}'
    group by s.session_id, s.name
    order by s.name
  `).map(([name, labels]) => ({ labels: JSON.parse(labels), name }));
