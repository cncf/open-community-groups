import { expect, test } from "../../fixtures.js";

import { TEST_EVENT_IDS } from "../../seed.js";
import { expectFocusIndicator, navigateToPath, pressKeyUntilFocused } from "../../utils.js";
import { openAttendeesTab } from "../group/events/attendees-helpers.js";

// Outline colour of the site-primary focus indicator.
const PRIMARY_OUTLINE = "var(--color-focus)";

test.describe("dashboard focus indicator", () => {
  test("shows the focus outline on dashboard fields, checkboxes and outline buttons", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab of the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );
    const searchField = attendeesContent.getByLabel("Search attendees");
    const sortSelect = attendeesContent.getByRole("combobox", { name: "Sort by" });
    const sendEmailButton = attendeesContent.getByRole("button", { name: "Send email" });
    await expect(sortSelect).toBeEnabled();
    await expect(sendEmailButton).toBeEnabled();

    // Verify the search field, the sort select and the outline button draw the outline on Tab.
    await expectFocusIndicator(searchField, () => pressKeyUntilFocused(organizerGroupPage, searchField), {
      outlineColor: PRIMARY_OUTLINE,
    });
    await expectFocusIndicator(sortSelect, () => pressKeyUntilFocused(organizerGroupPage, sortSelect), {
      outlineColor: PRIMARY_OUTLINE,
    });
    await expectFocusIndicator(
      sendEmailButton,
      () => pressKeyUntilFocused(organizerGroupPage, sendEmailButton),
      { outlineColor: PRIMARY_OUTLINE },
    );

    // Enter attendee selection mode, which focuses the first selection checkbox, then Tab past it.
    await sendEmailButton.click();
    await attendeesContent.getByRole("menuitem", { name: "Choose attendees" }).click();
    const selectionCheckbox = attendeesContent.getByRole("checkbox", { name: /^Select / }).first();
    await expect(selectionCheckbox).toBeFocused();
    await organizerGroupPage.keyboard.press("Tab");

    // Verify the checkbox draws the outline when Shift+Tab returns to it.
    await expectFocusIndicator(selectionCheckbox, () => organizerGroupPage.keyboard.press("Shift+Tab"), {
      outlineColor: PRIMARY_OUTLINE,
    });
  });

  test("shows the focus outline on an arrow-key-focused analytics tab", async ({ adminCommunityPage }) => {
    // Load the analytics tab wide enough for the summary cards to act as tabs.
    await adminCommunityPage.setViewportSize({ width: 1280, height: 800 });
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=analytics");
    const summaryTabs = adminCommunityPage.getByRole("tablist", { name: "Analytics summary" });
    const groupsTab = summaryTabs.getByRole("tab", { name: /^Groups/ });
    const membersTab = summaryTabs.getByRole("tab", { name: /^Members/ });
    await expect(summaryTabs).toBeVisible();

    // Select the first tab, then verify the arrow key moves a visible focus to the next one.
    await groupsTab.click();
    await expect(groupsTab).toBeFocused();
    await expectFocusIndicator(membersTab, () => adminCommunityPage.keyboard.press("ArrowRight"), {
      outlineColor: PRIMARY_OUTLINE,
    });
  });

  test("keeps script focus targets free of an outline", async ({ member1Page }) => {
    // Load the notifications tab and switch the page to keyboard modality.
    await navigateToPath(member1Page, "/dashboard/user?tab=notifications");
    const mutedGroupsHeading = member1Page.getByRole("heading", { name: "Muted groups" });
    await expect(mutedGroupsHeading).toBeVisible();
    await member1Page.keyboard.press("Tab");

    // Focus the heading from script and verify it draws no outline.
    await mutedGroupsHeading.focus();
    await expect(mutedGroupsHeading).toBeFocused();
    expect(await mutedGroupsHeading.evaluate((element) => element.matches(":focus-visible"))).toBe(true);
    await expect(mutedGroupsHeading).toHaveCSS("outline-style", "none");
  });
});
