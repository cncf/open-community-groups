import { expect, test } from "../../fixtures.js";
import { buildE2eUrl, navigateToPath, waitForActionResponse } from "../../utils.js";

const DASHBOARD_ROUTES = ["/dashboard/community", "/dashboard/group", "/dashboard/user"];

const MOBILE_WARNING = "This dashboard is not optimized yet for mobile devices";

// Users without an accepted team role; pending1 only has pending (unaccepted) team invitations.
const TEAMLESS_USERS = [
  { fixture: "member2Page", label: "plain member" },
  { fixture: "pending1Page", label: "pending invitee" },
];

test.describe("dashboard access and shared behavior", () => {
  for (const route of DASHBOARD_ROUTES) {
    test(`requires login for ${route}`, async ({ page }) => {
      // Open the protected dashboard route as a guest.
      await navigateToPath(page, route);

      // Verify the login page keeps the requested route as its return destination.
      await expect(page).toHaveURL(
        (url) => url.pathname === "/log-in" && url.searchParams.get("next_url") === route,
      );
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    });
  }

  for (const { fixture, label } of TEAMLESS_USERS) {
    for (const route of ["/dashboard/community", "/dashboard/group"]) {
      test(`forbids a ${label} from ${route}`, async ({ pageAs }) => {
        // Request the privileged dashboard route with a session that has no accepted team role.
        const page = await pageAs(fixture);
        const response = await page.goto(buildE2eUrl(route));

        // Verify the user is sent back to their own dashboard invitations.
        expect(response).not.toBeNull();
        expect(response.status()).toBe(200);
        await expect(page).toHaveURL(buildE2eUrl("/dashboard/user?tab=invitations"));
      });
    }
  }

  test.describe("mobile experience @mobile", () => {
    test("community dashboard shows the mobile unsupported state", async ({ adminCommunityPage }) => {
      // Load the community dashboard on a mobile viewport.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

      // Verify community dashboard shows the mobile unsupported state.
      await expect(adminCommunityPage.getByText(MOBILE_WARNING, { exact: true })).toBeVisible();
      await expect(adminCommunityPage.locator("#dashboard-main-content")).toBeHidden();

      // Verify no drawer trigger is offered, since every community section is desktop only.
      await expect(adminCommunityPage.getByRole("button", { name: "Open dashboard menu" })).toHaveCount(0);
    });

    test("group dashboard opens mobile check-in from its only available option", async ({
      organizerGroupPage,
    }) => {
      // Load the group dashboard on a mobile viewport.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Verify group dashboard shows the mobile unsupported state.
      await expect(organizerGroupPage.getByText(MOBILE_WARNING, { exact: true })).toBeVisible();
      await expect(organizerGroupPage.locator("#dashboard-main-content")).toBeHidden();
      const drawer = await openMobileDashboardDrawer(organizerGroupPage);
      const checkInLink = drawer.getByRole("link", {
        name: "Check-In",
        exact: true,
      });
      await expect(drawer.locator("a[hx-get]:visible")).toHaveCount(1);
      await expect(checkInLink).toHaveAttribute("hx-get", "/dashboard/group?tab=check-in");

      // Follow the available option and verify HTMX replaces the placeholder.
      await waitForActionResponse(organizerGroupPage, () => checkInLink.click(), {
        method: "GET",
        urlEndsWith: "/dashboard/group?tab=check-in",
      });
      await expect(organizerGroupPage).toHaveURL(/\/dashboard\/group\?tab=check-in$/u);
      await expect(organizerGroupPage.getByText(MOBILE_WARNING, { exact: true })).toBeHidden();
      await expect(organizerGroupPage.locator("#dashboard-main-content")).toBeVisible();
      await expect(organizerGroupPage.getByRole("heading", { name: "Check-In" })).toBeVisible();
    });

    test("user dashboard opens mobile check-in from its only available option", async ({ member1Page }) => {
      // Load the user dashboard on a mobile viewport.
      await navigateToPath(member1Page, "/dashboard/user?tab=events");

      // Verify user dashboard shows the mobile unsupported state.
      await expect(member1Page.getByText(MOBILE_WARNING, { exact: true })).toBeVisible();
      await expect(member1Page.locator("#dashboard-main-content")).toBeHidden();
      const drawer = await openMobileDashboardDrawer(member1Page);
      const checkInLink = drawer.getByRole("link", {
        name: "Check-In",
        exact: true,
      });
      await expect(drawer.locator("a[hx-get]:visible")).toHaveCount(1);
      await expect(checkInLink).toHaveAttribute("hx-get", "/dashboard/user?tab=check-in");

      // Follow the available option and verify the check-in surface replaces the page.
      await waitForActionResponse(member1Page, () => checkInLink.click(), {
        method: "GET",
        urlEndsWith: "/dashboard/user?tab=check-in",
      });
      await expect(member1Page).toHaveURL(/\/dashboard\/user\?tab=check-in$/u);
      await expect(member1Page.getByText(MOBILE_WARNING, { exact: true })).toBeHidden();
      await expect(member1Page.locator("#dashboard-main-content")).toBeVisible();
      await expect(member1Page.getByRole("heading", { name: "Check-In" })).toBeVisible();
    });

    test("desktop version mode replaces the mobile unsupported state", async ({ member1Page }) => {
      // Load unsupported user content on the mobile viewport.
      await navigateToPath(member1Page, "/dashboard/user?tab=events");
      const main = member1Page.locator("#dashboard-main-content");
      const warning = member1Page.getByText(MOBILE_WARNING, { exact: true });

      // Verify the placeholder points touch users to the desktop version entry.
      await expect(warning).toBeVisible();
      await expect(main).toBeHidden();
      await expect(member1Page.getByText(/load the desktop version from the user menu/u)).toBeVisible();

      // Enable the desktop version from the user menu and wait for the reload.
      await member1Page.locator('#user-dropdown-button[data-logged-in="true"]').click();
      const desktopVersionItem = member1Page
        .locator("#user-dropdown")
        .getByRole("menuitem", { name: "Desktop version" });
      await expect(desktopVersionItem).toBeVisible();
      await Promise.all([member1Page.waitForEvent("load"), desktopVersionItem.click()]);

      // Verify the dashboard content replaces the placeholder in desktop mode.
      await expect
        .poll(() => member1Page.evaluate(() => document.documentElement.dataset.viewportMode))
        .toBe("desktop");
      await expect(warning).toBeHidden();
      await expect(main).toBeVisible();
      await expect(member1Page.getByRole("button", { name: "Open dashboard menu" })).toBeHidden();

      // Verify the mobile version entry restores the responsive layout. The 1280px layout
      // exceeds the mobile visual viewport, so drive the menu through DOM events instead of
      // emulated pointer coordinates.
      await member1Page.locator('#user-dropdown-button[data-logged-in="true"]').dispatchEvent("click");
      const mobileVersionItem = member1Page
        .locator("#user-dropdown")
        .getByRole("menuitem", { name: "Mobile version" });
      await expect(mobileVersionItem).toBeVisible();
      await Promise.all([member1Page.waitForEvent("load"), mobileVersionItem.dispatchEvent("click")]);
      await expect(warning).toBeVisible();
      await expect(main).toBeHidden();
    });
  });
});

/** Opens the mobile dashboard drawer and returns its visible panel. */
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
