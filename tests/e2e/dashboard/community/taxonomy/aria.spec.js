import { expect, test } from "../../../fixtures.js";

import {
  cleanupCommunityTaxonomyItem,
  setupCommunityTaxonomyItem,
} from "../../../data-graphs/communities.js";
import { setupTemporaryGroup } from "../../../data-graphs/groups.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openCommunityDashboardView, setupAriaCommunity } from "../aria-helpers.js";

// Community taxonomies: form id, data-graph kind, item noun and dashboard tab, which also prefixes the snapshots.
const TAXONOMIES = {
  eventCategories: {
    formId: "event-category-form",
    kind: "eventCategory",
    noun: "Event Category",
    tab: "event-categories",
  },
  groupCategories: {
    formId: "group-category-form",
    kind: "groupCategory",
    noun: "Group Category",
    tab: "group-categories",
  },
  regions: { formId: "region-form", kind: "region", noun: "Region", tab: "regions" },
};

test.describe("community dashboard taxonomy ARIA snapshots", () => {
  for (const taxonomy of Object.values(TAXONOMIES)) {
    test(`matches the desktop ${taxonomy.tab} views`, async ({ adminCommunityPage, owned }) => {
      await expectTaxonomyViews({ owned, page: adminCommunityPage, taxonomy });
    });

    test(`matches the ${taxonomy.tab} views in the mobile desktop version @mobile`, async ({
      adminCommunityPage,
      owned,
    }) => {
      await enableDesktopVersion(adminCommunityPage);
      await expectTaxonomyViews({ owned, page: adminCommunityPage, taxonomy });
    });
  }
});

/**
 * Checks the layout of one taxonomy tab's views and captures them: the empty list, the add form,
 * an item in use next to a free one, and the update form.
 */
const expectTaxonomyViews = async ({ owned, page, taxonomy }) => {
  const { formId, kind, noun, tab } = taxonomy;
  const { communityId, groupCategoryId } = await setupAriaCommunity({ owned, page });
  const itemNoun = noun.toLowerCase();
  const usedName = `E2E ARIA ${itemNoun} one`;
  const freeName = `E2E ARIA ${itemNoun} two`;

  // The temporary community comes with the group category of its groups; drop it while empty.
  if (kind === "groupCategory") {
    cleanupCommunityTaxonomyItem({ itemId: groupCategoryId, kind });
  }

  await test.step("empty state", async () => {
    // Load the tab of a temporary community without items and check the layout.
    const content = await openCommunityDashboardView(page, `tab=${tab}`);

    // Capture the title, the count, the add button, the column headers and the empty state.
    await expectAriaSnapshot(page, content, `${tab}-empty`);
  });

  await test.step("add form", async () => {
    // Open the add form and check the layout.
    const form = page.locator(`#${formId}`);
    await page.getByRole("button", { name: `Add ${noun}` }).click();
    await expect(form.getByRole("button", { name: `Add ${noun}` })).toBeVisible();
    await expectPageLayout(page, { regions: [form] });

    // Capture the name field and the form actions.
    await expectAriaSnapshot(page, form, `${tab}-add-form`);
  });

  // Add an item in use, by a group or by an event of a group, and a free one that can be deleted.
  const usedId = setupCommunityTaxonomyItem({ communityId, kind, name: usedName });
  setupCommunityTaxonomyItem({ communityId, kind, name: freeName });
  setupTaxonomyUse({ communityId, groupCategoryId, kind, owned, usedId });

  await test.step("items list", async () => {
    // Load both items and check the layout.
    const table = page.getByRole("table");
    await openCommunityDashboardView(page, `tab=${tab}`, { regions: [table] });

    // Capture the count and the rows, with deletion disabled for the item in use.
    await expectAriaSnapshot(page, page.locator("#dashboard-content"), `${tab}-list`);
  });

  await test.step("update form", async () => {
    // Open the update form of the item in use and check the layout.
    const form = page.locator(`#${formId}`);
    await page.getByRole("button", { name: `Edit ${itemNoun}: ${usedName}` }).click();
    await expect(form.getByRole("button", { name: `Update ${noun}` })).toBeVisible();
    await expectPageLayout(page, { regions: [form] });

    // Capture the name field filled with the item and the form actions.
    await expectAriaSnapshot(page, form, `${tab}-update-form`);
  });
};

/**
 * Puts a taxonomy item in use: a region or group category by a temporary group of the community,
 * an event category by an owned event of that group.
 */
const setupTaxonomyUse = ({ communityId, groupCategoryId, kind, owned, usedId }) => {
  const group = setupTemporaryGroup({
    communityId,
    groupCategoryId: kind === "groupCategory" ? usedId : groupCategoryId,
    regionId: kind === "region" ? usedId : null,
  });
  if (kind === "eventCategory") {
    owned.event({ categoryId: usedId, groupId: group.groupId });
  }
};
