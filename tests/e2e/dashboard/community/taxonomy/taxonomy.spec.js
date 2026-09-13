import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import { navigateToPath, uniqueName, waitForActionResponse } from "../../../utils.js";
import { waitForCommunityDashboardMutation } from "../helpers.js";

const taxonomyCases = [
  {
    addButton: "Add Event Category",
    createLabel: "an event category",
    deleteAriaPrefix: "Delete event category",
    deleteConfirmMessage: "Are you sure you would like to delete this event category?",
    editAriaPrefix: "Edit event category",
    emptyState: "No event categories found for this community yet.",
    firstItemLabel: "event category",
    formFields: [{ label: "Name", name: "name" }],
    formHeading: "Event Category Details",
    heading: "Event Categories",
    namePrefix: "Event Category",
    path: "/dashboard/community?tab=event-categories",
    refreshPath: "/dashboard/community/event-categories",
    seededUnusedName: "Workshops",
    seededUsedName: "General",
    tableName: "event_category",
    tableSelector: "#event-categories-list",
    updateButton: "Update Event Category",
    unusedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333333",
    usedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333331",
  },
  {
    addButton: "Add Group Category",
    createLabel: "a group category",
    deleteAriaPrefix: "Delete group category",
    deleteConfirmMessage: "Are you sure you would like to delete this group category?",
    editAriaPrefix: "Edit group category",
    emptyState: "No group categories found for this community yet.",
    firstItemLabel: "group category",
    formFields: [{ label: "Name", name: "name" }],
    formHeading: "Group Category Details",
    heading: "Group Categories",
    namePrefix: "Group Category",
    path: "/dashboard/community?tab=group-categories",
    refreshPath: "/dashboard/community/group-categories",
    seededUnusedName: "E2E Category Unused",
    seededUsedName: "E2E Category One",
    tableName: "group_category",
    tableSelector: "#group-categories-list",
    updateButton: "Update Group Category",
    unusedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222223",
    usedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222221",
  },
  {
    addButton: "Add Region",
    createLabel: "a region",
    deleteAriaPrefix: "Delete region",
    deleteConfirmMessage: "Are you sure you would like to delete this region?",
    editAriaPrefix: "Edit region",
    emptyState: "No regions found for this community yet.",
    firstItemLabel: "community region",
    formFields: [{ label: "Name", name: "name" }],
    formHeading: "Region Details",
    heading: "Regions",
    namePrefix: "Region",
    path: "/dashboard/community?tab=regions",
    refreshPath: "/dashboard/community/regions",
    seededUnusedName: "APAC",
    seededUsedName: "North America",
    tableName: "region",
    tableSelector: "#regions-list",
    updateButton: "Update Region",
    unusedDeleteId: "delete-region-22222222-2222-2222-2222-222222222302",
    usedDeleteId: "delete-region-22222222-2222-2222-2222-222222222301",
  },
];

test.describe("community dashboard taxonomy view", () => {
  for (const taxonomy of taxonomyCases) {
    test(`empty state guides the first ${taxonomy.firstItemLabel}`, async ({ adminEmptyCommunityPage }) => {
      // Load the taxonomy tab for the dedicated community without taxonomy records.
      await navigateToPath(adminEmptyCommunityPage, taxonomy.path);
      const dashboardContent = adminEmptyCommunityPage.locator("#dashboard-content");

      // Verify first-use guidance and the creation action remain available.
      await expect(dashboardContent).toContainText(taxonomy.emptyState);
      await expect(dashboardContent.getByRole("button", { name: taxonomy.addButton })).toBeVisible();
    });

    test(`admin can add, update, and delete ${taxonomy.createLabel}`, async ({ adminCommunityPage }) => {
      test.setTimeout(60_000);

      // Create unique names for the temporary taxonomy flow.
      const itemName = uniqueName(taxonomy.namePrefix);
      const updatedItemName = `${itemName} Updated`;
      let deletedThroughUi = false;

      try {
        // Load the taxonomy dashboard.
        await navigateToPath(adminCommunityPage, taxonomy.path);

        // Open the add form and submit the temporary taxonomy entry.
        const dashboardContent = adminCommunityPage.locator("#dashboard-content");
        await expect(dashboardContent.getByText(taxonomy.heading, { exact: true })).toBeVisible();
        await dashboardContent.getByRole("button", { name: taxonomy.addButton }).click();
        await expect(dashboardContent.getByText(taxonomy.formHeading, { exact: true })).toBeVisible();
        await fillTaxonomyForm(adminCommunityPage, taxonomy, itemName);
        await waitForCommunityDashboardMutation(
          adminCommunityPage,
          taxonomy.refreshPath,
          () => adminCommunityPage.getByRole("button", { name: taxonomy.addButton }).click(),
          {
            method: "POST",
            status: 201,
            urlIncludes: `${taxonomy.refreshPath}/add`,
          },
        );

        // Verify the temporary entry appears before updating it.
        let itemRow = getTaxonomyRow(dashboardContent, taxonomy, itemName);
        await expect(itemRow).toBeVisible();

        // Edit the temporary entry and wait for the update form to load.
        await waitForActionResponse(
          adminCommunityPage,
          () => itemRow.getByRole("button", { name: `${taxonomy.editAriaPrefix}: ${itemName}` }).click(),
          {
            method: "GET",
            urlEndsWith: "/update",
            urlIncludes: `${taxonomy.refreshPath}/`,
          },
        );
        await fillTaxonomyForm(adminCommunityPage, taxonomy, updatedItemName);
        await waitForCommunityDashboardMutation(
          adminCommunityPage,
          taxonomy.refreshPath,
          () => adminCommunityPage.getByRole("button", { name: taxonomy.updateButton }).click(),
          {
            method: "PUT",
            urlEndsWith: "/update",
            urlIncludes: `${taxonomy.refreshPath}/`,
          },
        );

        // Find the renamed entry and verify it is rendered.
        itemRow = getTaxonomyRow(dashboardContent, taxonomy, updatedItemName);
        await expect(itemRow).toBeVisible();

        // Delete the taxonomy entry from its row action.
        await deleteTaxonomyRow(adminCommunityPage, dashboardContent, taxonomy, updatedItemName);
        deletedThroughUi = true;

        // Assert how many matching elements are shown.
        await expect(getTaxonomyRow(dashboardContent, taxonomy, itemName)).toHaveCount(0);
      } finally {
        // Clean up the temporary taxonomy entries.
        await cleanupTaxonomyEntry(
          adminCommunityPage,
          taxonomy,
          [updatedItemName, itemName],
          deletedThroughUi,
        );
      }
    });

    test(`admin can distinguish used and unused entries on ${taxonomy.heading}`, async ({
      adminCommunityPage,
    }) => {
      // Load the taxonomy case with seeded used and unused entries.
      await navigateToPath(adminCommunityPage, taxonomy.path);

      // Verify used entries cannot be deleted while unused entries can.
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText(taxonomy.heading, { exact: true })).toBeVisible();
      await expect(getTaxonomyRow(dashboardContent, taxonomy, taxonomy.seededUsedName)).toBeVisible();
      await expect(getTaxonomyRow(dashboardContent, taxonomy, taxonomy.seededUnusedName)).toBeVisible();
      await expect(dashboardContent.getByRole("button", { name: taxonomy.addButton })).toBeEnabled();
      await expect(dashboardContent.locator(`#${taxonomy.usedDeleteId}`)).toBeDisabled();
      await expect(dashboardContent.locator(`#${taxonomy.unusedDeleteId}`)).toBeEnabled();
    });

    test(`viewer sees read-only controls on ${taxonomy.heading}`, async ({ communityViewerPage }) => {
      // Load the taxonomy case as a read-only viewer.
      await navigateToPath(communityViewerPage, taxonomy.path);

      // Verify all mutation controls are disabled for the viewer.
      const dashboardContent = communityViewerPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText(taxonomy.heading, { exact: true })).toBeVisible();
      await expect(getTaxonomyRow(dashboardContent, taxonomy, taxonomy.seededUnusedName)).toBeVisible();
      await expect(dashboardContent.getByRole("button", { name: taxonomy.addButton })).toBeDisabled();
      await expect(dashboardContent.locator(`#${taxonomy.unusedDeleteId}`)).toBeDisabled();
    });
  }
});

/** Removes created taxonomy entries through the UI and database. */
const cleanupTaxonomyEntry = async (page, taxonomy, names, deletedThroughUi) => {
  const uniqueNames = [...new Set(names)];

  if (!deletedThroughUi) {
    await cleanupTaxonomyEntryThroughUi(page, taxonomy, uniqueNames);
  }

  cleanupTaxonomyEntryInDatabase(taxonomy, uniqueNames);
};

/** Deletes named taxonomy rows from the configured database table. */
const cleanupTaxonomyEntryInDatabase = (taxonomy, names) => {
  const nameList = names.map(sqlString).join(", ");

  queryE2eDatabase(`delete from ${taxonomy.tableName} where name in (${nameList});`);
};

/** Deletes named taxonomy rows through the dashboard when they are visible. */
const cleanupTaxonomyEntryThroughUi = async (page, taxonomy, names) => {
  await navigateToPath(page, taxonomy.path);
  const dashboardContent = page.locator("#dashboard-content");

  for (const name of names) {
    const itemRow = getTaxonomyRow(dashboardContent, taxonomy, name);

    if ((await itemRow.count()) > 0) {
      await deleteTaxonomyRow(page, dashboardContent, taxonomy, name);
    }
  }
};

/** Deletes a visible taxonomy row and waits for the dashboard refresh. */
const deleteTaxonomyRow = async (page, dashboardContent, taxonomy, name) => {
  const itemRow = getTaxonomyRow(dashboardContent, taxonomy, name);

  await itemRow.getByRole("button", { name: `${taxonomy.deleteAriaPrefix}: ${name}` }).click();
  await expect(page.locator(".swal2-popup")).toContainText(taxonomy.deleteConfirmMessage);
  await waitForCommunityDashboardMutation(
    page,
    taxonomy.refreshPath,
    () => page.getByRole("button", { name: "Yes" }).click(),
    { method: "DELETE", urlIncludes: `${taxonomy.refreshPath}/` },
  );
};

/** Fills each taxonomy form field with the supplied name. */
const fillTaxonomyForm = async (page, taxonomy, name) => {
  for (const field of taxonomy.formFields) {
    const formField = page.locator(`[name="${field.name}"]`);

    await expect(formField).toBeVisible();
    await page.getByLabel(field.label).fill(name);
  }
};

/** Returns the taxonomy table row matching the supplied name. */
const getTaxonomyRow = (dashboardContent, taxonomy, name) => {
  return dashboardContent.locator(taxonomy.tableSelector).locator("tr", { hasText: name });
};

/** Escapes a value for a SQL string literal. */
const sqlString = (value) => `'${value.replaceAll("'", "''")}'`;
