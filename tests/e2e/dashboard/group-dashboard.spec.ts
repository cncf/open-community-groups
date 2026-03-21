import { expect, test } from "../fixtures";

import { navigateToPath } from "../utils";

const ALPHA_EVENT_ONE_ID = "55555555-5555-5555-5555-555555555501";
const ALPHA_GROUP_ID = "44444444-4444-4444-4444-444444444441";
const BETA_GROUP_ID = "44444444-4444-4444-4444-444444444442";
const BETA_GROUP_SLUG = "test-group-beta";
const CFS_EVENT_ID = "55555555-5555-5555-5555-555555555519";
const PENDING1_USER_ID = "77777777-7777-7777-7777-777777777707";
const PENDING2_USER_ID = "77777777-7777-7777-7777-777777777708";

test.describe("group dashboard", () => {
  test("group team page shows seeded roles and last-admin protection", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Group Team", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add member" }),
    ).toBeEnabled();

    const adminRow = dashboardContent.locator("tr", {
      hasText: "E2E Organizer One",
    });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    const eventsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Events Manager One",
    });
    await expect(eventsManagerRow.locator('select[name="role"]')).toHaveValue(
      "events-manager",
    );

    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Group Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue("viewer");
    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending Two" }),
    ).toContainText("Invitation sent");
  });

  test("organizer can invite and remove a pending group team member", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Group Team", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add member" }).click();

    const addMemberForm = organizerGroupPage.locator("#team-add-form");
    await expect(addMemberForm).toBeVisible();

    const searchInput = addMemberForm.locator("#search-input");
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/users/search?q=e2e-pending-1") &&
          response.ok(),
      ),
      searchInput.fill("e2e-pending-1"),
    ]);

    await addMemberForm.getByText("E2E Pending One", { exact: true }).click();
    await addMemberForm.locator("#team-add-role").selectOption("viewer");

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/team/add") &&
          response.status() === 201,
      ),
      addMemberForm.locator("#team-add-submit").click(),
    ]);

    const pendingRow = dashboardContent.locator("tr", { hasText: "E2E Pending One" });
    await expect(pendingRow).toBeVisible();
    await expect(pendingRow).toContainText("Invitation sent");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue("viewer");

    const removeButton = pendingRow.locator(`#remove-member-${PENDING1_USER_ID}`);
    await removeButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this team member?",
    );

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/dashboard/group/team/${PENDING1_USER_ID}/delete`) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(
      dashboardContent.locator("tr", { hasText: "E2E Pending One" }),
    ).toHaveCount(0);
  });

  test("organizer can update and restore a group team member role", async ({
    organizerGroupPage,
  }) => {
    const SEEDED_ROLE = "viewer";
    const teamTabPath = "/dashboard/group?tab=team";

    await navigateToPath(organizerGroupPage, teamTabPath);

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const roleFormSelector = `form[hx-put="/dashboard/group/team/${PENDING2_USER_ID}/role"]`;
    const updateRole = async (role: string) => {
      const response = await organizerGroupPage.request.put(
        `/dashboard/group/team/${PENDING2_USER_ID}/role`,
        {
          form: { role },
        },
      );
      expect(response.ok()).toBeTruthy();
      await navigateToPath(organizerGroupPage, teamTabPath);
    };
    const currentRoleSelect = () =>
      dashboardContent.locator(roleFormSelector).locator('select[name="role"]');

    await expect(dashboardContent.getByText("Group Team", { exact: true })).toBeVisible();
    const currentRole = await currentRoleSelect().inputValue();
    if (currentRole !== SEEDED_ROLE) {
      await updateRole(SEEDED_ROLE);
    }

    await expect(currentRoleSelect()).toHaveValue(SEEDED_ROLE);

    await updateRole("events-manager");
    await expect(currentRoleSelect()).toHaveValue("events-manager");

    await updateRole(SEEDED_ROLE);
    await expect(currentRoleSelect()).toHaveValue(SEEDED_ROLE);
  });

  test("events manager can review CFS submissions with labels and ratings", async ({
    eventsManagerGroupPage,
  }) => {
    await navigateToPath(eventsManagerGroupPage, "/dashboard/group?tab=events");

    const cfsEventRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Alpha CFS Summit",
    });
    await expect(cfsEventRow).toBeVisible();

    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${CFS_EVENT_ID}/update`) &&
          response.ok(),
      ),
      cfsEventRow
        .locator('td button[aria-label="Edit event: Alpha CFS Summit"]')
        .click(),
    ]);

    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${CFS_EVENT_ID}/submissions`) &&
          response.ok(),
      ),
      eventsManagerGroupPage.locator('button[data-section="submissions"]').click(),
    ]);

    await expect(
      eventsManagerGroupPage.locator("#submissions-content").getByText(
        "Submissions",
        { exact: true },
      ),
    ).toBeVisible();
    const sortBy = eventsManagerGroupPage.getByLabel("Sort by");
    await expect(sortBy).toBeVisible();
    await expect(sortBy).toContainText("Stars (high to low)");
    await expect(sortBy).toContainText("Ratings count (high to low)");

    const notReviewedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Platform");

    const informationRequestedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Workshop");
    await expect(informationRequestedRow).toContainText("1 rating");

    const approvedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Platform");
    await expect(approvedRow).toContainText("Workshop");
    await expect(approvedRow).toContainText("2 ratings");
    await expect(approvedRow).toContainText("Approved");
    await expect(approvedRow.getByTitle("Review submission")).toBeEnabled();
  });

  test("viewer sees read-only event and submission controls", async ({
    groupViewerPage,
  }) => {
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    const dashboardContent = groupViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Event" }),
    ).toBeDisabled();

    const cfsEventRow = groupViewerPage.locator("tr", {
      hasText: "Alpha CFS Summit",
    });
    await expect(cfsEventRow).toBeVisible();

    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${CFS_EVENT_ID}/update`) &&
          response.ok(),
      ),
      cfsEventRow
        .locator('td button[aria-label="Edit event: Alpha CFS Summit"]')
        .click(),
    ]);

    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${CFS_EVENT_ID}/submissions`) &&
          response.ok(),
      ),
      groupViewerPage.locator('button[data-section="submissions"]').click(),
    ]);

    const reviewButtons = groupViewerPage.getByTitle(
      "Your role cannot manage events.",
    );
    await expect(reviewButtons.first()).toBeDisabled();
  });

  test("organizer can open the waitlist tab for an event with waitlist disabled", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Alpha Event One",
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${ALPHA_EVENT_ONE_ID}/update`) &&
          response.ok(),
      ),
      eventRow
        .locator('td button[aria-label="Edit event: Alpha Event One"]')
        .click(),
    ]);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${ALPHA_EVENT_ONE_ID}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent
        .locator('p.text-sm.lg\\:text-md.text-stone-700:visible')
        .filter({
          hasText: "Enable waitlist to allow full events to add people to the queue.",
        }),
    ).toBeVisible();
  });

  test("organizer can enable waitlist for an event and then restore it", async ({
    organizerGroupPage,
  }) => {
    const openAlphaEventEditor = async () => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      const eventRow = organizerGroupPage.locator("tr", {
        hasText: "Alpha Event One",
      });
      await expect(eventRow).toBeVisible();

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${ALPHA_EVENT_ONE_ID}/update`) &&
            response.ok(),
        ),
        eventRow
          .locator('td button[aria-label="Edit event: Alpha Event One"]')
          .click(),
      ]);
    };

    const submitWaitlistValue = async (nextValue: "true" | "false") => {
      await organizerGroupPage.locator("#toggle_waitlist_enabled").evaluate((input, value) => {
        if (!(input instanceof HTMLInputElement)) {
          throw new Error("waitlist toggle not found");
        }

        input.checked = value === "true";
        input.dispatchEvent(new Event("change", { bubbles: true }));
      }, nextValue);

      await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(nextValue);

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes(`/dashboard/group/events/${ALPHA_EVENT_ONE_ID}/update`) &&
            response.ok(),
        ),
        organizerGroupPage.locator("#update-event-button").click(),
      ]);
    };

    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");

    await submitWaitlistValue("true");

    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("true");

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${ALPHA_EVENT_ONE_ID}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent
        .locator('p.text-sm.lg\\:text-md.text-stone-700:visible')
        .filter({ hasText: "Waitlist entries for this event will appear here." }),
    ).toBeVisible();

    await submitWaitlistValue("false");

    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");
  });

  test("viewer sees read-only members and sponsors controls", async ({
    groupViewerPage,
  }) => {
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=members");

    const membersContent = groupViewerPage.locator("#dashboard-content");
    await expect(membersContent.getByText("Members", { exact: true })).toBeVisible();
    await expect(
      membersContent.getByRole("button", { name: "Send email" }),
    ).toBeDisabled();
    await expect(
      membersContent.getByRole("button", { name: "Send email" }),
    ).toHaveAttribute("title", "Your role cannot send emails to members.");

    await navigateToPath(groupViewerPage, "/dashboard/group?tab=sponsors");

    const sponsorsContent = groupViewerPage.locator("#dashboard-content");
    await expect(sponsorsContent.getByText("Sponsors", { exact: true })).toBeVisible();
    await expect(
      sponsorsContent.getByRole("button", { name: "Add Sponsor" }),
    ).toBeDisabled();

    const sponsorRow = sponsorsContent.locator("tr", { hasText: "Tech Corp" });
    await expect(sponsorRow).toBeVisible();
    await expect(
      sponsorRow.getByRole("button", { name: "Delete sponsor: Tech Corp" }),
    ).toBeDisabled();
    await expect(
      sponsorRow.getByRole("button", { name: "Delete sponsor: Tech Corp" }),
    ).toHaveAttribute("title", "Your role cannot delete sponsors.");
  });

  test("viewer sees read-only controls on group settings", async ({
    groupViewerPage,
  }) => {
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=settings");

    const dashboardContent = groupViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update group settings.", { exact: true }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(
      dashboardContent.getByRole("button", { name: "Update Group" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Update Group" }),
    ).toHaveAttribute("title", "Your role cannot update group settings.");
  });

  test("organizer can filter groups in the dashboard selector", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const groupSelectorButton = organizerGroupPage.locator("#group-selector-button");
    await expect(groupSelectorButton).toContainText("E2E Test Group Alpha");

    await groupSelectorButton.click();

    const groupSearchInput = organizerGroupPage.locator("#group-search-input");
    await expect(groupSearchInput).toBeVisible();
    await groupSearchInput.fill("Alpha");

    const groupOption = organizerGroupPage.locator(`#group-option-${ALPHA_GROUP_ID}`);
    await expect(groupOption).toBeVisible();
    await expect(groupOption).toBeDisabled();

    await groupSearchInput.fill("No matching group");
    await expect(organizerGroupPage.getByText("No groups found.", { exact: true })).toBeVisible();

    await groupSearchInput.press("Escape");
    await expect(groupSearchInput).toBeHidden();
    await expect(groupSelectorButton).toContainText("E2E Test Group Alpha");
  });

  test("organizer can unpublish and publish an event from the list", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const eventRow = dashboardContent.locator("tr", {
      hasText: "Alpha Event One",
    });
    await expect(eventRow).toBeVisible();
    await expect(eventRow).toContainText("Published");

    const actionsButton = eventRow.locator(`.btn-actions[data-event-id="${ALPHA_EVENT_ONE_ID}"]`);
    await actionsButton.click();

    const unpublishButton = organizerGroupPage.locator(
      `#unpublish-event-${ALPHA_EVENT_ONE_ID}`,
    );
    await expect(unpublishButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${ALPHA_EVENT_ONE_ID}/unpublish`) &&
          response.ok(),
      ),
      unpublishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(eventRow).toContainText("Draft");

    await eventRow.locator(`.btn-actions[data-event-id="${ALPHA_EVENT_ONE_ID}"]`).click();

    const publishButton = organizerGroupPage.locator(
      `#publish-event-${ALPHA_EVENT_ONE_ID}`,
    );
    await expect(publishButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${ALPHA_EVENT_ONE_ID}/publish`) &&
          response.ok(),
      ),
      publishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(eventRow).toContainText("Published");
  });
});
