import { expect, test } from "../../fixtures.js";

import {
  cleanupCohostEvents,
  readCohostsRevision,
  readCohostStatus,
  setupCohostEvent,
} from "../../data-graphs/cohosts.js";
import {
  addCohostThroughEditor,
  expectCohostDashboardRow,
  fillVirtualEventDraft,
  getCohostDashboardRows,
  getCohostGroupSearch,
  getCohostsSelector,
  getSelectedCohostCard,
  listSubmittedCohostIds,
  openCohostsSection,
  respondToCohostInvitation,
  waitForGroupOptions,
} from "../../dashboard/group/cohosts/helpers.js";
import {
  openEventUpdateFormByName,
  openGroupEventsTabWithEvent,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import {
  TEST_COMMUNITY_IDS,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
} from "../../seed.js";
import {
  buildE2eUrl,
  navigateToGroup,
  navigateToPath,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";

// Owner group members and team who receive publish notifications.
const ALPHA_EVENT_PUBLISHED_RECIPIENT_IDS = [
  TEST_USER_IDS.organizer1,
  TEST_USER_IDS.member1,
  "77777777-7777-7777-7777-777777777711",
  "77777777-7777-7777-7777-777777777712",
  "77777777-7777-7777-7777-777777777714",
  TEST_USER_IDS.checkInManager1,
];
// Cross-community group invited to co-host the scenario events.
const COHOST_GROUP_ID = TEST_GROUP_IDS.community2.delta;
const COHOST_GROUP_NAME = "E2E Second Group Delta";
const COHOST_GROUP_SLUG = TEST_GROUP_SLUGS.community2.delta;
// Co-host group admins who receive invitation and removal emails.
const COHOST_ADMIN_RECIPIENT_IDS = [TEST_USER_IDS.organizer2];
// Co-host group members and team who receive publish notifications.
const COHOST_AUDIENCE_RECIPIENT_IDS = [TEST_USER_IDS.organizer2, TEST_USER_IDS.member2];
// Owner group admins who receive co-host response emails.
const OWNER_RESPONSE_RECIPIENT_IDS = [TEST_USER_IDS.organizer1];
// Second cross-community group without admins, used where only selection state matters.
const SECOND_COHOST_GROUP_ID = TEST_GROUP_IDS.community2.zeta;
const SECOND_COHOST_GROUP_NAME = "E2E Second Group Zeta";

test.describe("event co-hosting workflows", () => {
  test("owner invites, co-host approves, owner publishes, and co-host cancels", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
    page,
  }) => {
    const eventName = uniqueName("co-hosted event");
    let eventId;
    let notificationIds = [];

    try {
      // Create a draft event with a pending co-host invitation.
      const created = await createDraftEventWithPendingCohost(organizerGroupPage, eventName, {
        days: 240,
      });
      eventId = created.eventId;
      notificationIds = notificationIds.concat(created.notificationIds);

      // Verify the create request carried the changed co-host selection.
      expect(created.submittedForm.get("cohost_group_ids[0]")).toBe(COHOST_GROUP_ID);
      expect(created.submittedForm.get("cohost_group_ids_present")).toBe("true");
      expect(created.submittedForm.get("cohosts_revision")).toBe("0");

      // Verify the pending invitation blocks publishing.
      await expectPendingCohostBlocksPublication(organizerGroupPage, 1);

      // Approve the invitation as the co-host and verify the owner is notified.
      const approveSnapshot = snapshotNotifications();
      await respondToCohostInvitation(organizerGroupWithoutPaymentsPage, eventName, "approve");
      notificationIds = notificationIds.concat(
        expectNewNotifications(approveSnapshot, [
          {
            kind: "event-cohost-responded",
            templateDataContains: {
              cohost_group_name: COHOST_GROUP_NAME,
              event: { name: eventName },
              status: "approved",
            },
            userIds: OWNER_RESPONSE_RECIPIENT_IDS,
          },
        ]),
      );

      // Publish the event and verify both group audiences are notified.
      await openEventUpdateFormByName(organizerGroupPage, eventName, eventId);
      await expect(organizerGroupPage.locator("#publish-event-button")).toBeEnabled();
      const publishSnapshot = snapshotNotifications();
      await organizerGroupPage.locator("#publish-event-button").click();
      await waitForEventPublish(organizerGroupPage, eventId);
      notificationIds = notificationIds.concat(
        expectNewNotifications(publishSnapshot, [
          {
            kind: "event-published",
            userIds: ALPHA_EVENT_PUBLISHED_RECIPIENT_IDS,
          },
          {
            kind: "event-published",
            templateDataContains: { cohost_group_name: COHOST_GROUP_NAME },
            userIds: COHOST_AUDIENCE_RECIPIENT_IDS,
          },
        ]),
      );

      const publicEventUrl = await organizerGroupPage
        .locator("#event-update-page")
        .getAttribute("data-event-public-url");
      expect(publicEventUrl).toBeTruthy();

      // Verify the locked editor selection and the public co-host credit.
      await expectPublishedCohostsLocked(organizerGroupPage);
      await expectPublicCohostCredit(page, publicEventUrl, eventName);

      // Cancel co-hosting as the co-host and verify the owner is notified.
      const cancelSnapshot = snapshotNotifications();
      await respondToCohostInvitation(organizerGroupWithoutPaymentsPage, eventName, "cancel");
      notificationIds = notificationIds.concat(
        expectNewNotifications(cancelSnapshot, [
          {
            kind: "event-cohost-responded",
            templateDataContains: {
              cohost_group_name: COHOST_GROUP_NAME,
              event: { name: eventName },
              status: "canceled",
            },
            userIds: OWNER_RESPONSE_RECIPIENT_IDS,
          },
        ]),
      );

      // Verify the durable canceled status and the removed public credit.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      await expectCohostDashboardRow(organizerGroupWithoutPaymentsPage, eventName, "Canceled");
      await navigateToPath(page, publicEventUrl);
      await expect(page.getByRole("list", { name: "Co-hosts" })).toHaveCount(0);
    } finally {
      // Restore seeded state.
      deleteNotifications(notificationIds);
      cleanupCohostEvents([eventId]);
    }
  });

  test("owner can invite a group again after it rejects the invitation", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    const eventName = uniqueName("rejected co-host event");
    let eventId;
    let notificationIds = [];

    try {
      // Create a draft event with a pending co-host invitation.
      const created = await createDraftEventWithPendingCohost(organizerGroupPage, eventName, {
        days: 250,
      });
      eventId = created.eventId;
      notificationIds = notificationIds.concat(created.notificationIds);

      // Reject the invitation as the co-host and verify the owner is notified.
      const rejectSnapshot = snapshotNotifications();
      await respondToCohostInvitation(organizerGroupWithoutPaymentsPage, eventName, "reject");
      notificationIds = notificationIds.concat(
        expectNewNotifications(rejectSnapshot, [
          {
            kind: "event-cohost-responded",
            templateDataContains: {
              cohost_group_name: COHOST_GROUP_NAME,
              event: { name: eventName },
              status: "rejected",
            },
            userIds: OWNER_RESPONSE_RECIPIENT_IDS,
          },
        ]),
      );

      // Verify the durable rejected status after a fresh load.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      await expectCohostDashboardRow(organizerGroupWithoutPaymentsPage, eventName, "Rejected");

      // Verify the rejected group no longer blocks publishing or appears as selected.
      await openEventUpdateFormByName(organizerGroupPage, eventName, eventId);
      await expect(organizerGroupPage.locator("#publish-event-button")).toBeEnabled();
      await openCohostsSection(organizerGroupPage);
      await expect(getCohostsSelector(organizerGroupPage).getByText("No co-hosts selected.")).toBeVisible();

      // Invite the same group again and verify a fresh invitation is sent.
      await addCohostThroughEditor(organizerGroupPage, {
        groupId: COHOST_GROUP_ID,
        groupName: COHOST_GROUP_NAME,
        search: "Delta",
      });
      const reinviteSnapshot = snapshotNotifications();
      await saveEventEditor(organizerGroupPage, eventId);
      notificationIds = notificationIds.concat(
        expectNewNotifications(reinviteSnapshot, [
          {
            kind: "event-cohost-invitation",
            templateDataContains: { cohost_group_name: COHOST_GROUP_NAME, events: [{ name: eventName }] },
            userIds: COHOST_ADMIN_RECIPIENT_IDS,
          },
        ]),
      );
      await expectPendingCohostBlocksPublication(organizerGroupPage, 1);

      // Verify the co-host can respond to the reopened invitation.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      const row = await expectCohostDashboardRow(organizerGroupWithoutPaymentsPage, eventName, "Pending");
      await expect(row.getByLabel(`Open co-host actions for ${eventName}`)).toBeVisible();
    } finally {
      // Restore seeded state.
      deleteNotifications(notificationIds);
      cleanupCohostEvents([eventId]);
    }
  });

  test("editor submits co-host fields only after changes and rejects stale selections", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    const scenario = setupCohostEvent({ cohosts: [{ groupId: COHOST_GROUP_ID }] });
    const invitationId = scenario.invitationIds[COHOST_GROUP_ID];
    const renamedEventName = `${scenario.name} renamed`;

    try {
      // Open the owner editor while the invitation is still pending.
      await openEventUpdateFormByName(organizerGroupPage, scenario.name, scenario.eventId);
      await openCohostsSection(organizerGroupPage);
      await expect(getCohostsSelector(organizerGroupPage)).toContainText("Pending");
      await expect(organizerGroupPage.locator('input[name="cohost_group_ids_present"]')).toHaveCount(0);

      // Approve the invitation from the co-host group while the editor stays open.
      const approveResponse = await organizerGroupWithoutPaymentsPage.request.put(
        buildE2eUrl(`/dashboard/group/cohosts/${invitationId}/approve`),
      );
      expect(approveResponse.status()).toBe(204);
      const approvedRevision = readCohostsRevision(scenario.eventId);

      // Save an unrelated change and verify the co-host fields are omitted.
      await organizerGroupPage.locator('button[data-section="details"]').click();
      await organizerGroupPage.locator("#name").fill(renamedEventName);
      const unrelatedForm = await saveEventEditor(organizerGroupPage, scenario.eventId);
      expect(unrelatedForm.get("name")).toBe(renamedEventName);
      expect(unrelatedForm.has("cohost_group_ids_present")).toBe(false);
      expect(unrelatedForm.has("cohosts_revision")).toBe(false);
      expect(listSubmittedCohostIds(unrelatedForm)).toEqual([]);

      // Verify the reloaded editor reflects the concurrent approval.
      await openCohostsSection(organizerGroupPage);
      await expect(getCohostsSelector(organizerGroupPage)).toContainText("Approved");
      await expect(organizerGroupPage.locator("#publish-event-button")).toBeEnabled();

      // Cancel co-hosting from the co-host group while the reloaded editor stays open.
      const cancelResponse = await organizerGroupWithoutPaymentsPage.request.put(
        buildE2eUrl(`/dashboard/group/cohosts/${invitationId}/cancel`),
      );
      expect(cancelResponse.status()).toBe(204);

      // Remove the stale co-host selection and verify the revision conflict is reported.
      await getCohostsSelector(organizerGroupPage)
        .getByRole("button", { name: `Remove ${COHOST_GROUP_NAME}` })
        .click();
      const staleResponse = await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        {
          method: "PUT",
          status: 422,
          urlIncludes: `/dashboard/group/events/${scenario.eventId}/update`,
        },
      );
      const staleForm = new URLSearchParams(staleResponse.request().postData() ?? "");
      expect(staleForm.get("cohost_group_ids_present")).toBe("true");
      expect(staleForm.get("cohosts_revision")).toBe(approvedRevision);
      expect(listSubmittedCohostIds(staleForm)).toEqual([]);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "co-hosts changed since this page was loaded; reload to continue",
      );
      await organizerGroupPage
        .locator(".swal2-popup")
        .getByRole("button", { name: "OK", exact: true })
        .click();

      // Verify the rejected save kept the co-host's own cancellation.
      expect(readCohostStatus(scenario.eventId, COHOST_GROUP_ID)).toBe("canceled");
    } finally {
      // Restore seeded state.
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("owner removal notifies the co-host and can be followed by a new invitation", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }, { groupId: SECOND_COHOST_GROUP_ID }],
    });
    let notificationIds = [];

    try {
      // Remove the approved co-host while keeping the pending one.
      await openEventUpdateFormByName(organizerGroupPage, scenario.name, scenario.eventId);
      await openCohostsSection(organizerGroupPage);
      await getCohostsSelector(organizerGroupPage)
        .getByRole("button", { name: `Remove ${COHOST_GROUP_NAME}` })
        .click();

      // Save the removal and verify the submitted selection and notification.
      const removeSnapshot = snapshotNotifications();
      const removalForm = await saveEventEditor(organizerGroupPage, scenario.eventId);
      expect(removalForm.get("cohost_group_ids_present")).toBe("true");
      expect(removalForm.get("cohosts_revision")).toBe("0");
      expect(listSubmittedCohostIds(removalForm)).toEqual([SECOND_COHOST_GROUP_ID]);
      notificationIds = notificationIds.concat(
        expectNewNotifications(removeSnapshot, [
          {
            kind: "event-cohost-removed",
            templateDataContains: {
              cohost_group_name: COHOST_GROUP_NAME,
              events: [{ name: scenario.name }],
              reason: "removed",
            },
            userIds: COHOST_ADMIN_RECIPIENT_IDS,
          },
        ]),
      );

      // Verify the owner editor keeps only the remaining pending co-host.
      await openCohostsSection(organizerGroupPage);
      const cohostsSelector = getCohostsSelector(organizerGroupPage);
      await expect(cohostsSelector.getByText(COHOST_GROUP_NAME)).toHaveCount(0);
      await expect(cohostsSelector).toContainText(SECOND_COHOST_GROUP_NAME);
      await expectPendingCohostBlocksPublication(organizerGroupPage, 1);

      // Verify the removed co-host sees the terminal status without actions.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      const removedRow = await expectCohostDashboardRow(
        organizerGroupWithoutPaymentsPage,
        scenario.name,
        "Removed by organizer",
      );
      await expect(removedRow.getByLabel(`Open co-host actions for ${scenario.name}`)).toHaveCount(0);

      // Invite the removed group again and verify a fresh invitation is sent.
      await addCohostThroughEditor(organizerGroupPage, {
        groupId: COHOST_GROUP_ID,
        groupName: COHOST_GROUP_NAME,
        search: "Delta",
      });
      const reinviteSnapshot = snapshotNotifications();
      const reinviteForm = await saveEventEditor(organizerGroupPage, scenario.eventId);
      expect(listSubmittedCohostIds(reinviteForm)).toEqual([SECOND_COHOST_GROUP_ID, COHOST_GROUP_ID]);
      notificationIds = notificationIds.concat(
        expectNewNotifications(reinviteSnapshot, [
          {
            kind: "event-cohost-invitation",
            templateDataContains: { cohost_group_name: COHOST_GROUP_NAME, events: [{ name: scenario.name }] },
            userIds: COHOST_ADMIN_RECIPIENT_IDS,
          },
        ]),
      );
      await expectPendingCohostBlocksPublication(organizerGroupPage, 2);
      expect(readCohostStatus(scenario.eventId, COHOST_GROUP_ID)).toBe("pending");
    } finally {
      // Restore seeded state.
      deleteNotifications(notificationIds);
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("unpublishing lets owners add co-hosts while keeping prior approvals", async ({
    organizerGroupPage,
  }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
      published: true,
    });

    try {
      // Unpublish the co-hosted event from the owner events list.
      await confirmEventListAction(organizerGroupPage, scenario.name, "unpublish", "Yes");

      // Add a second co-host now that the selection is editable again.
      await openEventUpdateFormByName(organizerGroupPage, scenario.name, scenario.eventId);
      await openCohostsSection(organizerGroupPage);
      await expect(
        getCohostsSelector(organizerGroupPage).getByLabel("Community", { exact: true }),
      ).toBeEnabled();
      await addCohostThroughEditor(organizerGroupPage, {
        groupId: SECOND_COHOST_GROUP_ID,
        groupName: SECOND_COHOST_GROUP_NAME,
        search: "Zeta",
      });
      const submittedForm = await saveEventEditor(organizerGroupPage, scenario.eventId);
      expect(listSubmittedCohostIds(submittedForm)).toEqual([COHOST_GROUP_ID, SECOND_COHOST_GROUP_ID]);

      // Verify only the new co-host blocks publishing again.
      await expectPendingCohostBlocksPublication(organizerGroupPage, 1);
      await openCohostsSection(organizerGroupPage);
      const cohostsSelector = getCohostsSelector(organizerGroupPage);
      await expect(getSelectedCohostCard(organizerGroupPage, COHOST_GROUP_NAME)).toContainText("Approved");
      await expect(getSelectedCohostCard(organizerGroupPage, SECOND_COHOST_GROUP_NAME)).toContainText(
        "Pending",
      );
      expect(readCohostStatus(scenario.eventId, COHOST_GROUP_ID)).toBe("approved");
    } finally {
      // Restore seeded state.
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("canceling a published event closes co-hosting and keeps public credit", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
    page,
  }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
      published: true,
    });
    let notificationIds = [];

    try {
      // Cancel the event and verify the co-host admins are told why co-hosting ended.
      const cancelSnapshot = snapshotNotifications();
      await confirmEventListAction(organizerGroupPage, scenario.name, "cancel", "Cancel event");
      notificationIds = expectNewNotifications(cancelSnapshot, [
        {
          kind: "event-cohost-removed",
          templateDataContains: {
            cohost_group_name: COHOST_GROUP_NAME,
            events: [{ name: scenario.name }],
            reason: "event-canceled",
          },
          userIds: COHOST_ADMIN_RECIPIENT_IDS,
        },
      ]);
      expect(readCohostStatus(scenario.eventId, COHOST_GROUP_ID)).toBe("event-canceled");

      // Verify the co-host sees the closed status without actions.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      const row = await expectCohostDashboardRow(
        organizerGroupWithoutPaymentsPage,
        scenario.name,
        "Event canceled",
      );
      await expect(row.getByLabel(`Open co-host actions for ${scenario.name}`)).toHaveCount(0);

      // Verify the canceled public page still credits the approved co-host.
      await navigateToPath(
        page,
        `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${scenario.slug}`,
      );
      await expect(
        page
          .getByRole("list", { name: "Co-hosts" })
          .getByRole("link", { name: new RegExp(COHOST_GROUP_NAME) }),
      ).toHaveAttribute("href", `/${TEST_COMMUNITY_NAME_2}/group/${COHOST_GROUP_SLUG}`);
    } finally {
      // Restore seeded state.
      deleteNotifications(notificationIds);
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("deleting a draft event closes pending co-host invitations", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    const scenario = setupCohostEvent({ cohosts: [{ groupId: COHOST_GROUP_ID }] });
    let notificationIds = [];

    try {
      // Confirm the co-host can see the pending invitation before deletion.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      await expectCohostDashboardRow(organizerGroupWithoutPaymentsPage, scenario.name, "Pending");

      // Delete the draft and verify the co-host admins are told why co-hosting ended.
      const deleteSnapshot = snapshotNotifications();
      await confirmEventListAction(organizerGroupPage, scenario.name, "delete", "Yes");
      notificationIds = expectNewNotifications(deleteSnapshot, [
        {
          kind: "event-cohost-removed",
          templateDataContains: {
            cohost_group_name: COHOST_GROUP_NAME,
            events: [{ name: scenario.name }],
            reason: "event-deleted",
          },
          userIds: COHOST_ADMIN_RECIPIENT_IDS,
        },
      ]);
      expect(readCohostStatus(scenario.eventId, COHOST_GROUP_ID)).toBe("event-deleted");

      // Verify the deleted event leaves the co-host dashboard list.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      await expect(
        organizerGroupWithoutPaymentsPage.getByRole("table", { name: "Co-hosted events list" }),
      ).toBeVisible();
      await expect(getCohostDashboardRows(organizerGroupWithoutPaymentsPage, scenario.name)).toHaveCount(0);
    } finally {
      // Restore seeded state.
      deleteNotifications(notificationIds);
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("keyboard selection adds a co-host without submitting the editor", async ({ organizerGroupPage }) => {
    const scenario = setupCohostEvent();
    const updateRequests = [];
    const trackUpdateRequest = (request) => {
      if (request.method() === "PUT" && request.url().includes(`/events/${scenario.eventId}/update`)) {
        updateRequests.push(request.url());
      }
    };

    try {
      // Open the empty co-hosts section of a draft event.
      await openEventUpdateFormByName(organizerGroupPage, scenario.name, scenario.eventId);
      await openCohostsSection(organizerGroupPage);
      const cohostsSelector = getCohostsSelector(organizerGroupPage);
      await expect(cohostsSelector.getByText("No co-hosts selected.")).toBeVisible();

      // Verify the owning group is never offered as its own co-host.
      const communitySelect = cohostsSelector.getByLabel("Community", { exact: true });
      const groupSearch = getCohostGroupSearch(organizerGroupPage);
      await Promise.all([
        waitForGroupOptions(organizerGroupPage, TEST_COMMUNITY_IDS.community1),
        communitySelect.selectOption(TEST_COMMUNITY_IDS.community1),
      ]);
      await groupSearch.focus();
      await groupSearch.fill(TEST_GROUP_NAMES.alpha);
      await expect(cohostsSelector.getByText("No groups found")).toBeVisible();

      // Choose a cross-community group with the keyboard only.
      await Promise.all([
        waitForGroupOptions(organizerGroupPage, TEST_COMMUNITY_IDS.community2),
        communitySelect.selectOption(TEST_COMMUNITY_IDS.community2),
      ]);
      organizerGroupPage.on("request", trackUpdateRequest);
      await groupSearch.focus();
      await groupSearch.fill("Zeta");
      await expect(
        cohostsSelector.getByRole("option", { name: new RegExp(SECOND_COHOST_GROUP_NAME) }),
      ).toBeVisible();
      await groupSearch.press("ArrowDown");
      await groupSearch.press("Enter");

      // Verify the selection changed locally without saving the event.
      await expect(
        cohostsSelector.getByRole("button", { name: `Remove ${SECOND_COHOST_GROUP_NAME}` }),
      ).toBeVisible();
      await expect(cohostsSelector.locator('input[name="cohost_group_ids[0]"]')).toHaveValue(
        SECOND_COHOST_GROUP_ID,
      );
      await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
      expect(updateRequests).toEqual([]);
    } finally {
      // Restore seeded state.
      organizerGroupPage.off("request", trackUpdateRequest);
      cleanupCohostEvents([scenario.eventId]);
    }
  });
  test("preview shows unsaved co-host selections without submitting co-host fields", async ({
    organizerGroupPage,
  }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
    });

    try {
      // Stage an unsaved co-host next to the approved one.
      await openEventUpdateFormByName(organizerGroupPage, scenario.name, scenario.eventId);
      await addCohostThroughEditor(organizerGroupPage, {
        groupId: SECOND_COHOST_GROUP_ID,
        groupName: SECOND_COHOST_GROUP_NAME,
        search: "Zeta",
      });

      // Open the preview and capture its request payload.
      const previewResponse = await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.locator("#event-preview-button").click(),
        {
          method: "POST",
          urlIncludes: "/dashboard/group/events/preview",
        },
      );
      const previewPayload = new URLSearchParams(previewResponse.request().postData() ?? "");
      expect(listSubmittedCohostIds(previewPayload)).toEqual([]);
      expect(previewPayload.has("cohost_group_ids_present")).toBe(false);
      expect(previewPayload.has("cohosts_revision")).toBe(false);
      expect(JSON.parse(previewPayload.get("preview_context") ?? "{}").cohosts).toEqual([
        expect.objectContaining({ name: COHOST_GROUP_NAME, status: "approved" }),
        expect.objectContaining({ name: SECOND_COHOST_GROUP_NAME, status: "pending" }),
      ]);

      // Verify the preview renders both selections with their statuses.
      const previewModal = organizerGroupPage.locator("#event-preview-modal");
      await expect(previewModal).toBeVisible();
      const cohostsBox = previewModal.getByText("Co-hosts", { exact: true }).locator("..").locator("..");
      await expect(cohostsBox.getByText(COHOST_GROUP_NAME, { exact: true })).toBeVisible();
      await expect(cohostsBox.getByText(SECOND_COHOST_GROUP_NAME, { exact: true })).toBeVisible();
      await expect(cohostsBox.getByText("Approved", { exact: true })).toHaveCount(1);
      await expect(cohostsBox.getByText("Pending", { exact: true })).toHaveCount(1);
      await expect(
        cohostsBox.getByText("Only approved co-hosts are shown on the public page.", { exact: true }),
      ).toBeVisible();

      // Close the preview and verify nothing was saved.
      await previewModal.getByRole("button", { name: "Close modal" }).click();
      await expect(previewModal).toHaveCount(0);
      expect(readCohostStatus(scenario.eventId, SECOND_COHOST_GROUP_ID)).toBe("");
    } finally {
      // Restore seeded state.
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("copying a co-hosted event leaves the new event without co-hosts", async ({ organizerGroupPage }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
      published: true,
    });

    try {
      // Open the add event form.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      await organizerGroupPage
        .locator("#dashboard-content")
        .getByRole("button", { name: "Add Event" })
        .click();
      await expect(organizerGroupPage.locator("#name")).toBeVisible();

      // Copy the co-hosted event details into the form.
      await organizerGroupPage.locator("#copy-event-selector").click();
      await organizerGroupPage.locator("#dropdown-events #event-search-input").fill(scenario.name);
      const eventOption = organizerGroupPage
        .locator('#dropdown-events button[id^="select-event-"]')
        .filter({ hasText: scenario.name });
      await waitForActionResponse(organizerGroupPage, () => eventOption.click(), {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${scenario.eventId}/details`,
      });
      await expect(organizerGroupPage.locator("#name")).toHaveValue(`${scenario.name} (copy)`);
      const copiedAlert = organizerGroupPage.locator(".swal2-popup");
      await expect(copiedAlert).toContainText("Event details copied.");
      await copiedAlert.getByRole("button", { name: "OK", exact: true }).click();

      // Verify co-host invitations are not copied to the new event.
      await openCohostsSection(organizerGroupPage);
      const cohostsSelector = getCohostsSelector(organizerGroupPage);
      await expect(cohostsSelector.getByText("No co-hosts selected.")).toBeVisible();
      await expect(cohostsSelector.locator('input[name^="cohost_group_ids["]')).toHaveCount(0);
    } finally {
      // Restore seeded state.
      cleanupCohostEvents([scenario.eventId]);
    }
  });
});

/** Runs one single-event action from the owner events list and waits for it to finish. */
const confirmEventListAction = async (page, eventName, action, confirmText) => {
  const eventRow = await openGroupEventsTabWithEvent(page, eventName);
  await eventRow.locator(".btn-actions").click();
  const actionButton = eventRow.locator(`button[id^="${action}-event-"]`);
  await expect(actionButton).toBeVisible();
  await actionButton.click();

  await waitForActionResponse(
    page,
    () => page.locator(".swal2-popup").getByRole("button", { name: confirmText, exact: true }).click(),
    {
      method: action === "delete" ? "DELETE" : "PUT",
      urlEndsWith: `/${action}`,
    },
  );
};

/** Creates a draft event and invites the cross-community co-host from the editor UI. */
const createDraftEventWithPendingCohost = async (page, eventName, { days }) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
  await dashboardContent.getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();

  await fillVirtualEventDraft(page, eventName, { days });
  await addCohostThroughEditor(page, {
    groupId: COHOST_GROUP_ID,
    groupName: COHOST_GROUP_NAME,
    search: "Delta",
  });

  const invitationSnapshot = snapshotNotifications();
  const visibleAddEventButton = page.locator("#pending-changes-alert:not(.hidden) #add-event-button");
  await expect(visibleAddEventButton).toBeVisible();
  const createResponse = await waitForActionResponse(page, () => visibleAddEventButton.click(), {
    method: "POST",
    status: 201,
    urlIncludes: "/dashboard/group/events/add",
  });

  const eventId = await waitForEventEditorAfterSave(page);
  const notificationIds = expectNewNotifications(invitationSnapshot, [
    {
      kind: "event-cohost-invitation",
      templateDataContains: {
        cohost_group_name: COHOST_GROUP_NAME,
        events: [{ name: eventName }],
        owner_group_name: TEST_GROUP_NAMES.alpha,
      },
      userIds: COHOST_ADMIN_RECIPIENT_IDS,
    },
  ]);

  await openCohostsSection(page);
  const cohostsSelector = getCohostsSelector(page);
  await expect(cohostsSelector).toContainText(COHOST_GROUP_NAME);
  await expect(cohostsSelector).toContainText("Pending");

  return {
    eventId,
    notificationIds,
    submittedForm: new URLSearchParams(createResponse.request().postData() ?? ""),
  };
};

/** Verifies pending co-hosts disable publishing with the required tooltip. */
const expectPendingCohostBlocksPublication = async (page, pendingCount) => {
  const publishButton = page.locator("#publish-event-button");

  await expect(publishButton).toBeDisabled();
  await expect(publishButton).toHaveAttribute("title", `Waiting for ${pendingCount} co-host(s) to respond.`);
};

/** Verifies public event and co-host group pages show approved co-host credit. */
const expectPublicCohostCredit = async (page, publicEventUrl, eventName) => {
  await navigateToPath(page, publicEventUrl);

  const cohostsList = page.getByRole("list", { name: "Co-hosts" });
  await expect(page.getByText("Co-hosted with", { exact: true })).toBeVisible();
  await expect(cohostsList.getByRole("link", { name: new RegExp(COHOST_GROUP_NAME) })).toHaveAttribute(
    "href",
    `/${TEST_COMMUNITY_NAME_2}/group/${COHOST_GROUP_SLUG}`,
  );

  // Co-hosted cards keep linking to the owner community event page.
  await navigateToGroup(page, TEST_COMMUNITY_NAME_2, COHOST_GROUP_SLUG);
  const eventCard = page.locator("a", { hasText: eventName }).first();
  await expect(eventCard).toContainText(`Hosted by ${TEST_GROUP_NAMES.alpha}`);
  await expect(eventCard).toHaveAttribute("href", new URL(publicEventUrl, buildE2eUrl("/")).pathname);
};

/** Verifies co-host selection is read-only once the event is published. */
const expectPublishedCohostsLocked = async (page) => {
  await openCohostsSection(page);

  await expect(
    page.getByText(
      "Co-hosts can't be changed while the event is published. If you unpublish it to change them, it can't be published again until every newly added group responds.",
      { exact: true },
    ),
  ).toBeVisible();
  await expect(getCohostsSelector(page).getByLabel("Community", { exact: true })).toBeDisabled();
  await expect(getCohostGroupSearch(page)).toBeDisabled();
};

/** Saves the event editor, waits for its reload, and returns the submitted form fields. */
const saveEventEditor = async (page, eventId) => {
  const [updateRequest] = await Promise.all([
    page.waitForRequest(
      (request) =>
        request.method() === "PUT" && request.url().includes(`/dashboard/group/events/${eventId}/update`),
    ),
    waitForEventEditorAfterSave(page, () => page.locator("#update-event-button").click(), {
      eventId,
      method: "PUT",
      urlIncludes: `/dashboard/group/events/${eventId}/update`,
    }),
  ]);

  return new URLSearchParams(updateRequest.postData() ?? "");
};

/** Confirms the publish dialog and waits for the editor to reload as published. */
const waitForEventPublish = async (page, eventId) => {
  await waitForEventEditorAfterSave(page, () => page.getByRole("button", { name: "Yes" }).click(), {
    eventId,
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${eventId}/publish`,
  });
  await expect(page.locator("#publish-event-button")).toBeDisabled();
};
