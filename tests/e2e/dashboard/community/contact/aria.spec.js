import { expect, test } from "../../../fixtures.js";

import { setupCommunityTaxonomyItem } from "../../../data-graphs/communities.js";
import { setupTemporaryGroup } from "../../../data-graphs/groups.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { waitForActionResponse } from "../../../utils.js";
import { openCommunityDashboardView, setupAriaCommunity } from "../aria-helpers.js";

const RECIPIENTS_URL = "/dashboard/community/contact/recipients";

test.describe("community dashboard contact ARIA snapshots", () => {
  test("matches the desktop views", async ({ adminCommunityPage, owned }) => {
    await expectContactViews({ owned, page: adminCommunityPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ adminCommunityPage, owned }) => {
    await enableDesktopVersion(adminCommunityPage);
    await expectContactViews({ owned, page: adminCommunityPage });
  });
});

/** Checks the layout of the contact tab views and captures them. */
const expectContactViews = async ({ owned, page }) => {
  const { communityId, groupCategoryId } = await setupAriaCommunity({ owned, page });
  const summary = page.locator("#community-contact-summary");

  await test.step("community without groups", async () => {
    // Load the contact form of a temporary community without groups and check the layout.
    const content = await openCommunityDashboardView(page, "tab=contact");

    // Capture the filters, the disabled groups picker, the empty preview and the message fields.
    await expectAriaSnapshot(page, content, "contact-no-groups");
  });

  // Add a group in a region whose team is the first organizer, and a group without a team.
  const regionId = setupCommunityTaxonomyItem({ communityId, kind: "region", name: "E2E ARIA region" });
  setupTemporaryGroup({
    communityId,
    groupCategoryId,
    regionId,
    teamRole: "admin",
    teamUserId: TEST_USER_IDS.organizer1,
  });
  const unstaffed = setupTemporaryGroup({ communityId, groupCategoryId });

  await test.step("contact form", async () => {
    // Load the contact form with both groups and check the layout.
    const form = page.locator("#community-contact-form");
    await openCommunityDashboardView(page, "tab=contact", { regions: [form] });
    await expect(summary).toHaveAttribute("data-people-count", "1");

    // Capture the filters with regions, the preview of one recipient and the message fields.
    await expectAriaSnapshot(page, form, "contact-form");
  });

  await test.step("matching groups", async () => {
    // Expand the preview's matching groups and check the layout.
    await summary.locator("summary").click();
    await expect(summary.getByRole("list", { name: "Matching groups" })).toBeVisible();
    await expectPageLayout(page, { regions: [summary] });

    // Capture the group of the only recipient, with its category, region and seats.
    await expectAriaSnapshot(page, summary, "contact-matching-groups");
  });

  await test.step("team roles options", async () => {
    // Open the team roles picker and check the layout.
    const listbox = page.getByRole("listbox");
    await page.getByRole("combobox", { name: "Team roles" }).click();
    await expect(listbox).toBeVisible();
    await expectPageLayout(page, { regions: [listbox] });

    // Capture the group team roles offered as filters.
    await expectAriaSnapshot(page, listbox, "contact-roles-options");
    await page.keyboard.press("Escape");
    await expect(listbox).toHaveCount(0);
  });

  await test.step("selected group without a team", async () => {
    // Select the group without a team and check the layout.
    await page.getByRole("combobox", { name: "Groups", exact: true }).click();
    await waitForActionResponse(
      page,
      () => page.getByRole("option", { name: new RegExp(`^${unstaffed.groupName}`) }).click(),
      { method: "POST", urlIncludes: RECIPIENTS_URL },
    );
    await expect(summary).toHaveAttribute("data-people-count", "0");
    await expectPageLayout(page, { regions: [summary] });

    // Capture the empty preview listing the selected group without matching team members.
    await expectAriaSnapshot(page, summary, "contact-unmatched-groups");
  });
};
