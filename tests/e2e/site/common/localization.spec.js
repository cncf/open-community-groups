import { expect, test } from "@playwright/test";
import { TEST_COMMUNITY_NAME, TEST_EVENT_NAME, TEST_EVENT_SLUG, TEST_GROUP_SLUG } from "../../seed.js";
import { buildE2eUrl, navigateToPath } from "../../utils.js";

const SERVER_DATE_LOCALE = "en-US";

const SERVER_TIME_ZONE = "UTC";

test.describe("site localization defaults", () => {
  test("public event dates use the server-rendered event timezone", async ({ page, request }) => {
    await expectSeededEventDates(page, request);
  });
});

test.describe("site localization with de-DE locale and Asia/Tokyo browser timezone", () => {
  test.use({ locale: "de-DE", timezoneId: "Asia/Tokyo" });

  test("public event dates stay server-rendered in the event timezone", async ({ page, request }) => {
    await expectSeededEventDates(page, request);
  });
});

/** Asserts seeded event dates match server-rendered event and explore formats. */
const expectSeededEventDates = async (page, request) => {
  const timing = await getSeededEventTiming(request);
  const expectedCardDate = formatServerCardDate(timing);
  const expectedPageDate = formatServerEventPageDate(timing);
  const expectedPageTimeRange = formatServerEventPageTimeRange(timing);

  // The public templates render event dates server-side with Chrono's English format strings.
  await page.setViewportSize({ width: 1280, height: 900 });
  await navigateToPath(page, `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`);

  // Verify the event page ignores browser locale/timezone and keeps the event timezone format.
  await expect(page.getByRole("heading", { level: 1, name: TEST_EVENT_NAME })).toBeVisible();
  await expect(page.getByText(expectedPageDate, { exact: true })).toBeVisible();
  await expect(page.getByText(expectedPageTimeRange, { exact: true })).toBeVisible();

  // Verify explore cards use the shared server-rendered card date format.
  await navigateToPath(
    page,
    `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&ts_query=${encodeURIComponent(TEST_EVENT_NAME)}`,
  );
  const eventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAME }).first();
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

/** Returns seeded event timing from the public explore search API. */
const getSeededEventTiming = async (request) => {
  const params = new URLSearchParams({
    "community[0]": TEST_COMMUNITY_NAME,
    limit: "20",
    ts_query: TEST_EVENT_NAME,
  });
  const response = await request.get(buildE2eUrl(`/explore/events/search?${params.toString()}`));
  expect(response.status()).toBe(200);
  const payload = await response.json();
  const event = payload.events.find((item) => item.slug === TEST_EVENT_SLUG);

  expect(event).toBeTruthy();
  return {
    endsAt: event.ends_at,
    startsAt: event.starts_at,
    timezone: event.timezone || SERVER_TIME_ZONE,
  };
};
