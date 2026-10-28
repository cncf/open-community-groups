import { expect, test } from "../../../fixtures.js";
import { queryCount, queryE2eDatabaseRows, sqlString, sqlUuid, withRowRestore } from "../../../database.js";
import { cleanupTemporaryGroup } from "../../../data-graphs/groups.js";
import {
  TEST_COMMUNITY_IDS,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_CATEGORY_IDS,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
} from "../../../seed.js";
import {
  confirmAlert,
  expectPaginationNavigation,
  navigateToPath,
  selectGroupContext,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillGroupLocation,
  fillKeyValueInputs,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../../form-helpers.js";

// Seeded group row changed by the deactivate and reactivate and the logo fallback tests.
const BETA_GROUP_ROW = { key: { group_id: TEST_GROUP_IDS.community1.beta }, table: "group" };

test.describe("community dashboard groups view", () => {
  test("empty state guides the first community group", async ({ adminEmptyCommunityPage }) => {
    // Load groups for the dedicated community without group records.
    await navigateToPath(adminEmptyCommunityPage, "/dashboard/community?tab=groups");
    const dashboardContent = adminEmptyCommunityPage.locator("#dashboard-content");

    // Verify first-use guidance and the creation action remain available.
    await expect(dashboardContent).toContainText("It looks like you haven't created any groups yet.");
    await expect(dashboardContent.getByRole("button", { name: "Add Group" })).toBeVisible();
  });

  test("admin can move between community group result pages", async ({ adminCommunityPage }) => {
    // Paginate the seeded group rows with one result per page.
    await expectPaginationNavigation(
      adminCommunityPage,
      "/dashboard/community?tab=groups&limit=1&offset=0",
      "#dashboard-content tbody tr",
    );
  });

  test("admin can deactivate and reactivate a group from the list", async ({ adminCommunityPage }) => {
    // Restore the seeded group row even when the UI reactivation below fails.
    await withRowRestore(BETA_GROUP_ROW, async () => {
      // Load the groups list before changing seeded group status.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

      // Target the dashboard content after the HTMX tab loads.
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

      // Verify the seeded group starts active before changing status.
      let betaGroupRow = dashboardContent.locator("tr", {
        hasText: "Inactive Local Chapter",
      });
      await expect(betaGroupRow).toBeVisible();
      await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);

      // Define a helper for opening the seeded group actions menu.
      const openActionsMenu = async () => {
        await dashboardContent
          .locator(`.btn-group-actions[data-group-id="${TEST_GROUP_IDS.community1.beta}"]`)
          .click();
      };

      // Open the actions menu before deactivating the group.
      await openActionsMenu();

      // Deactivate the seeded group from the actions menu.
      const deactivateButton = dashboardContent.locator(
        `#deactivate-group-${TEST_GROUP_IDS.community1.beta}`,
      );
      await expect(deactivateButton).toBeVisible();
      await deactivateButton.click();

      // Confirm deactivation and wait for the server response.
      await waitForActionResponse(
        adminCommunityPage,
        () =>
          confirmAlert(adminCommunityPage, { message: "Are you sure you wish to deactivate this group?" }),
        {
          method: "PUT",
          urlIncludes: `/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/deactivate`,
        },
      );

      // Verify the row reflects the deactivated state.
      betaGroupRow = dashboardContent.locator("tr", {
        hasText: "Inactive Local Chapter",
      });
      await expect(betaGroupRow).toContainText("Inactive");
      await expect(
        betaGroupRow.getByRole("button", {
          name: "View group page: Inactive Local Chapter",
        }),
      ).toBeDisabled();

      // Reopen the actions menu before restoring the seeded group.
      await openActionsMenu();

      // Reactivate the seeded group from the actions menu.
      const activateButton = dashboardContent.locator(`#activate-group-${TEST_GROUP_IDS.community1.beta}`);
      await expect(activateButton).toBeVisible();
      await activateButton.click();

      // Confirm reactivation and wait for the server response.
      await waitForActionResponse(
        adminCommunityPage,
        () => confirmAlert(adminCommunityPage, { message: "Are you sure you wish to activate this group?" }),
        {
          method: "PUT",
          urlIncludes: `/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/activate`,
        },
      );

      // Verify the row returns to the original active state.
      betaGroupRow = dashboardContent.locator("tr", {
        hasText: "Inactive Local Chapter",
      });
      await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);
      await expect(
        betaGroupRow.getByRole("link", {
          name: "View group page: Inactive Local Chapter",
        }),
      ).toBeVisible();
    });
  });

  test("saving a group without its own logo keeps following the community logo", async ({
    adminCommunityPage,
  }) => {
    // Count the seeded group row while it has no logo of its own.
    const countBetaGroupWithoutOwnLogo = () =>
      queryCount(`
        select count(*)
        from "group"
        where group_id = ${sqlUuid(TEST_GROUP_IDS.community1.beta)}
        and logo_url is null
      `);
    expect(countBetaGroupWithoutOwnLogo()).toBe(1);

    // Restore the seeded group row the form save rewrites.
    await withRowRestore(BETA_GROUP_ROW, async () => {
      // Open the seeded group update form from the groups list.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      const betaGroupRow = dashboardContent.locator("tr", { hasText: TEST_GROUP_NAMES.beta });
      await waitForActionResponse(
        adminCommunityPage,
        () => betaGroupRow.locator('button[hx-get*="/update"]').click(),
        {
          method: "GET",
          pathname: `/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update`,
          status: 200,
        },
      );

      // Verify the community logo fallback is not prefilled as the group logo.
      const updateGroupButton = adminCommunityPage.getByRole("button", { name: "Update Group" });
      await expect(updateGroupButton).toBeVisible();
      await expect(
        adminCommunityPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
      ).toHaveValue("");

      // Fill the required description the seeded group lacks, save, and verify the group still
      // has no logo of its own.
      await fillMarkdownEditor(
        adminCommunityPage,
        "description",
        "A seeded group edited to verify the community logo fallback is not stored.",
      );
      await waitForActionResponse(adminCommunityPage, () => updateGroupButton.click(), {
        method: "PUT",
        pathname: `/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update`,
        status: 204,
      });
      expect(countBetaGroupWithoutOwnLogo()).toBe(1);
    });
  });

  test("admin can create and remove a subgroup relationship", async ({ adminCommunityPage }) => {
    // Create a unique group name for the temporary subgroup flow.
    const groupName = uniqueName("child community group");
    let groupWasCreated = false;

    // Define cleanup that deletes the temporary child group through the UI.
    const deleteTemporaryGroup = async () => {
      // Return to the groups list and target the temporary child group.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      const groupRow = dashboardContent.locator("tr", { hasText: groupName });

      // Skip UI cleanup when the temporary child group is already absent.
      if ((await groupRow.count()) === 0) {
        return;
      }

      // Open the child group actions menu.
      await groupRow
        .getByRole("button", {
          name: `Open actions menu for group ${groupName}`,
        })
        .click();

      // Open the delete confirmation for the child group.
      const deleteButton = groupRow.locator('button[id^="delete-group-"]');
      await expect(deleteButton).toBeVisible();
      await deleteButton.click();

      // Confirm deletion and wait for the server response.
      await waitForActionResponse(
        adminCommunityPage,
        () => confirmAlert(adminCommunityPage, { message: "Are you sure you wish to delete this group?" }),
        {
          method: "DELETE",
          urlEndsWith: "/delete",
          urlIncludes: "/dashboard/community/groups/",
        },
      );
    };

    try {
      // Load the groups list and verify the dashboard is ready.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

      // Open the group form for the temporary child group.
      await dashboardContent.getByRole("button", { name: "Add Group" }).click();
      await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();

      // Fill required child group details and select its parent.
      await adminCommunityPage.getByLabel("Name").fill(groupName);
      await adminCommunityPage.getByLabel("Category").selectOption(TEST_GROUP_CATEGORY_IDS.one);
      await adminCommunityPage.getByLabel("Region").selectOption("22222222-2222-2222-2222-222222222301");
      await adminCommunityPage.locator("#parent_group_id").selectOption(TEST_GROUP_IDS.community1.alpha);
      await adminCommunityPage
        .getByLabel("Short Description")
        .fill("A child group created by the e2e suite.");
      await fillMarkdownEditor(
        adminCommunityPage,
        "description",
        "A child group used to verify parent group relationships.",
      );

      // Create the child group and wait for the server response.
      await waitForActionResponse(
        adminCommunityPage,
        () => adminCommunityPage.getByRole("button", { name: "Create Group" }).click(),
        {
          method: "POST",
          status: 201,
          urlIncludes: "/dashboard/community/groups/add",
        },
      );
      groupWasCreated = true;

      // Verify the child group appears in the dashboard list.
      const groupRow = dashboardContent.locator("tr", { hasText: groupName });
      await expect(groupRow).toBeVisible();

      // Read the child group public path from its row link.
      const viewGroupLink = groupRow.getByRole("link", {
        name: `View group page: ${groupName}`,
      });
      await expect(viewGroupLink).toBeVisible();
      const viewGroupHref = await viewGroupLink.getAttribute("href");
      expect(viewGroupHref).toBeTruthy();
      const childGroupPath = new URL(viewGroupHref, "http://127.0.0.1").pathname;
      const childGroupSlug = childGroupPath.split("/").at(-1);

      // Open the parent public page and verify it lists the child group.
      await navigateToPath(
        adminCommunityPage,
        `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`,
      );
      await expect(adminCommunityPage.getByText("Subgroups", { exact: true })).toBeVisible();
      await expect(adminCommunityPage.getByRole("link", { name: groupName, exact: true })).toBeVisible();

      // Verify parent event links include both parent and child group filters.
      const seeAllEventsHrefs = await adminCommunityPage
        .getByRole("link", { name: "See all events" })
        .evaluateAll((links) => links.map((link) => decodeURIComponent(link.getAttribute("href") || "")));
      expect(
        seeAllEventsHrefs.some(
          (href) =>
            href.includes(`group[0]=${TEST_GROUP_SLUGS.community1.alpha}`) &&
            new RegExp(`group\\[\\d+\\]=${childGroupSlug}`).test(href),
        ),
      ).toBeTruthy();

      // Open the child public page and verify it links back to the parent group.
      await navigateToPath(adminCommunityPage, childGroupPath);
      await expect(adminCommunityPage.getByText("Parent group", { exact: true })).toBeVisible();
      await expect(
        adminCommunityPage.getByRole("link", {
          name: TEST_GROUP_NAMES.alpha,
          exact: true,
        }),
      ).toBeVisible();

      // Open parent group settings and verify parent selection is locked while subgroups exist.
      await selectGroupContext(
        adminCommunityPage,
        TEST_COMMUNITY_IDS.community1,
        TEST_GROUP_IDS.community1.alpha,
      );
      await navigateToPath(adminCommunityPage, "/dashboard/group?tab=settings");
      const parentGroupSelect = adminCommunityPage.locator("#parent_group_id");
      await expect(parentGroupSelect).toBeDisabled();
      await expect(parentGroupSelect).toContainText("Unavailable while this group has subgroups");
      await expect(parentGroupSelect).toHaveCSS("cursor", "not-allowed");
      await expect(parentGroupSelect).toHaveCSS("opacity", "1");
    } finally {
      // Delete the temporary child group, then remove its soft-deleted rows.
      if (groupWasCreated) {
        await deleteTemporaryGroup();
      }
      cleanupGroupByName(groupName);
    }
  });

  test("admin can create, update, and delete a community group with images and rich fields", async ({
    adminCommunityPage,
  }) => {
    const initialGroupName = uniqueName("rich community group");
    const updatedGroupName = uniqueName("rich community group updated");

    // Define rich group values for the create and update flow.
    const initialValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      blueskyUrl: "https://bsky.app/profile/e2e-community-group-initial",
      categoryId: TEST_GROUP_CATEGORY_IDS.one,
      city: "Barcelona",
      countryCode: "ES",
      countryName: "Spain",
      description: "Initial rich description for a temporary community-managed group.",
      descriptionShort: "Initial community-managed group for rich update coverage.",
      extraLinks: [
        { key: "Docs", value: "https://initial-group.example.com/docs" },
        { key: "Slides", value: "https://initial-group.example.com/slides" },
      ],
      facebookUrl: "https://facebook.com/e2e-community-group-initial",
      flickrUrl: "https://flickr.com/photos/e2e-community-group-initial",
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryOne, TEST_UPLOAD_ASSET_PATHS.galleryTwo],
      githubUrl: "https://github.com/open-community-groups/e2e-community-group-initial",
      instagramUrl: "https://instagram.com/e2e-community_group_initial",
      latitude: "41.3874",
      linkedinUrl: "https://linkedin.com/company/e2e-community-group-initial",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      longitude: "2.1686",
      name: initialGroupName,
      regionId: "22222222-2222-2222-2222-222222222301",
      slackUrl: "https://e2e-community-group-initial.slack.com",
      state: "Catalonia",
      tags: ["platform", "observability"],
      twitterUrl: "https://x.com/e2e_group_initial",
      wechatUrl: "https://wechat.com/e2e-community-group-initial",
      websiteUrl: "https://initial-group.example.com",
      youtubeUrl: "https://youtube.com/@e2e-community-group-initial",
    };
    const updatedValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      blueskyUrl: "https://bsky.app/profile/e2e-community-group-updated",
      categoryId: TEST_GROUP_CATEGORY_IDS.one,
      city: "Madrid",
      countryCode: "PT",
      countryName: "Portugal",
      description: "Updated rich description for a temporary community-managed group.",
      descriptionShort: "Updated community-managed group for rich update coverage.",
      extraLinks: [
        { key: "Agenda", value: "https://updated-group.example.com/agenda" },
        { key: "Videos", value: "https://updated-group.example.com/videos" },
      ],
      facebookUrl: "https://facebook.com/e2e-community-group-updated",
      flickrUrl: "https://flickr.com/photos/e2e-community-group-updated",
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryTwo, TEST_UPLOAD_ASSET_PATHS.galleryOne],
      githubUrl: "https://github.com/open-community-groups/e2e-community-group-updated",
      instagramUrl: "https://instagram.com/e2e.community.group.updated",
      latitude: "40.4168",
      linkedinUrl: "https://linkedin.com/company/e2e-community-group-updated",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      longitude: "-3.7038",
      name: updatedGroupName,
      regionId: "22222222-2222-2222-2222-222222222301",
      slackUrl: "https://e2e-community-group-updated.slack.com",
      slugPretty: updatedGroupName.toLowerCase().replace(/\s+/g, "-"),
      state: "Community of Madrid",
      tags: ["cloud", "devex"],
      twitterUrl: "https://x.com/e2e_group_updated",
      wechatUrl: "https://wechat.com/e2e-community-group-updated",
      websiteUrl: "https://updated-group.example.com",
      youtubeUrl: "https://youtube.com/@e2e-community-group-updated",
    };

    // Fill every rich field used by the create and update flows.
    const fillGroupForm = async (values) => {
      await adminCommunityPage.locator("#name").fill(values.name);
      if (values.slugPretty) {
        await adminCommunityPage.locator("#slug_pretty").fill(values.slugPretty);
      }
      await adminCommunityPage.locator("#category_id").selectOption(values.categoryId);
      await adminCommunityPage.locator("#region_id").selectOption(values.regionId);
      await adminCommunityPage.locator("#description_short").fill(values.descriptionShort);
      await fillMarkdownEditor(adminCommunityPage, "description", values.description);
      await uploadImageField(adminCommunityPage, "logo_url", values.logoPath);
      await uploadImageField(adminCommunityPage, "banner_url", values.bannerPath);
      await uploadImageField(adminCommunityPage, "banner_mobile_url", values.bannerMobilePath);
      await fillGroupLocation(adminCommunityPage, {
        city: values.city,
        countryCode: values.countryCode,
        countryName: values.countryName,
        latitude: values.latitude,
        longitude: values.longitude,
        state: values.state,
      });
      await adminCommunityPage.locator("#website_url").fill(values.websiteUrl);
      await adminCommunityPage.locator("#bluesky_url").fill(values.blueskyUrl);
      await adminCommunityPage.locator("#facebook_url").fill(values.facebookUrl);
      await adminCommunityPage.locator("#flickr_url").fill(values.flickrUrl);
      await adminCommunityPage.locator("#github_url").fill(values.githubUrl);
      await adminCommunityPage.locator("#instagram_url").fill(values.instagramUrl);
      await adminCommunityPage.locator("#linkedin_url").fill(values.linkedinUrl);
      await adminCommunityPage.locator("#slack_url").fill(values.slackUrl);
      await adminCommunityPage.locator("#twitter_url").fill(values.twitterUrl);
      await adminCommunityPage.locator("#wechat_url").fill(values.wechatUrl);
      await adminCommunityPage.locator("#youtube_url").fill(values.youtubeUrl);
      await fillMultipleInputs(adminCommunityPage.locator('multiple-inputs[field-name="tags"]'), values.tags);
      await uploadGalleryImages(adminCommunityPage, "photos_urls", values.galleryPaths);
      await fillKeyValueInputs(
        adminCommunityPage.locator('key-value-inputs[field-name="extra_links"]'),
        values.extraLinks,
      );
    };

    // Define a helper for opening the edit form from a group row.
    const openGroupUpdateForm = async (groupRow) => {
      const updateButton = groupRow.locator('button[hx-get*="/update"]');
      await expect(updateButton).toBeVisible();
      await expect(updateButton).toBeEnabled();
      await updateButton.click();
      await expect(adminCommunityPage.getByRole("button", { name: "Update Group" })).toBeVisible({
        timeout: 10000,
      });
      await expect(adminCommunityPage.locator("#name")).toBeVisible({
        timeout: 10000,
      });
    };

    try {
      // Load the groups list before opening the rich group form.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

      // Target the dashboard content after the HTMX tab loads.
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

      // Open the group form from the dashboard list.
      await dashboardContent.getByRole("button", { name: "Add Group" }).click();
      await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();

      // Fill the form with the initial rich values.
      await fillGroupForm(initialValues);

      // Submit the group and wait for the created response.
      await waitForActionResponse(
        adminCommunityPage,
        () => adminCommunityPage.getByRole("button", { name: "Create Group" }).click(),
        {
          method: "POST",
          status: 201,
          urlIncludes: "/dashboard/community/groups/add",
        },
      );

      // Verify the initial temporary group appears in the dashboard list.
      let groupRow = dashboardContent.locator("tr", {
        hasText: initialValues.name,
      });
      await expect(groupRow).toBeVisible();

      // Update the group with the second set of rich values.
      await openGroupUpdateForm(groupRow);
      await fillGroupForm(updatedValues);

      // Submit the update and wait for the server response.
      await waitForActionResponse(
        adminCommunityPage,
        () => adminCommunityPage.getByRole("button", { name: "Update Group" }).click(),
        { method: "PUT", pathname: /^\/dashboard\/community\/groups\/[^/]+\/update$/u, status: 204 },
      );

      // Verify the updated group name appears in the dashboard list.
      groupRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
      await expect(groupRow).toBeVisible();

      // Reopen the form and verify the rich values persisted.
      await openGroupUpdateForm(groupRow);
      await expect(adminCommunityPage.locator("#name")).toHaveValue(updatedValues.name);
      await expect(adminCommunityPage.locator("#slug_pretty")).toHaveValue(updatedValues.slugPretty);
      await expect(adminCommunityPage.locator("#category_id")).toHaveValue(updatedValues.categoryId);
      await expect(adminCommunityPage.locator("#region_id")).toHaveValue(updatedValues.regionId);
      await expect(adminCommunityPage.locator("#description_short")).toHaveValue(
        updatedValues.descriptionShort,
      );
      await expect(adminCommunityPage.locator("#group-location-search-city")).toHaveValue(updatedValues.city);
      await expect(adminCommunityPage.locator("#group-location-search-state")).toHaveValue(
        updatedValues.state,
      );
      await expect(adminCommunityPage.locator("#group-location-search-country_name")).toHaveValue(
        updatedValues.countryName,
      );
      await expect(adminCommunityPage.locator("#website_url")).toHaveValue(updatedValues.websiteUrl);
      await expect(adminCommunityPage.locator("#bluesky_url")).toHaveValue(updatedValues.blueskyUrl);
      await expect(adminCommunityPage.locator("#github_url")).toHaveValue(updatedValues.githubUrl);
      await expect(
        adminCommunityPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
      ).toHaveValue(/\/images\//);
      await expect(
        adminCommunityPage.locator('image-field[name="banner_url"] input[name="banner_url"]'),
      ).toHaveValue(/\/images\//);
      await expect(
        adminCommunityPage.locator('image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]'),
      ).toHaveValue(/\/images\//);
      await expect(
        adminCommunityPage.locator('multiple-inputs[field-name="tags"] input[name="tags[]"]'),
      ).toHaveCount(updatedValues.tags.length);
      await expect(
        adminCommunityPage.locator('gallery-field[field-name="photos_urls"] input[name="photos_urls[]"]'),
      ).toHaveCount(initialValues.galleryPaths.length + updatedValues.galleryPaths.length);
      await expect(
        adminCommunityPage.locator(
          `key-value-inputs[field-name="extra_links"] input[name="extra_links[${updatedValues.extraLinks[0].key}]"]`,
        ),
      ).toHaveValue(updatedValues.extraLinks[0].value);

      // Return to the groups list before deleting the temporary group.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");
      groupRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
      await expect(groupRow).toBeVisible();
      await expect(
        groupRow.getByRole("link", {
          name: `View group page: ${updatedValues.name}`,
        }),
      ).toHaveAttribute("href", new RegExp(`/group/${updatedValues.slugPretty}$`));

      // Open the actions menu for the updated temporary group.
      await groupRow
        .getByRole("button", {
          name: `Open actions menu for group ${updatedValues.name}`,
        })
        .click();

      // Open the delete confirmation for the temporary group.
      const deleteButton = groupRow.locator('button[id^="delete-group-"]');
      await expect(deleteButton).toBeVisible();
      await deleteButton.click();

      // Confirm deletion and wait for the server response.
      await waitForActionResponse(
        adminCommunityPage,
        () => confirmAlert(adminCommunityPage, { message: "Are you sure you wish to delete this group?" }),
        {
          method: "DELETE",
          urlEndsWith: "/delete",
          urlIncludes: "/dashboard/community/groups/",
        },
      );

      // Verify the deleted group is removed from the dashboard list.
      await expect(dashboardContent.locator("tr", { hasText: updatedValues.name })).toHaveCount(0);
    } finally {
      // Remove the soft-deleted rich group rows the UI deletion leaves behind.
      cleanupGroupByName(initialValues.name);
      cleanupGroupByName(updatedValues.name);
    }
  });

  test("admin can search community groups and clear the filter", async ({ adminCommunityPage }) => {
    // Load the groups list before applying search filters.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    // Target the dashboard content after the HTMX tab loads.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    // Target the search input used to submit dashboard filters.
    const searchInput = dashboardContent.getByRole("textbox", {
      name: "Search groups",
    });

    // Enter a query expected to match a seeded group.
    await searchInput.fill("Observability");

    // Submit the matching search and wait for filtered results.
    await waitForActionResponse(adminCommunityPage, () => searchInput.press("Enter"), {
      method: "GET",
      urlIncludes: "/dashboard/community/groups?ts_query=Observability",
    });

    // Verify the matching result and durable search URL.
    await expect(adminCommunityPage).toHaveURL(/tab=groups.*ts_query=Observability/);
    await expect(dashboardContent.locator("tr", { hasText: "Observability Guild" })).toBeVisible();
    await expect(dashboardContent.locator("tr", { hasText: "Platform Ops Meetup" })).toHaveCount(0);

    // Enter a query expected to return no groups.
    await searchInput.fill("");
    await searchInput.fill("zzzzzzzzzzzz");

    // Submit the empty-result search and wait for the response.
    await waitForActionResponse(adminCommunityPage, () => searchInput.press("Enter"), {
      method: "GET",
      urlIncludes: "/dashboard/community/groups?ts_query=zzzzzzzzzzzz",
    });

    // Verify the empty result message is shown.
    await expect(
      dashboardContent
        .locator("div.text-xl.lg\\:text-2xl.mb-4:visible")
        .filter({ hasText: "No groups found matching your search." })
        .first(),
    ).toBeVisible();
    await expect(dashboardContent).not.toHaveClass(/htmx-settling/);

    // Target the clear-filter control shown for empty results.
    const clearFilterButton = dashboardContent.getByRole("button", {
      name: "Clear group search",
    });
    await expect(clearFilterButton).toBeVisible();

    // Click the clear-filter control to reset the list.
    await waitForActionResponse(adminCommunityPage, () => clearFilterButton.click(), {
      method: "GET",
      params: { ts_query: null },
      pathname: "/dashboard/community/groups",
      status: 200,
    });

    // Verify clearing removes the empty state and restores seeded rows.
    await expect(adminCommunityPage).toHaveURL(/\/dashboard\/community\?tab=groups(?:&limit=50&offset=0)?$/);
    await expect(
      dashboardContent
        .locator("div.text-xl.lg\\:text-2xl.mb-4:visible")
        .filter({ hasText: "No groups found matching your search." }),
    ).toHaveCount(0);
    await expect(dashboardContent.locator("tr", { hasText: "Platform Ops Meetup" })).toBeVisible();
    await expect(dashboardContent.locator("tr", { hasText: "Observability Guild" })).toBeVisible();
    await expect(searchInput).toHaveValue("");
  });

  test("viewer sees read-only controls on community groups", async ({ communityViewerPage }) => {
    // Load the groups list as a read-only community viewer.
    await navigateToPath(communityViewerPage, "/dashboard/community?tab=groups");

    // Target the dashboard content after the HTMX tab loads.
    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    // Verify the list actions expose disabled read-only controls.
    await expect(dashboardContent.getByRole("button", { name: "Add Group" })).toBeDisabled();
    await expect(dashboardContent.getByRole("button", { name: "Add Group" })).toHaveAttribute(
      "title",
      "Your role cannot add groups.",
    );

    // Locate the seeded group row used for read-only action checks.
    const betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow).toBeVisible();

    // Verify row actions stay disabled for the viewer role.
    const actionsButton = betaGroupRow.getByRole("button", {
      name: "Open actions menu for group Inactive Local Chapter",
    });
    await expect(actionsButton).toBeDisabled();
    await expect(actionsButton).toHaveAttribute(
      "title",
      "Your role cannot activate, deactivate, or delete groups.",
    );

    // Open details and verify the form remains read-only.
    await waitForActionResponse(
      communityViewerPage,
      () =>
        betaGroupRow
          .locator(`button[hx-get="/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update"]`)
          .click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update`,
      },
    );

    // Verify the details form communicates the read-only state.
    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update groups.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(dashboardContent.getByRole("button", { name: "Update Group" })).toBeDisabled();
    await expect(dashboardContent.getByRole("button", { name: "Update Group" })).toHaveAttribute(
      "title",
      "Your role cannot update groups.",
    );
  });
});

/** Deletes every group of the seeded community with the given name, including soft-deleted ones. */
const cleanupGroupByName = (groupName) => {
  const groupRows = queryE2eDatabaseRows(`
    select group_id
    from "group"
    where community_id = ${sqlUuid(TEST_COMMUNITY_IDS.community1)}
    and name = ${sqlString(groupName)};
  `);

  for (const [groupId] of groupRows) {
    cleanupTemporaryGroup(groupId);
  }
};
