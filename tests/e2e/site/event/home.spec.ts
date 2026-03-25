import { expect, test } from "@playwright/test";

import {
  getEventAboutSection,
  getEventInfoSection,
  getEventLogo,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  navigateToEvent,
} from "../../utils";

const isPrimaryEvent = TEST_EVENT_SLUG === "alpha-event-1";

test.describe("event page", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );
  });

  test("breadcrumb navigation is visible", async ({ page }) => {
    const breadcrumb = page.locator("breadcrumb-nav");
    await expect(breadcrumb).toBeVisible();
  });

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

  test("event kind badge displays for event", async ({ page }) => {
    const badge = page.getByText(/^(in-person|virtual|hybrid)$/i).first();
    await expect(badge).toBeVisible();
  });

  test("event date section renders with heading", async ({ page }) => {
    await expect(page.getByText("Event date", { exact: true })).toBeVisible();
  });

  test("event date displays a formatted date or TBD", async ({ page }) => {
    const eventDateSection = getEventInfoSection(page, "Event date");
    const eventDateText = (await eventDateSection.textContent()) || "";
    const hasFormattedDate =
      /(Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2},\s+\d{4}/.test(
        eventDateText,
      );
    const hasTbdDate = /\bTBD\b/.test(eventDateText);

    expect(hasFormattedDate || hasTbdDate).toBeTruthy();

    if (hasFormattedDate) {
      expect(eventDateText).toMatch(/\d{1,2}:\d{2}\s?(AM|PM)/);
    } else {
      await expect(eventDateSection.getByText("TBD", { exact: true })).toBeVisible();
    }
  });

  test("location section renders with heading", async ({ page }) => {
    await expect(page.getByText("Location", { exact: true })).toBeVisible();
  });

  test("location section shows map or fallback text", async ({ page }) => {
    const locationSection = getEventInfoSection(page, "Location");
    const locationText = ((await locationSection.textContent()) || "")
      .replace(/\s+/g, " ")
      .trim();
    const hasMapButton =
      (await locationSection
        .getByRole("button", { name: "Open full map view" })
        .count()) > 0;
    const hasFallbackText = /Virtual event|Location not provided/.test(
      locationText,
    );
    const hasLocationDetails =
      locationText !== "Location" &&
      locationText !== "" &&
      /,/.test(locationText);

    expect(
      hasMapButton || hasFallbackText || hasLocationDetails,
    ).toBeTruthy();

    if (hasMapButton) {
      await expect(
        locationSection.getByRole("button", { name: "Open full map view" }).first(),
      ).toBeVisible();
    } else if (hasFallbackText) {
      await expect(locationSection).toContainText(
        /Virtual event|Location not provided/,
      );
    } else {
      expect(hasLocationDetails).toBeTruthy();
    }
  });

  test.describe("primary event seed data", () => {
    test.skip(!isPrimaryEvent, "Requires Upcoming In-Person Event seed data");

    test("capacity displays when set", async ({ page }) => {
      await expect(page.getByText(/Capacity:\s*100/)).toBeVisible();
    });

    test("location displays venue information for in-person event", async ({
      page,
    }) => {
      await expect(page.getByText(/New York/).first()).toBeVisible();
    });

    test("about section renders with heading and description", async ({
      page,
    }) => {
      const aboutSection = getEventAboutSection(page);
      const description = aboutSection.locator(".markdown");

      await expect(aboutSection).toContainText("About this event");
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
      const meetupLink = page.getByRole("link", { name: "Meetup", exact: true });
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

test.describe("event page - responsive", () => {
  test("event page renders correctly on mobile viewport @mobile", async ({
    page,
  }) => {
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

    await expect(getEventInfoSection(page, "Event date")).toBeVisible();
    await expect(getEventInfoSection(page, "Location")).toBeVisible();
    await expect(getEventAboutSection(page)).toBeVisible();
  });

  test("event page renders correctly on desktop viewport", async ({ page }) => {
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

    await expect(getEventInfoSection(page, "Event date")).toBeVisible();
    await expect(getEventInfoSection(page, "Location")).toBeVisible();
    await expect(getEventAboutSection(page)).toBeVisible();
  });
});

test.describe("event page - alpha event logo", () => {
  test.skip(!isPrimaryEvent, "Requires Upcoming In-Person Event seed data");

  test("event logo is visible on desktop", async ({ page }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );

    const logo = getEventLogo(page);
    await expect(logo).toBeVisible();
  });
});

test.describe("event page - virtual event with recording", () => {
  test("recording link is hidden until the event is past", async ({
    page,
  }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      "alpha-event-2",
    );

    const recordingLink = page.getByRole("link", { name: "View recording" });
    await expect(recordingLink).toHaveCount(0);
  });
});
