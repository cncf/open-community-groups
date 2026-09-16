import { expect } from "../../../fixtures.js";

import {
  buildE2eUrl,
  navigateToPath,
  routeNextRequestWithQuery,
  selectTimezone,
  waitForActionResponse,
} from "../../../utils.js";
import { fillMarkdownEditor } from "../../form-helpers.js";

/** Opens the payments section and retries until the tab state is active. */
export const openPaymentsSection = async (page) => {
  const paymentsSectionButton = page.locator('button[data-section="payments"]');

  await paymentsSectionButton.scrollIntoViewIfNeeded();
  await expect(paymentsSectionButton).toBeVisible();

  if ((await paymentsSectionButton.getAttribute("data-active")) === "true") {
    return;
  }

  for (let attempt = 0; attempt < 3; attempt += 1) {
    await paymentsSectionButton.click({ force: true });

    try {
      await expect(paymentsSectionButton).toHaveAttribute("data-active", "true", {
        timeout: 1000,
      });
      return;
    } catch (error) {
      if (attempt === 2) {
        throw error;
      }
    }
  }
};

const EVENT_EDITOR_UPDATE_PATH = /\/dashboard\/group\/events\/[^/]+\/update$/;
const GROUP_EVENTS_PAGE_LIMIT = 100;

/**
 * Returns whether a response is the follow-up GET that reloads the event editor.
 * @param {import("@playwright/test").Response} response - Playwright response.
 * @param {string} [eventId] - Optional event id that must appear in the URL.
 * @returns {boolean} Whether the response reloads the update editor.
 */
const isEventEditorFollowUpGet = (response, eventId) => {
  const pathname = new URL(response.url()).pathname;
  return (
    response.request().method() === "GET" &&
    EVENT_EDITOR_UPDATE_PATH.test(pathname) &&
    (eventId ? pathname.includes(eventId) : true) &&
    response.ok()
  );
};

/**
 * Waits for the event update editor after a successful create or save.
 * When `action` is provided, the follow-up GET and editor-element replacement
 * are armed before the action runs so an already-open editor cannot satisfy the wait.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {() => Promise<unknown>|unknown} [action] - Click or submit that triggers save.
 * @param {{
 *   eventId?: string,
 *   method?: string,
 *   status?: number,
 *   urlEndsWith?: string,
 *   urlIncludes?: string
 * }} [request] - Mutation request matcher.
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
    await Promise.all([
      page.waitForResponse((response) => isEventEditorFollowUpGet(response, eventId)),
      actionRequest.method ? waitForActionResponse(page, action, actionRequest) : action(),
    ]);
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

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes("/dashboard/group/events/") &&
        response.url().includes("/update") &&
        (eventId ? response.url().includes(eventId) : true) &&
        response.ok(),
    ),
    editButton.click(),
  ]);
  await expect(page.locator('[data-event-page="update"]')).toHaveAttribute("data-event-page-ready", "true");
};

/**
 * Opens one event editor section from the currently loaded event editor.
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
  const sectionTab = page.locator(`button[data-section="${section}"]`);
  if (query !== "") {
    await routeNextRequestWithQuery(page, `/dashboard/group/events/${eventId}/${section}`, query);
  }

  await waitForActionResponse(page, () => sectionTab.click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${eventId}/${section}`,
  });

  const content = page.locator(contentSelector);
  if (tableName) {
    await expect(content.getByRole("table", { name: tableName })).toBeVisible();
  }

  return content;
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

/** Creates a published event that requires organizer approval for attendees. */
export const createApprovalRequiredEvent = async (page, eventName) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
  await dashboardContent.getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();

  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
  await page.locator("#description_short").fill("A temporary approval-required event from the e2e suite.");
  await fillMarkdownEditor(
    page,
    "description",
    "A temporary approval-required event for invitation request coverage.",
  );
  await page.locator("#toggle_attendee_approval_required").check({ force: true });

  await page.locator("button[data-section-next]").click();
  await expect(page.locator('button[data-section="date-venue"]')).toHaveAttribute("data-active", "true");
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill("2030-06-20T10:00");
  await page.locator("#ends_at").fill("2030-06-20T12:00");
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
  const viewEventHref = await page.locator("#event-update-page").getAttribute("data-event-public-url");

  expect(viewEventHref).not.toBeNull();

  return {
    eventId: eventId ?? "",
    viewEventHref: viewEventHref ?? "",
  };
};

/** Cancels and deletes the temporary event created for invitation request coverage. */
export const deleteEventFromList = async (page, eventId) => {
  if (page.isClosed()) {
    return;
  }

  const cancelResponse = await page.request.put(buildE2eUrl(`/dashboard/group/events/${eventId}/cancel`));
  expect([200, 204, 404]).toContain(cancelResponse.status());
  const deleteResponse = await page.request.delete(buildE2eUrl(`/dashboard/group/events/${eventId}/delete`));
  expect([200, 204, 404]).toContain(deleteResponse.status());
};
