import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  TEST_SITE_TITLE,
  TEST_UNPUBLISHED_EVENT,
} from "../../seed.js";
import { navigateToPath, navigateToSiteHome, waitForActionResponse } from "../../utils.js";

const ALPHA_GROUP_PATH = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`;

const BOOSTED_MISSING_PATH = "/missing-e2e-boosted";

const NESTED_NOT_FOUND_CASES = [
  {
    name: "an unknown group in a valid community",
    path: `/${TEST_COMMUNITY_NAME}/group/missing-e2e-group`,
  },
  {
    name: "an unknown event in a valid group",
    path: `${ALPHA_GROUP_PATH}/event/missing-e2e-event`,
  },
  {
    hiddenText: TEST_UNPUBLISHED_EVENT.name,
    name: "an unpublished event",
    path: `${ALPHA_GROUP_PATH}/event/${TEST_UNPUBLISHED_EVENT.slug}`,
  },
];

test.describe("site not found page", () => {
  test("explains the missing page and provides a working recovery path @smoke", async ({ page }) => {
    // Load a public route that does not exist and verify its HTTP status.
    await waitForActionResponse(page, () => navigateToPath(page, "/missing-e2e-page"), {
      method: "GET",
      pathname: "/missing-e2e-page",
      settle: false,
      status: 404,
    });

    // Verify the recovery copy describes the missing page.
    await expect(page.getByText("Page not found", { exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();
    await expect(
      page.getByText("The page you requested may have moved, been deleted, or the link may be incorrect.", {
        exact: true,
      }),
    ).toBeVisible();

    // Follow the recovery link and verify it returns to the home page.
    const homeLink = page.getByRole("link", { name: "Go to home page" });
    await expect(homeLink).toHaveAttribute("href", "/");
    await homeLink.click();
    await expect(page).toHaveURL(/\/$/);
  });

  test("boosted navigation swaps in the not-found page and keeps history", async ({ page }) => {
    // Load the home page and add a boosted link, since no seeded link targets a missing page.
    await navigateToSiteHome(page);
    await page.evaluate((path) => {
      const link = document.createElement("a");
      link.href = path;
      link.setAttribute("hx-boost", "true");
      link.setAttribute("hx-target", "body");
      link.textContent = "Missing boosted page";
      document.body.prepend(link);
      window.htmx.process(link);
    }, BOOSTED_MISSING_PATH);

    // Follow the boosted link and verify the not-found response contract.
    const response = await waitForActionResponse(
      page,
      () => page.getByRole("link", { name: "Missing boosted page", exact: true }).click(),
      { method: "GET", pathname: BOOSTED_MISSING_PATH, status: 404 },
    );
    expect(response.request().headers()["hx-boosted"]).toBe("true");
    expect(response.headers()["x-ocg-not-found"]).toBe("true");

    // Verify the not-found page replaced the body and the URL was pushed.
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();
    await expect(page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })).toBeHidden();
    await expect(page).toHaveURL(new RegExp(`${BOOSTED_MISSING_PATH}$`));

    // Return through browser history and verify the home page is restored.
    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })).toBeVisible();
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeHidden();
  });

  test("recovery content remains visible on mobile @mobile", async ({ page }) => {
    // Load an unknown route using the mobile project viewport.
    await navigateToPath(page, "/missing-e2e-page-mobile");

    // Verify the recovery content remains within the viewport.
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeInViewport();
    await expect(page.getByRole("link", { name: "Go to home page" })).toBeInViewport();
  });

  for (const notFoundCase of NESTED_NOT_FOUND_CASES) {
    test(`returns 404 for ${notFoundCase.name}`, async ({ page }) => {
      // Verify the valid parent does not mask the not-found response.
      await waitForActionResponse(page, () => navigateToPath(page, notFoundCase.path), {
        method: "GET",
        pathname: notFoundCase.path,
        settle: false,
        status: 404,
      });
      await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();

      // Verify private details stay hidden behind the not-found response.
      if (notFoundCase.hiddenText) {
        await expect(page.locator("body")).not.toContainText(notFoundCase.hiddenText);
      }
    });
  }
});
