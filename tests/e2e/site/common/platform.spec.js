import { expect, test } from "../../fixtures.js";

import { queryE2eDatabase, queryE2eDatabaseRows, sqlString } from "../../database.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_CREDENTIALS,
} from "../../seed.js";
import { buildE2eUrl, logInWithSeededUser, navigateToPath } from "../../utils.js";

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

// Public shared-cache pages; the event is TEST_EVENT_IDS.alpha.one.
const PUBLIC_PAGE_PATHS = [
  "/",
  `/${TEST_COMMUNITY_NAME}`,
  `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`,
  `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`,
];

// Redirector mappings seeded as legacy URLs in 20_groups.sql and 30_events.sql.
const SEEDED_REDIRECTS = [
  {
    legacyPath: "/events/alpha-event-1",
    newPath: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`,
  },
  {
    legacyPath: "/groups/platform-ops-meetup",
    newPath: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`,
  },
];

// Cookie holding the tower-sessions id, which is also the `auth_session` primary key.
const SESSION_COOKIE_NAME = "id";

// Logged-in and anonymous markers; public pages only render the placeholder that loads the user menu.
const LOGGED_IN_MARKER = 'data-logged-in="true"';
const LOGGED_OUT_MARKER = 'data-logged-in="false"';
const USER_MENU_PLACEHOLDER = 'hx-get="/section/user-menu"';

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

  test("every redirector target path resolves to a page", async ({ request }) => {
    // The redirector sends legacy URLs to list_redirects() new_path values on this server.
    const redirects = queryE2eDatabaseRows(
      "select community_name, legacy_path, new_path from list_redirects()",
    ).map(([communityName, legacyPath, newPath]) => ({ communityName, legacyPath, newPath }));

    // Verify the seeded mappings are listed with normalized legacy paths.
    expect(redirects).toEqual(
      expect.arrayContaining(
        SEEDED_REDIRECTS.map((redirect) => ({ communityName: TEST_COMMUNITY_NAME, ...redirect })),
      ),
    );

    for (const { newPath } of redirects) {
      await test.step(newPath, async () => {
        // Verify the target answers 200, or 307 to a page that answers 200.
        const response = await request.get(buildE2eUrl(newPath), { maxRedirects: 0 });
        if (response.status() === 307) {
          const location = new URL(response.headers().location, buildE2eUrl(newPath));
          const redirected = await request.get(location.href, { maxRedirects: 0 });
          expect(redirected.status()).toBe(200);
        } else {
          expect(response.status()).toBe(200);
        }
      });
    }
  });

  test("cross-site page view POST is rejected before analytics are accepted", async ({ request }) => {
    // event::track_view also requires same-origin evidence, but the router middleware rejects first.
    const response = await request.post(buildE2eUrl(`/events/${TEST_EVENT_IDS.alpha.one}/views`), {
      headers: { "Sec-Fetch-Site": "cross-site" },
    });

    // Verify public analytics mutations are covered by the same browser-origin contract.
    expect(response.status()).toBe(403);
  });
});

test.describe("public pages with a session cookie", () => {
  test("a valid session gets the anonymous shared-cache page", async ({ member1Page }) => {
    // Positive control: the same request context is logged in on the private user menu section.
    const userMenu = await member1Page.request.get(buildE2eUrl("/section/user-menu"));
    expect(userMenu.status()).toBe(200);
    await expect(userMenu.text()).resolves.toContain(LOGGED_IN_MARKER);

    for (const path of PUBLIC_PAGE_PATHS) {
      await test.step(path, async () => {
        // Verify the cookie neither personalizes nor reaches the shared-cache response.
        await expectAnonymousPublicPage(member1Page.request, path);
      });
    }
  });

  test("a stale session cookie is not removed by shared-cache pages", async ({ browser, browserHealth }) => {
    // Create an isolated browser context and page.
    const context = await browser.newContext();
    browserHealth.track(context);
    const page = await context.newPage();

    try {
      // Log in with a dedicated context, then delete its session so the cookie becomes stale.
      await logInWithSeededUser(page, TEST_USER_CREDENTIALS.empty);
      const sessionCookie = await getSessionCookie(context);
      queryE2eDatabase(`delete from auth_session where auth_session_id = ${sqlString(sessionCookie.value)}`);

      for (const path of PUBLIC_PAGE_PATHS) {
        await test.step(path, async () => {
          // Verify the public response carries no removal cookie (BUG-10).
          await expectAnonymousPublicPage(page.request, path);
        });
      }

      // Verify the stale cookie is still sent, so the private user menu sees it and removes it.
      const keptCookie = await getSessionCookie(context);
      expect(keptCookie.value).toBe(sessionCookie.value);
      const userMenu = await page.request.get(buildE2eUrl("/section/user-menu"));
      expect(userMenu.status()).toBe(200);
      await expect(userMenu.text()).resolves.toContain(LOGGED_OUT_MARKER);
      expect(userMenu.headers()["set-cookie"]).toMatch(new RegExp(`^${SESSION_COOKIE_NAME}=;`));
    } finally {
      // Close the isolated browser context.
      await context.close();
    }
  });
});

/** Asserts a public page answers with an anonymous, cookie-free shared-cache response. */
const expectAnonymousPublicPage = async (request, path) => {
  const response = await request.get(buildE2eUrl(path), { maxRedirects: 0 });
  const headers = response.headers();
  const body = await response.text();

  expect(response.status()).toBe(200);
  expect(headers["cache-control"]).toMatch(/^public\b/);
  expect(headers["set-cookie"]).toBeUndefined();
  expect(body).toContain(USER_MENU_PLACEHOLDER);
  expect(body).not.toContain(LOGGED_IN_MARKER);
};

/** Returns the session cookie of a browser context, failing when it is missing. */
const getSessionCookie = async (context) => {
  const sessionCookie = (await context.cookies()).find((cookie) => cookie.name === SESSION_COOKIE_NAME);

  expect(sessionCookie, "authenticated context should carry a session cookie").toBeDefined();

  return sessionCookie;
};
