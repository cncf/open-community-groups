import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  TEST_UNPUBLISHED_EVENT,
  navigateToPath,
} from "../../utils.js";

test.describe("site not found page", () => {
  test("explains the missing page and provides a working recovery path", async ({ page }) => {
    // Watch the missing route so its HTTP status can be verified.
    const responsePromise = page.waitForResponse(
      (response) => new URL(response.url()).pathname === "/missing-e2e-page",
    );

    // Load a public route that does not exist.
    await navigateToPath(page, "/missing-e2e-page");

    // Verify the response and recovery copy describe the missing page.
    const response = await responsePromise;
    expect(response.status()).toBe(404);
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

  test("recovery content remains visible on mobile @mobile", async ({ page }) => {
    // Load an unknown route using the mobile project viewport.
    await navigateToPath(page, "/missing-e2e-page-mobile");

    // Verify the recovery content remains within the viewport.
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeInViewport();
    await expect(page.getByRole("link", { name: "Go to home page" })).toBeInViewport();
  });

  test("returns 404 for an unknown group in a valid community", async ({ page }) => {
    // Watch the nested group route before loading the unknown slug.
    const path = `/${TEST_COMMUNITY_NAME}/group/missing-e2e-group`;
    const responsePromise = page.waitForResponse((response) => new URL(response.url()).pathname === path);

    // Verify the valid community does not mask the missing group response.
    await navigateToPath(page, path);
    expect((await responsePromise).status()).toBe(404);
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();
  });

  test("returns 404 for an unknown event in a valid group", async ({ page }) => {
    // Watch the nested event route before loading the unknown slug.
    const path = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/missing-e2e-event`;
    const responsePromise = page.waitForResponse((response) => new URL(response.url()).pathname === path);

    // Verify the valid group does not mask the missing event response.
    await navigateToPath(page, path);
    expect((await responsePromise).status()).toBe(404);
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();
  });

  test("returns 404 for an unpublished event", async ({ page }) => {
    // Watch the seeded unpublished event route before opening it publicly.
    const path = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_UNPUBLISHED_EVENT.slug}`;
    const responsePromise = page.waitForResponse((response) => new URL(response.url()).pathname === path);

    // Verify unpublished event details stay private behind a not-found response.
    await navigateToPath(page, path);
    expect((await responsePromise).status()).toBe(404);
    await expect(page.getByRole("heading", { name: "We could not find that page" })).toBeVisible();
    await expect(page.locator("body")).not.toContainText(TEST_UNPUBLISHED_EVENT.name);
  });
});
