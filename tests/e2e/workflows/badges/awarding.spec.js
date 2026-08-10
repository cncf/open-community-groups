import { expect, test } from "../../fixtures.js";

import {
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  navigateToPath,
  waitForActionResponse,
} from "../../utils.js";

const HOST_BADGE_ID = "babababa-baba-baba-baba-babababab001";

const closeAwardDialog = async (page) => {
  await page
    .getByRole("dialog", { name: "Award badge" })
    .getByRole("button", { name: "Cancel" })
    .click();
};

const openPrimaryEvent = async (page) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  const eventRow = page.getByRole("row", {
    name: new RegExp(TEST_EVENT_NAMES.alpha[0], "u"),
  });

  await waitForActionResponse(
    page,
    () =>
      eventRow
        .getByRole("button", {
          name: `Edit event: ${TEST_EVENT_NAMES.alpha[0]}`,
        })
        .click(),
    {
      method: "GET",
      urlIncludes: `/events/${TEST_EVENT_IDS.alpha.one}/update`,
    },
  );
};

const openPrimaryEventAttendees = async (page) => {
  await openPrimaryEvent(page);
  await waitForActionResponse(
    page,
    () => page.locator('button[data-section="attendees"]').click(),
    {
      method: "GET",
      urlIncludes: `/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
    },
  );
  await expect(
    page.getByRole("table", { name: "Attendees list" }),
  ).toBeVisible();
};

test.describe("group badge awarding", () => {
  test("organizer can award a badge to all eligible attendees", async ({
    organizerGroupPage,
  }) => {
    // Resolve all attendees and open the shared badge picker.
    await openPrimaryEventAttendees(organizerGroupPage);
    await organizerGroupPage
      .getByRole("button", { name: "Award badge" })
      .click();
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        organizerGroupPage
          .getByRole("menuitem", { name: "All attendees" })
          .click(),
      {
        method: "GET",
        urlIncludes: `/events/${TEST_EVENT_IDS.alpha.one}/badges/recipients?scope=all-attendees`,
      },
    );

    const awardDialog = organizerGroupPage.getByRole("dialog", {
      name: "Award badge",
    });
    await expect(
      awardDialog.getByRole("radiogroup", { name: "Badge" }),
    ).toBeVisible();
    await awardDialog.locator(`input[value="${HOST_BADGE_ID}"]`).check({
      force: true,
    });

    // Submit the real request; both seeded attendees already hold this badge.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        awardDialog.getByRole("button", { name: "Award", exact: true }).click(),
      {
        method: "POST",
        urlEndsWith: "/dashboard/group/badges/award",
        status: 201,
      },
    );
    await expect(awardDialog.getByRole("status")).toContainText(
      "Award accepted",
    );
    await expect(awardDialog.getByRole("status")).toContainText(
      "2 active holders were skipped.",
    );
    await awardDialog
      .getByRole("button", { name: "Close", exact: true })
      .click();
  });

  test("organizer can award a badge to chosen attendees", async ({
    organizerGroupPage,
  }) => {
    // Enter badge selection mode from the attendee award menu.
    await openPrimaryEventAttendees(organizerGroupPage);
    await organizerGroupPage
      .getByRole("button", { name: "Award badge" })
      .click();
    await organizerGroupPage
      .getByRole("menuitem", { name: "Choose attendees" })
      .click();

    const selectionBar = organizerGroupPage.locator(
      "[data-attendee-email-selection-bar]",
    );
    const attendeeCheckbox = organizerGroupPage.getByRole("checkbox", {
      name: "Select E2E Member One",
    });

    await expect(selectionBar).toBeVisible();
    await attendeeCheckbox.check();
    await expect(selectionBar).toContainText("1 attendee selected");
    await selectionBar.getByRole("button", { name: "Continue" }).click();

    // Verify the exact selection opens the same reusable picker.
    const awardDialog = organizerGroupPage.getByRole("dialog", {
      name: "Award badge",
    });
    await expect(
      awardDialog.getByRole("radiogroup", { name: "Badge" }),
    ).toBeVisible();
    await awardDialog.locator(`input[value="${HOST_BADGE_ID}"]`).check({
      force: true,
    });

    // Submit the real request; the selected attendee already holds this badge.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        awardDialog.getByRole("button", { name: "Award", exact: true }).click(),
      {
        method: "POST",
        urlEndsWith: "/dashboard/group/badges/award",
        status: 201,
      },
    );
    await expect(awardDialog.getByRole("status")).toContainText(
      "Award accepted",
    );
    await expect(awardDialog.getByRole("status")).toContainText(
      "1 active holder was skipped.",
    );
    await awardDialog
      .getByRole("button", { name: "Close", exact: true })
      .click();
  });

  test("host, speaker, and session-speaker actions use the shared picker", async ({
    organizerGroupPage,
  }) => {
    // Open the contributor section of the seeded event.
    await openPrimaryEvent(organizerGroupPage);
    await organizerGroupPage
      .locator('button[data-section="hosts-sponsors"]')
      .click();

    // Open the all-hosts picker.
    await organizerGroupPage.locator("#event-hosts-award-button").click();
    await expect(
      organizerGroupPage
        .getByRole("dialog", { name: "Award badge" })
        .getByRole("radiogroup", { name: "Badge" }),
    ).toBeVisible();
    await closeAwardDialog(organizerGroupPage);

    // Open the all-speakers picker and verify session speakers are included.
    await organizerGroupPage
      .locator("speakers-selector")
      .getByRole("button", { name: "Award badge" })
      .click();
    const speakerDialog = organizerGroupPage.getByRole("dialog", {
      name: "Award badge",
    });
    await expect(
      speakerDialog.getByText(
        "including speakers assigned to individual sessions",
        { exact: false },
      ),
    ).toBeVisible();
    await closeAwardDialog(organizerGroupPage);

    // Open one session speaker's row action.
    const sessionSpeakers = organizerGroupPage.locator(
      "session-speakers-table",
    );
    const sessionSpeakerRow = sessionSpeakers.locator("tr", {
      hasText: "E2E Member One",
    });
    await sessionSpeakerRow
      .locator(
        'summary[aria-label="Open session speaker actions for E2E Member One"]',
      )
      .click();
    const sessionSpeakerAwardButton = sessionSpeakerRow.locator(
      "button[data-badge-award-open]",
    );
    await expect(sessionSpeakerAwardButton).toBeEnabled();
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        sessionSpeakerAwardButton.evaluate((button) => {
          const badgeAwardModal = document.querySelector("badge-award-modal");

          if (!badgeAwardModal || typeof badgeAwardModal.open !== "function") {
            throw new Error("Badge award modal is unavailable");
          }
          badgeAwardModal.open({
            eventId: button.dataset.eventId,
            trigger: button,
            userIds: button.dataset.userIds.split(",").filter(Boolean),
          });
        }),
      {
        method: "GET",
        urlIncludes: "/dashboard/group/badges/options",
      },
    );
    await expect(
      organizerGroupPage
        .getByRole("dialog", { name: "Award badge" })
        .getByRole("radiogroup", { name: "Badge" }),
    ).toBeVisible();
    await closeAwardDialog(organizerGroupPage);
  });

  test("accepted group team members can receive badges", async ({
    organizerGroupPage,
  }) => {
    // Open an accepted member's team action menu.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");
    const memberRow = organizerGroupPage.getByRole("row", {
      name: /E2E Events Manager One/u,
    });

    await memberRow
      .locator(
        'summary[aria-label="Open team member actions for E2E Events Manager One"]',
      )
      .click();
    await memberRow.getByRole("menuitem", { name: "Award badge" }).click();

    // Verify group-level awards omit an event but reuse the picker experience.
    const awardDialog = organizerGroupPage.getByRole("dialog", {
      name: "Award badge",
    });
    await expect(
      awardDialog.getByRole("radiogroup", { name: "Badge" }),
    ).toBeVisible();
    await awardDialog.locator(`input[value="${HOST_BADGE_ID}"]`).check({
      force: true,
    });

    // Submit the real request; the team member already holds this badge.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        awardDialog.getByRole("button", { name: "Award", exact: true }).click(),
      {
        method: "POST",
        urlEndsWith: "/dashboard/group/badges/award",
        status: 201,
      },
    );
    await expect(awardDialog.getByRole("status")).toContainText(
      "Award accepted",
    );
    await expect(awardDialog.getByRole("status")).toContainText(
      "1 active holder was skipped.",
    );
    await awardDialog
      .getByRole("button", { name: "Close", exact: true })
      .click();
  });
});
