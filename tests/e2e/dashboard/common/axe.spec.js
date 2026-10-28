import { expect, test } from "../../fixtures.js";

import { expectNoAxeViolations } from "../../axe.js";
import { TEST_EVENT_IDS, TEST_EVENT_NAMES } from "../../seed.js";
import { navigateToPath, waitForHtmxSettle } from "../../utils.js";
import { openAttendeesTab } from "../group/events/attendees-helpers.js";
import { openEventUpdateFormByName } from "../group/events/helpers.js";

// Representative dashboard tabs. `open` leaves the page on the scanned view without saving;
// `ready` is visible once the view, including the components allowlist entries match, rendered.
const DASHBOARD_TABS = [
  {
    fixture: "adminCommunityPage",
    name: "community groups",
    open: (page) => navigateToPath(page, "/dashboard/community?tab=groups"),
    ready: (page) => page.getByRole("button", { name: /^Edit group: / }).first(),
  },
  {
    fixture: "adminCommunityPage",
    name: "community settings",
    open: (page) => navigateToPath(page, "/dashboard/community?tab=settings"),
    ready: (page) => page.locator("markdown-editor#description .CodeMirror"),
  },
  {
    fixture: "organizerGroupPage",
    name: "group events",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=events"),
    ready: (page) => page.locator("#upcoming-content"),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event editor",
    open: (page) => openEventUpdateFormByName(page, TEST_EVENT_NAMES.alpha[0], TEST_EVENT_IDS.alpha.one),
    ready: (page) => page.locator('[data-event-page="update"] markdown-editor#description .CodeMirror'),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event attendees",
    open: (page) => openAttendeesTab(page, TEST_EVENT_NAMES.alpha[0], TEST_EVENT_IDS.alpha.one),
    ready: (page) => page.locator("#attendees-content [data-user-profile-modal]").first(),
  },
  {
    fixture: "member1Page",
    name: "user events",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=events"),
    ready: (page) => page.locator("#dashboard-content").getByText("My Events", { exact: true }),
  },
  {
    fixture: "member1Page",
    name: "user account",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=account"),
    ready: (page) => page.locator("#user-details-form timezone-selector #timezone-selector-button"),
  },
];

test.describe("dashboard tabs axe scan", () => {
  for (const dashboardTab of DASHBOARD_TABS) {
    test(`${dashboardTab.name} has no critical or serious axe violations`, async ({ pageAs }) => {
      // Open the seeded dashboard view and let HTMX finish any swaps before scanning.
      const page = await pageAs(dashboardTab.fixture);
      await dashboardTab.open(page);
      await expect(page.locator("#dashboard-content")).toBeVisible();
      await expect(dashboardTab.ready(page)).toBeVisible({ timeout: 15_000 });
      await waitForHtmxSettle(page);

      // Verify the rendered view against the critical/serious baseline.
      await expectNoAxeViolations(page, { scan: `dashboard ${dashboardTab.name}` });
    });
  }
});
