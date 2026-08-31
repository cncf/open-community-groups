import { expect, test } from "@playwright/test";

import {
  getEventAboutSection,
  getEventInfoSection,
  getEventLogo,
  getAttendButton,
  getIntroSection,
  TEST_CANCELED_PUBLIC_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAME,
  TEST_EVENT_PAGE_BADGE_EVENT,
  TEST_EVENT_SLUG,
  TEST_GROUP_NAME,
  TEST_GROUP_SLUG,
  TEST_MULTI_DAY_EVENT,
  buildE2eUrl,
  navigateToEvent,
  waitForAttendanceState,
} from "../../utils.js";

const isPrimaryEvent = TEST_EVENT_SLUG === "alpha-event-1";
const OPEN_GRAPH_IMAGE_FILE_NAME = "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png";

test.describe("event page", () => {
  test.beforeEach(async ({ page }) => {
    // Load the configured event page before each public page assertion.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
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

  test("event page exposes its canonical URL and page title", async ({ page }) => {
    // The page title appends the start date, so match the event name prefix.
    await expect(page).toHaveTitle(new RegExp(`^${TEST_EVENT_NAME} - `));
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
      "href",
      buildE2eUrl(`/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`),
    );
  });

  test("event share action uses the canonical event title and URL", async ({ page }) => {
    // Open the event actions menu and inspect its page-specific share contract.
    await page
      .locator('[data-attendance-role="actions-menu"] summary')
      .click();
    const shareModal = page.locator('share-modal[trigger-variant="menu-item"]');
    const expectedEventPath =
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`;
    await expect(shareModal).toHaveAttribute(
      "title",
      `${TEST_GROUP_NAME} · ${TEST_EVENT_NAME}`,
    );
    await expect(shareModal).toHaveAttribute("url", expectedEventPath);

    // Verify the rendered dialog resolves the relative path to its public URL.
    await shareModal.getByRole("button", { name: "Share" }).click();
    const shareDialog = page.getByRole("dialog", { name: "Share" });
    await expect(shareDialog).toBeVisible();
    await expect(shareDialog.getByRole("button", { name: "Email" })).toHaveAttribute(
      "data-url",
      buildE2eUrl(expectedEventPath),
    );
  });

  test("event page sends its page-view beacon", async ({ page }) => {
    // Read the rendered event identifier before watching its page-view endpoint.
    const eventId = await page
      .locator('[data-page-view][data-entity-type="event"]')
      .getAttribute("data-entity-id");
    expect(eventId).toBeTruthy();
    const pageViewRequestPromise = page.waitForRequest(
      (request) =>
        request.method() === "POST" && new URL(request.url()).pathname === `/events/${eventId}/views`,
    );

    // Reload the page and verify its analytics beacon targets the event identifier.
    await page.reload();
    const pageViewRequest = await pageViewRequestPromise;
    expect(new URL(pageViewRequest.url()).pathname).toBe(`/events/${eventId}/views`);
  });

  test("availability refreshes capacity and remaining spots", async ({ page }) => {
    test.skip(!isPrimaryEvent, "Requires Upcoming In-Person Event seed data");

    // Let the initial availability fetch settle so the watcher only matches the reload's
    // response, whose body stays readable after navigation.
    await expect(page.locator('[data-availability-url][data-availability-hydrated="true"]')).toBeAttached();

    // Watch the public availability endpoint before reloading the event page.
    const availabilityPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}/availability`;
    const availabilityResponsePromise = page
      .waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          new URL(response.url()).pathname === availabilityPath,
      )
      .then(async (response) => ({
        availability: await response.json(),
        responseIsOk: response.ok(),
      }));

    // Reload the page and read the same payload used by the availability UI.
    await page.reload();
    const { availability, responseIsOk } = await availabilityResponsePromise;
    expect(responseIsOk).toBeTruthy();
    expect(availability.capacity).toBe(100);
    expect(availability.remaining_capacity).toBeGreaterThan(0);

    // Verify capacity and remaining copy reflect the fresh server values.
    await expect(page.locator("[data-availability-capacity]")).toHaveText("100");
    await expect(page.locator('[data-availability-caption="remaining"]')).toBeVisible();
    await expect(page.locator("[data-availability-remaining]")).toHaveText(
      String(availability.remaining_capacity),
    );
  });

  test("publishes Open Graph metadata and serves its preview image", async ({ page }) => {
    // Resolve the public preview image configured by the seeded community.
    const openGraphImageUrl = buildE2eUrl(`/images/og/${OPEN_GRAPH_IMAGE_FILE_NAME}`);

    // Verify the event metadata exposes the canonical preview contract.
    await expect(page.locator('meta[property="og:type"]')).toHaveAttribute("content", "website");
    await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
      "content",
      /Upcoming In-Person Event/,
    );
    await expect(page.locator('meta[property="og:url"]')).toHaveAttribute(
      "content",
      buildE2eUrl(`/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`),
    );
    await expect(page.locator('meta[property="og:description"]')).toHaveAttribute(
      "content",
      /Platform Ops Meetup/,
    );
    await expect(page.locator('meta[property="og:image"]')).toHaveAttribute("content", openGraphImageUrl);
    await expect(page.locator('meta[property="og:image:width"]')).toHaveAttribute("content", "1200");
    await expect(page.locator('meta[property="og:image:height"]')).toHaveAttribute("content", "630");
    await expect(page.locator('meta[property="og:image:alt"]')).toHaveAttribute("content", TEST_GROUP_NAME);
    await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute("content", "summary_large_image");

    // Request the public Open Graph route and verify its immutable image response.
    const imageResponse = await page.request.get(openGraphImageUrl);
    expect(imageResponse.status()).toBe(200);
    expect(imageResponse.headers()["content-type"]).toContain("image/png");
    expect(imageResponse.headers()["cache-control"]).toContain("immutable");
  });

  test("group link displays and links correctly", async ({ page }) => {
    // Verify the event header links back to the hosting group page.
    const groupLink = page.getByRole("link", { name: TEST_GROUP_NAME }).last();

    // Verify group link displays and links correctly.
    await expect(groupLink).toBeVisible();
    await expect(groupLink).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`);
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

    // Only check the formatted date when event data includes one.
    if (hasFormattedDate) {
      expect(eventDateText).toMatch(/\d{1,2}:\d{2}\s?(AM|PM)/);
    } else {
      await expect(eventDateSection.getByText("TBD", { exact: true })).toBeVisible();
    }
  });

  test("location section renders with heading", async ({ page }) => {
    // Verify the location section heading is present.
    await expect(page.getByText("Location", { exact: true })).toBeVisible();
  });

  test("location section shows map or fallback text", async ({ page }) => {
    // Read the location section text and map controls.
    const locationSection = getEventInfoSection(page, "Location");
    const locationText = ((await locationSection.textContent()) || "").replace(/\s+/g, " ").trim();
    const hasMapButton =
      (await locationSection.getByRole("button", { name: "Open full map view" }).count()) > 0;
    const hasFallbackText = /Virtual event|Location not provided/.test(locationText);
    const hasLocationDetails = locationText !== "Location" && locationText !== "" && /,/.test(locationText);

    // Verify the location section has either map, fallback, or details.
    expect(hasMapButton || hasFallbackText || hasLocationDetails).toBeTruthy();

    // Only test the map modal when the venue has a map button.
    if (hasMapButton) {
      // Verify the map action is visible when map data is available.
      await expect(locationSection.getByRole("button", { name: "Open full map view" }).first()).toBeVisible();
    } else if (hasFallbackText) {
      // Verify virtual or missing locations show fallback copy.
      await expect(locationSection).toContainText(/Virtual event|Location not provided/);
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

    test("location displays venue information for in-person event", async ({ page }) => {
      // Verify the in-person event includes its venue city.
      await expect(page.getByText(/New York/).first()).toBeVisible();
    });

    test("location map modal opens and closes", async ({ page }) => {
      // Target the public location map and modal elements.
      const locationSection = getEventInfoSection(page, "Location");
      const mapButton = locationSection.getByRole("button", {
        name: "Open full map view",
      });
      const mapModal = page.locator("#event-map-modal");
      const modalMap = page.locator("#event-map-modal-map");

      // Verify the seeded event renders the interactive map trigger.
      await expect(mapButton).toBeVisible();
      await expect(page.locator("#event-map")).toHaveAttribute("data-lat", "40.7128");
      await expect(page.locator("#event-map")).toHaveAttribute("data-lng", "-74.006");

      // Open the full map modal from the location preview.
      await mapButton.click();

      // Verify the modal opens and MapLibre initializes the modal map.
      await expect(mapModal).toBeVisible();
      await expect(modalMap).toHaveClass(/maplibregl-map/);

      // Close the map modal and verify it is hidden again.
      await page.locator("#close-event-map-modal").click();
      await expect(mapModal).toBeHidden();
    });

    test("location map modal supports keyboard dismissal and focus restoration", async ({ page }) => {
      // Find the map trigger and modal.
      const mapButton = getEventInfoSection(page, "Location").getByRole("button", {
        name: "Open full map view",
      });
      const mapModal = page.locator("#event-map-modal");

      // Open the map with the keyboard and verify initial modal focus.
      await mapButton.focus();
      await mapButton.press("Enter");
      await expect(mapModal).toBeVisible();
      const closeButton = page.locator("#close-event-map-modal");
      await expect(closeButton).toBeFocused();

      // The map modal does not bind Escape, so close it with the focused
      // close button and verify focus returns to the map trigger.
      await closeButton.press("Enter");
      await expect(mapModal).toBeHidden();
      await expect(mapButton).toBeFocused();
    });

    test("about section renders with heading and description", async ({ page }) => {
      // Target the about section markdown content.
      const aboutSection = getEventAboutSection(page);
      const description = aboutSection.locator(".markdown");

      // Verify the about section includes heading and description text.
      await expect(aboutSection).toContainText("About this event");
      await expect(description).toContainText(/\S/);
    });

    test("tags section renders when event has tags", async ({ page }) => {
      // Verify the event tags section is present.
      await expect(page.getByText("Tags", { exact: true }).first()).toBeVisible();
    });

    test("individual tags display correctly", async ({ page }) => {
      // Verify each expected event tag is visible.
      await expect(page.getByText("meetup", { exact: true })).toBeVisible();

      // Verify the remaining expected event tags are visible.
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
      await expect(meetupLink).toHaveAttribute("href", "https://www.meetup.com/test-group/events/123456789/");
    });

    test("gallery section renders with photos", async ({ page }) => {
      // Verify the event gallery section and image gallery render.
      await expect(page.getByText("Gallery", { exact: true }).first()).toBeVisible();

      // Verify the gallery component is present.
      const gallery = page.locator("images-gallery");
      await expect(gallery).toBeVisible();
    });

    test("gallery handles broken images in thumbnails and carousel", async ({ page }) => {
      // Target the gallery thumbnail with a broken fixture image.
      const gallery = page.locator("images-gallery");
      const brokenImageAlt = `Event ${TEST_EVENT_NAME} image 1`;
      const validImageAlt = `Event ${TEST_EVENT_NAME} image 2`;
      const thumbnailButton = gallery.locator(`button:has(img[alt="${brokenImageAlt}"])`);
      const thumbnailImage = thumbnailButton.locator(`img[alt="${brokenImageAlt}"]`);

      // Verify the thumbnail shows the broken-image placeholder.
      await expect(gallery).toBeVisible();
      await expect(thumbnailButton).toBeVisible();
      await expect(thumbnailButton).toHaveClass(/relative/);
      await expect(thumbnailImage).toHaveAttribute("data-ocg-broken-image-placeholder", "true");
      await expect(thumbnailImage).toHaveAttribute("src", /\/static\/images\/icons\/broken_image\.svg$/);
      await expect(thumbnailButton.locator('[data-ocg-broken-image-icon="true"]')).toBeVisible();

      // Open the gallery carousel from the broken thumbnail.
      await thumbnailButton.click();

      // Verify the active carousel slide keeps the placeholder stable.
      const modal = gallery.locator(".modal");
      const activeSlide = modal.locator(".z-30.translate-x-0");
      await expect(modal).not.toHaveClass(/pointer-events-none/);
      await expect(activeSlide).toHaveClass(/absolute/);
      await expect(activeSlide).not.toHaveClass(/relative/);
      await expect(activeSlide.locator(`img[alt="${brokenImageAlt}"]`)).toHaveAttribute(
        "data-ocg-broken-image-placeholder",
        "true",
      );
      await expect(activeSlide.locator('[data-ocg-broken-image-icon="true"]')).toBeVisible();

      // Verify navigating to the valid image shows the next slide.
      await modal.getByRole("button", { name: "Next" }).click();
      await expect(modal.locator(".z-30.translate-x-0").locator(`img[alt="${validImageAlt}"]`)).toBeVisible();
    });

    test("sponsors section renders with sponsor badge", async ({ page }) => {
      // Verify public sponsor content is shown for the event.
      await expect(page.getByText("Sponsors", { exact: true })).toBeVisible();

      // Verify the seeded sponsor appears in the section.
      await expect(page.getByText("Tech Corp")).toBeVisible();
    });

    test("hosts section renders", async ({ page }) => {
      // Verify the event hosts section is present.
      await expect(page.getByText("Hosts", { exact: true })).toBeVisible();
    });

    test("speakers section renders with featured and regular speakers", async ({ page }) => {
      // Verify featured and regular speaker sections are present.
      await expect(page.getByText("Featured speakers", { exact: true })).toBeVisible();

      // Verify the regular speakers section is present.
      await expect(page.getByText("Speakers", { exact: true })).toBeVisible();
    });

    test("agenda section renders with sessions", async ({ page }) => {
      // Verify the agenda includes the expected session names.
      await expect(page.getByText("Agenda", { exact: true })).toBeVisible();

      // Verify seeded agenda sessions are visible.
      await expect(page.getByText("Opening Keynote")).toBeVisible();
      await expect(page.getByText("Technical Workshop")).toBeVisible();

      // Verify the keynote session lists its featured and regular speakers.
      const keynoteItem = page.locator("li", { hasText: "Opening Keynote" });
      await expect(keynoteItem.getByText("SPEAKERS", { exact: true })).toBeVisible();
      await expect(keynoteItem.getByText("E2E Member One")).toBeVisible();
      await expect(keynoteItem.getByText("E2E Member Two")).toBeVisible();
    });
  });
});

test.describe("event page - canceled event", () => {
  test("shows canceled state and suppresses unavailable event actions", async ({ page }) => {
    // Load a canceled event that still stores CFS and meeting details.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_CANCELED_PUBLIC_EVENT.slug);

    // Verify the public canceled state and disabled attendance action.
    await expect(
      page.getByRole("heading", {
        level: 1,
        name: TEST_CANCELED_PUBLIC_EVENT.name,
      }),
    ).toBeVisible();
    await expect(page.getByText("Canceled", { exact: true })).toBeVisible();
    await waitForAttendanceState(page);
    await expect(getAttendButton(page)).toBeVisible();
    await expect(getAttendButton(page)).toBeDisabled();
    await expect(getAttendButton(page)).toHaveAttribute("title", "This event has been canceled.");

    // Verify cancellation suppresses CFS, meeting links, and the actions menu.
    await expect(page.getByText("Call for Speakers", { exact: true })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Submit session proposal" })).toHaveCount(0);
    await expect(page.locator("[data-join-link], [data-join-link-always]")).toHaveCount(0);
    await expect(page.getByText("Join the canceled event using the private meeting room.")).toHaveCount(0);
    await expect(page.getByRole("button", { name: "More actions" })).toHaveCount(0);
  });
});

test.describe("event page - sold-out availability", () => {
  test("shows the sold-out ribbon when no capacity remains", async ({ page }) => {
    // Watch availability while loading the dedicated full event fixture.
    const eventSlug = "alpha-waitlist-lab";
    const availabilityPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${eventSlug}/availability`;
    const availabilityResponsePromise = page
      .waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          new URL(response.url()).pathname === availabilityPath,
      )
      .then(async (response) => ({
        availability: await response.json(),
        responseIsOk: response.ok(),
      }));
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, eventSlug);

    // Verify the server and page both expose the exhausted capacity state.
    const { availability, responseIsOk } = await availabilityResponsePromise;
    expect(responseIsOk).toBeTruthy();
    expect(availability.capacity).toBe(1);
    expect(availability.remaining_capacity).toBe(0);
    await expect(page.locator("[data-availability-capacity]")).toHaveText("1");
    await expect(page.locator("[data-availability-sold-out-ribbon]")).toBeVisible();
    await expect(page.locator("[data-availability-sold-out-ribbon]")).toContainText("Sold out");
    await expect(page.locator('[data-availability-caption="remaining"]')).toBeHidden();
  });
});

test.describe("event page - responsive", () => {
  test("event page renders correctly on mobile viewport @mobile", async ({ page }) => {
    // Load the event page for the mobile viewport.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Find the heading.
    const heading = page.getByRole("heading", {
      level: 1,
      name: TEST_EVENT_NAME,
    });

    // Verify the mobile page sections are visible.
    await expect(heading).toBeVisible();

    // Assert the expected content is visible.
    await expect(getEventInfoSection(page, "Event date")).toBeVisible();
    await expect(getEventInfoSection(page, "Location")).toBeVisible();
    await expect(getEventAboutSection(page)).toBeVisible();
  });

  test("event page renders correctly on desktop viewport", async ({ page }) => {
    // Load the event page for the desktop viewport.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Find the heading.
    const heading = page.getByRole("heading", {
      level: 1,
      name: TEST_EVENT_NAME,
    });

    // Verify the desktop page sections are visible.
    await expect(heading).toBeVisible();

    // Assert the expected content is visible.
    await expect(getEventInfoSection(page, "Event date")).toBeVisible();
    await expect(getEventInfoSection(page, "Location")).toBeVisible();
    await expect(getEventAboutSection(page)).toBeVisible();
  });

  test("social links swap between mobile and desktop variants at the md breakpoint", async ({
    page,
  }) => {
    // Load the primary event that carries a seeded Meetup link.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Find the desktop and mobile social link variants.
    const desktopMeetupLink = page.locator('div.hidden.md\\:flex a[title="Meetup"]');
    const mobileMeetupLink = page.locator('div.md\\:hidden a[title="Meetup"]');

    // Verify only the desktop variant shows from the md breakpoint up.
    await expect(desktopMeetupLink).toBeVisible();
    await expect(mobileMeetupLink).toBeHidden();

    // Verify only the mobile variant shows below the md breakpoint.
    await page.setViewportSize({ width: 767, height: 900 });
    await expect(mobileMeetupLink).toBeVisible();
    await expect(desktopMeetupLink).toBeHidden();
  });
});

test.describe("event page - alpha event logo", () => {
  test.skip(!isPrimaryEvent, "Requires Upcoming In-Person Event seed data");

  test("event logo is visible on desktop", async ({ page }) => {
    // Load the primary event page before checking the desktop logo.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Verify the event logo image is visible.
    const logo = getEventLogo(page);
    await expect(logo).toBeVisible();
  });

  test("event logo is hidden below the md breakpoint", async ({ page }) => {
    // Load the primary event page before checking the mobile logo state.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Verify the logo container disappears below the md breakpoint.
    await page.setViewportSize({ width: 767, height: 900 });
    await expect(getEventLogo(page)).toBeHidden();
  });
});

test.describe("event page - multi-day agenda", () => {
  test.beforeEach(async ({ page }) => {
    // Load the seeded two-day summit before each agenda tab assertion.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_MULTI_DAY_EVENT.slug);
  });

  test("day tabs switch the visible agenda day", async ({ page }) => {
    // Verify the first day tab starts active with its sessions shown.
    const dayTabs = page.locator("button[data-day-tab]");
    await expect(dayTabs).toHaveCount(2);
    await expect(dayTabs.first()).toHaveAttribute("data-active", "true");
    await expect(page.getByText("Summit Kickoff")).toBeVisible();
    await expect(page.getByText("Summit Wrap-Up")).toBeHidden();

    // Verify selecting the second day swaps the visible sessions.
    await dayTabs.nth(1).click();
    await expect(dayTabs.nth(1)).toHaveAttribute("data-active", "true");
    await expect(dayTabs.first()).toHaveAttribute("data-active", "false");
    await expect(page.getByText("Summit Wrap-Up")).toBeVisible();
    await expect(page.getByText("Summit Kickoff")).toBeHidden();
  });

  test("day tab labels swap between long and short formats at the md breakpoint", async ({ page }) => {
    // Target the long and short date labels of the first day tab.
    const firstDayTab = page.locator("button[data-day-tab]").first();
    const longLabel = firstDayTab.locator("span.hidden.md\\:inline");
    const shortLabel = firstDayTab.locator("span.inline.md\\:hidden");

    // Verify the long weekday label shows on desktop viewports.
    await expect(longLabel).toBeVisible();
    await expect(shortLabel).toBeHidden();

    // Verify the compact date label replaces it below the md breakpoint.
    await page.setViewportSize({ width: 767, height: 900 });
    await expect(shortLabel).toBeVisible();
    await expect(longLabel).toBeHidden();
  });
});

test.describe("event page - virtual event with recording", () => {
  test("location fallback uses virtual event artwork", async ({ page }) => {
    // Load a future virtual event with virtual location fallback artwork.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, "alpha-event-2");

    // Verify the virtual location fallback text and artwork render.
    const locationSection = getEventInfoSection(page, "Location");
    await expect(locationSection).toContainText("Virtual event");
    await expect(locationSection.locator('[style*="/static/images/virtual_event.png"]')).toBeVisible();
  });

  test("recording link is hidden until the event is past", async ({ page }) => {
    // Load a future virtual event with a recording configured.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, "alpha-event-2");

    // Verify future recordings stay hidden on the public event page.
    const recordingLink = page.getByRole("link", { name: "View recording" });
    await expect(recordingLink).toHaveCount(0);
  });

  test("past event exposes its recording and suppresses attendance actions", async ({ page }) => {
    // Load a past virtual event with a public recording configured.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUG,
      "alpha-past-roundup",
    );

    // Verify the recording replaces live meeting and attendance actions.
    const recordingLink = page.getByRole("link", { name: "View recording" });
    await expect(page.getByText("Use the link below to watch the recording.")).toBeVisible();
    await expect(recordingLink).toHaveAttribute(
      "href",
      "https://recordings.example.test/alpha-past-roundup",
    );
    await expect(page.locator("[data-join-link], [data-join-link-always]")).toHaveCount(0);
    await expect(getAttendButton(page)).toBeHidden();
  });
});

test.describe("event page - test event badge", () => {
  test("shows the test badge next to the event type", async ({ page }) => {
    // Load an event configured with the public test badge.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_PAGE_BADGE_EVENT.slug);

    // Verify the configured test event heading is visible.
    const introSection = getIntroSection(page);
    await expect(
      introSection.getByRole("heading", {
        level: 1,
        name: TEST_EVENT_PAGE_BADGE_EVENT.name,
      }),
    ).toBeVisible();

    // Set up event type badge.
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
