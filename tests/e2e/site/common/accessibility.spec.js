import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_REGISTRATION_QUESTIONS_EVENT,
} from "../../seed.js";
import { navigateToEvent, navigateToPath, navigateToSiteHome } from "../../utils.js";
import { getAttendButton, waitForAttendanceState } from "../event/helpers.js";

const PUBLIC_LANDMARK_PAGES = [
  {
    name: "home",
    path: "/",
    ready: (page) => page.getByRole("heading", { level: 1 }),
  },
  {
    name: "explore",
    path: `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    ready: (page) => page.getByPlaceholder("Search events"),
  },
  {
    name: "event",
    path: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`,
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_EVENT_NAME }),
  },
  {
    name: "group",
    path: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`,
    ready: (page) => page.getByRole("heading", { level: 1, name: TEST_GROUP_NAME }),
  },
];

test.describe("site structural accessibility", () => {
  for (const landmarkPage of PUBLIC_LANDMARK_PAGES) {
    test(`${landmarkPage.name} exposes the shared public landmarks`, async ({ page }) => {
      // Load a seeded public page before checking its application shell.
      await navigateToPath(page, landmarkPage.path);
      await expect(landmarkPage.ready(page)).toBeVisible();

      // Verify the shared shell landmarks stay unique; event/group pages may also render breadcrumbs.
      await expect(page.getByRole("banner")).toHaveCount(1);
      await expect(page.getByRole("main")).toHaveCount(1);
      await expect(page.getByRole("navigation", { name: "Main navigation" })).toHaveCount(1);
      await expect(page.getByRole("contentinfo", { name: "Site footer" })).toHaveCount(1);
    });

    test(`${landmarkPage.name} images have alternative text or are hidden`, async ({ page }) => {
      // Load a seeded public page before scanning rendered image elements.
      await navigateToPath(page, landmarkPage.path);
      await expect(landmarkPage.ready(page)).toBeVisible();

      // Verify every rendered image has an alt attribute or is explicitly hidden from assistive tech.
      const inaccessibleImages = await page
        .locator("img")
        .evaluateAll((images) =>
          images
            .filter(
              (image) =>
                !image.hasAttribute("alt") && image.getAttribute("aria-hidden")?.toLowerCase() !== "true",
            )
            .map((image) => image.currentSrc || image.getAttribute("src") || image.outerHTML),
        );
      expect(inaccessibleImages).toEqual([]);
    });
  }

  test("skip link and guest header menu are keyboard operable", async ({ page }) => {
    // Load the home page and wait for the guest menu to replace its loading state.
    await navigateToSiteHome(page);
    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="false"]');
    await expect(userMenuButton).toBeVisible();

    // Verify the first tab stop exposes the skip link.
    await page.keyboard.press("Tab");
    const skipLink = page.getByRole("link", { name: "Skip to main content" });
    await expect(skipLink).toBeFocused();
    await expect(skipLink).toHaveAttribute("href", "#main-content");

    // Tab through the desktop navigation into the user menu and activate it with Enter.
    for (let tabIndex = 0; tabIndex < 5; tabIndex += 1) {
      await page.keyboard.press("Tab");
    }
    await expect(userMenuButton).toBeFocused();
    await page.keyboard.press("Enter");
    const userMenu = page.locator("#user-dropdown");
    await expect(userMenu).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Log in" })).toBeVisible();
  });

  test("login form controls are labelled", async ({ page }) => {
    // Load the public login form.
    await navigateToPath(page, "/log-in");

    // Verify form controls expose their labels and submit action.
    const form = page.getByRole("form", { name: "Log In" });
    await expect(form).toBeVisible();
    await expect(form.getByLabel("Username")).toHaveAttribute("name", "username");
    await expect(form.getByLabel("Password")).toHaveAttribute("name", "password");
    await expect(form.getByRole("button", { name: "Sign In" })).toBeVisible();
  });

  test("registration questions dialog is named, modal, and traps focus", async ({ emptyUserPage }) => {
    // Open a seeded public event whose attendance action shows a registration dialog.
    await navigateToEvent(
      emptyUserPage,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_REGISTRATION_QUESTIONS_EVENT.slug,
    );
    await waitForAttendanceState(emptyUserPage);

    // Open the dialog from the keyboard so focus restoration has a real origin.
    const attendButton = getAttendButton(emptyUserPage);
    await expect(attendButton).toBeVisible();
    await attendButton.focus();
    await attendButton.press("Enter");

    // Verify the dialog exposes modal semantics and wraps keyboard focus.
    const dialog = emptyUserPage.getByRole("dialog", { name: "Registration questions" });
    await expect(dialog).toBeVisible();
    await expect(dialog).toHaveAttribute("aria-modal", "true");
    const closeButton = dialog.getByRole("button", { name: "Close modal" });
    await expect(closeButton).toBeFocused();
    await closeButton.press("Shift+Tab");
    await expect(dialog.getByRole("button", { name: "Continue" })).toBeFocused();

    // Verify Escape closes the dialog and restores focus to the opener.
    await emptyUserPage.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
    await expect(attendButton).toBeFocused();
  });
});
