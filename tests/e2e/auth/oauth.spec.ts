import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_HOST,
  buildE2eUrl,
  navigateToPath,
  setHostHeader,
} from "../utils";

const githubEnabled = process.env.OCG_E2E_GITHUB_ENABLED !== "false";
const githubAuthUrl =
  process.env.OCG_E2E_GITHUB_AUTH_URL || "https://example.test/oauth/authorize";
const linuxfoundationEnabled =
  process.env.OCG_E2E_LINUXFOUNDATION_ENABLED === "true";

test.describe("oauth providers", () => {
  test.beforeEach(async ({ page }) => {
    await setHostHeader(page, TEST_COMMUNITY_HOST);
  });

  test("github login redirects to authorization url", async ({ page, request }) => {
    if (!githubEnabled) {
      test.skip(true, "GitHub login not enabled");
    }

    await navigateToPath(page, "/log-in");
    await expect(page.getByRole("link", { name: "GitHub" })).toBeVisible();

    const response = await request.get(buildE2eUrl("/log-in/oauth2/github"), {
      maxRedirects: 0,
    });
    expect([302, 303]).toContain(response.status());
    const location = response.headers()["location"];
    expect(location).toContain(githubAuthUrl);
  });

  test("linux foundation sso is available when configured", async ({ page }) => {
    if (!linuxfoundationEnabled) {
      test.skip(true, "Linux Foundation SSO not enabled");
    }

    await navigateToPath(page, "/log-in");
    await expect(
      page.getByRole("link", { name: "Linux Foundation SSO" })
    ).toBeVisible();
  });
});
