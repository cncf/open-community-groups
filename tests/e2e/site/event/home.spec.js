import { expect, test } from "@playwright/test";

import {
  getEventAboutSection,
  getEventInfoSection,
  getEventLogo,
  getIntroSection,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_PAGE_BADGE_EVENT,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  navigateToEvent,
} from "../../utils.js";

const isPrimaryEvent = TEST_EVENT_SLUG === "alpha-event-1";

test.describe("event page", () => {
  test.beforeEach(async ({ page }) => {
    // Load the configured event page before each public page assertion.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );
  });

  test("breadcrumb navigation is visible", async ({ page }) => {
    // Verify the event breadcrumb renders in the page header.
    const breadcrumb = page.locator("breadcrumb-nav");
    await expect(breadcrumb).toBeVisible();
  });

  test("event name displays as h1 heading", async ({ page }) => {
    // Target the event heading from the public page.
    const heading = page.getByRole("heading", {
      level: 1,
      name: TEST_EVENT_NAME,
    });

    // Verify the event name renders as the primary heading.
    await expect(heading).toBeVisible();
  });

  test("group link displays and links correctly", async ({ page }) => {
    // Verify the event header links back to the hosting group page.
    const groupLink = page.getByRole("link", { name: TEST_GROUP_NAME }).last();
    await expect(groupLink).toBeVisible();
    await expect(groupLink).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`,
    );
  });

  test("event kind badge displays for event", async ({ page }) => {
    // Verify the event kind badge renders in the event header.
    const badge = page.getByText(/^(in-person|virtual|hybrid)$/i).first();
    await expect(badge).toBeVisible();
  });

  test("event date section renders with heading", async ({ page }) => {
    // Verify the event date section heading is present.
    await expect(page.getByText("Event date", { exact: true })).toBeVisible();
  });

  test("event date displays a formatted date or TBD", async ({ page }) => {
    // Read the event date section text for date fallback coverage.
    const eventDateSection = getEventInfoSection(page, "Event date");
    const eventDateText = (await eventDateSection.textContent()) || "";
    const hasFormattedDate =
      /(Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2},\s+\d{4}/.test(
        eventDateText,
      );
    const hasTbdDate = /\bTBD\b/.test(eventDateText);

    // Verify the date section shows either a formatted date or TBD.
    expect(hasFormattedDate || hasTbdDate).toBeTruthy();

    if (hasFormattedDate) {
      expect(eventDateText).toMatch(/\d{1,2}:\d{2}\s?(AM|PM)/);
    } else {
      await expect(
        eventDateSection.getByText("TBD", { exact: true }),
      ).toBeVisible();
    }
  });

  test("location section renders with heading", async ({ page }) => {
    // Verify the location section heading is present.
    await expect(page.getByText("Location", { exact: true })).toBeVisible();
  });

  test("location section shows map or fallback text", async ({ page }) => {
    // Read the location section text and map controls.
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

    // Verify the location section has either map, fallback, or details.
    expect(hasMapButton || hasFallbackText || hasLocationDetails).toBeTruthy();

    if (hasMapButton) {
      // Verify the map action is visible when map data is available.
      await expect(
        locationSection
          .getByRole("button", { name: "Open full map view" })
          .first(),
      ).toBeVisible();
    } else if (hasFallbackText) {
      // Verify virtual or missing locations show fallback copy.
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
      // Verify the event capacity label is rendered.
      await expect(page.getByText(/Capacity:\s*100/)).toBeVisible();
    });

    test("location displays venue information for in-person event", async ({
      page,
    }) => {
      // Verify the in-person event includes its venue city.
      await expect(page.getByText(/New York/).first()).toBeVisible();
    });

    test("about section renders with heading and description", async ({
      page,
    }) => {
      // Target the about section markdown content.
      const aboutSection = getEventAboutSection(page);
      const description = aboutSection.locator(".markdown");

      // Verify the about section includes heading and description text.
      await expect(aboutSection).toContainText("About this event");
      await expect(description).toContainText(/\S/);
    });

    test("tags section renders when event has tags", async ({ page }) => {
      // Verify the event tags section is present.
      await expect(
        page.getByText("Tags", { exact: true }).first(),
      ).toBeVisible();
    });

    test("individual tags display correctly", async ({ page }) => {
      // Verify each expected event tag is visible.
      await expect(page.getByText("meetup", { exact: true })).toBeVisible();
      await expect(page.getByText("tech", { exact: true })).toBeVisible();
      await expect(page.getByText("networking", { exact: true })).toBeVisible();
    });

    test("meetup social link is visible", async ({ page }) => {
      // Target the event Meetup link.
      const meetupLink = page.getByRole("link", {
        name: "Meetup",
        exact: true,
      });

      // Verify the Meetup link points to the configured event page.
      await expect(meetupLink).toBeVisible();
      await expect(meetupLink).toHaveAttribute(
        "href",
        "https://www.meetup.com/test-group/events/123456789/",
      );
    });

    test("gallery section renders with photos", async ({ page }) => {
      // Verify the event gallery section and image gallery render.
      await expect(
        page.getByText("Gallery", { exact: true }).first(),
      ).toBeVisible();
      const gallery = page.locator("images-gallery");
      await expect(gallery).toBeVisible();
    });

    test("gallery handles broken images in thumbnails and carousel", async ({
      page,
    }) => {
      // Target the gallery thumbnail with a broken fixture image.
      const gallery = page.locator("images-gallery");
      const brokenImageAlt = `Event ${TEST_EVENT_NAME} image 1`;
      const validImageAlt = `Event ${TEST_EVENT_NAME} image 2`;
      const thumbnailButton = gallery.locator(
        `button:has(img[alt="${brokenImageAlt}"])`,
      );
      const thumbnailImage = thumbnailButton.locator(
        `img[alt="${brokenImageAlt}"]`,
      );

      // Verify the thumbnail shows the broken-image placeholder.
      await expect(gallery).toBeVisible();
      await expect(thumbnailButton).toBeVisible();
      await expect(thumbnailButton).toHaveClass(/relative/);
      await expect(thumbnailImage).toHaveAttribute(
        "data-ocg-broken-image-placeholder",
        "true",
      );
      await expect(thumbnailImage).toHaveAttribute(
        "src",
        /\/static\/images\/icons\/broken_image\.svg$/,
      );
      await expect(
        thumbnailButton.locator('[data-ocg-broken-image-icon="true"]'),
      ).toBeVisible();

      // Open the gallery carousel from the broken thumbnail.
      await thumbnailButton.click();

      // Verify the active carousel slide keeps the placeholder stable.
      const modal = gallery.locator(".modal");
      const activeSlide = modal.locator(".z-30.translate-x-0");
      await expect(modal).not.toHaveClass(/pointer-events-none/);
      await expect(activeSlide).toHaveClass(/absolute/);
      await expect(activeSlide).not.toHaveClass(/relative/);
      await expect(
        activeSlide.locator(`img[alt="${brokenImageAlt}"]`),
      ).toHaveAttribute("data-ocg-broken-image-placeholder", "true");
      await expect(
        activeSlide.locator('[data-ocg-broken-image-icon="true"]'),
      ).toBeVisible();

      // Verify navigating to the valid image shows the next slide.
      await modal.getByRole("button", { name: "Next" }).click();
      await expect(
        modal
          .locator(".z-30.translate-x-0")
          .locator(`img[alt="${validImageAlt}"]`),
      ).toBeVisible();
    });

    test("sponsors section renders with sponsor badge", async ({ page }) => {
      // Verify public sponsor content is shown for the event.
      await expect(page.getByText("Sponsors", { exact: true })).toBeVisible();
      await expect(page.getByText("Tech Corp")).toBeVisible();
    });

    test("hosts section renders", async ({ page }) => {
      // Verify the event hosts section is present.
      await expect(page.getByText("Hosts", { exact: true })).toBeVisible();
    });

    test("speakers section renders with featured and regular speakers", async ({
      page,
    }) => {
      // Verify featured and regular speaker sections are present.
      await expect(
        page.getByText("Featured speakers", { exact: true }),
      ).toBeVisible();
      await expect(page.getByText("Speakers", { exact: true })).toBeVisible();
    });

    test("agenda section renders with sessions", async ({ page }) => {
      // Verify the agenda includes the expected session names.
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
    // Load the event page for the mobile viewport.
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

    // Verify the mobile page sections are visible.
    await expect(heading).toBeVisible();

    await expect(getEventInfoSection(page, "Event date")).toBeVisible();
    await expect(getEventInfoSection(page, "Location")).toBeVisible();
    await expect(getEventAboutSection(page)).toBeVisible();
  });

  test("event page renders correctly on desktop viewport", async ({ page }) => {
    // Load the event page for the desktop viewport.
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

    // Verify the desktop page sections are visible.
    await expect(heading).toBeVisible();

    await expect(getEventInfoSection(page, "Event date")).toBeVisible();
    await expect(getEventInfoSection(page, "Location")).toBeVisible();
    await expect(getEventAboutSection(page)).toBeVisible();
  });
});

test.describe("event page - alpha event logo", () => {
  test.skip(!isPrimaryEvent, "Requires Upcoming In-Person Event seed data");

  test("event logo is visible on desktop", async ({ page }) => {
    // Load the primary event page before checking the desktop logo.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_SLUG,
    );

    // Verify the event logo image is visible.
    const logo = getEventLogo(page);
    await expect(logo).toBeVisible();
  });
});

test.describe("event page - virtual event with recording", () => {
  test("location fallback uses virtual event artwork", async ({ page }) => {
    // Load a future virtual event with virtual location fallback artwork.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      "alpha-event-2",
    );

    // Verify the virtual location fallback text and artwork render.
    const locationSection = getEventInfoSection(page, "Location");
    await expect(locationSection).toContainText("Virtual event");
    await expect(
      locationSection.locator('[style*="/static/images/virtual_event.png"]'),
    ).toBeVisible();
  });

  test("recording link is hidden until the event is past", async ({ page }) => {
    // Load a future virtual event with a recording configured.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      "alpha-event-2",
    );

    // Verify future recordings stay hidden on the public event page.
    const recordingLink = page.getByRole("link", { name: "View recording" });
    await expect(recordingLink).toHaveCount(0);
  });
});

test.describe("event page - test event badge", () => {
  test("shows the test badge next to the event type", async ({ page }) => {
    // Load an event configured with the public test badge.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      TEST_EVENT_PAGE_BADGE_EVENT.slug,
    );

    // Verify the configured test event heading is visible.
    const introSection = getIntroSection(page);
    await expect(
      introSection.getByRole("heading", {
        level: 1,
        name: TEST_EVENT_PAGE_BADGE_EVENT.name,
      }),
    ).toBeVisible();

    const eventTypeBadge = introSection
      .locator(".custom-badge")
      .filter({ hasText: /^virtual$/i })
      .first();
    const badgeGroup = eventTypeBadge.locator("..");
    const testBadge = badgeGroup.getByText("Test", { exact: true });

    // Verify the test badge appears beside the event type badge.
    await expect(eventTypeBadge).toBeVisible();
    await expect(testBadge).toBeVisible();
    await expect(testBadge).toHaveClass(/custom-badge/);
  });
});
