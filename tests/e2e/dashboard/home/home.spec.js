import { expect, test } from "../../fixtures.js";

import { buildE2eUrl, navigateToPath } from "../../utils.js";

const DASHBOARD_ROUTES = [
  "/dashboard/community",
  "/dashboard/group",
  "/dashboard/user",
];

const MOBILE_WARNING = "This dashboard is not optimized yet for mobile devices";

test.describe("dashboard home", () => {
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
    });

    test("group dashboard shows the mobile unsupported state", async ({
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
    });

    test("user dashboard shows the mobile unsupported state", async ({
      member1Page,
    }) => {
      // Load the user dashboard on a mobile viewport.
      await navigateToPath(member1Page, "/dashboard/user?tab=events");

      // Verify user dashboard shows the mobile unsupported state.
      await expect(
        member1Page.getByText(MOBILE_WARNING, { exact: true }),
      ).toBeVisible();
      await expect(member1Page.locator("#dashboard-main-content")).toBeHidden();
    });
  });
});
