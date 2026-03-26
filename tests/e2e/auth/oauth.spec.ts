import { expect, test } from "@playwright/test";
import type { Locator, Page } from "@playwright/test";

import { buildE2eUrl, navigateToPath } from "../utils";

const githubEnabled = process.env.OCG_E2E_GITHUB_ENABLED !== "false";
const linuxfoundationEnabled =
  process.env.OCG_E2E_LINUXFOUNDATION_ENABLED === "true";

const expectProviderToWorkWhenVisible = async (page: Page, providerButton: Locator) => {
  if ((await providerButton.count()) === 0) {
    return false;
  }

  await expect(providerButton).toBeVisible();

  const authPath = await providerButton.getAttribute("href");
  expect(authPath).not.toBeNull();

  const authResponse = await page.request.get(buildE2eUrl(authPath ?? "/"), {
    failOnStatusCode: false,
    maxRedirects: 0,
  });
  expect(authResponse.status()).not.toBe(400);

  return true;
};

test.describe("oauth provider buttons", () => {
  test("shows the enabled auth buttons", async ({ page }) => {
    await navigateToPath(page, "/log-in");

    const githubButton = page.getByRole("link", { name: "GitHub" });
    const linuxFoundationButton = page.getByRole("link", {
      name: "Linux Foundation SSO",
    });

    if (githubEnabled) {
      await expect(expectProviderToWorkWhenVisible(page, githubButton)).resolves.toBeTruthy();
    } else if ((await githubButton.count()) > 0) {
      await expectProviderToWorkWhenVisible(page, githubButton);
    }

    if (linuxfoundationEnabled) {
      await expect(
        expectProviderToWorkWhenVisible(page, linuxFoundationButton),
      ).resolves.toBeTruthy();
    } else if ((await linuxFoundationButton.count()) > 0) {
      await expectProviderToWorkWhenVisible(page, linuxFoundationButton);
    }
  });
});
