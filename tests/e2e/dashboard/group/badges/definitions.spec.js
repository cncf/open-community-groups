import { expect, test } from "../../../fixtures.js";

import { buildE2eUrl, navigateToPath } from "../../../utils.js";

const BADGES_PATH = "/dashboard/group?tab=badges";

test.describe("group badge definitions", () => {
  test("badge management is available only to authorized roles", async ({
    eventsManagerGroupPage,
    groupViewerPage,
  }) => {
    // Verify an events manager can open every badge management tab.
    await navigateToPath(eventsManagerGroupPage, BADGES_PATH);
    const dashboardNavigation = eventsManagerGroupPage.getByRole("navigation", {
      name: "Dashboard navigation",
    });
    await expect(eventsManagerGroupPage.getByRole("heading", { name: "Badges", exact: true })).toBeVisible();
    await expect(dashboardNavigation.getByText("Artwork", { exact: true })).toBeVisible();
    await expect(dashboardNavigation.getByText("Awards", { exact: true })).toBeVisible();

    // Verify a viewer cannot discover or directly request protected badge tabs.
    await navigateToPath(groupViewerPage, "/dashboard/group");
    await expect(
      groupViewerPage
        .getByRole("navigation", { name: "Dashboard navigation" })
        .getByText("Badges", { exact: true }),
    ).toHaveCount(0);

    for (const tab of ["artwork", "awards", "badges"]) {
      const response = await groupViewerPage.request.get(buildE2eUrl(`/dashboard/group?tab=${tab}`));

      expect(response.status()).toBe(403);
    }
  });

  test("organizer can search, create, edit, and delete a badge", async ({ organizerGroupPage }) => {
    const badgeSuffix = Date.now();
    const badgeName = `E2E Lifecycle Badge ${badgeSuffix}`;
    const updatedBadgeName = `E2E Updated Lifecycle Badge ${badgeSuffix}`;

    // Filter the seeded badge list and clear the search again.
    await navigateToPath(organizerGroupPage, BADGES_PATH);
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const searchInput = dashboardContent.getByRole("textbox", {
      name: "Search badges",
    });

    await searchInput.fill("Speaker");
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/badges?") &&
          response.url().includes("badges_query=Speaker") &&
          response.ok(),
      ),
      searchInput.press("Enter"),
    ]);
    await expect(
      dashboardContent.getByRole("table", { name: "Badges list" }).getByText("Speaker", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("table", { name: "Badges list" }).getByText("Host", {
        exact: true,
      }),
    ).toHaveCount(0);

    await expect(dashboardContent.getByRole("button", { name: "Clear badge search" })).toBeVisible();
    await searchInput.fill("");
    await Promise.all([
      organizerGroupPage.waitForResponse((response) => {
        const responseUrl = new URL(response.url());

        return (
          response.request().method() === "GET" &&
          responseUrl.pathname === "/dashboard/group/badges" &&
          !responseUrl.searchParams.has("badges_query") &&
          response.ok()
        );
      }),
      searchInput.press("Enter"),
    ]);
    await expect(searchInput).toHaveValue("");
    await expect(dashboardContent.locator("[data-group-badges]")).toHaveAttribute(
      "data-group-badges-ready",
      "true",
    );

    // Create a definition using seeded gallery artwork.
    await dashboardContent.getByRole("button", { name: "Add badge" }).click();
    const addDialog = organizerGroupPage.getByRole("dialog", { name: "Add badge" });

    await addDialog.getByLabel("Name").fill(badgeName);
    await addDialog.getByLabel("Description").fill("Created by the badge lifecycle E2E test.");
    await addDialog.getByLabel("Criteria").fill("Complete the lifecycle E2E scenario.");
    await addDialog.getByLabel("Badge artwork 1").check({ force: true });
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().endsWith("/dashboard/group/badges") &&
          response.status() === 201,
      ),
      addDialog.getByRole("button", { name: "Add badge" }).click(),
    ]);

    const createdRow = dashboardContent.getByRole("row", { name: new RegExp(badgeName, "u") });
    await expect(createdRow).toBeVisible();
    await expect(dashboardContent.locator("[data-group-badges]")).toHaveAttribute(
      "data-group-badges-ready",
      "true",
    );

    // Edit the definition and verify the durable list refresh.
    await createdRow.getByRole("button", { name: `Edit badge: ${badgeName}` }).click();
    const editDialog = organizerGroupPage.getByRole("dialog", {
      name: `Edit ${badgeName}`,
    });

    await editDialog.getByLabel("Name").fill(updatedBadgeName);
    await editDialog.getByLabel("Description").fill("Updated by the badge lifecycle E2E test.");
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/group/badges/") &&
          response.status() === 204,
      ),
      editDialog.getByRole("button", { name: "Save" }).click(),
    ]);
    await expect(
      dashboardContent.getByRole("row", {
        name: new RegExp(updatedBadgeName, "u"),
      }),
    ).toBeVisible();

    // Delete the temporary definition so the shared list remains reusable.
    const updatedRow = dashboardContent.getByRole("row", {
      name: new RegExp(updatedBadgeName, "u"),
    });
    await updatedRow.getByRole("button", { name: `Delete badge: ${updatedBadgeName}` }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(`Delete ${updatedBadgeName}?`);
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/badges/") &&
          response.status() === 204,
      ),
      organizerGroupPage.getByRole("button", { name: "Delete badge" }).click(),
    ]);
    await expect(updatedRow).toHaveCount(0);
  });
});
