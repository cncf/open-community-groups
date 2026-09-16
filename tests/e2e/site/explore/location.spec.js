import { expect, test } from "@playwright/test";
import { TEST_COMMUNITY_NAME, TEST_EVENT_NAMES, TEST_EVENT_SLUGS, TEST_GROUP_SLUGS } from "../../seed.js";
import { buildE2eUrl, navigateToPath } from "../../utils.js";

const CLOUDFRONT_NEW_YORK_HEADERS = {
  "CloudFront-Viewer-Latitude": "40.7128",
  "CloudFront-Viewer-Longitude": "-74.006",
};

const DISTANCE_SORT_QUERY = "Observability";

const OBSERVABILITY_DISTANCE_ORDER = TEST_EVENT_NAMES.gamma;

const OBSERVABILITY_NEW_YORK_EVENT = TEST_EVENT_NAMES.gamma[0];

test.describe("site explore location search", () => {
  test("orders and filters event JSON by CloudFront viewer distance", async ({ request }) => {
    // types/search.rs extracts CloudFront-Viewer-Latitude/Longitude and search_events sorts by distance.
    const sortedResponse = await request.get(buildE2eUrl(buildEventSearchPath()), {
      headers: CLOUDFRONT_NEW_YORK_HEADERS,
    });
    const sortedPayload = await sortedResponse.json();

    // Verify distance-sensitive JSON is not cached and follows seeded NY-before-Seattle coordinates.
    expect(sortedResponse.status()).toBe(200);
    expect(sortedResponse.headers()["cache-control"]).toBe("no-store");
    expect(sortedPayload.events.map((event) => event.name)).toEqual(OBSERVABILITY_DISTANCE_ORDER);

    // Verify the same CloudFront location powers the distance radius filter.
    const filteredResponse = await request.get(buildE2eUrl(buildEventSearchPath({ distance: "1000" })), {
      headers: CLOUDFRONT_NEW_YORK_HEADERS,
    });
    const filteredPayload = await filteredResponse.json();

    // Verify the distance radius filter keeps only the nearby event.
    expect(filteredResponse.status()).toBe(200);
    expect(filteredPayload.events.map((event) => event.name)).toEqual([OBSERVABILITY_NEW_YORK_EVENT]);
  });

  test("browser distance sort shows the CloudFront-nearest events first", async ({ page }) => {
    // Load explore with viewer headers so the Distance sort option is available.
    await page.setExtraHTTPHeaders(CLOUDFRONT_NEW_YORK_HEADERS);
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&ts_query=${encodeURIComponent(DISTANCE_SORT_QUERY)}&sort_by=distance`,
    );

    // Verify the list view keeps the same NY-before-Seattle order as the JSON endpoint.
    await expect(page.locator("#sort_selector")).toHaveValue("distance-asc");
    const eventCards = page.locator("#cards-list article");
    await expect(eventCards).toHaveCount(OBSERVABILITY_DISTANCE_ORDER.length);
    await expect(eventCards.locator(".card-title")).toHaveText(OBSERVABILITY_DISTANCE_ORDER);
  });

  test("event map markers expose accessible links to public event pages", async ({ page }) => {
    // Keep MapLibre running while avoiding external basemap tile dependencies.
    await page.route("https://tiles.openfreemap.org/styles/bright", (route) =>
      route.fulfill({
        headers: { "access-control-allow-origin": "*" },
        json: { layers: [], sources: {}, version: 8 },
      }),
    );
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

/** Builds the event search API path for distance sorting assertions. */
const buildEventSearchPath = (extraParams = {}) => {
  const params = new URLSearchParams({
    "community[0]": TEST_COMMUNITY_NAME,
    limit: "10",
    sort_by: "distance",
    sort_direction: "asc",
    ts_query: DISTANCE_SORT_QUERY,
    ...extraParams,
  });

  return `/explore/events/search?${params.toString()}`;
};
