import { expect, test } from "../../fixtures.js";

import { expectNoAxeViolations } from "../../axe.js";
import { TEST_EVENT_IDS, TEST_EVENT_NAMES } from "../../seed.js";
import { navigateToPath, waitForHtmxSettle } from "../../utils.js";
import { openAttendeesTab } from "../group/events/attendees-helpers.js";
import { openEventUpdateFormByName } from "../group/events/helpers.js";

// Representative dashboard tabs. `open` leaves the page on the scanned view without saving;
// `ready` is visible once the view, including the components allowlist entries match, rendered.
// `viewport` (optional) is set before `open`, for views whose markup differs below xl.
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
    fixture: "adminCommunityPage",
    name: "community analytics",
    open: (page) => navigateToPath(page, "/dashboard/community?tab=analytics"),
    ready: (page) => page.getByRole("tablist", { name: "Analytics tabs" }),
    viewport: { width: 1024, height: 900 },
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

// Dashboard tabs rendered on phones, with their own scan keys. `fixture` signs in the page.
const MOBILE_DASHBOARD_TABS = [
  {
    fixture: "pending2Page",
    name: "check-in",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=check-in"),
    ready: (page) => page.locator("[data-user-check-in-open]").first(),
  },
  {
    fixture: "checkInManagerGroupPage",
    name: "group check-in",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=check-in"),
    ready: (page) => page.locator("[data-group-check-in-open]").first(),
  },
  {
    fixture: "pending1Page",
    name: "invitations",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=invitations"),
    ready: (page) => page.getByRole("button", { name: "Approve" }).first(),
  },
];

test.describe("dashboard tabs axe scan", () => {
  for (const dashboardTab of DASHBOARD_TABS) {
    test(`${dashboardTab.name} has no critical or serious axe violations`, async ({ pageAs }) => {
      // Open the seeded dashboard view and let HTMX finish any swaps before scanning.
      const page = await pageAs(dashboardTab.fixture);
      if (dashboardTab.viewport) {
        await page.setViewportSize(dashboardTab.viewport);
      }
      await dashboardTab.open(page);
      await expect(page.locator("#dashboard-content")).toBeVisible();
      await expect(dashboardTab.ready(page)).toBeVisible({ timeout: 15_000 });
      await waitForHtmxSettle(page);

      // Verify the rendered view against the critical/serious baseline.
      await expectNoAxeViolations(page, { scan: `dashboard ${dashboardTab.name}` });
    });
  }
});

test.describe("dashboard tabs mobile axe scan @mobile", () => {
  for (const dashboardTab of MOBILE_DASHBOARD_TABS) {
    test(`${dashboardTab.name} has no critical or serious axe violations`, async ({ pageAs }) => {
      // Open the seeded tab and let HTMX finish any swaps before scanning.
      const page = await pageAs(dashboardTab.fixture);
      await dashboardTab.open(page);
      await expect(dashboardTab.ready(page)).toBeVisible({ timeout: 15_000 });
      await waitForHtmxSettle(page);

      // Verify the rendered tab against the critical/serious baseline.
      await expectNoAxeViolations(page, { scan: `${dashboardTab.name} mobile` });
    });
  }
});
