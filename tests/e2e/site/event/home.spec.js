import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, sqlUuid } from "../../database.js";
import {
  TEST_CANCELED_PUBLIC_EVENT,
  TEST_COHOSTED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAME,
  TEST_EVENT_PAGE_BADGE_EVENT,
  TEST_EVENT_SLUG,
  TEST_EVENT_SLUGS,
  TEST_GROUP_IDS,
  TEST_GROUP_NAME,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUG,
  TEST_GROUP_SLUGS,
  TEST_MULTI_DAY_EVENT,
} from "../../seed.js";
import {
  getAttendanceContainer,
  getAttendButton,
  getEventAboutSection,
  getEventInfoSection,
  getEventLogo,
  waitForAttendanceState,
} from "./helpers.js";
import {
  buildE2eUrl,
  getIntroSection,
  getPageOverflow,
  navigateToEvent,
  navigateToPath,
  routeEmptyBasemap,
  swipeHorizontally,
  waitForResponseMatching,
} from "../../utils.js";
import { selectLabels } from "../../dashboard/group/events/event-form-helpers.js";
import { enableDesktopVersion, waitForPageSettled } from "../../snapshots.js";

// Android Chrome, which keeps the Google Maps directions link.
const ANDROID_USER_AGENT =
  "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36";
// Approved co-hosts seeded for the cross-community summit.
const COHOSTED_EVENT_COHOSTS = [
  {
    communityDisplayName: "Platform Engineering Community",
    href: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.gamma}`,
    name: TEST_GROUP_NAMES.gamma,
  },
  {
    communityDisplayName: "Developer Experience Community",
    href: `/${TEST_COMMUNITY_NAME_2}/group/${TEST_GROUP_SLUGS.community2.delta}`,
    name: TEST_GROUP_NAMES.delta,
  },
  {
    communityDisplayName: "Developer Experience Community",
    href: `/${TEST_COMMUNITY_NAME_2}/group/${TEST_GROUP_SLUGS.community2.zeta}`,
    name: TEST_GROUP_NAMES.zeta,
  },
];

const DASHBOARD_WAITLIST_EVENT_SLUG = "alpha-dashboard-waitlist-lab";

const OPEN_GRAPH_IMAGE_FILE_NAME = "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png";

const PRIMARY_EVENT_DESCRIPTION = "Upcoming in-person event used for attendance and dashboard coverage.";

const PRIMARY_EVENT_LOCATION = "Tech Conference Center, 123 Main Street, New York, NY, United States";

test.describe("event page", () => {
  test.beforeEach(async ({ page }) => {
    // Load the configured event page before each public page assertion.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
  });

  test("event header shows breadcrumb, title, group link and kind", async ({ page }) => {
    await test.step("breadcrumb ends at the event", async () => {
      const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
      await expect(breadcrumb).toBeVisible();
      await expect(breadcrumb).toContainText(TEST_EVENT_NAME);
    });

    await test.step("event name is the h1 heading", async () => {
      await expect(page.getByRole("heading", { level: 1, name: TEST_EVENT_NAME })).toBeVisible();
    });

    await test.step("group link points to the hosting group", async () => {
      const groupLink = page.getByRole("link", { name: TEST_GROUP_NAME }).last();
      await expect(groupLink).toBeVisible();
      await expect(groupLink).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`);
    });

    await test.step("kind badge shows the in-person kind", async () => {
      const kindBadge = getIntroSection(page)
        .locator(".custom-badge")
        .filter({ hasText: /^in-person$/ });
      await expect(kindBadge).toBeVisible();
      await expect(kindBadge).toHaveText("in-person");
    });
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
    await page.locator('[data-attendance-role="actions-menu"] summary').click();
    const shareModal = page.locator('share-modal[trigger-variant="menu-item"]');
    const expectedEventPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`;
    await expect(shareModal).toHaveAttribute("title", `${TEST_GROUP_NAME} · ${TEST_EVENT_NAME}`);
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

  test("event page sends its UTM attribution and removes it from the URL", async ({ page }) => {
    // Read the rendered event identifier before watching its page-view endpoint.
    const eventId = await page
      .locator('[data-page-view][data-entity-type="event"]')
      .getAttribute("data-entity-id");
    expect(eventId).toBeTruthy();
    const pageViewRequestPromise = page.waitForRequest(
      (request) =>
        request.method() === "POST" && new URL(request.url()).pathname === `/events/${eventId}/views`,
    );

    // Open the event from a campaign link that also carries a non-UTM parameter.
    const eventPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}`;
    await navigateToPath(
      page,
      `${eventPath}?ref=home&utm_source=newsletter&utm_medium=&utm_campaign=spring-launch#about`,
    );

    // Verify the beacon carries only the non-empty UTM parameters.
    const pageViewRequest = await pageViewRequestPromise;
    expect(Object.fromEntries(new URL(pageViewRequest.url()).searchParams)).toEqual({
      utm_campaign: "spring-launch",
      utm_source: "newsletter",
    });

    // Verify the address bar keeps the other parameter and the hash.
    await expect(page).toHaveURL(buildE2eUrl(`${eventPath}?ref=home#about`));
  });

  test("availability refreshes capacity and remaining spots", async ({ page }) => {
    // Let the initial availability fetch settle so the watcher only matches the reload's
    // response, whose body stays readable after navigation.
    await expect(page.locator('[data-availability-url][data-availability-hydrated="true"]')).toBeAttached();

    // Watch the public availability endpoint before reloading the event page.
    const availabilityPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}/availability`;
    const availabilityPromise = waitForResponseMatching(page, {
      method: "GET",
      pathname: availabilityPath,
      status: 200,
    }).then((response) => response.json());

    // Reload the page and read the same payload used by the availability UI.
    await page.reload();
    const availability = await availabilityPromise;
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

  test("event info cards show date, venue and capacity", async ({ page }) => {
    await test.step("date card shows the seeded date and time range", async () => {
      const eventDateSection = getEventInfoSection(page, "Event date");
      const expectedDate = await getPrimaryEventDateParts(page);
      await expect(page.getByText("Event date", { exact: true })).toBeVisible();
      await expect(eventDateSection.getByText(expectedDate.date, { exact: true })).toBeVisible();
      await expect(eventDateSection.getByText(expectedDate.timeRange, { exact: true })).toBeVisible();
      await expect(eventDateSection.getByText("TBD", { exact: true })).toHaveCount(0);
    });

    await test.step("location card shows the seeded venue and map trigger", async () => {
      const locationSection = getEventInfoSection(page, "Location");
      await expect(page.getByText("Location", { exact: true })).toBeVisible();
      await expect(locationSection.getByText(PRIMARY_EVENT_LOCATION, { exact: true }).first()).toBeVisible();
      await expect(locationSection.getByRole("button", { name: "Open full map view" }).first()).toBeVisible();
      await expect(locationSection.getByText("Virtual event", { exact: true })).toHaveCount(0);
      await expect(locationSection.getByText("Location not provided", { exact: true })).toHaveCount(0);
    });

    await test.step("capacity shows the seeded limit", async () => {
      await expect(page.getByText(/Capacity:\s*100/)).toBeVisible();
    });
  });

  test("event content sections show seeded description, tags, links, gallery, people and agenda", async ({
    page,
  }) => {
    await test.step("about section shows the seeded description", async () => {
      const aboutSection = getEventAboutSection(page);
      await expect(aboutSection).toContainText("About this event");
      await expect(aboutSection.locator(".markdown")).toContainText(PRIMARY_EVENT_DESCRIPTION);
    });

    await test.step("tags section lists the seeded tags", async () => {
      await expect(page.getByText("Tags", { exact: true }).first()).toBeVisible();
      for (const tag of ["meetup", "tech", "networking"]) {
        await expect(page.getByText(tag, { exact: true })).toBeVisible();
      }
    });

    await test.step("meetup link points to the seeded event page", async () => {
      const meetupLink = page.getByRole("link", { name: "Meetup", exact: true });
      await expect(meetupLink).toBeVisible();
      await expect(meetupLink).toHaveAttribute("href", "https://www.meetup.com/test-group/events/123456789/");
    });

    await test.step("gallery section renders the images gallery", async () => {
      await expect(page.getByText("Gallery", { exact: true }).first()).toBeVisible();
      await expect(page.locator("images-gallery")).toBeVisible();
    });

    await test.step("people sections list the seeded sponsor, hosts and speakers", async () => {
      await expect(getPeopleSection(page, "Sponsors")).toContainText("Tech Corp");
      await expect(getPeopleSection(page, "Hosts")).toContainText("E2E Organizer One");
      await expect(getPeopleSection(page, "Featured speakers")).toContainText("E2E Member One");
      await expect(getPeopleSection(page, "Speakers")).toContainText("E2E Member Two");
    });

    await test.step("agenda lists the seeded sessions and their speakers", async () => {
      await expect(page.getByText("Agenda", { exact: true })).toBeVisible();
      await expect(page.getByText("Opening Keynote")).toBeVisible();
      await expect(page.getByText("Technical Workshop")).toBeVisible();

      // The labels filter is omitted when no session has labels.
      await expect(page.locator("#agenda-label-filter")).toHaveCount(0);

      const keynoteItem = page.locator("li", { hasText: "Opening Keynote" });
      await expect(keynoteItem.getByText("SPEAKERS", { exact: true })).toBeVisible();
      await expect(keynoteItem.getByText("E2E Member One")).toBeVisible();
      await expect(keynoteItem.getByText("E2E Member Two")).toBeVisible();
    });
  });

  test.describe("primary event interactions", () => {
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

      // Keep the real map runtime while removing the external basemap dependency.
      await routeEmptyBasemap(page);

      // Open the full map modal from the location preview.
      await mapButton.click();

      // Verify the modal opens and MapLibre initializes the modal map.
      await expect(mapModal).toBeVisible();
      await expect(modalMap).toHaveClass(/maplibregl-map/);

      // Verify only the modal map exposes zoom controls.
      const zoomInButton = modalMap.getByRole("button", { name: "Zoom in" });
      await expect(zoomInButton).toBeVisible();
      await expect(modalMap.getByRole("button", { name: "Zoom out" })).toBeVisible();
      await expect(page.locator("#event-map").getByRole("button", { name: "Zoom in" })).toHaveCount(0);

      // Zoom in until MapLibre disables the control at its maximum zoom. Let each
      // zoom step settle before clicking again, since clicking mid-animation
      // restarts the zoom from the intermediate level and gains less than one level.
      await expect(async () => {
        if (await zoomInButton.isEnabled()) await zoomInButton.click();
        await expect(zoomInButton).toBeDisabled({ timeout: 1_000 });
      }).toPass({ intervals: [0], timeout: 20_000 });
      await expect(modalMap.getByRole("button", { name: "Zoom out" })).toBeEnabled();

      // Verify zooming keeps the modal open.
      await expect(mapModal).toBeVisible();

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

      // Close the modal with Escape and verify focus returns to the map trigger.
      await page.keyboard.press("Escape");
      await expect(mapModal).toBeHidden();
      await expect(mapButton).toBeFocused();
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
    const availabilityPromise = waitForResponseMatching(page, {
      method: "GET",
      pathname: availabilityPath,
      status: 200,
    }).then((response) => response.json());
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, eventSlug);

    // Verify the server and page both expose the exhausted capacity state.
    const availability = await availabilityPromise;
    expect(availability.capacity).toBe(1);
    expect(availability.remaining_capacity).toBe(0);
    await expect(page.locator("[data-availability-capacity]")).toHaveText("1");
    await expect(page.locator("[data-availability-sold-out-ribbon]")).toBeVisible();
    await expect(page.locator("[data-availability-sold-out-ribbon]")).toContainText("Sold out");
    await expect(page.locator('[data-availability-caption="remaining"]')).toBeHidden();
    await expect(page.locator('[data-availability-caption="waitlist"]')).toBeHidden();
  });

  test("shows the waiting list size when no capacity remains", async ({ page }) => {
    // Load the full event whose waiting list holds two seeded members.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, DASHBOARD_WAITLIST_EVENT_SLUG);
    await expect(page.locator('[data-availability-url][data-availability-hydrated="true"]')).toBeAttached();

    // Verify the queue size replaces the remaining seats caption.
    await expect(page.locator("[data-availability-capacity]")).toHaveText("1");
    await expect(page.locator("[data-availability-sold-out-ribbon]")).toBeVisible();
    await expect(page.locator('[data-availability-caption="remaining"]')).toBeHidden();
    await expect(page.locator('[data-availability-caption="waitlist"]')).toBeVisible();
    await expect(page.locator("[data-availability-waitlist]")).toHaveText("2");
  });
});

test.describe("event page - responsive", () => {
  test("gallery shows its position and swipes in the lightbox @mobile", async ({ page }) => {
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    const gallery = page.locator("images-gallery");
    const lightbox = gallery.locator(".modal");
    const activeSlideImage = lightbox.locator(".z-30.translate-x-0 img");
    const counter = gallery.locator("[data-snap-counter]");
    const dots = gallery.locator("[data-snap-dots] .snap-dot");
    const secondTile = gallery.getByRole("button", { name: `Open Event ${TEST_EVENT_NAME} image 2` });

    await test.step("dots and counter follow the tiles", async () => {
      await gallery.scrollIntoViewIfNeeded();
      await expect(dots).toHaveCount(2);
      await expect(dots.first()).toHaveAttribute("data-active", "");
      await expect(counter).toHaveText("1 / 2");

      await gallery.locator(":has(+ [data-snap-dots])").evaluate((list) => {
        list.scrollTo({ left: list.scrollWidth });
      });
      await expect(dots.last()).toHaveAttribute("data-active", "");
      await expect(counter).toHaveText("2 / 2");
    });

    await test.step("a tile opens the lightbox on its image", async () => {
      await secondTile.tap();
      await expect(lightbox).not.toHaveClass(/opacity-0/);
      await expect(activeSlideImage).toHaveAttribute("alt", `Event ${TEST_EVENT_NAME} image 2`);
    });

    await test.step("a swipe changes the image and a short one does not", async () => {
      await swipeHorizontally(page, 300, 150);
      await expect(activeSlideImage).toHaveAttribute("alt", `Event ${TEST_EVENT_NAME} image 1`);

      await swipeHorizontally(page, 150, 300);
      await expect(activeSlideImage).toHaveAttribute("alt", `Event ${TEST_EVENT_NAME} image 2`);

      await swipeHorizontally(page, 300, 270);
      await expect(activeSlideImage).toHaveAttribute("alt", `Event ${TEST_EVENT_NAME} image 2`);
    });

    await test.step("the close button still works", async () => {
      await lightbox.getByRole("button", { name: "Close" }).tap();
      await expect(lightbox).toHaveClass(/opacity-0/);
    });
  });

  test("a single gallery image has no position row and ignores swipes @mobile", async ({ page }) => {
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    const gallery = page.locator("images-gallery");
    const lightbox = gallery.locator(".modal");
    const activeSlideImage = lightbox.locator(".z-30.translate-x-0 img");

    // The seed has no single-image event, so trim the rendered gallery to one image.
    await gallery.evaluate((element) => {
      element.images = element.images.slice(1);
    });
    await expect(gallery.locator("[data-snap-dots]")).toHaveCount(0);

    // A swipe leaves the only slide in place.
    await gallery.getByRole("button", { name: `Open Event ${TEST_EVENT_NAME} image 1` }).tap();
    await expect(lightbox).not.toHaveClass(/opacity-0/);
    await swipeHorizontally(page, 300, 100);
    await expect(activeSlideImage).toHaveCount(1);
    await expect(activeSlideImage).toHaveAttribute("alt", `Event ${TEST_EVENT_NAME} image 1`);
    await expect(lightbox).not.toHaveClass(/opacity-0/);
  });

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

  test("social links swap between mobile and desktop variants at the md breakpoint", async ({ page }) => {
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

test.describe("event page - phone layout @mobile", () => {
  /** Checks that a dialog opened as a sheet on the bottom edge with a 44px close button. */
  const expectBottomSheet = async (page, dialog) => {
    const panel = dialog.locator(".sheet-panel");
    const close = dialog.locator(".sheet-head button");

    await expect(panel).toHaveCSS("position", "fixed");
    await expect
      .poll(async () => {
        const box = await panel.boundingBox();
        return Math.round(box.y + box.height);
      })
      .toBe(page.viewportSize().height);
    expect(await close.boundingBox()).toMatchObject({ height: 44, width: 44 });
  };

  test("action row offers Share and Add to calendar as 44px pills", async ({ page }) => {
    // Load an upcoming event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Find the two pills in the summary.
    const summary = getIntroSection(page);
    const share = summary.locator('share-modal[trigger-variant="action"]').getByRole("button", {
      name: "Share",
    });
    const calendar = summary.getByRole("link", { name: "Add to calendar" });

    // Verify they sit side by side at the tap size.
    await expect(share).toBeVisible();
    await expect(calendar).toBeVisible();
    const [shareBox, calendarBox] = [await share.boundingBox(), await calendar.boundingBox()];
    expect(shareBox.height).toBe(44);
    expect(calendarBox.height).toBe(44);
    expect(calendarBox.y).toBe(shareBox.y);
    expect(calendarBox.x).toBeGreaterThan(shareBox.x + shareBox.width);
    expect(calendarBox.width).toBe(shareBox.width);

    // Verify the calendar link points at the event's public file.
    await expect(calendar).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/${TEST_EVENT_SLUG}/calendar.ics`,
    );

    // Verify Share falls back to the sheet where the system share is missing.
    await share.tap();
    await expectBottomSheet(page, page.getByRole("dialog", { name: "Share" }));
  });

  test("past events show a Past event pill and Share takes the row", async ({ page }) => {
    // Load a past event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, "alpha-past-roundup");

    // Verify the pill shows and there is no calendar to add to.
    const summary = getIntroSection(page);
    await expect(summary.getByText("Past event", { exact: true })).toBeVisible();
    await expect(summary.getByRole("link", { name: "Add to calendar" })).toHaveCount(0);

    // Verify Share fills the row on its own.
    const share = summary.locator('share-modal[trigger-variant="action"]');
    const [shareBox, rowBox] = [await share.boundingBox(), await share.locator("..").boundingBox()];
    expect(shareBox.width).toBe(rowBox.width);
  });

  test("canceled events keep the ribbon clear of the title and drop the calendar", async ({ page }) => {
    // Load a canceled event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_CANCELED_PUBLIC_EVENT.slug);

    // Verify the ribbon shows, the title clears it and the calendar is gone.
    await expect(page.getByText("Canceled", { exact: true })).toBeVisible();
    await expect(page.locator(".event-title-col")).toHaveCSS("padding-right", "36px");
    await expect(getIntroSection(page).getByRole("link", { name: "Add to calendar" })).toHaveCount(0);
  });

  test("sold-out events keep the ribbon clear of the title", async ({ page }) => {
    // Load the full event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, "alpha-waitlist-lab");

    // Verify the title makes room once availability shows the ribbon.
    await expect(page.locator("[data-availability-sold-out-ribbon]")).toBeVisible();
    await expect(page.locator(".event-title-col")).toHaveCSS("padding-right", "36px");
  });

  test("meta and social links share a row without overflowing at 320", async ({ page }) => {
    // Load an event with a Meetup link and add a second link, as Luma would.
    await page.setViewportSize({ width: 320, height: 640 });
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const social = page.locator('div.md\\:hidden:has(a[title="Meetup"])');
    await social.locator('a[title="Meetup"]').evaluate((link) => link.after(link.cloneNode(true)));

    // Verify the links stay on the right edge of the gutter, in the meta row.
    const socialBox = await social.boundingBox();
    const metaBox = await social.locator("..").boundingBox();
    expect(Math.round(socialBox.x + socialBox.width)).toBe(308);
    expect(socialBox.y).toBeGreaterThanOrEqual(metaBox.y);
    expect(socialBox.y + socialBox.height).toBeLessThanOrEqual(metaBox.y + metaBox.height);
    expect(await getPageOverflow(page)).toBeLessThanOrEqual(0);

    // Verify the narrower meta column keeps the remaining caption on one line.
    const remaining = page.locator('[data-availability-caption="remaining"]');
    await expect(remaining).toBeVisible();
    expect((await remaining.boundingBox()).height).toBeLessThanOrEqual(16);
  });

  test("a long unbroken place name stays inside the map pill", async ({ page }) => {
    // Load an event with a map at the narrowest phone and give the pill a long name.
    await page.setViewportSize({ width: 320, height: 640 });
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const pill = page.locator('[class*="phone:wrap-anywhere"]:visible').first();
    await pill.evaluate((node) => {
      node.textContent = "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch";
    });

    // Verify the name wraps rather than running past the pill's edge.
    expect(await pill.evaluate((node) => node.scrollWidth <= node.clientWidth)).toBe(true);
  });

  test("the date card shows the large desktop date", async ({ page }) => {
    // Load a single-day event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const panel = page.locator("[data-registration-window-date-panel]");

    // Verify the full date replaces the short one.
    await expect(panel.locator(".phone\\:text-2xl\\/7")).toBeVisible();
    await expect(panel.locator(".phone\\:text-2xl\\/7")).toHaveCSS("font-size", "24px");
    await expect(panel.locator("div.sm\\:hidden")).toBeHidden();
  });

  test("multi-day dates stack below 375 and sit side by side above it", async ({ page }) => {
    // Load a multi-day event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_MULTI_DAY_EVENT.slug);
    const panel = page.locator("[data-registration-window-date-panel]");
    const range = panel.locator("div.flex.items-start");
    const arrow = panel.getByText("→", { exact: true });

    // Use dates wider than the seed's, so the fit does not depend on the month.
    await panel.locator(".phone\\:text-lg\\/6").evaluateAll((dates) => {
      dates.forEach((date, index) => {
        date.textContent = `Nov ${28 + 2 * index}, 2026`;
      });
    });

    // Verify the narrow widths stack From and To without the arrow.
    for (const width of [320, 360]) {
      await page.setViewportSize({ width, height: 700 });
      await expect(range).toHaveCSS("flex-direction", "column");
      await expect(arrow).toBeHidden();
      expect(await getPageOverflow(page)).toBeLessThanOrEqual(0);
    }

    // Verify wider phones keep desktop's row.
    await page.setViewportSize({ width: 402, height: 874 });
    await expect(range).toHaveCSS("flex-direction", "row");
    await expect(arrow).toBeVisible();
    expect(await getPageOverflow(page)).toBeLessThanOrEqual(0);

    // Verify the labels read like the eyebrow, because the panel's stone-400 fails contrast.
    const eyebrowColor = await page
      .getByText("Event date", { exact: true })
      .first()
      .evaluate((eyebrow) => getComputedStyle(eyebrow).color);
    await expect(panel.getByText("From", { exact: true })).toHaveCSS("color", eyebrowColor);
    await expect(panel.getByText("To", { exact: true })).toHaveCSS("color", eyebrowColor);
  });

  test("the location card shows the full address over a 150px map", async ({ page }) => {
    // Load an event with coordinates.
    await routeEmptyBasemap(page);
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const location = getEventInfoSection(page, "Location");

    // Verify the long address pill shows and the map keeps its height.
    await expect(location.getByText(PRIMARY_EVENT_LOCATION, { exact: true }).first()).toBeVisible();
    const panel = location.locator(".phone\\:h-\\[150px\\]");
    expect((await panel.boundingBox()).height).toBe(150);

    // Verify the map opens as a sheet that the close button dismisses.
    await location.getByRole("button", { name: "Open full map view" }).tap();
    const mapSheet = page.locator("#event-map-modal");
    await expectBottomSheet(page, mapSheet);
    await mapSheet.locator(".sheet-head button").tap();
    await expect(mapSheet).toBeHidden();
  });

  test("directions open Apple Maps on an iPhone", async ({ page }) => {
    // Load an event with coordinates under the iPhone user agent.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Verify the Google link was swapped.
    const directions = getEventInfoSection(page, "Location").getByRole("link", { name: "Directions" });
    await expect(directions).toBeVisible();
    await expect(directions).toHaveAttribute(
      "href",
      /^https:\/\/maps\.apple\.com\/directions\?destination=40\.71\d*,-74\.00\d*$/,
    );
    await expect(directions).toHaveAttribute("target", "_blank");
  });

  test("an event without coordinates keeps its address pill and directions", async ({ owned, page }) => {
    // Create an in-person event that stores its address but no coordinates.
    const event = owned.event({ groupId: TEST_GROUP_IDS.community1.alpha, kind: "in-person" });
    queryE2eDatabase(`
      update event
      set venue_city = 'Chicago', venue_name = 'Harbor Hall'
      where event_id = ${sqlUuid(event.eventId)}
    `);

    // Load the event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, event.slug);
    const location = getEventInfoSection(page, "Location");

    // Verify the card shows the place over the static map.
    await expect(location.getByText("Harbor Hall, Chicago", { exact: true }).first()).toBeVisible();

    // Verify the place is the destination, since there is nothing else to navigate to.
    await expect(location.getByRole("link", { name: "Directions" })).toHaveAttribute(
      "href",
      "https://maps.apple.com/directions?destination=Harbor%20Hall,%20Chicago",
    );
  });

  for (const { name, slug } of [
    { name: "virtual events", slug: "alpha-event-2" },
    { name: "events without a location", slug: "alpha-event-3" },
  ]) {
    test(`${name} drop the location card and directions`, async ({ page }) => {
      // Load the event.
      await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, slug);

      // Verify the card takes no room and offers no directions.
      await expect(getEventInfoSection(page, "Location")).toBeHidden();
      await expect(page.locator("[data-directions-link]")).toHaveCount(0);
    });
  }

  test("section headings pin under the header", async ({ page }) => {
    // Load an event and find a section title.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const heading = page.getByText("About this event", { exact: true });

    // Verify the title takes the strip's look.
    await expect(heading).toHaveCSS("position", "sticky");
    await expect(heading).toHaveCSS("font-size", "15px");

    // Scroll until the title would sit just under the header's bottom edge.
    await heading.evaluate((element) => {
      window.scrollTo(0, element.getBoundingClientRect().top + window.scrollY - 43);
    });

    // Verify it stops at the header's hairline.
    await expect.poll(async () => Math.round((await heading.boundingBox()).y)).toBe(63);
  });

  test("the About text collapses behind Read more", async ({ page }) => {
    // Load an event with a short description.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const about = getEventAboutSection(page);
    const body = about.locator(".read-more-body");
    const toggle = about.getByRole("button", { name: "Read more" });

    // Verify a short description offers nothing to expand.
    await expect(body).toContainText(PRIMARY_EVENT_DESCRIPTION);
    await expect(toggle).toBeHidden();

    // Grow it past three lines.
    await body.evaluate((element) => {
      element.firstElementChild.textContent = "Long event description. ".repeat(40);
    });

    // Verify it clips to three lines and opens on tap.
    await expect(toggle).toBeVisible();
    expect(await body.evaluate((element) => element.clientHeight)).toBe(72);
    await toggle.tap();
    await expect(about.getByRole("button", { name: "Read less" })).toHaveAttribute("aria-expanded", "true");
    expect(await body.evaluate((element) => element.clientHeight)).toBeGreaterThan(72);
  });

  test("agenda descriptions collapse behind Read more", async ({ page }) => {
    // Load an event whose sessions have descriptions.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const block = page.locator("[data-agenda-session] .read-more").first();
    const body = block.locator(".read-more-body");
    const toggle = block.getByRole("button", { name: "Read more" });

    // Grow one past three lines.
    await expect(toggle).toBeHidden();
    await body.evaluate((element) => {
      element.firstElementChild.textContent = "Long session description. ".repeat(40);
    });

    // Verify it clips to three lines and opens on tap.
    await expect(toggle).toBeVisible();
    expect(await body.evaluate((element) => element.clientHeight)).toBe(72);
    await toggle.tap();
    await expect(block.getByRole("button", { name: "Read less" })).toBeVisible();
  });

  test("agenda tabs stay on one scrolling row at the tap size", async ({ page }) => {
    // Load a multi-day event.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_MULTI_DAY_EVENT.slug);
    const firstTab = page.locator("button[data-day-tab]").first();
    const tabs = page.locator("ul:has(> li > button[data-day-tab])");

    // Verify the row scrolls instead of wrapping, and each tab is a 44px target.
    await expect(tabs).toHaveCSS("flex-wrap", "nowrap");
    await expect(tabs).toHaveCSS("overflow-x", "auto");
    expect((await firstTab.boundingBox()).height).toBeGreaterThanOrEqual(44);
  });

  test("contact organizers opens a sheet from a full-width button", async ({ page }) => {
    // Load an event and find the button.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const contact = page.locator("#open-contact-modal");

    // Verify the button fills its row at the tap size.
    const [contactBox, rowBox] = [await contact.boundingBox(), await contact.locator("..").boundingBox()];
    expect(contactBox.height).toBe(44);
    expect(contactBox.width).toBe(rowBox.width);

    // Verify the modal opens as a sheet.
    await contact.tap();
    const sheet = page.locator("#contact-modal");
    await expect(sheet.locator("[data-contact-sign-in]")).toBeVisible();
    await expectBottomSheet(page, sheet);
  });

  test("the proposal form opens a sheet from a full-width button", async ({ page }) => {
    // Load an event with an open Call for Speakers.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, "alpha-cfs-summit");
    const submit = page.locator("#open-cfs-modal");

    // Verify the button fills its row at the tap size.
    const [submitBox, rowBox] = [await submit.boundingBox(), await submit.locator("..").boundingBox()];
    expect(submitBox.height).toBe(44);
    expect(submitBox.width).toBe(rowBox.width);

    // Verify the modal opens as a sheet.
    await submit.tap();
    await expectBottomSheet(page, page.locator("#cfs-modal"));
  });

  test("breadcrumb opens its links over the event summary", async ({ page }) => {
    // Load an upcoming event once its controls have hydrated.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    await waitForPageSettled(page);
    const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
    const links = breadcrumb.getByRole("listbox", { name: "Breadcrumb links" });
    await expect(links).toBeHidden();

    // Open the trail.
    await breadcrumb.getByRole("button", { name: TEST_EVENT_NAME }).tap();
    await expect(links).toBeVisible();

    // Verify every level is listed and only the current page has no link.
    const options = links.getByRole("option");
    const groupPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}`;
    await expect(options).toHaveText(["Home", TEST_COMMUNITY_TITLE, TEST_GROUP_NAME, TEST_EVENT_NAME]);
    await expect(options.nth(0)).toHaveAttribute("href", "/");
    await expect(options.nth(1)).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME}`);
    await expect(options.nth(2)).toHaveAttribute("href", groupPath);
    await expect(options.nth(3)).not.toHaveAttribute("href");
    await expect(options.nth(3)).toHaveAttribute("aria-selected", "true");

    // Verify the rows reach 44px once the opening transition ends.
    await expect
      .poll(() => options.evaluateAll((rows) => rows.map((row) => row.getBoundingClientRect().height)))
      .toEqual([44, 44, 44, 44]);

    // Verify the list reaches the summary and every row paints on top of it.
    const lastRow = await options.last().boundingBox();
    const summary = await getIntroSection(page).boundingBox();
    expect(lastRow.y + lastRow.height / 2).toBeGreaterThan(summary.y);
    const paintedRows = await options.evaluateAll((rows) =>
      rows.map((row) => {
        const { height, left, top, width } = row.getBoundingClientRect();
        return row.contains(document.elementFromPoint(left + width / 2, top + height / 2));
      }),
    );
    expect(paintedRows).toEqual([true, true, true, true]);

    // Follow the group row.
    await options.nth(2).tap();
    await expect(page).toHaveURL(buildE2eUrl(groupPath));
    await expect(page.getByRole("heading", { level: 1, name: TEST_GROUP_NAME })).toBeVisible();
  });

  test("the page does not overflow at phone widths", async ({ page }) => {
    // Load an event with a map, an agenda and a gallery.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Verify each supported width.
    for (const width of [320, 360, 402]) {
      await page.setViewportSize({ width, height: 800 });
      await expect.poll(() => getPageOverflow(page)).toBeLessThanOrEqual(0);
    }
  });
});

test.describe("event page - desktop version on a phone @mobile", () => {
  test("keeps the desktop event page", async ({ page }) => {
    // Load an upcoming event in the desktop version.
    await enableDesktopVersion(page);
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Verify the attendance controls stay in the summary, with no bar.
    const container = getAttendanceContainer(page);
    await expect(container).toHaveAttribute("data-availability-hydrated", "true");
    await expect(container).toBeVisible();
    await expect(container).not.toHaveCSS("position", "fixed");
    await expect(container.locator('[data-attendance-role="bar-summary"]')).toBeHidden();

    // Verify the phone pills and pinned headings stay out.
    const summary = getIntroSection(page);
    await expect(summary.locator('share-modal[trigger-variant="action"]')).toBeHidden();
    await expect(summary.getByRole("link", { name: "Add to calendar" })).toBeHidden();
    await expect(page.locator(".section-strip").first()).not.toHaveCSS("position", "sticky");

    // Verify Share stays in the actions menu and opens the centred modal rather than a sheet.
    await page.locator('[data-attendance-role="actions-menu"] summary').click();
    await page.locator('share-modal[trigger-variant="menu-item"]').getByRole("button").click();
    const dialog = page.getByRole("dialog", { name: "Share" });
    await expect(dialog).toBeVisible();
    await expect(dialog.locator(".sheet-panel")).not.toHaveCSS("position", "fixed");
  });
});

test.describe("event page - directions on Android @mobile", () => {
  test.use({ userAgent: ANDROID_USER_AGENT });

  test("directions stay on Google Maps", async ({ page }) => {
    // Load an event with coordinates under an Android user agent.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Verify the server's link is left alone.
    await expect(page.locator("[data-directions-link]")).toHaveAttribute(
      "href",
      /^https:\/\/www\.google\.com\/maps\/dir\/\?api=1&destination=40\.71\d*%2C-74\.00\d*$/,
    );
  });
});

test.describe("event page - alpha event logo", () => {
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

  test("labels filter shows sessions with any selected label", async ({ page }) => {
    // Target the labels filter, its status and the second day controls.
    const labelFilter = page.locator("label-selector#agenda-label-filter");
    const filterStatus = page.locator("[data-agenda-filter-status]");
    const secondDayTab = page.locator("button[data-day-tab]").nth(1);
    const secondDayPanel = page.locator('[data-day-content="day-1"]');
    const emptyMessage = "No sessions match the selected labels.";

    // Verify selecting a first day label leaves the second day empty.
    await selectLabels(labelFilter, ["Keynotes"]);
    await expect(filterStatus).toHaveText("Showing 1 of 2 sessions.");
    await expect(page.getByText("Summit Kickoff")).toBeVisible();
    await secondDayTab.click();
    await expect(secondDayPanel.getByText(emptyMessage)).toBeVisible();
    await expect(page.getByText("Summit Wrap-Up")).toBeHidden();

    // Verify adding a second day label shows sessions matching either label.
    await selectLabels(labelFilter, ["Community"]);
    await expect(filterStatus).toHaveText("Showing 2 of 2 sessions.");
    await expect(page.getByText("Summit Wrap-Up")).toBeVisible();
    await expect(secondDayPanel.getByText(emptyMessage)).toBeHidden();

    // Verify removing the selected chips below the input restores the unfiltered agenda.
    await labelFilter.getByRole("button", { name: "Remove Keynotes", exact: true }).click();
    await expect(filterStatus).toHaveText("Showing 1 of 2 sessions.");
    await labelFilter.getByRole("button", { name: "Remove Community", exact: true }).click();
    await expect(filterStatus).toHaveText("");
    await expect(page.getByText("Summit Wrap-Up")).toBeVisible();
    await page.locator("button[data-day-tab]").first().click();
    await expect(page.getByText("Summit Kickoff")).toBeVisible();
  });

  test("labels filter closes after a pick and reopens from the focused input", async ({ page }) => {
    // Target the labels filter search input and its options list.
    const labelFilter = page.locator("label-selector#agenda-label-filter");
    const searchInput = labelFilter.getByRole("combobox");
    const optionsList = labelFilter.getByRole("listbox");

    // Verify picking a label closes the list and keeps the input focused.
    await searchInput.click();
    await expect(optionsList).toBeVisible();
    await labelFilter.getByRole("option", { name: "Keynotes", exact: true }).click();
    await expect(optionsList).toBeHidden();
    await expect(searchInput).toBeFocused();
    await expect(labelFilter.getByRole("button", { name: "Remove Keynotes", exact: true })).toBeVisible();

    // Verify clicking the focused input reopens the list and clicking it again closes it.
    await searchInput.click();
    await expect(optionsList).toBeVisible();
    await searchInput.click();
    await expect(optionsList).toBeHidden();

    // Verify typing shows a single clear button and picking a label clears the search.
    await searchInput.fill("Comm");
    await expect(labelFilter.getByRole("button", { name: "Clear search" })).toHaveCount(1);
    await labelFilter.getByRole("option", { name: "Community", exact: true }).click();
    await expect(searchInput).toHaveValue("");
    await expect(labelFilter.getByRole("button", { name: "Clear search" })).toHaveCount(0);
    await expect(labelFilter.getByRole("button", { name: "Remove Community", exact: true })).toBeVisible();
  });

  test("labels filter opens on touch without focusing the search input @mobile", async ({ page }) => {
    // Target the labels filter search input and its options.
    const labelFilter = page.locator("label-selector#agenda-label-filter");
    const searchInput = labelFilter.getByRole("combobox");

    // Verify the first touch lists the labels without focusing the input.
    await searchInput.tap();
    await expect(labelFilter.getByRole("option", { name: "Keynotes", exact: true })).toBeVisible();
    await expect(searchInput).not.toBeFocused();

    // Verify picking a label filters the agenda, closes the list and keeps the input unfocused.
    await labelFilter.getByRole("option", { name: "Keynotes", exact: true }).tap();
    await expect(page.locator("[data-agenda-filter-status]")).toHaveText("Showing 1 of 2 sessions.");
    await expect(labelFilter.getByRole("listbox")).toBeHidden();
    await expect(searchInput).not.toBeFocused();

    // Verify the next touch reopens the list and a second touch focuses the input to search.
    await searchInput.tap();
    await expect(labelFilter.getByRole("listbox")).toBeVisible();
    await expect(searchInput).not.toBeFocused();
    await searchInput.tap();
    await expect(searchInput).toBeFocused();
    await expect(labelFilter.getByRole("listbox")).toBeVisible();
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
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, "alpha-past-roundup");

    // Verify the recording replaces live meeting and attendance actions.
    const recordingLink = page.getByRole("link", { name: "View recording" });
    await expect(page.getByText("Use the link below to watch the recording.")).toBeVisible();
    await expect(recordingLink).toHaveAttribute("href", "https://recordings.example.test/alpha-past-roundup");
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

test.describe("event page - co-hosts", () => {
  test("lists approved co-hosts with links to their community group pages", async ({ page }) => {
    // Load the seeded cross-community co-hosted event.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME_2,
      TEST_GROUP_SLUGS.community2.epsilon,
      TEST_COHOSTED_EVENT.slug,
    );

    // Verify each co-host links to its own community group page.
    await expect(page.getByText("Co-hosted with", { exact: true })).toBeVisible();
    const cohostsList = page.getByRole("list", { name: "Co-hosts" });
    await expect(cohostsList.getByRole("listitem")).toHaveCount(COHOSTED_EVENT_COHOSTS.length);
    for (const cohost of COHOSTED_EVENT_COHOSTS) {
      const cohostLink = cohostsList.getByRole("link", { name: new RegExp(cohost.name, "u") });
      await expect(cohostLink).toHaveAttribute("href", cohost.href);
      await expect(cohostLink).toContainText(cohost.communityDisplayName);
    }
  });

  test("events without co-hosts omit the co-hosts box", async ({ page }) => {
    // Load an event without co-hosts.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Verify the co-hosts box is not rendered.
    await expect(page.getByRole("heading", { level: 1, name: TEST_EVENT_NAME })).toBeVisible();
    await expect(page.getByText("Co-hosted with", { exact: true })).toHaveCount(0);
    await expect(page.getByRole("list", { name: "Co-hosts" })).toHaveCount(0);
  });
});

/** Formats a UTC date for public event page assertions. */
const formatUtcDate = (date) =>
  new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "long",
    timeZone: "UTC",
    year: "numeric",
  }).format(date);

/** Formats a UTC time for public event page assertions. */
const formatUtcTime = (date) =>
  new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    hour12: true,
    minute: "2-digit",
    timeZone: "UTC",
  }).format(date);

/** Selects an event people section, such as hosts or speakers, by its heading. */
const getPeopleSection = (page, heading) => page.getByText(heading, { exact: true }).locator("..");

/** Returns the primary event date text expected from data-starts. */
const getPrimaryEventDateParts = async (page) => {
  const startsAt = await page.locator("[data-attendance-container]").first().getAttribute("data-starts");
  expect(startsAt).toBeTruthy();

  const startDate = new Date(startsAt);
  const endDate = new Date(startDate.getTime() + 2 * 60 * 60 * 1000);

  return {
    date: formatUtcDate(startDate),
    timeRange: `${formatUtcTime(startDate)} - ${formatUtcTime(endDate)} UTC`,
  };
};
