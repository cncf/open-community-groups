import { expect, test } from "@playwright/test";

import { navigateToPath } from "../utils";

const githubEnabled = process.env.OCG_E2E_GITHUB_ENABLED !== "false";
const linuxfoundationEnabled =
  process.env.OCG_E2E_LINUXFOUNDATION_ENABLED !== "false";

test.describe("oauth provider buttons", () => {
  test("shows the enabled auth buttons", async ({ page }) => {
    await navigateToPath(page, "/log-in");

    const githubButton = page.getByRole("link", { name: "GitHub" });
    const linuxFoundationButton = page.getByRole("link", {
      name: "Linux Foundation SSO",
    });

    if (githubEnabled) {
      await expect(githubButton).toBeVisible();
    } else {
      await expect(githubButton).toHaveCount(0);
    }

    if (linuxfoundationEnabled) {
      await expect(linuxFoundationButton).toBeVisible();
    } else {
      await expect(linuxFoundationButton).toHaveCount(0);
    }
  });
});
