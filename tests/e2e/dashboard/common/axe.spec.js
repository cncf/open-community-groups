import { expect, test } from "../../fixtures.js";

import { expectNoAxeViolations } from "../../axe.js";
import { TEST_EVENT_SURVEYS } from "../../data-graphs/surveys.js";
import {
  TEST_APPROVAL_REQUIRED_EVENT,
  TEST_EVENT_ANALYTICS,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_OPEN_CHECK_IN_EVENT,
} from "../../seed.js";
import {
  expectDarkTheme,
  navigateToPath,
  useTheme,
  waitForActionResponse,
  waitForHtmxSettle,
} from "../../utils.js";
import { openAttendeesTab, openInvitationRequestsTab } from "../group/events/attendees-helpers.js";
import {
  openCfsEventSubmissionsTab,
  openDashboardWaitlist,
  openEventSection,
  openEventUpdateFormByName,
} from "../group/events/helpers.js";

// Desktop dashboard tabs only the dark scans cover, shaped like `DASHBOARD_TABS` rows.
const DARK_DASHBOARD_TABS = [
  {
    fixture: "adminCommunityPage",
    name: "community team",
    open: (page) => navigateToPath(page, "/dashboard/community?tab=team"),
    ready: (page) => page.locator("#dashboard-content").getByText("Community Team", { exact: true }),
  },
  {
    fixture: "adminCommunityPage",
    name: "community regions",
    open: (page) => navigateToPath(page, "/dashboard/community?tab=regions"),
    ready: (page) => page.getByRole("button", { name: /^Edit region: / }).first(),
  },
  {
    fixture: "adminCommunityPage",
    name: "community event categories",
    open: (page) => navigateToPath(page, "/dashboard/community?tab=event-categories"),
    ready: (page) => page.getByRole("button", { name: /^Edit event category: / }).first(),
  },
  {
    fixture: "organizerGroupPage",
    name: "group analytics",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=analytics"),
    ready: (page) => page.locator("#members-running-chart"),
  },
  {
    fixture: "organizerGroupPage",
    name: "group members",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=members"),
    ready: (page) => page.getByRole("table", { name: "Members list" }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group team",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=team"),
    ready: (page) => page.locator("#dashboard-content").getByText("Group Team", { exact: true }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group sponsors",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=sponsors"),
    ready: (page) => page.getByRole("table", { name: "Sponsors list" }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group badges",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=badges"),
    ready: (page) => page.locator("#dashboard-content").getByRole("heading", { level: 1, name: "Badges" }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group settings",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=settings"),
    ready: (page) => page.locator("markdown-editor#description .CodeMirror"),
  },
  {
    fixture: "organizerGroupPage",
    name: "group refunds",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=refunds"),
    ready: (page) => page.getByRole("table", { name: "Refunds list" }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group inbox",
    open: (page) => navigateToPath(page, "/dashboard/group?tab=inbox"),
    ready: (page) => page.locator("[data-inbox-list]"),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event analytics",
    open: (page) =>
      openEventSection(page, {
        contentSelector: "#analytics-content",
        eventId: TEST_EVENT_ANALYTICS.pastPaid.id,
        eventName: TEST_EVENT_ANALYTICS.pastPaid.name,
        eventsTab: "past",
        section: "analytics",
      }),
    // The ready marker sits on a hidden JSON script, so wait for the loaded container holding it.
    ready: (page) =>
      page.locator(
        '#analytics-content[data-analytics-state="loaded"]:has([data-event-analytics][data-event-analytics-ready="true"])',
      ),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event surveys",
    open: (page) =>
      openEventSection(page, {
        contentSelector: "#surveys-content",
        eventId: TEST_EVENT_SURVEYS.event.id,
        eventName: TEST_EVENT_SURVEYS.event.name,
        eventsTab: "past",
        section: "surveys",
        tableName: "Event surveys list",
      }),
    ready: (page) => page.locator("#surveys-content").getByRole("table", { name: "Event surveys list" }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event submissions",
    open: (page) => openCfsEventSubmissionsTab(page),
    ready: (page) => page.locator("#submissions-content").getByText("Submissions", { exact: true }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event waitlist",
    open: (page) => openDashboardWaitlist(page),
    ready: (page) => page.locator("#waitlist-content").getByRole("table", { name: "Waitlist entries" }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event invitation requests",
    open: (page) =>
      openInvitationRequestsTab(page, TEST_APPROVAL_REQUIRED_EVENT.name, TEST_APPROVAL_REQUIRED_EVENT.id),
    ready: (page) =>
      page.locator("#invitation-requests-content").getByRole("table", { name: "Invitation requests" }),
  },
  {
    fixture: "organizerGroupPage",
    name: "group event preview",
    open: async (page) => {
      await openEventUpdateFormByName(page, TEST_EVENT_NAMES.alpha[0], TEST_EVENT_IDS.alpha.one);
      await waitForActionResponse(page, () => page.locator("#event-preview-button").click(), {
        method: "POST",
        urlIncludes: "/dashboard/group/events/preview",
      });
    },
    ready: (page) => page.locator("#event-preview-modal"),
  },
  {
    fixture: "pending1Page",
    name: "user invitations",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=invitations"),
    ready: (page) => page.locator("#dashboard-content").getByText("Event Invitations", { exact: true }),
  },
  {
    fixture: "member1Page",
    name: "user groups",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=groups"),
    ready: (page) => page.locator("#dashboard-content").getByText("My Groups", { exact: true }),
  },
  {
    fixture: "member1Page",
    name: "user purchases",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=purchases"),
    ready: (page) => page.locator("#dashboard-content").getByText("Purchases & documents", { exact: true }),
  },
  {
    fixture: "member1Page",
    name: "user badges",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=badges"),
    ready: (page) => page.locator("#dashboard-content").getByRole("heading", { level: 1, name: "Badges" }),
  },
  {
    fixture: "member1Page",
    name: "user notifications",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=notifications"),
    ready: (page) => page.locator("#dashboard-content").getByText("Notifications", { exact: true }),
  },
  {
    fixture: "member1Page",
    name: "user session proposals",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=session-proposals"),
    ready: (page) => page.locator("#dashboard-content").getByText("Session proposals", { exact: true }),
  },
  {
    fixture: "member1Page",
    name: "user submissions",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=submissions"),
    ready: (page) => page.locator("#dashboard-content").getByText("Submissions", { exact: true }),
  },
  {
    fixture: "member1Page",
    name: "user surveys",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=surveys"),
    ready: (page) => page.locator("#dashboard-content").getByText("Surveys", { exact: true }),
  },
  {
    fixture: "member2Page",
    name: "user inbox",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=inbox"),
    ready: (page) => page.locator("[data-inbox-conversation-row]").first(),
  },
  {
    fixture: "member1Page",
    name: "user logs",
    open: (page) => navigateToPath(page, "/dashboard/user?tab=logs"),
    ready: (page) => page.locator("#dashboard-content").getByText("Logs", { exact: true }),
  },
];

// Phone views only the dark scans cover, shaped like `MOBILE_DASHBOARD_TABS` rows. The closed
// menu drawer is only translated off screen, so the sheet is ready once its opener is expanded.
const DARK_MOBILE_DASHBOARD_TABS = [
  {
    fixture: "pending2Page",
    name: "menu sheet",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/user?tab=check-in");
      await page.getByRole("button", { name: "Open dashboard menu" }).click();
    },
    ready: (page) => page.locator('#open-dashboard-menu[aria-expanded="true"]'),
  },
];

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

test.describe("dashboard tabs dark axe scan", () => {
  for (const dashboardTab of [...DASHBOARD_TABS, ...DARK_DASHBOARD_TABS]) {
    test(`${dashboardTab.name} has no critical or serious color violations in dark`, async ({ pageAs }) => {
      // Open the seeded dashboard view in the dark theme and let HTMX finish any swaps.
      const page = await pageAs(dashboardTab.fixture);
      if (dashboardTab.viewport) {
        await page.setViewportSize(dashboardTab.viewport);
      }
      await useTheme(page, { stored: "dark" });
      await dashboardTab.open(page);
      await expectDarkTheme(page);
      await expect(page.locator("#dashboard-content")).toBeVisible();
      await expect(dashboardTab.ready(page)).toBeVisible({ timeout: 15_000 });
      await waitForHtmxSettle(page);

      // Verify the dark colors under the light key plus " dark".
      await expectNoAxeViolations(page, { colorOnly: true, scan: `dashboard ${dashboardTab.name} dark` });
    });
  }

  test("user events has no critical or serious color violations in a dark system theme", async ({
    member1Page,
  }) => {
    // Open the events tab with a dark OS scheme and no stored choice.
    await useTheme(member1Page, { system: "dark" });
    await navigateToPath(member1Page, "/dashboard/user?tab=events");
    await expectDarkTheme(member1Page);
    await expect(
      member1Page.locator("#dashboard-content").getByText("My Events", { exact: true }),
    ).toBeVisible({
      timeout: 15_000,
    });
    await waitForHtmxSettle(member1Page);

    // Verify that System resolves to dark on a dashboard.
    await expectNoAxeViolations(member1Page, { colorOnly: true, scan: "dashboard user events system dark" });
  });
});

test.describe("dashboard dialog dark axe scan", () => {
  test("user check-in dialog has no critical or serious color violations in dark", async ({
    pending2Page,
  }) => {
    // Open the attendee credential in the dark theme.
    await useTheme(pending2Page, { stored: "dark" });
    await navigateToPath(pending2Page, "/dashboard/user?tab=check-in");
    await expectDarkTheme(pending2Page);
    await pending2Page
      .locator("[data-user-check-in-open]", { hasText: TEST_OPEN_CHECK_IN_EVENT.name })
      .click();
    const modal = pending2Page.locator("#user-check-in-modal");
    await expect(modal).toBeVisible();
    await expect(modal.locator("#user-check-in-qr-image")).toBeVisible();

    // Verify the open credential.
    await expectNoAxeViolations(pending2Page, {
      colorOnly: true,
      include: ["#user-check-in-modal"],
      scan: "user check-in dialog dark",
    });
  });
});

test.describe("dashboard tabs mobile dark axe scan @mobile", () => {
  for (const dashboardTab of [...MOBILE_DASHBOARD_TABS, ...DARK_MOBILE_DASHBOARD_TABS]) {
    test(`${dashboardTab.name} has no critical or serious color violations in dark`, async ({ pageAs }) => {
      // Open the seeded view in the dark theme and let HTMX finish any swaps.
      const page = await pageAs(dashboardTab.fixture);
      await useTheme(page, { stored: "dark" });
      await dashboardTab.open(page);
      await expectDarkTheme(page);
      await expect(dashboardTab.ready(page)).toBeVisible({ timeout: 15_000 });
      await waitForHtmxSettle(page);

      // Verify the dark colors under the mobile key plus " dark".
      await expectNoAxeViolations(page, { colorOnly: true, scan: `${dashboardTab.name} mobile dark` });
    });
  }
});
