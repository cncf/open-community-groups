import { test, expect } from "@playwright/test";
import {
  loginWithCredentials,
  navigateWithRetry,
  waitForLoadingComplete,
  waitForAlert,
  confirmAlert,
  cancelAlert,
} from "./utils";

test.describe("Group Membership - Anonymous User", () => {
  test.beforeEach(async ({ page }) => {
    await navigateWithRetry(page, "/group/test-group");
  });

  test("should show sign-in prompt button for anonymous users", async ({
    page,
  }) => {
    await waitForLoadingComplete(page);

    await expect(page.locator("#signin-btn")).toBeVisible();
    await expect(page.locator("#join-btn")).not.toBeVisible();
    await expect(page.locator("#leave-btn")).not.toBeVisible();
  });

  test("should show info alert when clicking sign-in button", async ({
    page,
  }) => {
    await waitForLoadingComplete(page);
    await page.locator("#signin-btn").click();

    const alert = await waitForAlert(page);
    await expect(alert).toContainText("logged in");
  });
});

test.describe("Group Membership - Authenticated Non-Member", () => {
  test.beforeEach(async ({ page }) => {
    await loginWithCredentials(page, "e2e-user", "testtest");
    await navigateWithRetry(page, "/group/test-group");
  });

  test("should show join button for non-members", async ({ page }) => {
    await waitForLoadingComplete(page);

    await expect(page.locator("#join-btn")).toBeVisible();
    await expect(page.locator("#leave-btn")).not.toBeVisible();
    await expect(page.locator("#signin-btn")).not.toBeVisible();
  });

  test("should be able to join a group", async ({ page }) => {
    await waitForLoadingComplete(page);
    await expect(page.locator("#join-btn")).toBeVisible();

    await page.locator("#join-btn").click();

    const alert = await waitForAlert(page);
    await expect(alert).toContainText("successfully joined");
  });
});

test.describe("Group Membership - Authenticated Member", () => {
  test.beforeEach(async ({ page }) => {
    await loginWithCredentials(page, "e2e-user", "testtest");
    await navigateWithRetry(page, "/group/test-group");
    await waitForLoadingComplete(page);

    // Ensure user is a member first (join if not already a member)
    const joinBtn = page.locator("#join-btn");
    if (await joinBtn.isVisible()) {
      await joinBtn.click();
      await waitForAlert(page);
      await page.reload();
      await waitForLoadingComplete(page);
    }
  });

  test("should show leave button for members", async ({ page }) => {
    await expect(page.locator("#leave-btn")).toBeVisible();
    await expect(page.locator("#join-btn")).not.toBeVisible();
    await expect(page.locator("#signin-btn")).not.toBeVisible();
  });

  test("should show confirmation dialog when clicking leave", async ({
    page,
  }) => {
    await page.locator("#leave-btn").click();

    const alert = await waitForAlert(page);
    await expect(alert).toContainText("sure");
  });

  test("should be able to leave a group after confirming", async ({ page }) => {
    await expect(page.locator("#leave-btn")).toBeVisible();

    await page.locator("#leave-btn").click();

    await confirmAlert(page);

    const successAlert = await waitForAlert(page);
    await expect(successAlert).toContainText("successfully left");
  });

  test("should not leave group if cancel is clicked", async ({ page }) => {
    await page.locator("#leave-btn").click();

    await cancelAlert(page);

    await expect(page.locator("#leave-btn")).toBeVisible();
  });
});
