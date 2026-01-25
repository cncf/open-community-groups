/**
 * E2E tests for the event page template.
 */

import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  navigateToEvent,
} from "../utils";

/** Alpha Event One seed data gate. */
const isAlphaEventOne = TEST_EVENT_SLUG === "alpha-event-1";

test.describe("event page", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );
  });

  /** Breadcrumb. */
  test("breadcrumb navigation is visible", async ({ page }) => {
    const breadcrumb = page.locator("breadcrumb-nav");
    await expect(breadcrumb).toBeVisible();
  });

  /** Event header. */
  test("event name displays as h1 heading", async ({ page }) => {
    const heading = page.getByRole("heading", {
      level: 1,
      name: TEST_EVENT_NAME,
    });
    await expect(heading).toBeVisible();
  });

  test("group link displays and links correctly", async ({ page }) => {
    const groupLink = page.getByRole("link", { name: TEST_GROUP_NAME }).last();
    await expect(groupLink).toBeVisible();
    await expect(groupLink).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`,
    );
  });

  /** Event kind badge. */
  test("event kind badge displays for event", async ({ page }) => {
    const badge = page.getByText(/^(in-person|virtual|hybrid)$/i).first();
    await expect(badge).toBeVisible();
  });

  /** Event date. */
  test("event date section renders with heading", async ({ page }) => {
    await expect(page.getByText("Event date", { exact: true })).toBeVisible();
  });

  test("event date displays a formatted date or TBD", async ({ page }) => {
    const eventDateSection = page
      .getByText("Event date", { exact: true })
      .locator("..");
    const formattedDate = eventDateSection.getByText(
      /(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}/,
    );
    const tbdDate = eventDateSection.getByText("TBD", { exact: true });
    const hasFormattedDate = (await formattedDate.count()) > 0;
    const hasTbdDate = (await tbdDate.count()) > 0;

    expect(hasFormattedDate || hasTbdDate).toBeTruthy();

    if (hasFormattedDate) {
      await expect(formattedDate.first()).toBeVisible();
      const timeText = eventDateSection.getByText(/\d{1,2}:\d{2}\s?(AM|PM)/);
      if ((await timeText.count()) > 0) {
        await expect(timeText.first()).toBeVisible();
      }
    } else {
      await expect(tbdDate).toBeVisible();
    }
  });

  /** Location. */
  test("location section renders with heading", async ({ page }) => {
    await expect(page.getByText("Location", { exact: true })).toBeVisible();
  });

  test("location section shows map or fallback text", async ({ page }) => {
    const locationSection = page
      .getByText("Location", { exact: true })
      .locator("..");
    const mapButton = locationSection.getByRole("button", {
      name: "Open full map view",
    });
    const fallbackText = locationSection.getByText(
      /Virtual event|Location not provided/,
    );
    const mapPlaceholder = locationSection.locator("[class*='map.png']");
    const hasMapButton = (await mapButton.count()) > 0;
    const hasFallbackText = (await fallbackText.count()) > 0;
    const hasMapPlaceholder = (await mapPlaceholder.count()) > 0;

    expect(
      hasMapButton || hasFallbackText || hasMapPlaceholder,
    ).toBeTruthy();

    if (hasMapButton) {
      await expect(mapButton.first()).toBeVisible();
    }
    if (hasFallbackText) {
      await expect(fallbackText.first()).toBeVisible();
    }
    if (hasMapPlaceholder) {
      await expect(mapPlaceholder.first()).toBeVisible();
    }
  });

  /** Alpha event seed data. */
  test.describe("alpha event seed data", () => {
    test.skip(!isAlphaEventOne, "Requires Alpha Event One seed data");

    test("capacity displays when set", async ({ page }) => {
      await expect(page.getByText("Capacity: 100")).toBeVisible();
    });

    test("location displays venue information for in-person event", async ({
      page,
    }) => {
      await expect(page.getByText(/New York/).first()).toBeVisible();
    });

    test("about section renders with heading and description", async ({
      page,
    }) => {
      const aboutSection = page
        .getByText("About this event", { exact: true })
        .locator("..");
      const description = aboutSection.locator(".markdown");

      await expect(
        page.getByText("About this event", { exact: true }),
      ).toBeVisible();
      await expect(description).toContainText(/\S/);
    });

    test("tags section renders when event has tags", async ({ page }) => {
      await expect(
        page.getByText("Tags", { exact: true }).first(),
      ).toBeVisible();
    });

    test("individual tags display correctly", async ({ page }) => {
      await expect(page.getByText("meetup", { exact: true })).toBeVisible();
      await expect(page.getByText("tech", { exact: true })).toBeVisible();
      await expect(page.getByText("networking", { exact: true })).toBeVisible();
    });

    test("meetup social link is visible", async ({ page }) => {
      const meetupLink = page.getByRole("link", { name: "Meetup" });
      await expect(meetupLink).toBeVisible();
      await expect(meetupLink).toHaveAttribute(
        "href",
        "https://www.meetup.com/test-group/events/123456789/",
      );
    });

    test("gallery section renders with photos", async ({ page }) => {
      await expect(page.getByText("Gallery", { exact: true }).first()).toBeVisible();
      const gallery = page.locator("images-gallery");
      await expect(gallery).toBeVisible();
    });

    test("sponsors section renders with sponsor badge", async ({ page }) => {
      await expect(page.getByText("Sponsors", { exact: true })).toBeVisible();
      await expect(page.getByText("Tech Corp")).toBeVisible();
    });

    test("hosts section renders", async ({ page }) => {
      await expect(page.getByText("Hosts", { exact: true })).toBeVisible();
    });

    test("speakers section renders with featured and regular speakers", async ({
      page,
    }) => {
      await expect(
        page.getByText("Featured speakers", { exact: true }),
      ).toBeVisible();
      await expect(page.getByText("Speakers", { exact: true })).toBeVisible();
    });

    test("agenda section renders with sessions", async ({ page }) => {
      await expect(page.getByText("Agenda", { exact: true })).toBeVisible();
      await expect(page.getByText("Opening Keynote")).toBeVisible();
      await expect(page.getByText("Technical Workshop")).toBeVisible();
    });
  });
});

/** Responsive layout assertions. */
test.describe("event page - responsive", () => {
  test("event page renders correctly on mobile viewport", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );

    const heading = page.getByRole("heading", {
      level: 1,
      name: TEST_EVENT_NAME,
    });
    await expect(heading).toBeVisible();

    await expect(page.getByText("Event date", { exact: true })).toBeVisible();
    await expect(page.getByText("Location", { exact: true })).toBeVisible();
    await expect(page.getByText("About this event")).toBeVisible();
  });

  test("event page renders correctly on desktop viewport", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );

    const heading = page.getByRole("heading", {
      level: 1,
      name: TEST_EVENT_NAME,
    });
    await expect(heading).toBeVisible();

    await expect(page.getByText("Event date", { exact: true })).toBeVisible();
    await expect(page.getByText("Location", { exact: true })).toBeVisible();
    await expect(page.getByText("About this event")).toBeVisible();
  });
});

/** Alpha event logo visibility. */
test.describe("event page - alpha event logo", () => {
  test.skip(!isAlphaEventOne, "Requires Alpha Event One seed data");

  test("event logo is visible on desktop", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );

    const logo = page.locator("div[style*='background-image']").first();
    await expect(logo).toBeVisible();
  });
});

/** Virtual event recording link. */
test.describe("event page - virtual event with recording", () => {
  test("recording link appears in meeting details section", async ({
    page,
  }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      "alpha-event-2",
    );

    const recordingLink = page.getByRole("link", { name: "View recording" });
    await expect(recordingLink).toBeVisible();
    await expect(recordingLink).toHaveAttribute(
      "href",
      "https://www.youtube.com/watch?v=test123",
    );
  });
});
