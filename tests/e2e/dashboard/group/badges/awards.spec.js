import { expect, test } from "../../../fixtures.js";

import {
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";

const AWARDS_PATH = "/dashboard/group?tab=awards";
const MENTOR_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada07";

const waitForAwardsRefresh = async (page, action) =>
  Promise.all([
    page.waitForResponse((response) => {
      const responseUrl = new URL(response.url());

      return (
        response.request().method() === "GET" &&
        responseUrl.pathname === "/dashboard/group/awards" &&
        response.ok()
      );
    }),
    action(),
  ]);

test.describe("group badge award history", () => {
  test("empty state explains where award history will appear", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load award history for the dedicated group without credentials.
    await navigateToPath(organizerEmptyGroupPage, AWARDS_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator(
      "#dashboard-content",
    );

    // Verify the zero count and durable-history guidance remain visible.
    await expect(dashboardContent).toContainText("0 awards");
    await expect(dashboardContent).toContainText("No awards matched");
    await expect(dashboardContent).toContainText(
      "Awarded badges and revoked history appear here.",
    );
  });

  test("award history table exposes its responsive columns", async ({ organizerGroupPage }) => {
    // Load badge award history before checking table structure.
    await navigateToPath(organizerGroupPage, AWARDS_PATH);

    // Find the award history table.
    const awardsTable = organizerGroupPage.getByRole("table", {
      name: "Awards list",
    });

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(awardsTable, ["Recipient", "Badge", "Source", "Awarded", "Status", "Actions"]);
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      awardsTable,
      1024,
      ["Recipient", "Badge", "Awarded", "Status", "Actions"],
      ["Source"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      awardsTable,
      1280,
      ["Recipient", "Badge", "Source", "Awarded", "Status", "Actions"],
      [],
    );
  });

  test("organizer can move between badge award result pages", async ({ organizerGroupPage }) => {
    // Paginate the seeded award rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      `${AWARDS_PATH}&limit=1&offset=0`,
      "#dashboard-content tbody tr",
    );
  });

  test("organizer can search and combine award filters", async ({ organizerGroupPage }) => {
    // Search by recipient and verify the result set.
    await navigateToPath(organizerGroupPage, AWARDS_PATH);
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const awardsTable = dashboardContent.getByRole("table", { name: "Awards list" });

    const searchInput = dashboardContent.getByRole("textbox", {
      name: "Search awards",
    });
    await searchInput.fill("E2E Member Two");
    await waitForAwardsRefresh(organizerGroupPage, () => searchInput.press("Enter"));
    await expect(awardsTable.getByText("E2E Member Two", { exact: true }).first()).toBeVisible();
    await expect(awardsTable.getByText("E2E Organizer One", { exact: true })).toHaveCount(0);

    // Combine status, badge, source, and date filters in one form submission.
    const filtersForm = dashboardContent.locator("#awards-filters");
    await waitForAwardsRefresh(organizerGroupPage, () =>
      filtersForm.evaluate((form) => {
        const selectOptionByLabel = (select, label) => {
          const option = [...select.options].find((candidate) => candidate.textContent.trim() === label);

          if (!option) {
            throw new Error(`Missing filter option: ${label}`);
          }
          select.value = option.value;
        };

        selectOptionByLabel(form.elements.namedItem("status"), "Revoked");
        selectOptionByLabel(form.elements.namedItem("badge_id"), "Speaker");
        selectOptionByLabel(form.elements.namedItem("source"), "Upcoming In-Person Event");
        form.elements.namedItem("from").value = "2000-01-01";
        form.elements.namedItem("to").value = "2100-01-01";
        form.requestSubmit();
      }),
    );

    await expect(dashboardContent.getByText("Status: Revoked")).toBeVisible();
    await expect(dashboardContent.getByText("Badge: Speaker")).toBeVisible();
    await expect(dashboardContent.getByText("Source: Upcoming In-Person Event")).toBeVisible();
    await expect(dashboardContent.getByText("Awarded from: 2000-01-01")).toBeVisible();
    await expect(dashboardContent.getByText("Through: 2100-01-01")).toBeVisible();

    const revokedRow = awardsTable.getByRole("row", {
      name: /E2E Member Two Speaker Upcoming In-Person Event/u,
    });
    await expect(revokedRow).toContainText("Revoked");
    await expect(
      revokedRow.getByRole("button", {
        name: "Revoke credential: Speaker (already revoked)",
      }),
    ).toBeDisabled();

    // Clear every filter and restore the complete history.
    await dashboardContent.getByRole("link", { name: "Clear all" }).click();
    await expect(dashboardContent.getByText("Status: Revoked")).toHaveCount(0);
    await expect(awardsTable.getByText("E2E Organizer One", { exact: true }).first()).toBeVisible();
  });

  test("organizer can permanently revoke an active credential with a reason", async ({
    organizerGroupPage,
  }) => {
    // Find the dedicated active credential.
    await navigateToPath(organizerGroupPage, AWARDS_PATH);
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const searchInput = dashboardContent.getByRole("textbox", {
      name: "Search awards",
    });
    await searchInput.fill("Mentor");
    await waitForAwardsRefresh(organizerGroupPage, () => searchInput.press("Enter"));
    const mentorRow = dashboardContent.getByRole("row", {
      name: /E2E Member Two Mentor Upcoming In-Person Event/u,
    });

    await expect(mentorRow).toContainText("Active");
    await expect(mentorRow.getByRole("link", { name: "View credential: Mentor" })).toHaveAttribute(
      "href",
      `/badges/credentials/${MENTOR_CREDENTIAL_ID}`,
    );
    await expect(dashboardContent.locator("[data-group-badges]")).toHaveAttribute(
      "data-group-badges-ready",
      "true",
    );

    // Revoke it and supply the required private reason.
    await mentorRow.getByRole("button", { name: "Revoke credential: Mentor" }).click();
    const revokeDialog = organizerGroupPage.getByRole("dialog", {
      name: "Revoke Mentor",
    });
    await revokeDialog.getByLabel("Internal reason").fill("Credential revoked by the manager E2E scenario.");
    await waitForActionResponse(
      organizerGroupPage,
      () => revokeDialog.getByRole("button", { name: "Permanently revoke" }).click(),
      {
        method: "POST",
        urlEndsWith: `/badges/awards/${MENTOR_CREDENTIAL_ID}/revoke`,
        status: 204,
      },
    );

    // Verify the durable history retains the reason and disables the action.
    await expect(mentorRow).toContainText("Revoked");
    await expect(mentorRow).toContainText("Credential revoked by the manager E2E scenario.");
    await expect(
      mentorRow.getByRole("button", {
        name: "Revoke credential: Mentor (already revoked)",
      }),
    ).toBeDisabled();
  });
});
