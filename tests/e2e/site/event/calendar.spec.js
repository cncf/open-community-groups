import { expect, test } from "../../fixtures.js";

import {
  TEST_CANCELED_PUBLIC_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_SLUG,
  TEST_OPEN_CHECK_IN_EVENT,
  TEST_UNPUBLISHED_EVENT,
} from "../../seed.js";
import { buildE2eUrl } from "../../utils.js";

/** Builds the public calendar file path of an event in the seeded group. */
const getCalendarPath = (eventSlug) =>
  `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${eventSlug}/calendar.ics`;

/** Reads a calendar response, joining the lines folded by the iCalendar format. */
const readCalendar = async (response) => (await response.text()).replace(/\r?\n[ \t]/g, "");

test.describe("event calendar file", () => {
  test("downloads the calendar entry of a published event", async ({ request }) => {
    // Request the calendar file of the primary event.
    const response = await request.get(buildE2eUrl(getCalendarPath(TEST_EVENT_SLUG)));
    const calendar = await readCalendar(response);

    // Verify the file downloads as a calendar entry that links back to the event.
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toBe("text/calendar; charset=utf-8");
    expect(response.headers()["content-disposition"]).toBe(
      `attachment; filename="event-${TEST_EVENT_SLUG}.ics"`,
    );
    expect(calendar).toContain("BEGIN:VCALENDAR");
    expect(calendar).toContain("DTSTART;TZID=");
    expect(calendar).toContain("STATUS:CONFIRMED");
    expect(calendar).toContain(`SUMMARY:${TEST_EVENT_NAME}`);
    expect(calendar).toContain(`/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`);
  });

  test("leaves meeting access details out of a published event", async ({ request }) => {
    // Request the seeded event that has a join link and instructions.
    const response = await request.get(buildE2eUrl(getCalendarPath(TEST_OPEN_CHECK_IN_EVENT.slug)));
    const calendar = await readCalendar(response);

    // Verify the event is served without its meeting access details.
    expect(response.status()).toBe(200);
    expect(calendar).toContain(`SUMMARY:${TEST_OPEN_CHECK_IN_EVENT.name}`);
    expect(calendar).not.toContain("meet.example.com");
    expect(calendar).not.toContain("Meeting link");
    expect(calendar).not.toContain("Meeting password");
    expect(calendar).not.toContain("passcode");
  });

  test("marks a canceled event without its meeting access details", async ({ request }) => {
    // Request the seeded canceled event that has a join link and instructions.
    const response = await request.get(buildE2eUrl(getCalendarPath(TEST_CANCELED_PUBLIC_EVENT.slug)));
    const calendar = await readCalendar(response);

    // Verify calendars that imported the event can show the cancellation.
    expect(response.status()).toBe(200);
    expect(calendar).toContain("STATUS:CANCELLED");
    expect(calendar).not.toContain("meet.example.com");
    expect(calendar).not.toContain("private meeting room");
  });

  test("does not serve an unpublished event", async ({ request }) => {
    // Request the calendar file of the seeded unpublished event.
    const response = await request.get(buildE2eUrl(getCalendarPath(TEST_UNPUBLISHED_EVENT.slug)));

    // Verify nothing about the event is returned.
    expect(response.status()).toBe(404);
    expect(await response.text()).not.toContain(TEST_UNPUBLISHED_EVENT.name);
  });

  test("does not serve an unknown event", async ({ request }) => {
    // Request the calendar file of an event that does not exist.
    const response = await request.get(buildE2eUrl(getCalendarPath("missing-e2e-event")));

    // Verify the route answers as missing.
    expect(response.status()).toBe(404);
  });
});
