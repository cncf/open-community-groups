import { expect, test } from "../../../fixtures.js";
import { TEST_EVENT_SURVEYS } from "../../../data-graphs/surveys.js";
import { TEST_REGISTRATION_QUESTIONS_EVENT } from "../../../seed.js";
import { buildE2eUrl } from "../../../utils.js";

// Group dashboard CSV exports, each with a seeded respondent name that marks attendee PII.
const CSV_EXPORTS = [
  {
    fileName: `event-${TEST_REGISTRATION_QUESTIONS_EVENT.slug}-attendees.csv`,
    name: "attendees CSV",
    path: `/dashboard/group/events/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attendees.csv`,
    piiMarker: "E2E Member One",
  },
  {
    fileName: `event-${TEST_REGISTRATION_QUESTIONS_EVENT.slug}-attendees-with-answers.csv`,
    name: "attendees with answers CSV",
    path: `/dashboard/group/events/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attendees-with-answers.csv`,
    piiMarker: "E2E Member One",
  },
  {
    fileName: `event-${TEST_EVENT_SURVEYS.event.slug}-survey-${TEST_EVENT_SURVEYS.surveys.openIdentified.id}.csv`,
    name: "survey responses CSV",
    path: `/dashboard/group/events/${TEST_EVENT_SURVEYS.event.id}/surveys/${TEST_EVENT_SURVEYS.surveys.openIdentified.id}/responses.csv`,
    piiMarker: "E2E Survey Attendee One",
  },
];

// Leading header columns shared by every identified export.
const CSV_HEADER_PREFIX = "Name,Company,Title,";

// Redirect sent to signed-in users without a group team role.
const INVITATIONS_REDIRECT = { location: "/dashboard/user?tab=invitations", status: 303 };

// `page.request` bypasses `browserHealth`, so every response below is asserted exactly.
test.describe("group dashboard CSV exports", () => {
  test("organizer downloads every export of the selected group", async ({ organizerGroupPage }) => {
    for (const csvExport of CSV_EXPORTS) {
      await test.step(csvExport.name, async () => {
        await expectCsvAttachment(organizerGroupPage, csvExport);
      });
    }
  });

  test("group viewer downloads every export of the selected group", async ({ groupViewerPage }) => {
    // Viewers keep attendee exports: they stay in the read permission bucket.
    for (const csvExport of CSV_EXPORTS) {
      await test.step(csvExport.name, async () => {
        await expectCsvAttachment(groupViewerPage, csvExport);
      });
    }
  });

  test("member without a team role is redirected without an attachment", async ({ member1Page }) => {
    for (const csvExport of CSV_EXPORTS) {
      await test.step(csvExport.name, async () => {
        // Request the export without following the dashboard redirect.
        const response = await member1Page.request.get(buildE2eUrl(csvExport.path), {
          maxRedirects: 0,
        });

        // Verify the redirect to the invitations tab leaks no export.
        expect(response.status()).toBe(INVITATIONS_REDIRECT.status);
        expect(response.headers().location).toBe(INVITATIONS_REDIRECT.location);
        await expectNoCsvLeak(response, csvExport);
      });
    }
  });

  test("organizer of another community's group gets not found", async ({
    organizerGroupWithoutPaymentsPage,
  }) => {
    for (const csvExport of CSV_EXPORTS) {
      await test.step(csvExport.name, async () => {
        // Request the export of an event outside the selected group.
        const response = await organizerGroupWithoutPaymentsPage.request.get(buildE2eUrl(csvExport.path), {
          maxRedirects: 0,
        });

        // Verify the foreign event is not found and nothing is exported.
        expect(response.status()).toBe(404);
        await expectNoCsvLeak(response, csvExport);
      });
    }
  });
});

/** Asserts that a page's session downloads the export as a CSV attachment with attendee PII. */
async function expectCsvAttachment(page, csvExport) {
  const response = await page.request.get(buildE2eUrl(csvExport.path), { maxRedirects: 0 });
  const headers = response.headers();

  expect(response.status()).toBe(200);
  expect(headers["content-type"]).toContain("text/csv");
  expect(headers["content-disposition"]).toBe(`attachment; filename="${csvExport.fileName}"`);
  const body = await response.text();
  expect(body.startsWith(CSV_HEADER_PREFIX)).toBe(true);
  expect(body).toContain(csvExport.piiMarker);
}

/** Asserts that a rejected export response carries no attachment, CSV header or attendee PII. */
async function expectNoCsvLeak(response, csvExport) {
  expect(response.headers()["content-disposition"]).toBeUndefined();
  const body = await response.text();
  expect(body).not.toContain(CSV_HEADER_PREFIX);
  expect(body).not.toContain(csvExport.piiMarker);
}
