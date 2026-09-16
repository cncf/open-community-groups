import { expect, test } from "@playwright/test";

import { TEST_COMMUNITY_NAME, TEST_EVENT_IDS } from "../../seed.js";
import { buildE2eUrl, navigateToPath } from "../../utils.js";

const FAVICON_CACHE_CONTROL = "public, max-age=604800";
const SITE_FAVICON_URL = "https://static.example.com/e2e/favicon.ico";

const E2E_STORED_IMAGE_PATH = "/images/7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png";
const FOREIGN_ORIGIN = "https://attacker.example";
const IMAGE_CACHE_CONTROL = "public, max-age=31536000, immutable";
const SAME_ORIGIN_RESOURCE_POLICY = "same-origin";

const APPLE_TOUCH_ICON_PATHS = ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"];
const DISABLED_IDENTITY_PROVIDER_PATHS = [
  "/log-in/oauth2/github",
  "/log-in/oauth2/github/callback",
  "/log-in/oidc/linuxfoundation",
  "/log-in/oidc/linuxfoundation/callback",
];

const CROSS_SITE_MUTATION_CASES = [
  {
    headers: { "Sec-Fetch-Site": "cross-site" },
    name: "Fetch Metadata cross-site signal",
  },
  {
    headers: { Origin: FOREIGN_ORIGIN },
    name: "foreign Origin",
  },
];

test.describe("site platform request contracts", () => {
  test("health check is readiness-only", async ({ request }) => {
    // router.rs::health_check returns only StatusCode::OK.
    const response = await request.get(buildE2eUrl("/health-check"));

    // Verify the readiness probe stays empty and successful.
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toBeUndefined();
    await expect(response.text()).resolves.toBe("");
  });

  test("favicon redirects to the configured site favicon with a cacheable response", async ({ request }) => {
    // router.rs::favicon redirects to site.favicon_url seeded in 00_site.sql.
    const response = await request.get(buildE2eUrl("/favicon.ico"), { maxRedirects: 0 });

    // Verify the redirect target and the week-long cache directive.
    expect(response.status()).toBe(303);
    expect(response.headers().location).toBe(SITE_FAVICON_URL);
    expect(response.headers()["cache-control"]).toBe(FAVICON_CACHE_CONTROL);
  });

  test("apple touch icon probes return not found", async ({ request }) => {
    for (const path of APPLE_TOUCH_ICON_PATHS) {
      await test.step(path, async () => {
        // The router registers both apple-touch-icon paths as explicit 404s.
        const response = await request.get(buildE2eUrl(path));

        // Verify mobile icon probes do not fall through to another route.
        expect(response.status()).toBe(404);
      });
    }
  });

  test("disabled OAuth and OIDC routes return not found", async ({ request }) => {
    for (const path of DISABLED_IDENTITY_PROVIDER_PATHS) {
      await test.step(path, async () => {
        // router.rs registers these identity routes only when their login flags are enabled.
        const response = await request.get(buildE2eUrl(path), { maxRedirects: 0 });

        // Verify the e2e config keeps disabled providers unreachable.
        expect(response.status()).toBe(404);
        expect(response.headers().location).toBeUndefined();
      });
    }
  });

  test("login page omits disabled OAuth and OIDC provider links", async ({ page }) => {
    // Load the login page rendered with tests/e2e/config/server.yml provider flags.
    await navigateToPath(page, "/log-in");
    const main = page.getByRole("main");

    // Verify template branches for GitHub OAuth and Linux Foundation OIDC stay absent.
    await expect(main.getByRole("heading", { name: "Log In" })).toBeVisible();
    await expect(main.locator('a[href^="/log-in/oauth2/"]')).toHaveCount(0);
    await expect(main.locator('a[href^="/log-in/oidc/"]')).toHaveCount(0);
    await expect(main.getByRole("link", { name: "GitHub", exact: true })).toHaveCount(0);
    await expect(main.getByRole("link", { name: "Linux Foundation SSO", exact: true })).toHaveCount(0);
  });

  test("stored images use immutable same-origin response headers", async ({ request }) => {
    // handlers/images.rs allows /images/{file} only with same-origin Origin/Referer evidence.
    const response = await request.get(buildE2eUrl(E2E_STORED_IMAGE_PATH), {
      headers: { Referer: buildE2eUrl(`/${TEST_COMMUNITY_NAME}`) },
    });
    const headers = response.headers();

    // Verify the stored image response matches serve_image headers.
    expect(response.status()).toBe(200);
    expect(headers["cache-control"]).toBe(IMAGE_CACHE_CONTROL);
    expect(headers["content-type"]).toBe("image/png");
    expect(headers["cross-origin-resource-policy"]).toBe(SAME_ORIGIN_RESOURCE_POLICY);
    expect(headers["x-content-type-options"]).toBe("nosniff");
  });

  test("stored images reject foreign hotlinking evidence", async ({ request }) => {
    // handlers/images.rs rejects before storage lookup when Origin/Referer is off-site.
    const response = await request.get(buildE2eUrl(E2E_STORED_IMAGE_PATH), {
      headers: { Referer: `${FOREIGN_ORIGIN}/article` },
    });

    // Verify the hotlinking guard returns the real handler status.
    expect(response.status()).toBe(403);
  });

  for (const crossSiteCase of CROSS_SITE_MUTATION_CASES) {
    test(`cross-site POST is rejected for ${crossSiteCase.name}`, async ({ request }) => {
      // router.rs::enforce_browser_same_origin rejects unsafe browser signals before handlers run.
      const response = await request.post(buildE2eUrl("/log-in"), {
        form: { password: "wrong-password", username: "wrong-user" },
        headers: crossSiteCase.headers,
        maxRedirects: 0,
      });

      // Verify the login mutation is blocked before it can create a session or redirect.
      expect(response.status()).toBe(403);
      expect(response.headers()["set-cookie"]).toBeUndefined();
      expect(response.headers().location).toBeUndefined();
    });
  }

  test("cross-site page view POST is rejected before analytics are accepted", async ({ request }) => {
    // event::track_view also requires same-origin evidence, but the router middleware rejects first.
    const response = await request.post(buildE2eUrl(`/events/${TEST_EVENT_IDS.alpha.one}/views`), {
      headers: { "Sec-Fetch-Site": "cross-site" },
    });

    // Verify public analytics mutations are covered by the same browser-origin contract.
    expect(response.status()).toBe(403);
  });
});
