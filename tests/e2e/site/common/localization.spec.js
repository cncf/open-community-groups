import { expect, test } from "../../fixtures.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_IDS,
  TEST_GROUP_SLUG,
  TEST_GROUP_SLUGS,
} from "../../seed.js";
import { buildE2eUrl, futureDate, navigateToPath } from "../../utils.js";

/** Non-UTC zone of the owned event; Intl and chrono-tz agree on its abbreviations. */
const NON_UTC_EVENT_TIME_ZONE = "America/New_York";

/** Seeded event, which uses the server time zone. */
const SEEDED_EVENT = {
  groupSlug: TEST_GROUP_SLUG,
  name: TEST_EVENT_NAME,
  slug: TEST_EVENT_SLUG,
  timezone: "UTC",
};

const SERVER_DATE_LOCALE = "en-US";

test.describe("site localization defaults", () => {
  test("public event dates use the server-rendered event timezone", async ({ page, request }) => {
    await expectEventDates(page, request, SEEDED_EVENT);
  });

  test("non-UTC event dates render in the event timezone", async ({ owned, page, request }) => {
    await expectEventDates(page, request, setupNonUtcEvent(owned));
  });
});

test.describe("site localization with de-DE locale and Asia/Tokyo browser timezone", () => {
  test.use({ locale: "de-DE", timezoneId: "Asia/Tokyo" });

  test("public event dates stay server-rendered in the event timezone", async ({ page, request }) => {
    await expectEventDates(page, request, SEEDED_EVENT);
  });

  test("non-UTC event dates render in the event timezone", async ({ owned, page, request }) => {
    await expectEventDates(page, request, setupNonUtcEvent(owned));
  });
});

/**
 * Asserts an event's dates match server-rendered event page and explore formats.
 * @param {import("@playwright/test").Page} page - Page used to load the public pages.
 * @param {import("@playwright/test").APIRequestContext} request - Context used for the explore search API.
 * @param {{ groupSlug: string, name: string, slug: string, timezone: string }} event - Event and its
 * expected time zone.
 */
const expectEventDates = async (page, request, event) => {
  const timing = await getEventTiming(request, event);
  const expectedCardDate = formatServerCardDate(timing);
  const expectedPageDate = formatServerEventPageDate(timing);
  const expectedPageTimeRange = formatServerEventPageTimeRange(timing);

  // The public templates render event dates server-side with Chrono's English format strings.
  await page.setViewportSize({ width: 1280, height: 900 });
  await navigateToPath(page, `/${TEST_COMMUNITY_NAME}/group/${event.groupSlug}/event/${event.slug}`);

  // Verify the event page ignores browser locale/timezone and keeps the event timezone format.
  await expect(page.getByRole("heading", { level: 1, name: event.name })).toBeVisible();
  await expect(page.getByText(expectedPageDate, { exact: true })).toBeVisible();
  await expect(page.getByText(expectedPageTimeRange, { exact: true })).toBeVisible();

  // Verify explore cards use the shared server-rendered card date format.
  await navigateToPath(
    page,
    `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&ts_query=${encodeURIComponent(event.name)}`,
  );
  const eventCard = page.getByRole("link").filter({ hasText: event.name }).first();
  await expect(eventCard).toBeVisible();
  await expect(eventCard).toContainText(expectedCardDate);
};

/** Formats the server-rendered event card date for assertions. */
const formatServerCardDate = ({ startsAt, timezone }) => {
  const date = new Date(startsAt * 1000);
  const parts = getDateParts(date, timezone, {
    day: "numeric",
    hour: "numeric",
    hour12: true,
    minute: "2-digit",
    month: "short",
    timeZoneName: "short",
    year: "numeric",
  });

  return `${parts.month} ${parts.day}, ${parts.year} · ${parts.hour}:${parts.minute} ${parts.dayPeriod} ${parts.timeZoneName}`;
};

/** Formats the server-rendered event page date for assertions. */
const formatServerEventPageDate = ({ startsAt, timezone }) => {
  const date = new Date(startsAt * 1000);
  const parts = getDateParts(date, timezone, {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

  return `${parts.month} ${parts.day}, ${parts.year}`;
};

/** Formats the server-rendered event page time range for assertions. */
const formatServerEventPageTimeRange = ({ endsAt, startsAt, timezone }) => {
  const start = new Date(startsAt * 1000);
  const end = new Date(endsAt * 1000);
  const startParts = getDateParts(start, timezone, {
    hour: "2-digit",
    hour12: true,
    minute: "2-digit",
  });
  const endParts = getDateParts(end, timezone, {
    hour: "2-digit",
    hour12: true,
    minute: "2-digit",
    timeZoneName: "short",
  });

  return `${startParts.hour}:${startParts.minute} ${startParts.dayPeriod} - ${endParts.hour}:${endParts.minute} ${endParts.dayPeriod} ${endParts.timeZoneName}`;
};

/** Returns date parts for a date in the server locale and target time zone. */
const getDateParts = (date, timeZone, options) => {
  const parts = new Intl.DateTimeFormat(SERVER_DATE_LOCALE, {
    timeZone,
    ...options,
  }).formatToParts(date);

  return Object.fromEntries(
    parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]),
  );
};

/** Returns an event's timing from the public explore search API, in its expected time zone. */
const getEventTiming = async (request, { name, slug, timezone }) => {
  const params = new URLSearchParams({
    "community[0]": TEST_COMMUNITY_NAME,
    date_from: "1900-01-01",
    date_to: "2100-12-31",
    ts_query: name,
    view_mode: "calendar",
  });
  const response = await request.get(buildE2eUrl(`/explore/events/search?${params.toString()}`));
  expect(response.status()).toBe(200);
  const payload = await response.json();
  const event = payload.events.find((item) => item.slug === slug);

  expect(event).toBeTruthy();
  return {
    endsAt: event.ends_at,
    startsAt: event.starts_at,
    timezone,
  };
};

/**
 * Creates a published alpha group event at 21:30 New York time about forty days ahead, so its UTC start
 * falls on the next calendar day and a UTC rendering would show the wrong date.
 * @param {{ event: Function }} owned - Owned data registry that removes the event after the test.
 * @returns {{ groupSlug: string, name: string, slug: string, timezone: string }}
 */
const setupNonUtcEvent = (owned) => {
  const { name, slug } = owned.event({
    groupId: TEST_GROUP_IDS.community1.alpha,
    startsAt: futureDate({ days: 40, hour: 21, minute: 30 }),
    timezone: NON_UTC_EVENT_TIME_ZONE,
  });

  return { groupSlug: TEST_GROUP_SLUGS.community1.alpha, name, slug, timezone: NON_UTC_EVENT_TIME_ZONE };
};
