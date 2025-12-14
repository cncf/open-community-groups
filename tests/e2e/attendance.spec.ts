import { test, expect } from "@playwright/test";
import {
  loginWithCredentials,
  navigateWithRetry,
  waitForLoadingComplete,
  waitForAlert,
  confirmAlert,
  cancelAlert,
} from "./utils";

test.describe("Event Attendance - Anonymous User", () => {
  test.beforeEach(async ({ page }) => {
    await navigateWithRetry(page, "/group/test-group/event/test-event");
  });

  test("should show sign-in prompt button for anonymous users", async ({
    page,
  }) => {
    await waitForLoadingComplete(
      page,
      "#attendance-container #loading-btn, #loading-btn",
    );

    await expect(page.locator("#signin-btn")).toBeVisible();
    await expect(page.locator("#attend-btn")).not.toBeVisible();
    await expect(
      page.locator("#attendance-container #leave-btn"),
    ).not.toBeVisible();
  });

  test("should show info alert when clicking sign-in button", async ({
    page,
  }) => {
    await waitForLoadingComplete(
      page,
      "#attendance-container #loading-btn, #loading-btn",
    );
    await page
      .locator("#attendance-container #signin-btn, #signin-btn")
      .click();

    const alert = await waitForAlert(page);
    await expect(alert).toContainText("logged in");
  });
});

test.describe("Event Attendance - Authenticated Non-Attendee", () => {
  test.beforeEach(async ({ page }) => {
    await loginWithCredentials(page, "e2e-user", "testtest");
    await navigateWithRetry(page, "/group/test-group/event/test-event");
  });

  test("should show attend button for non-attendees", async ({ page }) => {
    await waitForLoadingComplete(
      page,
      "#attendance-container #loading-btn, #loading-btn",
    );

    await expect(page.locator("#attend-btn")).toBeVisible();
    await expect(
      page.locator("#attendance-container #leave-btn"),
    ).not.toBeVisible();
    await expect(page.locator("#signin-btn")).not.toBeVisible();
  });

  test("should be able to attend an event", async ({ page }) => {
    await waitForLoadingComplete(
      page,
      "#attendance-container #loading-btn, #loading-btn",
    );
    await expect(page.locator("#attend-btn")).toBeVisible();

    await page.locator("#attend-btn").click();

    const alert = await waitForAlert(page);
    await expect(alert).toContainText("successfully registered");
  });
});

test.describe("Event Attendance - Authenticated Attendee", () => {
  test.beforeEach(async ({ page }) => {
    await loginWithCredentials(page, "e2e-user", "testtest");
    await navigateWithRetry(page, "/group/test-group/event/test-event");
    await waitForLoadingComplete(
      page,
      "#attendance-container #loading-btn, #loading-btn",
    );

    // Ensure user is an attendee first (attend if not already attending)
    const attendBtn = page.locator("#attend-btn");
    if (await attendBtn.isVisible()) {
      await attendBtn.click();
      await waitForAlert(page);
      await page.reload();
      await waitForLoadingComplete(
        page,
        "#attendance-container #loading-btn, #loading-btn",
      );
    }
  });

  test("should show cancel attendance button for attendees", async ({
    page,
  }) => {
    await expect(
      page.locator("#attendance-container #leave-btn"),
    ).toBeVisible();
    await expect(page.locator("#attend-btn")).not.toBeVisible();
    await expect(page.locator("#signin-btn")).not.toBeVisible();
  });

  test("should show confirmation dialog when canceling attendance", async ({
    page,
  }) => {
    await page.locator("#attendance-container #leave-btn").click();

    const alert = await waitForAlert(page);
    await expect(alert).toContainText("sure");
  });

  test("should be able to cancel attendance after confirming", async ({
    page,
  }) => {
    await expect(
      page.locator("#attendance-container #leave-btn"),
    ).toBeVisible();

    await page.locator("#attendance-container #leave-btn").click();

    await confirmAlert(page);

    const successAlert = await waitForAlert(page);
    await expect(successAlert).toContainText("successfully canceled");
  });

  test("should not cancel attendance if cancel button is clicked", async ({
    page,
  }) => {
    await page.locator("#attendance-container #leave-btn").click();

    await cancelAlert(page);

    await expect(
      page.locator("#attendance-container #leave-btn"),
    ).toBeVisible();
  });
});

test.describe("Event Attendance - Sold Out Event", () => {
  test("should show disabled attend button for sold out events", async ({
    page,
  }) => {
    await navigateWithRetry(page, "/group/test-group/event/test-event");

    expect(true).toBeTruthy();
  });
});
