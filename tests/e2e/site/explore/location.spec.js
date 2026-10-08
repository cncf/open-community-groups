import { expect, test } from "@playwright/test";
import { TEST_COMMUNITY_NAME, TEST_EVENT_NAMES, TEST_EVENT_SLUGS, TEST_GROUP_SLUGS } from "../../seed.js";
import { buildE2eUrl, navigateToPath, routeEmptyBasemap } from "../../utils.js";

const CLOUDFRONT_NEW_YORK_HEADERS = {
  "CloudFront-Viewer-Latitude": "40.7128",
  "CloudFront-Viewer-Longitude": "-74.006",
};

const DISTANCE_SORT_QUERY = "Observability";

const OBSERVABILITY_DISTANCE_ORDER = TEST_EVENT_NAMES.gamma;

const OBSERVABILITY_NEW_YORK_EVENT = TEST_EVENT_NAMES.gamma[0];

test.describe("site explore location search", () => {
  test("filters minimal event JSON by CloudFront viewer distance", async ({ request }) => {
    // The explore handlers read CloudFront-Viewer-Latitude/Longitude for the distance radius filter.
    const response = await request.get(buildE2eUrl(buildEventSearchPath({ distance: "1000" })), {
      headers: CLOUDFRONT_NEW_YORK_HEADERS,
    });
    const payload = await response.json();

    // Verify distance-sensitive JSON is not cached and keeps only the nearby event.
    expect(response.status()).toBe(200);
    expect(response.headers()["cache-control"]).toBe("no-store");
    expect(payload.events.map((event) => event.name)).toEqual([OBSERVABILITY_NEW_YORK_EVENT]);
  });

  test("browser distance sort shows the CloudFront-nearest events first", async ({ page }) => {
    // Load explore with viewer headers so the Distance sort option is available.
    await page.setExtraHTTPHeaders(CLOUDFRONT_NEW_YORK_HEADERS);
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&ts_query=${encodeURIComponent(DISTANCE_SORT_QUERY)}&sort_by=distance`,
    );

    // Verify the list view follows seeded NY-before-Seattle coordinates.
    await expect(page.locator("#sort_selector")).toHaveValue("distance-asc");
    const eventCards = page.locator("#cards-list article");
    await expect(eventCards).toHaveCount(OBSERVABILITY_DISTANCE_ORDER.length);
    await expect(eventCards.locator(".card-title")).toHaveText(OBSERVABILITY_DISTANCE_ORDER);
  });

  test("event map markers expose accessible links to public event pages", async ({ page }) => {
    // Keep MapLibre running while avoiding external basemap tile dependencies.
    await routeEmptyBasemap(page);
    await page.setExtraHTTPHeaders(CLOUDFRONT_NEW_YORK_HEADERS);

    // Open the map view directly; the events toolbar exposes calendar instead of a map toggle.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&ts_query=${encodeURIComponent(DISTANCE_SORT_QUERY)}&sort_by=distance&view_mode=map`,
    );

    // Verify only the event with its own seeded coordinates renders a marker link.
    await expect(page.locator("#map-box.maplibregl-map")).toBeVisible();
    const marker = page.locator(`a.marker-${TEST_EVENT_SLUGS.gamma[0]}[role="link"]`);
    await expect.poll(async () => marker.count()).toBe(1);
    await expect(marker).toBeVisible();
    await expect(page.locator("#loading-map")).not.toHaveClass(/is-loading/u);
    await expect(marker).toHaveAttribute("aria-label", OBSERVABILITY_NEW_YORK_EVENT);

    // Follow the marker without waiting for any external map tiles.
    await Promise.all([
      page.waitForURL(
        new RegExp(
          `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.gamma}/event/${TEST_EVENT_SLUGS.gamma[0]}$`,
        ),
      ),
      marker.click(),
    ]);
    await expect(page.getByRole("heading", { level: 1, name: OBSERVABILITY_NEW_YORK_EVENT })).toBeVisible();
  });
});

/** Builds the event search API path for distance filter assertions. */
const buildEventSearchPath = (extraParams = {}) => {
  const params = new URLSearchParams({
    "community[0]": TEST_COMMUNITY_NAME,
    ts_query: DISTANCE_SORT_QUERY,
    view_mode: "map",
    ...extraParams,
  });

  return `/explore/events/search?${params.toString()}`;
};
