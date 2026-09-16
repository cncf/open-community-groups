import { expect, test } from "../../../fixtures.js";
import { cleanupEventsByIds } from "../../../data-graphs/events.js";
import { TEST_USER_IDS } from "../../../seed.js";
import {
  futureDate,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";
import { fillMarkdownEditor } from "../../form-helpers.js";
import { openEventUpdateFormByName, waitForEventEditorAfterSave } from "./helpers.js";

const HIDDEN_SPONSOR_ID = "66666666-6666-6666-6666-666666666602";

const TECH_CORP_SPONSOR_ID = "66666666-6666-6666-6666-666666666601";

test.describe("group dashboard event contributors", () => {
  test("organizer can persist hosts, speakers, and sponsors to the public event page", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(120_000);

    const eventName = uniqueName("Event Contributors");
    let eventId = "";
    let publicEventPath = "";

    try {
      // Create an event and configure people and sponsors through the editor.
      await fillEventDetails(organizerGroupPage, eventName);
      await organizerGroupPage.locator('button[data-section="hosts-sponsors"]').click();
      await addEventHost(organizerGroupPage, {
        name: "E2E Organizer One",
        userId: TEST_USER_IDS.organizer1,
        username: "e2e-organizer-1",
      });
      await addEventHost(organizerGroupPage, {
        name: "E2E Member One",
        userId: TEST_USER_IDS.member1,
        username: "e2e-member-1",
      });
      await addEventSpeaker(organizerGroupPage, {
        featured: true,
        name: "E2E Member One",
        userId: TEST_USER_IDS.member1,
        username: "e2e-member-1",
      });
      await addEventSpeaker(organizerGroupPage, {
        name: "E2E Member Two",
        userId: TEST_USER_IDS.member2,
        username: "e2e-member-2",
      });
      await addEventSponsor(organizerGroupPage, {
        level: "Platinum",
        name: "Tech Corp",
        sponsorId: TECH_CORP_SPONSOR_ID,
      });
      await addEventSponsor(organizerGroupPage, {
        level: "Community",
        name: "Hidden Sponsor",
        sponsorId: HIDDEN_SPONSOR_ID,
      });

      // Save and publish the event so the public page can render the persisted contributors.
      const visibleAddEventButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #add-event-button",
      );
      await expect(visibleAddEventButton).toBeVisible();
      await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
        method: "POST",
        status: 201,
        urlIncludes: "/dashboard/group/events/add",
      });
      eventId = await waitForEventEditorAfterSave(organizerGroupPage);
      publicEventPath =
        (await organizerGroupPage.locator("#event-update-page").getAttribute("data-event-public-url")) || "";
      await publishCurrentEvent(organizerGroupPage, eventId);

      // Verify the public event page renders people, avatars, sponsor logos, and featured ordering.
      await navigateToPath(organizerGroupPage, publicEventPath);
      await expect(organizerGroupPage.getByRole("heading", { level: 1, name: eventName })).toBeVisible();
      await assertPublicContributors(organizerGroupPage, {
        hiddenSponsorVisible: true,
        memberTwoVisible: true,
      });

      // Reopen the editor and verify the saved selections are restored.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      await openEventUpdateFormByName(organizerGroupPage, eventName, eventId);
      await organizerGroupPage.locator('button[data-section="hosts-sponsors"]').click();
      await assertEditorContributors(organizerGroupPage, {
        hiddenSponsorVisible: true,
        memberTwoVisible: true,
      });

      // Remove one host, one speaker, and one sponsor, then save the editor again.
      const hostRow = organizerGroupPage.locator("#event-hosts-selector tr", {
        hasText: "E2E Organizer One",
      });
      await hostRow.locator("[data-actions-menu] summary").click();
      await hostRow.getByRole("menuitem", { name: "Delete" }).click();
      const speakerRow = organizerGroupPage.locator("#event-speakers-selector tr", {
        hasText: "E2E Member Two",
      });
      await speakerRow.locator("[data-actions-menu] summary").click();
      await speakerRow.getByRole("menuitem", { name: "Delete" }).click();
      await organizerGroupPage
        .locator("sponsors-section")
        .getByRole("button", {
          name: "Remove Hidden Sponsor",
        })
        .click();
      await saveCurrentEvent(organizerGroupPage, eventId);

      // Verify both the reopened editor and public event page reflect the removals.
      await organizerGroupPage.locator('button[data-section="hosts-sponsors"]').click();
      await expect(
        organizerGroupPage.locator("#event-hosts-selector").getByText("E2E Organizer One"),
      ).toHaveCount(0);
      await assertEditorContributors(organizerGroupPage, {
        hiddenSponsorVisible: false,
        memberTwoVisible: false,
        organizerOneVisible: false,
      });
      await navigateToPath(organizerGroupPage, publicEventPath);
      await expect(organizerGroupPage.getByRole("heading", { level: 1, name: eventName })).toBeVisible();
      await assertPublicContributors(organizerGroupPage, {
        hiddenSponsorVisible: false,
        memberTwoVisible: false,
        organizerOneVisible: false,
      });
    } finally {
      // Delete the copied event used for contributor visibility checks.
      cleanupEventsByIds(eventId ? [eventId] : []);
    }
  });
});

/** Adds an event host through the user selector and asserts its hidden input. */
const addEventHost = async (page, { name, userId, username }) => {
  const hostsSelector = page.locator("#event-hosts-selector");
  const searchInput = hostsSelector.locator("[data-user-search-input]");

  await searchInput.fill(username);
  await expect(hostsSelector.getByText(name, { exact: true })).toBeVisible();
  await hostsSelector.getByText(name, { exact: true }).click();
  await expect(hostsSelector.locator(`input[name="hosts[]"][value="${userId}"]`)).toHaveCount(1);
};

/** Adds an event speaker through the modal and asserts its hidden input. */
const addEventSpeaker = async (page, { featured = false, name, userId, username }) => {
  const speakersSelector = page.locator("#event-speakers-selector");

  await speakersSelector.getByRole("button", { name: "Add speaker" }).click();
  const speakerModal = speakersSelector.locator("session-speaker-modal");
  await expect(speakerModal.getByRole("heading", { name: "Add speaker" })).toBeVisible();

  await speakerModal.locator("[data-user-search-input]").fill(username);
  await expect(speakerModal.getByText(name, { exact: true })).toBeVisible();
  await speakerModal.getByText(name, { exact: true }).click();

  if (featured) {
    await speakerModal.getByLabel("Featured speaker").check({ force: true });
  }

  await speakerModal.getByRole("button", { name: "Add speaker" }).click();
  await expect(speakerModal.getByRole("heading", { name: "Add speaker" })).toHaveCount(0);
  await expect(
    speakersSelector.locator(`input[name^="speakers"][name$="[user_id]"][value="${userId}"]`),
  ).toHaveCount(1);
};

/** Adds an event sponsor with its level and asserts its hidden input. */
const addEventSponsor = async (page, { level, name, sponsorId }) => {
  const sponsorsSection = page.locator("sponsors-section");
  const searchInput = sponsorsSection.getByPlaceholder("Search sponsors");

  await searchInput.fill(name);
  await expect(sponsorsSection.getByText(name, { exact: true }).first()).toBeVisible();
  await searchInput.press("Enter");
  await expect(sponsorsSection.locator("#sponsor-level-input")).toBeVisible();
  await sponsorsSection.locator("#sponsor-level-input").fill(level);
  await sponsorsSection.getByRole("button", { name: "Add" }).click();
  await expect(sponsorsSection.locator(`input[value="${sponsorId}"]`)).toHaveCount(1);
};

/** Asserts the hosts, speakers and sponsors shown in the event editor. */
const assertEditorContributors = async (
  page,
  { hiddenSponsorVisible = true, memberTwoVisible = true, organizerOneVisible = true },
) => {
  const hostsSelector = page.locator("#event-hosts-selector");
  const speakersSelector = page.locator("#event-speakers-selector");
  const sponsorsSection = page.locator("sponsors-section");

  await expect(hostsSelector.getByText("E2E Organizer One", { exact: true })).toHaveCount(
    organizerOneVisible ? 1 : 0,
  );
  await expect(hostsSelector.getByRole("table", { name: "Event hosts" })).toContainText("E2E Member One");
  await expect(speakersSelector.getByRole("table", { name: "Event speakers" })).toContainText(
    "E2E Member One",
  );
  await expect(speakersSelector.locator('[title="Featured speaker"]')).toBeVisible();
  await expect(speakersSelector.getByText("E2E Member Two", { exact: true })).toHaveCount(
    memberTwoVisible ? 1 : 0,
  );
  await expect(sponsorsSection.getByText("Tech Corp", { exact: true })).toBeVisible();
  await expect(sponsorsSection.getByText("Platinum", { exact: true })).toBeVisible();
  await expect(sponsorsSection.getByText("Hidden Sponsor", { exact: true })).toHaveCount(
    hiddenSponsorVisible ? 1 : 0,
  );
};

/** Asserts the hosts, speakers and sponsors shown on the public event page. */
const assertPublicContributors = async (
  page,
  { hiddenSponsorVisible = true, memberTwoVisible = true, organizerOneVisible = true },
) => {
  // Scope host assertions to the Hosts block; group organizers render the same chips further down.
  const hostsSection = page.getByText("Hosts", { exact: true }).locator("..");
  await expect(hostsSection).toBeVisible();
  await expect(hostsSection.locator("user-chip", { hasText: "E2E Organizer One" })).toHaveCount(
    organizerOneVisible ? 1 : 0,
  );
  if (organizerOneVisible) {
    await expect(
      hostsSection.locator("user-chip", { hasText: "E2E Organizer One" }).locator("logo-image"),
    ).toBeVisible();
  }
  await expect(hostsSection.locator("user-chip", { hasText: "E2E Member One" })).toBeVisible();

  await expect(page.getByText("Featured speakers", { exact: true })).toBeVisible();
  const featuredChip = page.locator(".featured-speakers-section user-chip", {
    hasText: "E2E Member One",
  });
  await expect(featuredChip).toBeVisible();
  await expect(featuredChip).toHaveAttribute("featured", "");
  await expect(page.locator("user-chip", { hasText: "E2E Member Two" })).toHaveCount(
    memberTwoVisible ? 1 : 0,
  );

  await expect(page.getByText("Sponsors", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Tech Corp/ })).toContainText("Platinum");
  await expect(page.locator('img[alt="Tech Corp logo"]')).toHaveAttribute(
    "src",
    "/static/images/e2e/sponsor-logo.svg",
  );
  await expect(page.getByText("Hidden Sponsor", { exact: true })).toHaveCount(hiddenSponsorVisible ? 1 : 0);
};

/** Fills the event form with contributor coverage details. */
const fillEventDetails = async (page, eventName) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  await page.locator("#dashboard-content").getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();

  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
  await page.locator("#description_short").fill("Contributor persistence coverage for event people.");
  await fillMarkdownEditor(
    page,
    "description",
    "Contributor persistence coverage for hosts, speakers, and event sponsors.",
  );

  await page.locator('button[data-section="date-venue"]').click();
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill(futureDate({ days: 360, hour: 10 }));
  await page.locator("#ends_at").fill(futureDate({ days: 360, hour: 12 }));
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-people-sponsors");
};

/** Publishes the current event and waits for the editor save response. */
const publishCurrentEvent = async (page, eventId) => {
  await page.locator("#publish-event-button").click();
  await waitForEventEditorAfterSave(page, () => page.getByRole("button", { name: "Yes" }).click(), {
    eventId,
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${eventId}/publish`,
  });
};

/** Saves the current event and waits for the editor update response. */
const saveCurrentEvent = async (page, eventId) => {
  const visibleSaveButton = page.locator("#pending-changes-alert:not(.hidden) #update-event-button");
  await expect(visibleSaveButton).toBeVisible();
  await waitForEventEditorAfterSave(page, () => visibleSaveButton.click(), {
    eventId,
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${eventId}/update`,
  });
};
