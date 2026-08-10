import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  expectPaginationNavigation,
  navigateToPath,
} from "../../utils.js";

test.describe("site explore groups page", () => {
  test("moves between group result pages and restores the first card", async ({ page }) => {
    // Paginate seeded group cards with one result per page.
    await expectPaginationNavigation(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}&limit=1&offset=0`,
      "#cards-list article",
    );
  });

  test("restores every group filter and sort option from the URL", async ({ page }) => {
    // Build a URL containing every supported group filter and sort option.
    const filters = new URLSearchParams({
      entity: "groups",
      "community[0]": TEST_COMMUNITY_NAME,
      "group_category[0]": "e2e-category-one",
      "region[0]": "north-america",
      sort_by: "name",
    });

    // Load the filtered groups page.
    await navigateToPath(page, `/explore?${filters.toString()}`);

    // Find the desktop form and verify every control restores its URL value.
    const desktopForm = page.locator("#groups-form");
    await expect(desktopForm).toBeAttached();
    await expect(desktopForm.locator('collapsible-filter[name="community"]')).toHaveAttribute(
      "selected",
      JSON.stringify([TEST_COMMUNITY_NAME]),
    );
    await expect(desktopForm.locator('collapsible-filter[name="group_category"]')).toHaveAttribute(
      "selected",
      JSON.stringify(["e2e-category-one"]),
    );
    await expect(desktopForm.locator('collapsible-filter[name="region"]')).toHaveAttribute(
      "selected",
      JSON.stringify(["north-america"]),
    );
    await expect(page.locator("#sort_selector")).toHaveValue("name");
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
  });

  test("switches sort options and entity while preserving the search", async ({ page }) => {
    // Load a filtered group search before changing its sort and entity.
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}&ts_query=Observability`,
    );

    // Switch to date sorting and wait for the group list to refresh.
    await expect(page.locator("#sort_selector")).toHaveValue("name");
    // Switch to events and verify the existing search value is preserved.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("sort_by=date") &&
          response.ok(),
      ),
      page.locator("#sort_selector").selectOption("date"),
    ]);
    await expect(page.locator("#sort_selector")).toHaveValue("date");

    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/events-section") &&
          response.url().includes("ts_query=Observability") &&
          response.ok(),
      ),
      // The entity selector renders in both drawer and sidebar, so click the
      // desktop sidebar instance that is actually visible at this viewport.
      page.locator("#explore-filters #events-button").click(),
    ]);
    await expect(page.getByPlaceholder("Search events")).toHaveValue("Observability");
    await expect(page.locator("#events-form")).toBeAttached();
  });

  test("opens and dismisses group filters from the mobile backdrop @mobile", async ({ page }) => {
    // Load community groups using the mobile project viewport.
    await navigateToPath(page, `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`);

    // Open the filter drawer and verify its mobile form is available.
    const drawer = page.locator("#drawer-filters");
    const backdrop = page.locator("#drawer-backdrop");
    await page.locator("#open-filters").click();
    await expect(drawer).not.toHaveClass(/-translate-x-full/);
    await expect(page.locator("#groups-form-mobile")).toBeAttached();

    // Dismiss the drawer through its backdrop and verify both become hidden.
    await backdrop.click({ position: { x: 350, y: 50 } });
    await expect(drawer).toHaveClass(/-translate-x-full/);
    await expect(backdrop).toHaveClass(/hidden/);
  });

  test("filters move between the drawer and the sidebar at the lg breakpoint", async ({
    page,
  }) => {
    // Load community groups right below the lg breakpoint.
    await page.setViewportSize({ width: 1023, height: 900 });
    await navigateToPath(page, `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`);

    // Find the layout pieces that swap with the viewport width.
    const desktopFilters = page.locator("#explore-filters");
    const openFiltersButton = page.locator("#open-filters");
    const viewModeControls = page.locator("#view-mode-controls");

    // Verify the drawer trigger replaces the desktop sidebar below lg.
    await expect(openFiltersButton).toBeVisible();
    await expect(desktopFilters).toBeHidden();
    await expect(viewModeControls).toBeVisible();

    // Verify the desktop sidebar replaces the drawer trigger from lg up.
    await page.setViewportSize({ width: 1024, height: 900 });
    await expect(desktopFilters).toBeVisible();
    await expect(openFiltersButton).toBeHidden();

    // Verify the view mode controls only disappear below the md breakpoint.
    await page.setViewportSize({ width: 767, height: 900 });
    await expect(viewModeControls).toBeHidden();
    await expect(page.getByPlaceholder("Search groups")).toBeVisible();
  });

  test("supports searching groups and switching to map view", async ({ page }) => {
    // Load the groups explore page with the community filter applied.
    await navigateToPath(page, `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`);

    // Find the Search groups control.
    const searchInput = page.getByPlaceholder("Search groups");

    // Verify groups render before applying search.
    await expect(searchInput).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    // Submit a group search and wait for the results to refresh.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("ts_query=Observability") &&
          response.ok(),
      ),
      searchInput.fill("Observability").then(() => searchInput.press("Enter")),
    ]);

    // Verify the search narrows the list to the matching group.
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toHaveCount(0);

    // Switch to the map view and wait for list controls to refresh.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("view_mode=map") &&
          response.ok(),
      ),
      page.locator('label[for="map"]').click(),
    ]);

    // Verify map mode renders the map and hides sorting controls.
    await expect(page.locator("#map-box")).toBeVisible();
    await expect(page.locator("#map-box.leaflet-container")).toBeVisible();
    await expect(page.locator("#sort_selector")).toHaveCount(0);

    // Verify the filtered group marker exposes its card and public destination.
    const groupMarker = page.locator(
      `.leaflet-marker-icon.marker-${TEST_GROUP_SLUGS.community1.gamma}`,
    );
    await expect(groupMarker).toBeVisible();
    await groupMarker.hover();
    await expect(page.locator(".leaflet-tooltip")).toContainText(TEST_GROUP_NAMES.gamma);
    await Promise.all([
      page.waitForURL(
        new RegExp(
          `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.gamma}$`,
        ),
      ),
      groupMarker.click(),
    ]);
    await expect(
      page.getByRole("heading", {
        level: 1,
        name: TEST_GROUP_NAMES.gamma,
      }),
    ).toBeVisible();
  });

  test("shows an empty state when no groups match the search", async ({ page }) => {
    // Load the groups explore page with the community filter applied.
    await navigateToPath(page, `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`);

    // Submit a group search that has no matches.
    const searchInput = page.getByPlaceholder("Search groups");
    await expect(searchInput).toBeVisible();

    // Submit the unmatched search query and wait for filtered results.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("ts_query=No%20matching%20group") &&
          response.ok(),
      ),
      searchInput.fill("No matching group").then(() => searchInput.press("Enter")),
    ]);

    // Verify the filtered empty state explains the missing matches.
    await expect(page.getByText("We're sorry!", { exact: true })).toBeVisible();
    await expect(
      page.getByText(
        "We can't seem to find any groups that match your search criteria. You can reset your filters or try a different search.",
      ),
    ).toBeVisible();
  });
});
