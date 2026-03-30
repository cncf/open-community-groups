import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  getSectionLink,
  navigateToGroup,
} from "../../utils";

test.describe("group page", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
  });

  test("renders summary sections and seeded upcoming content", async ({ page }) => {
    await expect(
      page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha }),
    ).toBeVisible();
    await expect(page.locator("breadcrumb-nav")).toBeVisible();
    await expect(page.getByText("North America", { exact: true })).toBeVisible();
    await expect(page.getByText(/\d+\s+members/, { exact: false })).toBeVisible();

    await expect(page.getByText("Next event", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "See details" })).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`,
    );

    await expect(page.getByText("Location", { exact: true })).toBeVisible();
    await expect(page.getByText("Location not provided", { exact: true })).toBeVisible();

    await expect(page.getByText("Upcoming Events", { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[2], { exact: true })).toBeVisible();

    await expect(page.getByText("Past Events", { exact: true })).toBeVisible();
    await expect(page.getByText("Past Event For Filtering", { exact: true })).toBeVisible();
  });

  test("renders organizers and sponsors sections from seeded data", async ({ page }) => {
    await expect(page.getByText("Organizers", { exact: true })).toBeVisible();
    await expect(page.getByText("E2E Organizer One", { exact: true })).toBeVisible();

    await expect(page.getByText("Sponsors", { exact: true })).toBeVisible();
    await expect(page.getByText("Tech Corp", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "Tech Corp" })).toHaveAttribute(
      "href",
      "https://techcorp.example.com",
    );
  });
});

test.describe("group page - responsive links", () => {
  test("see all events links use the group-scoped explore filters on desktop", async ({
    page,
  }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    const expectedUpcomingHref =
      `/explore?entity=events&group[0]=${TEST_GROUP_SLUGS.community1.alpha}` +
      `&community[0]=${TEST_COMMUNITY_NAME}`;

    await expect(
      getSectionLink(page, "Upcoming Events", "See all events", "desktop"),
    ).toHaveAttribute("href", expectedUpcomingHref);

    await expect(
      getSectionLink(page, "Past Events", "See all events", "desktop"),
    ).toHaveAttribute(
      "href",
      new RegExp(
        String.raw`^/explore\?entity=events&group\[0\]=${TEST_GROUP_SLUGS.community1.alpha}` +
          String.raw`&community\[0\]=${TEST_COMMUNITY_NAME}&date_from=1900-01-01` +
          String.raw`&sort_direction=desc&date_to=\d{4}-\d{2}-\d{2}$`,
      ),
    );
  });

  test("see all events links are available on mobile @mobile", async ({ page }) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    await expect(
      getSectionLink(page, "Upcoming Events", "See all events", "mobile"),
    ).toBeVisible();
    await expect(
      getSectionLink(page, "Past Events", "See all events", "mobile"),
    ).toBeVisible();
  });
});
