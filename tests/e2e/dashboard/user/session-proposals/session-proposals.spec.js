import { expect, test } from "../../../fixtures.js";

import {
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  waitForActionResponse,
} from "../../../utils.js";

import { createSessionProposal, openUserDashboardPath } from "../helpers.js";

test.describe("user dashboard session proposals view", () => {
  test("empty state guides a user without session proposals", async ({
    emptyUserPage,
  }) => {
    // Load session proposals for the dedicated user without proposal records.
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      emptyUserPage,
    );
    const dashboardContent = emptyUserPage.locator("#dashboard-content");

    // Verify the empty guidance keeps the proposal creation action available.
    await expect(dashboardContent).toContainText(
      "You don't have any session proposals yet.",
    );
    await expect(
      dashboardContent.getByRole("button", { name: "New proposal" }),
    ).toBeVisible();
  });

  test("session proposals table exposes every user-facing column", async ({ member1Page }) => {
    // Load session proposals before checking table structure.
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member1Page);

    // Find the seeded session proposals table.
    const proposalsTable = member1Page.locator("table", {
      has: member1Page.getByText("Cloud Native Operations Deep Dive", {
        exact: true,
      }),
    });

    // Verify the complete ordered header set.
    const headers = ["Proposal", "Co-speaker", "Updated", "Status", "Actions"];
    await expectTableColumnsAtViewport(
      member1Page,
      proposalsTable,
      1024,
      ["Proposal", "Status", "Actions"],
      ["Co-speaker", "Updated"],
    );
    await expectTableColumnsAtViewport(
      member1Page,
      proposalsTable,
      1280,
      ["Proposal", "Co-speaker", "Status", "Actions"],
      ["Updated"],
    );
    await expectTableColumnsAtViewport(member1Page, proposalsTable, 1536, headers, []);
    await expectTableHeaders(proposalsTable, headers);
  });

  test("user can move between session proposal result pages", async ({ member1Page }) => {
    // Paginate the seeded proposal rows with one result per page.
    await expectPaginationNavigation(
      member1Page,
      "/dashboard/user?tab=session-proposals&limit=1&offset=0",
      "#dashboard-content tbody tr",
    );
  });

  test("session proposals page shows seeded proposal states and locks", async ({ member1Page }) => {
    // Load the session proposals tab before checking seeded states.
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member1Page);

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");

    // Verify session proposals page shows seeded proposal states and locks.
    await expect(dashboardContent.getByText("Session proposals", { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: "New proposal" })).toBeVisible();

    // Find the ready row.
    const readyRow = dashboardContent.locator("tr", {
      hasText: "Cloud Native Operations Deep Dive",
    });
    await expect(readyRow).toContainText("Ready for submission");
    await expect(readyRow.getByTitle("Delete proposal")).toBeEnabled();

    // Find the submitted row.
    const submittedRow = dashboardContent.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(submittedRow).toContainText("Submitted");
    await expect(submittedRow.getByTitle("Submitted proposals cannot be deleted")).toBeDisabled();

    // Find the linked row.
    const linkedRow = dashboardContent.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(linkedRow).toContainText("Linked");
    await expect(linkedRow.getByTitle("Linked proposals cannot be edited")).toBeDisabled();

    // Find the pending row.
    const pendingRow = dashboardContent.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    await expect(pendingRow).toContainText(/Awaiting co-speaker response|Ready for submission/);

    // Find the declined row.
    const declinedRow = dashboardContent.locator("tr", {
      hasText: "Co-Speaker Retrospective",
    });
    await expect(declinedRow).toContainText("Declined by co-speaker");
  });

  test("user can create, update, and delete a session proposal", async ({ pending1Page }) => {
    // Create a unique proposal title for the temporary proposal flow.
    const proposalTitle = `Pending1 reusable proposal ${Date.now()}`;
    const updatedProposalTitle = `${proposalTitle} updated`;
    const dashboardContent = await createSessionProposal(pending1Page, proposalTitle);

    // Find the proposal row.
    let proposalRow = dashboardContent.locator("tr", {
      hasText: proposalTitle,
    });

    // Verify user can create, update, and delete a session proposal.
    await expect(proposalRow).toContainText("Ready for submission");

    // Dismiss the creation feedback before opening the delete confirmation.
    const creationAlert = pending1Page.locator(".swal2-popup");
    await expect(creationAlert).toContainText("Session proposal added.");
    await creationAlert.getByRole("button", { name: "OK" }).click();

    // Open the proposal editor and persist an updated title.
    await proposalRow.getByTitle("Edit proposal").click();
    const editModal = pending1Page.getByRole("dialog", {
      name: "Edit session proposal",
    });
    await expect(editModal.getByLabel("Title")).toHaveValue(proposalTitle);
    await expect(editModal.getByLabel("Level")).toHaveValue("intermediate");
    await expect(editModal.getByLabel("Duration (minutes)")).toHaveValue("45");
    await editModal.getByLabel("Title").fill(updatedProposalTitle);
    await waitForActionResponse(
      pending1Page,
      () => editModal.getByRole("button", { name: "Update" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/user/session-proposals/",
      },
    );
    await expect(editModal).toBeHidden();
    proposalRow = dashboardContent.locator("tr", {
      hasText: updatedProposalTitle,
    });
    await expect(proposalRow).toContainText("Ready for submission");

    // Dismiss the update feedback before opening the delete confirmation.
    const updateAlert = pending1Page.locator(".swal2-popup");
    await expect(updateAlert).toContainText("Session proposal updated.");
    await updateAlert.getByRole("button", { name: "OK" }).click();

    // Find the delete proposal button.
    const deleteProposalButton = proposalRow.getByTitle("Delete proposal");
    await expect(deleteProposalButton).toBeVisible();

    // Click the delete proposal button.
    await deleteProposalButton.click();
    const deleteConfirmation = pending1Page.locator(".swal2-popup");
    await expect(deleteConfirmation).toContainText("Are you sure you want to delete this session proposal?");
    // Click Delete.
    await waitForActionResponse(
      pending1Page,
      () => deleteConfirmation.getByRole("button", { name: "Delete", exact: true }).click(),
      {
        method: "DELETE",
        urlIncludes: "/dashboard/user/session-proposals/",
      },
    );

    // Assert how many matching elements are shown.
    await expect(dashboardContent.locator("tr", { hasText: updatedProposalTitle })).toHaveCount(0);
  });

  test("empty proposal forms and cancelled deletions leave proposals untouched", async ({
    member1Page,
  }) => {
    // Load the session proposals tab before exercising the negative paths.
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member1Page);

    // Open the new proposal modal and submit the untouched form.
    const dashboardContent = member1Page.locator("#dashboard-content");
    await member1Page.getByRole("button", { name: "New proposal" }).click();
    const proposalModal = member1Page.getByRole("dialog", { name: "New session proposal" });
    await expect(proposalModal).toBeVisible();
    await proposalModal.getByRole("button", { name: "Save" }).click();

    // Verify browser validation keeps the modal open on the empty title.
    await expect(proposalModal.getByLabel("Title")).toBeFocused();
    await expect(proposalModal).toBeVisible();

    // Cancel the modal and verify no proposal row was added.
    await proposalModal.getByRole("button", { name: "Cancel" }).click();
    await expect(proposalModal).toBeHidden();
    await expect(dashboardContent.getByText("Session proposals", { exact: true })).toBeVisible();

    // Open the delete confirmation for a seeded deletable proposal.
    const readyRow = dashboardContent.locator("tr", {
      hasText: "Cloud Native Operations Deep Dive",
    });
    await readyRow.getByTitle("Delete proposal").click();
    const deleteConfirmation = member1Page.locator(".swal2-popup");
    await expect(deleteConfirmation).toContainText("Are you sure you want to delete this session proposal?");

    // Dismiss the confirmation and verify the proposal is preserved.
    await deleteConfirmation.getByRole("button", { name: "No" }).click();
    await expect(deleteConfirmation).toBeHidden();
    await expect(readyRow).toContainText("Ready for submission");
  });

  test("pending co-speaker invitations are surfaced to the invited user", async ({ member2Page }) => {
    // Load the invited user's session proposals tab.
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member2Page);

    // Find the dashboard content.
    const dashboardContent = member2Page.locator("#dashboard-content");
    const invitationAlert = dashboardContent.locator("[role='alert']");
    const invitationRow = dashboardContent.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });

    // Verify pending co-speaker invitations are surfaced to the invited user.
    await expect(invitationAlert).toContainText("co-speaker invitation waiting for your response");
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(invitationRow.getByTitle("View proposal")).toBeVisible();
    await expect(invitationRow.getByTitle("Accept invitation")).toBeVisible();
    await expect(invitationRow.getByTitle("Decline invitation")).toBeVisible();
  });
});
