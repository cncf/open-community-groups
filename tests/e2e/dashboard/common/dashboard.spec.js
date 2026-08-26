import { expect, test } from "../../fixtures.js";

import {
  buildE2eUrl,
  navigateToPath,
  waitForActionResponse,
} from "../../utils.js";

const DASHBOARD_ROUTES = [
  "/dashboard/community",
  "/dashboard/group",
  "/dashboard/user",
];

const MOBILE_WARNING = "This dashboard is not optimized yet for mobile devices";

const openMobileDashboardDrawer = async (page) => {
  const openMenuButton = page.getByRole("button", {
    name: "Open dashboard menu",
  });
  await expect(openMenuButton).toBeVisible();
  await openMenuButton.click();

  const drawer = page.locator("#dashboard-menu-drawer");
  await expect(drawer).toBeVisible();

  return drawer;
};

test.describe("dashboard access and shared behavior", () => {
  for (const route of DASHBOARD_ROUTES) {
    test(`requires login for ${route}`, async ({ page }) => {
      // Open the protected dashboard route as a guest.
      await navigateToPath(page, route);

      // Verify requires login for route.
      await expect(page).toHaveURL(/\/log-in/);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    });
  }

  for (const route of ["/dashboard/community", "/dashboard/group"]) {
    test(`forbids a plain member from ${route}`, async ({ member2Page }) => {
      // Request the privileged dashboard route with a regular member session.
      const response = await member2Page.goto(buildE2eUrl(route));

      // Verify members without team roles are sent back to their own dashboard.
      expect(response).not.toBeNull();
      expect(response.status()).toBe(200);
      await expect(member2Page).toHaveURL(
        buildE2eUrl("/dashboard/user?tab=invitations"),
      );
    });
  }

  test("community viewers cannot call protected write endpoints", async ({
    communityViewerPage,
  }) => {
    // Probe one endpoint from every community write-permission bucket.
    const protectedRequests = [
      { method: "POST", path: "/dashboard/community/groups/add" },
      { method: "PUT", path: "/dashboard/community/settings/update" },
      { method: "POST", path: "/dashboard/community/event-categories/add" },
      { method: "POST", path: "/dashboard/community/team/add" },
    ];

    // Verify read access never grants direct mutation access.
    for (const protectedRequest of protectedRequests) {
      const response = await communityViewerPage.request.fetch(
        buildE2eUrl(protectedRequest.path),
        {
          form: {},
          method: protectedRequest.method,
        },
      );

      expect(response.status()).toBe(403);
    }
  });

  test("group viewers cannot call protected write endpoints", async ({
    groupViewerPage,
  }) => {
    // Probe one endpoint from every group write-permission bucket.
    const protectedRequests = [
      { method: "POST", path: "/dashboard/group/badges" },
      { method: "POST", path: "/dashboard/group/events/add" },
      { method: "POST", path: "/dashboard/group/notifications" },
      { method: "PUT", path: "/dashboard/group/settings/update" },
      { method: "POST", path: "/dashboard/group/sponsors/add" },
      { method: "POST", path: "/dashboard/group/team/add" },
    ];

    // Verify read access never grants direct mutation access.
    for (const protectedRequest of protectedRequests) {
      const response = await groupViewerPage.request.fetch(
        buildE2eUrl(protectedRequest.path),
        {
          form: {},
          method: protectedRequest.method,
        },
      );

      expect(response.status()).toBe(403);
    }
  });

  test.describe("mobile experience @mobile", () => {
    test("community dashboard shows the mobile unsupported state", async ({
      adminCommunityPage,
    }) => {
      // Load the community dashboard on a mobile viewport.
      await navigateToPath(
        adminCommunityPage,
        "/dashboard/community?tab=groups",
      );

      // Verify community dashboard shows the mobile unsupported state.
      await expect(
        adminCommunityPage.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(
        adminCommunityPage.locator("#dashboard-main-content"),
      ).toBeHidden();
      const drawer = await openMobileDashboardDrawer(adminCommunityPage);
      await expect(drawer.locator("a[hx-get]:visible")).toHaveCount(0);
      await expect(
        drawer.getByRole("button", { name: "Log out" }),
      ).toBeVisible();
    });

    test("group dashboard opens mobile check-in from its only available option", async ({
      organizerGroupPage,
    }) => {
      // Load the group dashboard on a mobile viewport.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Verify group dashboard shows the mobile unsupported state.
      await expect(
        organizerGroupPage.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(
        organizerGroupPage.locator("#dashboard-main-content"),
      ).toBeHidden();
      const drawer = await openMobileDashboardDrawer(organizerGroupPage);
      const checkInLink = drawer.getByRole("link", {
        name: "Check-In",
        exact: true,
      });
      await expect(drawer.locator("a[hx-get]:visible")).toHaveCount(1);
      await expect(checkInLink).toHaveAttribute(
        "hx-get",
        "/dashboard/group?tab=check-in",
      );

      // Follow the available option and verify HTMX replaces the placeholder.
      await waitForActionResponse(organizerGroupPage, () => checkInLink.click(), {
        method: "GET",
        urlEndsWith: "/dashboard/group?tab=check-in",
      });
      await expect(organizerGroupPage).toHaveURL(
        /\/dashboard\/group\?tab=check-in$/u,
      );
      await expect(
        organizerGroupPage.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeHidden();
      await expect(
        organizerGroupPage.locator("#dashboard-main-content"),
      ).toBeVisible();
      await expect(
        organizerGroupPage.getByRole("heading", { name: "Check-In" }),
      ).toBeVisible();
    });

    test("user dashboard opens mobile check-in from its only available option", async ({
      member1Page,
    }) => {
      // Load the user dashboard on a mobile viewport.
      await navigateToPath(member1Page, "/dashboard/user?tab=events");

      // Verify user dashboard shows the mobile unsupported state.
      await expect(
        member1Page.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(member1Page.locator("#dashboard-main-content")).toBeHidden();
      const drawer = await openMobileDashboardDrawer(member1Page);
      const checkInLink = drawer.getByRole("link", {
        name: "Check-In",
        exact: true,
      });
      await expect(drawer.locator("a[hx-get]:visible")).toHaveCount(1);
      await expect(checkInLink).toHaveAttribute(
        "hx-get",
        "/dashboard/user?tab=check-in",
      );

      // Follow the available option and verify the check-in surface replaces the page.
      await waitForActionResponse(member1Page, () => checkInLink.click(), {
        method: "GET",
        urlEndsWith: "/dashboard/user?tab=check-in",
      });
      await expect(member1Page).toHaveURL(
        /\/dashboard\/user\?tab=check-in$/u,
      );
      await expect(
        member1Page.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeHidden();
      await expect(member1Page.locator("#dashboard-main-content")).toBeVisible();
      await expect(
        member1Page.getByRole("heading", { name: "Check-In" }),
      ).toBeVisible();
    });

    test("keeps the drawer and placeholder aligned at the md breakpoint", async ({
      member1Page,
    }) => {
      // Load unsupported user content at the first desktop width.
      await member1Page.setViewportSize({ width: 768, height: 900 });
      await navigateToPath(member1Page, "/dashboard/user?tab=events");
      const main = member1Page.locator("#dashboard-main-content");
      const openMenuButton = member1Page.getByRole("button", {
        name: "Open dashboard menu",
      });
      const warning = member1Page.getByText(MOBILE_WARNING, { exact: true });
      await expect(main).toBeVisible();
      await expect(openMenuButton).toBeHidden();
      await expect(warning).toBeHidden();

      // Cross below md and verify the placeholder always has its drawer trigger.
      await member1Page.setViewportSize({ width: 767, height: 900 });
      await expect(main).toBeHidden();
      await expect(warning).toBeVisible();
      await expect(openMenuButton).toBeVisible();
      await openMobileDashboardDrawer(member1Page);

      // Return to md and verify the static sidebar and content replace mobile state.
      await member1Page.setViewportSize({ width: 768, height: 900 });
      await expect(main).toBeVisible();
      await expect(warning).toBeHidden();
      await expect(openMenuButton).toBeHidden();
    });
  });
});
