import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_SEARCH_QUERY,
  TEST_SITE_TITLE,
  navigateToCommunityHome,
  navigateToEvent,
  navigateToGroup,
  navigateToPath,
  navigateToSiteExplore,
  navigateToSiteHome,
} from "../utils";

test.describe("public pages", () => {
  test("site home page loads and displays correctly", async ({ page }) => {
    await navigateToSiteHome(page);

    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: TEST_COMMUNITY_TITLE })
    ).toBeVisible();
  });

  test("community home page loads and displays correctly", async ({ page }) => {
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

    await expect(page.getByText(TEST_COMMUNITY_TITLE)).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Explore all groups" })
    ).toBeVisible();
  });

  test("explore page loads for events and groups", async ({ page }) => {
    await navigateToSiteExplore(page);
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })
    ).toBeVisible();

    await navigateToPath(page, "/explore?entity=groups");
    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_SITE_TITLE })
    ).toBeVisible();
  });

  test("group page displays group information", async ({ page }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG);
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAME })
    ).toBeVisible();
  });

  test("event page displays event information", async ({ page }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG
    );
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_EVENT_NAME })
    ).toBeVisible();
  });

  test("search returns matching groups", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&ts_query=${encodeURIComponent(TEST_SEARCH_QUERY)}`
    );
    await expect(page.getByText(TEST_GROUP_NAME)).toBeVisible();
  });
});
