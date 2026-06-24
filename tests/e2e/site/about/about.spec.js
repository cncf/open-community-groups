import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils.js";

test.describe("about page", () => {
  test("renders GOUP story, values, and joining model", async ({ page }) => {
    // Load the public about page.
    await navigateToPath(page, "/about");

    // Verify the page explains GOUP and its story.
    await expect(
      page.getByRole("heading", {
        level: 1,
        name: "A referral-based alliance for people who build",
      }),
    ).toBeVisible();
    await expect(page.getByText("TechBrains 2025 speakers chat")).toBeVisible();
    await expect(
      page.getByText("As long as we continue giving more than we take"),
    ).toBeVisible();

    // Verify the values and joining model are visible.
    await expect(page.getByText("Five non-negotiable values")).toBeVisible();
    await expect(
      page.getByText("Growth", { exact: true }).first(),
    ).toBeVisible();
    await expect(page.getByText("Startup founders")).toBeVisible();
    await expect(page.getByText("Community leads")).toBeVisible();
    await expect(page.getByText("GOUP grows through trust")).toBeVisible();
    await expect(page.getByText("Good people refer good people")).toBeVisible();
  });
});
