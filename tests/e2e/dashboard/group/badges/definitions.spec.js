import { expect, test } from "../../../fixtures.js";

import {
  buildE2eUrl,
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";

const BADGES_PATH = "/dashboard/group?tab=badges";

test.describe("group badge definitions", () => {
  test("empty state guides the first badge definition", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load badge definitions for the dedicated group without badge records.
    await navigateToPath(organizerEmptyGroupPage, BADGES_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator(
      "#dashboard-content",
    );

    // Verify first-use guidance and the creation action remain available.
    await expect(dashboardContent).toContainText("0 badges");
    await expect(dashboardContent).toContainText("Create your first badge");
    await expect(dashboardContent).toContainText(
      "Upload artwork first, then define what the badge recognizes.",
    );
    await expect(
      dashboardContent.getByRole("button", { name: "Add badge" }),
    ).toBeVisible();
  });

  test("badge definitions table exposes its responsive columns", async ({ organizerGroupPage }) => {
    // Load badge definitions before checking table structure.
    await navigateToPath(organizerGroupPage, BADGES_PATH);

    // Find the badge definitions table.
    const badgesTable = organizerGroupPage.getByRole("table", {
      name: "Badges list",
    });

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(badgesTable, ["Badge", "Description", "Actions"]);
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      badgesTable,
      1024,
      ["Badge", "Actions"],
      ["Description"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      badgesTable,
      1280,
      ["Badge", "Description", "Actions"],
      [],
    );
  });

  test("organizer can move between badge definition result pages", async ({
    organizerGroupPage,
  }) => {
    // Paginate the seeded badge rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      `${BADGES_PATH}&limit=1&offset=0`,
      "#dashboard-content tbody tr",
    );
  });

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
    // Create unique badge values for the temporary definition flow.
    const badgeSuffix = Date.now();
    const badgeName = `E2E Lifecycle Badge ${badgeSuffix}`;
    const updatedBadgeName = `E2E Updated Lifecycle Badge ${badgeSuffix}`;

    // Filter the seeded badge list and clear the search again.
    await navigateToPath(organizerGroupPage, BADGES_PATH);
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const searchInput = dashboardContent.getByRole("textbox", {
      name: "Search badges",
    });
    const badgesRoot = dashboardContent.locator("[data-group-badges]");

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
    await expect(badgesRoot).toHaveAttribute("data-group-badges-ready", "true");
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

    const clearSearchButton = dashboardContent.getByRole("button", {
      name: "Clear badge search",
    });
    await expect(clearSearchButton).toBeVisible();
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
      clearSearchButton.click(),
    ]);
    await expect(searchInput).toHaveValue("");
    await expect(badgesRoot).toHaveAttribute("data-group-badges-ready", "true");

    // Create a definition using seeded gallery artwork.
    await dashboardContent.getByRole("button", { name: "Add badge" }).click();
    const addDialog = organizerGroupPage.getByRole("dialog", { name: "Add badge" });

    await addDialog.getByLabel("Name").fill(badgeName);
    await addDialog.getByLabel("Description").fill("Created by the badge lifecycle E2E test.");
    await addDialog.getByLabel("Criteria").fill("Complete the lifecycle E2E scenario.");
    await addDialog.getByLabel("Badge artwork 1").check({ force: true });
    await waitForActionResponse(
      organizerGroupPage,
      () => addDialog.getByRole("button", { name: "Add badge" }).click(),
      {
        method: "POST",
        urlEndsWith: "/dashboard/group/badges",
        status: 201,
      },
    );

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
    await waitForActionResponse(
      organizerGroupPage,
      () => editDialog.getByRole("button", { name: "Save" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/badges/",
        status: 204,
      },
    );
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
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Delete badge" }).click(),
      {
        method: "DELETE",
        urlIncludes: "/dashboard/group/badges/",
        status: 204,
      },
    );
    await expect(updatedRow).toHaveCount(0);
  });
});
