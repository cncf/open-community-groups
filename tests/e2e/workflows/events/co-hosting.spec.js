import { expect, test } from "../../fixtures.js";

import { cleanupEventsByIds } from "../../data-graphs/events.js";
import { queryE2eDatabase } from "../../database.js";
import { fillMarkdownEditor } from "../../dashboard/form-helpers.js";
import {
  openEventUpdateFormByName,
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
  futureDate,
  navigateToGroup,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";

const COHOST_GROUP_ID = TEST_GROUP_IDS.community2.delta;
const COHOST_GROUP_NAME = "E2E Second Group Delta";
const COHOST_GROUP_SLUG = TEST_GROUP_SLUGS.community2.delta;
const COHOST_INVITATION_RECIPIENT_IDS = ["77777777-7777-7777-7777-777777777704"];
const OWNER_RESPONSE_RECIPIENT_IDS = [TEST_USER_IDS.organizer1];

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
      const created = await createDraftEventWithPendingCohost(organizerGroupPage, eventName, {
        days: 240,
      });
      eventId = created.eventId;
      notificationIds = notificationIds.concat(created.notificationIds);

      await expectPendingCohostBlocksPublication(organizerGroupPage);

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

      await openEventUpdateFormByName(organizerGroupPage, eventName, eventId);
      await organizerGroupPage.locator("#publish-event-button").click();
      await waitForEventPublish(organizerGroupPage, eventId);

      const publicEventUrl = await organizerGroupPage
        .locator("#event-update-page")
        .getAttribute("data-event-public-url");
      expect(publicEventUrl).toBeTruthy();

      await expectPublishedCohostsLocked(organizerGroupPage);
      await expectPublicCohostCredit(page, publicEventUrl, eventName);

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

      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      await expectCohostDashboardRow(organizerGroupWithoutPaymentsPage, eventName, "Canceled");
    } finally {
      deleteNotifications(notificationIds);
      if (eventId) {
        cleanupCohostEvent(eventId);
      }
    }
  });

  test("co-host admin can reject a pending invitation", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    const eventName = uniqueName("rejected co-host event");
    let eventId;
    let notificationIds = [];

    try {
      const created = await createDraftEventWithPendingCohost(organizerGroupPage, eventName, {
        days: 250,
      });
      eventId = created.eventId;
      notificationIds = notificationIds.concat(created.notificationIds);

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

      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      await expectCohostDashboardRow(organizerGroupWithoutPaymentsPage, eventName, "Rejected");
    } finally {
      deleteNotifications(notificationIds);
      if (eventId) {
        cleanupCohostEvent(eventId);
      }
    }
  });
});

/** Removes disposable co-host event data and notification rows owned by a scenario. */
const cleanupCohostEvent = (eventId) => {
  queryE2eDatabase(`
    delete from notification n
    using notification_template_data ntd
    where n.notification_template_data_id = ntd.notification_template_data_id
    and ntd.data::text like '%${eventId}%';

    delete from event_cohost where event_id = '${eventId}'::uuid;
  `);
  cleanupEventsByIds([eventId]);
};

/** Creates a draft event and invites the cross-community co-host from the editor UI. */
const createDraftEventWithPendingCohost = async (page, eventName, { days }) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
  await dashboardContent.getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();

  await fillDraftEventDetails(page, eventName, { days });
  await inviteCohostThroughEditor(page);

  const invitationSnapshot = snapshotNotifications();
  const visibleAddEventButton = page.locator("#pending-changes-alert:not(.hidden) #add-event-button");
  await expect(visibleAddEventButton).toBeVisible();
  await waitForActionResponse(page, () => visibleAddEventButton.click(), {
    method: "POST",
    status: 201,
    urlIncludes: "/dashboard/group/events/add",
  });

  const eventId = await waitForCreatedEventEditor(page);
  const notificationIds = expectNewNotifications(invitationSnapshot, [
    {
      kind: "event-cohost-invitation",
      templateDataContains: {
        cohost_group_name: COHOST_GROUP_NAME,
        events: [{ name: eventName }],
        owner_group_name: TEST_GROUP_NAMES.alpha,
      },
      userIds: COHOST_INVITATION_RECIPIENT_IDS,
    },
  ]);

  await page.locator('button[data-section="cohosts"]').click();
  const cohostsSelector = page.locator("#cohosts-form cohosts-selector");
  await expect(cohostsSelector).toContainText(COHOST_GROUP_NAME);
  await expect(cohostsSelector).toContainText("Pending");

  return { eventId, notificationIds };
};

/** Fills the minimum event fields required to create a future virtual event. */
const fillDraftEventDetails = async (page, eventName, { days }) => {
  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
  await page.locator("#description_short").fill("A co-hosting workflow event from the e2e suite.");
  await fillMarkdownEditor(page, "description", "A co-hosting workflow event created by the e2e suite.");

  await page.locator('button[data-section="date-venue"]').click();
  await expect(page.locator('button[data-section="date-venue"]')).toHaveAttribute("data-active", "true");
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill(futureDate({ days, hour: 10 }));
  await page.locator("#ends_at").fill(futureDate({ days, hour: 12 }));
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-co-hosting");
};

/** Selects a cross-community group in the co-hosts editor tab. */
const inviteCohostThroughEditor = async (page) => {
  await page.locator('button[data-section="cohosts"]').click();
  const cohostsSelector = page.locator("#cohosts-form cohosts-selector");

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes("/dashboard/group/events/cohosts/groups") &&
        response.url().includes(TEST_COMMUNITY_IDS.community2) &&
        response.ok(),
    ),
    cohostsSelector.locator("#cohost-community").selectOption(TEST_COMMUNITY_IDS.community2),
  ]);

  const groupSearch = cohostsSelector.locator("#cohost-group-search");
  await expect(groupSearch).toBeEnabled();
  await groupSearch.fill("Delta");

  const cohostOption = cohostsSelector.getByRole("option", {
    name: new RegExp(COHOST_GROUP_NAME, "u"),
  });
  await expect(cohostOption).toBeVisible();
  await cohostOption.click();

  await expect(cohostsSelector).toContainText(COHOST_GROUP_NAME);
  await expect(cohostsSelector.locator(`input[value="${COHOST_GROUP_ID}"]`)).toHaveCount(1);
};

/** Waits for the created event editor and returns its event id. */
const waitForCreatedEventEditor = async (page) => {
  await expect(page.locator('[data-event-page="update"]')).toHaveAttribute("data-event-page-ready", "true");
  const saveUrl = await page.locator("#update-event-button").getAttribute("hx-put");
  const match = saveUrl?.match(/\/events\/([^/?]+)\/update/u);
  expect(match).not.toBeNull();
  return match?.[1] ?? "";
};

/** Verifies pending co-hosts are visible and disable publishing with the required tooltip. */
const expectPendingCohostBlocksPublication = async (page) => {
  const publishButton = page.locator("#publish-event-button");

  await expect(publishButton).toBeDisabled();
  await expect(publishButton).toHaveAttribute("title", "Waiting for 1 co-host(s) to respond.");
};

/** Publishes the currently open event editor. */
const waitForEventPublish = async (page, eventId) => {
  await waitForEventEditorAfterSave(page, () => page.getByRole("button", { name: "Yes" }).click(), {
    eventId,
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${eventId}/publish`,
  });
  await expect(page.locator("#publish-event-button")).toBeDisabled();
};

/** Verifies co-host selection is read-only once the event is published. */
const expectPublishedCohostsLocked = async (page) => {
  await page.locator('button[data-section="cohosts"]').click();

  await expect(
    page.getByText(
      "Co-hosts can't be changed while the event is published. If you unpublish it to change them, it can't be published again until every newly added group responds.",
      { exact: true },
    ),
  ).toBeVisible();
  await expect(page.locator("#cohosts-form cohosts-selector #cohost-community")).toBeDisabled();
  await expect(page.locator("#cohosts-form cohosts-selector #cohost-group-search")).toBeDisabled();
};

/** Verifies public event and co-host group pages show approved co-host credit. */
const expectPublicCohostCredit = async (page, publicEventUrl, eventName) => {
  await navigateToPath(page, publicEventUrl);

  const cohostsBox = page.locator('[aria-label="Co-hosts"]').locator("..").locator("..");
  await expect(cohostsBox.getByText("Co-hosts", { exact: true })).toBeVisible();
  await expect(cohostsBox.getByRole("link", { name: COHOST_GROUP_NAME })).toHaveAttribute(
    "href",
    `/${TEST_COMMUNITY_NAME_2}/group/${COHOST_GROUP_SLUG}`,
  );

  await navigateToGroup(page, TEST_COMMUNITY_NAME_2, COHOST_GROUP_SLUG);
  const eventCard = page.locator("a", { hasText: eventName }).first();
  await expect(eventCard).toContainText(`Hosted by ${TEST_GROUP_NAMES.alpha}`);
};

/** Approves, rejects, or cancels co-hosting from the co-host dashboard list. */
const respondToCohostInvitation = async (page, eventName, action) => {
  await navigateToPath(page, "/dashboard/group?tab=cohosts");
  const row = await expectCohostDashboardRow(page, eventName, action === "cancel" ? "Approved" : "Pending");

  await row.locator("summary").click();
  await row.locator(`[data-cohost-action="${action}"]`).click();

  const dialog = page.locator(".swal2-popup");
  if (action === "approve") {
    await expect(dialog).toContainText("The event appears on your group page");
    await expect(dialog).toContainText("you get no access to it");
  }

  await waitForActionResponse(page, () => dialog.getByRole("button", { name: actionLabel(action) }).click(), {
    method: "PUT",
    status: 204,
    urlEndsWith: `/${action}`,
  });

  await expectCohostDashboardRow(page, eventName, statusAfterAction(action));
};

/** Finds a co-host dashboard row and verifies its current status. */
const expectCohostDashboardRow = async (page, eventName, status) => {
  const row = page.locator("[data-group-cohosts-list] tbody tr", { hasText: eventName }).first();
  await expect(row).toBeVisible();
  await expect(row).toContainText(status);
  return row;
};

/** Returns the confirmation button label for one co-host action. */
const actionLabel = (action) => {
  if (action === "approve") {
    return "Approve";
  }

  if (action === "cancel") {
    return "Cancel co-hosting";
  }

  return "Reject";
};

/** Returns the visible status after one co-host action succeeds. */
const statusAfterAction = (action) => {
  if (action === "approve") {
    return "Approved";
  }

  if (action === "cancel") {
    return "Canceled";
  }

  return "Rejected";
};
