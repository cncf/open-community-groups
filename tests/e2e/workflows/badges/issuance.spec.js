import { expect, test } from "../../fixtures.js";
import { queryE2eDatabaseRows } from "../../database.js";
import {
  cleanupBadgeAwardJobs,
  cleanupCredential,
  setupBadgeDefinition,
  setupBadgeStatusList,
} from "../../data-graphs/badges.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_EVENT_IDS, TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import { buildE2eUrl, navigateToPath, waitForActionResponse } from "../../utils.js";

const BADGE_ISSUANCE_TIMEOUT_MS = 45_000;

const ELIGIBLE_EVENT_ID = TEST_EVENT_IDS.alpha.pastFiltering;

const ELIGIBLE_EVENT_NAME = "Past Event For Filtering";

const GROUP_AWARDS_PATH = "/dashboard/group?tab=awards";

const MEMBER_ONE_NAME = "E2E Member One";

test.describe("badge issuance workflow", () => {
  test("organizer awards, recipient exports, verifies, and revokes a badge", async ({
    member1Page,
    organizerGroupPage,
  }) => {
    const badge = setupBadgeDefinition({ groupId: TEST_GROUP_IDS.community1.alpha });
    const statusList = setupBadgeStatusList({ groupId: TEST_GROUP_IDS.community1.alpha });
    let credentialId;
    let notificationIds = [];

    try {
      // Snapshot badge notifications before awarding the credential.
      const awardedNotifications = snapshotNotifications();

      // Award the badge and assert the recipient notification.
      await awardBadgeToMemberOne(organizerGroupPage, badge.badgeId);
      credentialId = await waitForIssuedCredential({
        badgeId: badge.badgeId,
        userId: TEST_USER_IDS.member1,
      });
      notificationIds = notificationIds.concat(
        expectNewNotifications(awardedNotifications, [
          {
            kind: "badge-awarded",
            templateDataContains: {
              badge: {
                name: badge.badgeName,
              },
              dashboard_url: "/dashboard/user?tab=badges",
            },
            userIds: [TEST_USER_IDS.member1],
          },
        ]),
      );

      // Open the recipient badge dashboard and verify the issued badge appears.
      await navigateToPath(member1Page, "/dashboard/user?tab=badges");
      const recipientBadge = member1Page.locator(`[data-user-badge-id="${credentialId}"]`);
      await expect(recipientBadge).toContainText(badge.badgeName);

      // Export the credential PNG and verify its file signature.
      const exportResponse = await member1Page.request.get(
        buildE2eUrl(`/dashboard/user/badges/${credentialId}/export`),
      );
      const png = await exportResponse.body();
      expect(exportResponse.ok()).toBeTruthy();
      expect([...png.subarray(0, 8)]).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

      // Verify the exported badge is valid before revocation.
      await verifyExportedBadge(member1Page, png, badge.badgeName, "Valid and active");

      // Revoke the credential and assert the recipient notification.
      const revokedNotifications = snapshotNotifications();
      await revokeCredentialFromAwards(organizerGroupPage, {
        badgeName: badge.badgeName,
        reason: "Credential revoked by the badge issuance E2E scenario.",
        userBadgeId: credentialId,
      });
      notificationIds = notificationIds.concat(
        expectNewNotifications(revokedNotifications, [
          {
            kind: "badge-revoked",
            templateDataContains: {
              badge_name: badge.badgeName,
              group_name: "Platform Ops Meetup",
            },
            userIds: [TEST_USER_IDS.member1],
          },
        ]),
      );

      // Verify the public credential page reports the revocation.
      await expectCredentialVerification(member1Page, credentialId, badge.badgeName, "Credential revoked");
    } finally {
      // Remove generated notifications, jobs, and credential rows.
      deleteNotifications(notificationIds);
      cleanupBadgeAwardJobs({ badgeId: badge.badgeId });
      cleanupCredential({
        badgeCreated: badge.badgeCreated,
        badgeId: badge.badgeId,
        badgeStatusListId: statusList.badgeStatusListId,
        userBadgeId: credentialId,
      });
    }
  });

  test("duplicate award submission creates one active credential", async ({ organizerGroupPage }) => {
    const badge = setupBadgeDefinition({ groupId: TEST_GROUP_IDS.community1.alpha });
    const statusList = setupBadgeStatusList({ groupId: TEST_GROUP_IDS.community1.alpha });
    let credentialId;
    let notificationIds = [];

    try {
      // Snapshot badge notifications before submitting duplicate awards.
      const awardedNotifications = snapshotNotifications();

      // Submit duplicate awards and resolve the issued credential.
      await awardBadgeToMemberOne(organizerGroupPage, badge.badgeId);
      await awardBadgeToMemberOne(organizerGroupPage, badge.badgeId);
      credentialId = await waitForIssuedCredential({
        badgeId: badge.badgeId,
        userId: TEST_USER_IDS.member1,
      });

      // Verify duplicate submissions produce one credential and one notification.
      expect(countActiveCredentials(badge.badgeId, TEST_USER_IDS.member1)).toBe(1);
      notificationIds = notificationIds.concat(
        expectNewNotifications(awardedNotifications, [
          {
            kind: "badge-awarded",
            templateDataContains: {
              badge: {
                name: badge.badgeName,
              },
            },
            userIds: [TEST_USER_IDS.member1],
          },
        ]),
      );
    } finally {
      // Remove generated notifications, jobs, and credential rows.
      deleteNotifications(notificationIds);
      cleanupBadgeAwardJobs({ badgeId: badge.badgeId });
      cleanupCredential({
        badgeCreated: badge.badgeCreated,
        badgeId: badge.badgeId,
        badgeStatusListId: statusList.badgeStatusListId,
        userBadgeId: credentialId,
      });
    }
  });
});

/** Awards a selected badge to member one through the attendee picker. */
const awardBadgeToMemberOne = async (page, badgeId) => {
  await openEligibleEventAttendees(page);
  await page.getByRole("button", { name: "Award badge" }).click();
  await page.getByRole("menuitem", { name: "Choose attendees" }).click();

  const selectionBar = page.locator("[data-attendee-email-selection-bar]");
  const attendeeCheckbox = page.getByRole("checkbox", {
    name: `Select ${MEMBER_ONE_NAME}`,
  });

  await expect(selectionBar).toBeVisible();
  await attendeeCheckbox.check();
  await expect(selectionBar).toContainText("1 attendee selected");
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes("/dashboard/group/badges/options") &&
        response.ok(),
    ),
    selectionBar.getByRole("button", { name: "Continue" }).click(),
  ]);

  const awardDialog = page.getByRole("dialog", {
    name: "Award badge",
  });
  await expect(awardDialog.getByRole("radiogroup", { name: "Badge" })).toBeVisible();
  await awardDialog.locator(`input[value="${badgeId}"]`).check({
    force: true,
  });
  await waitForActionResponse(
    page,
    () => awardDialog.getByRole("button", { name: "Award", exact: true }).click(),
    {
      method: "POST",
      urlEndsWith: "/dashboard/group/badges/award",
      status: 201,
    },
  );
  await expect(awardDialog.getByRole("status")).toContainText("Award accepted");
  await awardDialog.getByRole("button", { name: "Close", exact: true }).click();
};

/** Counts active user_badge rows for the supplied badge and user. */
const countActiveCredentials = (badgeId, userId) =>
  Number(
    queryE2eDatabaseRows(`
      select count(*)
      from user_badge
      where badge_id = '${badgeId}'::uuid
      and user_id = '${userId}'::uuid
      and revoked_at is null
    `)[0][0],
  );

/** Asserts the credential verification page shows the expected status. */
const expectCredentialVerification = async (page, credentialId, badgeName, statusText) => {
  await navigateToPath(page, "/badges/verify");
  await page.getByLabel("Credential URL or ID").fill(credentialId);
  await page.getByRole("button", { name: "Verify badge" }).click();

  await expect(page.getByText(statusText, { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: badgeName })).toBeVisible();
};

/** Returns badge_award_job and user_badge diagnostics for issuance polling. */
const getIssuanceDiagnostics = ({ badgeId, userId }) => {
  const jobs = queryE2eDatabaseRows(`
    select
      badge_award_job_id,
      status,
      accepted_count,
      awarded_count,
      skipped_count,
      next_recipient_offset,
      coalesce(error, '')
    from badge_award_job
    where badge_id = '${badgeId}'::uuid
    order by created_at desc, badge_award_job_id desc
  `).map(([jobId, status, accepted, awarded, skipped, offset, error]) => ({
    accepted,
    awarded,
    error,
    jobId,
    offset,
    skipped,
    status,
  }));
  const credentials = queryE2eDatabaseRows(`
    select user_badge_id, revoked_at is null
    from user_badge
    where badge_id = '${badgeId}'::uuid
    and user_id = '${userId}'::uuid
    order by awarded_at desc, user_badge_id desc
  `).map(([userBadgeId, active]) => ({ active: active === "t", userBadgeId }));

  return {
    credentials,
    jobs,
    ready:
      credentials.filter((credential) => credential.active).length === 1 &&
      jobs.some((job) => job.status === "completed"),
  };
};

/** Opens the eligible past event editor from the group dashboard. */
const openEligibleEvent = async (page) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  await page.locator("#past-tab").click();
  await expect(page.locator("#past-content")).toBeVisible();
  const eventRow = page.locator("#past-content").getByRole("row", {
    name: new RegExp(ELIGIBLE_EVENT_NAME, "u"),
  });

  await waitForActionResponse(
    page,
    () => eventRow.getByRole("button", { name: `Edit event: ${ELIGIBLE_EVENT_NAME}` }).click(),
    {
      method: "GET",
      urlIncludes: `/events/${ELIGIBLE_EVENT_ID}/update`,
    },
  );
};

/** Opens the eligible event attendees section and waits for its table. */
const openEligibleEventAttendees = async (page) => {
  await openEligibleEvent(page);
  await waitForActionResponse(page, () => page.locator('button[data-section="attendees"]').click(), {
    method: "GET",
    urlIncludes: `/events/${ELIGIBLE_EVENT_ID}/attendees`,
  });
  await expect(page.getByRole("table", { name: "Attendees list" })).toBeVisible();
};

/** Revokes a credential from the awards dashboard with an internal reason. */
const revokeCredentialFromAwards = async (page, { badgeName, reason, userBadgeId }) => {
  await navigateToPath(page, GROUP_AWARDS_PATH);
  const dashboardContent = page.locator("#dashboard-content");
  const searchInput = dashboardContent.getByRole("textbox", {
    name: "Search awards",
  });
  await searchInput.fill(badgeName);
  await waitForAwardsRefresh(page, () => searchInput.press("Enter"));
  const credentialLink = dashboardContent.locator(`a[href="/badges/credentials/${userBadgeId}"]`);
  const credentialRow = credentialLink.locator("xpath=ancestor::tr");

  await expect(credentialLink).toBeVisible();
  await expect(credentialRow).toContainText(MEMBER_ONE_NAME);
  await expect(credentialRow).toContainText("Active");
  await credentialRow.getByRole("button", { name: `Revoke credential: ${badgeName}` }).click();

  const revokeDialog = page.getByRole("dialog", { name: `Revoke ${badgeName}` });
  await revokeDialog.getByLabel("Internal reason").fill(reason);
  await waitForActionResponse(
    page,
    () => revokeDialog.getByRole("button", { name: "Permanently revoke" }).click(),
    {
      method: "POST",
      status: 204,
      urlEndsWith: `/badges/awards/${userBadgeId}/revoke`,
    },
  );

  await expect(credentialRow).toContainText("Revoked");
  await expect(credentialRow).toContainText(reason);
};

/** Asserts an exported badge PNG verifies with the expected status. */
const verifyExportedBadge = async (page, png, badgeName, statusText) => {
  await navigateToPath(page, "/badges/verify");
  await page.locator('image-field[name="png"] input[type="file"]').setInputFiles({
    buffer: png,
    mimeType: "image/png",
    name: "issued-open-badge.png",
  });
  await page.getByRole("button", { name: "Verify badge" }).click();

  await expect(page.getByText(statusText, { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: badgeName })).toBeVisible();
};

/** Waits for the awards dashboard HTMX refresh triggered by an action. */
const waitForAwardsRefresh = async (page, action) => {
  await page.evaluate(() => {
    window.__e2eAwardsRefreshSettled = new Promise((resolve) => {
      const handleAwardsRefreshSettled = (event) => {
        const responseUrl = new URL(event.detail.xhr.responseURL);

        if (responseUrl.pathname !== "/dashboard/group/awards") {
          return;
        }

        document.body.removeEventListener("htmx:afterSettle", handleAwardsRefreshSettled);
        resolve();
      };

      document.body.addEventListener("htmx:afterSettle", handleAwardsRefreshSettled);
    });
  });

  await Promise.all([
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

  await page.evaluate(() => window.__e2eAwardsRefreshSettled);
  await page.evaluate(() => {
    delete window.__e2eAwardsRefreshSettled;
  });
};

/** Waits for issuance diagnostics to expose the active credential. */
const waitForIssuedCredential = async ({ badgeId, userId }) => {
  await expect
    .poll(() => JSON.stringify(getIssuanceDiagnostics({ badgeId, userId })), {
      intervals: [1_000, 2_000, 5_000],
      message: "badge_award_job diagnostics should show one issued credential",
      timeout: BADGE_ISSUANCE_TIMEOUT_MS,
    })
    .toContain('"ready":true');

  return getIssuanceDiagnostics({ badgeId, userId }).credentials.find((credential) => credential.active)
    .userBadgeId;
};
