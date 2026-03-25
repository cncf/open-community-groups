import type { Locator } from "@playwright/test";

import { expect, test } from "../../fixtures";

import { TEST_GROUP_IDS, navigateToPath } from "../../utils";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillGroupLocation,
  fillKeyValueInputs,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../form-helpers";

test.describe("community dashboard groups view", () => {
  test("admin can deactivate and reactivate a group from the list", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    let betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow).toBeVisible();
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);

    const openActionsMenu = async () => {
      await dashboardContent
        .locator(`.btn-group-actions[data-group-id="${TEST_GROUP_IDS.community1.beta}"]`)
        .click();
    };

    await openActionsMenu();

    const deactivateButton = dashboardContent.locator(
      `#deactivate-group-${TEST_GROUP_IDS.community1.beta}`,
    );
    await expect(deactivateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(`/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/deactivate`) &&
          response.ok(),
      ),
      deactivateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow).toContainText("Inactive");
    await expect(
      betaGroupRow.getByRole("button", { name: "View group page: Inactive Local Chapter" }),
    ).toBeDisabled();

    await openActionsMenu();

    const activateButton = dashboardContent.locator(
      `#activate-group-${TEST_GROUP_IDS.community1.beta}`,
    );
    await expect(activateButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(`/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/activate`) &&
          response.ok(),
      ),
      activateButton.click(),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow.getByText("Inactive", { exact: true })).toHaveCount(0);
    await expect(
      betaGroupRow.getByRole("link", { name: "View group page: Inactive Local Chapter" }),
    ).toBeVisible();
  });

  test("admin can add and delete a community group", async ({ adminCommunityPage }) => {
    const groupName = `E2E Community Group ${Date.now()}`;

    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Group" }).click();
    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();

    await adminCommunityPage.getByLabel("Name").fill(groupName);
    await adminCommunityPage.getByLabel("Category").selectOption(
      "22222222-2222-2222-2222-222222222221",
    );
    await adminCommunityPage.getByLabel("Region").selectOption(
      "22222222-2222-2222-2222-222222222301",
    );
    await adminCommunityPage.getByLabel("Short Description").fill(
      "A short e2e-created community group.",
    );
    await adminCommunityPage
      .locator('markdown-editor#description .CodeMirror textarea')
      .fill("A community group created and removed by the e2e suite.");

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/groups/add") &&
          response.status() === 201,
      ),
      adminCommunityPage.getByRole("button", { name: "Create Group" }).click(),
    ]);

    const groupRow = dashboardContent.locator("tr", { hasText: groupName });
    await expect(groupRow).toBeVisible();

    await groupRow.getByRole("button", {
      name: `Open actions menu for group ${groupName}`,
    }).click();

    const deleteButton = groupRow.locator('button[id^="delete-group-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you wish to delete this group?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/groups/") &&
          response.url().endsWith("/delete") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: groupName })).toHaveCount(0);
  });

  test("admin can create, update, and delete a community group with images and rich fields", async ({
    adminCommunityPage,
  }) => {
    const initialValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      blueskyUrl: "https://bsky.app/profile/e2e-community-group-initial",
      categoryId: "22222222-2222-2222-2222-222222222221",
      city: "Barcelona",
      countryCode: "ES",
      countryName: "Spain",
      description:
        "Initial rich description for a temporary community-managed group.",
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
      name: `E2E Rich Community Group ${Date.now()}`,
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
      categoryId: "22222222-2222-2222-2222-222222222223",
      city: "Madrid",
      countryCode: "PT",
      countryName: "Portugal",
      description:
        "Updated rich description for a temporary community-managed group.",
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
      name: `E2E Rich Community Group Updated ${Date.now()}`,
      regionId: "22222222-2222-2222-2222-222222222302",
      slackUrl: "https://e2e-community-group-updated.slack.com",
      state: "Community of Madrid",
      tags: ["cloud", "devex"],
      twitterUrl: "https://x.com/e2e_group_updated",
      wechatUrl: "https://wechat.com/e2e-community-group-updated",
      websiteUrl: "https://updated-group.example.com",
      youtubeUrl: "https://youtube.com/@e2e-community-group-updated",
    };

    const fillGroupForm = async (values: typeof initialValues) => {
      await adminCommunityPage.locator("#name").fill(values.name);
      await adminCommunityPage.locator("#category_id").selectOption(values.categoryId);
      await adminCommunityPage.locator("#region_id").selectOption(values.regionId);
      await adminCommunityPage.locator("#description_short").fill(values.descriptionShort);
      await fillMarkdownEditor(adminCommunityPage, "description", values.description);
      await uploadImageField(adminCommunityPage, "logo_url", values.logoPath);
      await uploadImageField(adminCommunityPage, "banner_url", values.bannerPath);
      await uploadImageField(
        adminCommunityPage,
        "banner_mobile_url",
        values.bannerMobilePath,
      );
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
      await fillMultipleInputs(
        adminCommunityPage.locator('multiple-inputs[field-name="tags"]'),
        values.tags,
      );
      await uploadGalleryImages(adminCommunityPage, "photos_urls", values.galleryPaths);
      await fillKeyValueInputs(
        adminCommunityPage.locator('key-value-inputs[field-name="extra_links"]'),
        values.extraLinks,
      );
    };

    const openGroupUpdateForm = async (groupRow: Locator) => {
      await Promise.all([
        adminCommunityPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes("/dashboard/community/groups/") &&
            response.url().includes("/update") &&
            response.ok(),
        ),
        groupRow.locator('button[hx-get*="/update"]').click(),
      ]);
    };

    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Group" }).click();
    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();

    await fillGroupForm(initialValues);

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/community/groups/add") &&
          response.status() === 201,
      ),
      adminCommunityPage.getByRole("button", { name: "Create Group" }).click(),
    ]);

    let groupRow = dashboardContent.locator("tr", { hasText: initialValues.name });
    await expect(groupRow).toBeVisible();

    await openGroupUpdateForm(groupRow);
    await fillGroupForm(updatedValues);

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/community/groups/") &&
          response.url().includes("/update") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Update Group" }).click(),
    ]);

    groupRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(groupRow).toBeVisible();

    await openGroupUpdateForm(groupRow);
    await expect(adminCommunityPage.locator("#name")).toHaveValue(updatedValues.name);
    await expect(adminCommunityPage.locator("#category_id")).toHaveValue(updatedValues.categoryId);
    await expect(adminCommunityPage.locator("#region_id")).toHaveValue(updatedValues.regionId);
    await expect(adminCommunityPage.locator("#group-location-search-city")).toHaveValue(
      updatedValues.city,
    );
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
      adminCommunityPage.locator(
        'image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]',
      ),
    ).toHaveValue(/\/images\//);
    await expect(
      adminCommunityPage.locator('multiple-inputs[field-name="tags"] input[name="tags[]"]'),
    ).toHaveCount(updatedValues.tags.length);
    await expect(
      adminCommunityPage.locator('gallery-field[field-name="photos_urls"] input[name="photos_urls[]"]'),
    ).toHaveCount(
      initialValues.galleryPaths.length + updatedValues.galleryPaths.length,
    );
    await expect(
      adminCommunityPage.locator(
        `key-value-inputs[field-name="extra_links"] input[name="extra_links[${updatedValues.extraLinks[0].key}]"]`,
      ),
    ).toHaveValue(updatedValues.extraLinks[0].value);

    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");
    groupRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(groupRow).toBeVisible();

    await groupRow.getByRole("button", {
      name: `Open actions menu for group ${updatedValues.name}`,
    }).click();

    const deleteButton = groupRow.locator('button[id^="delete-group-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(adminCommunityPage.locator(".swal2-popup")).toContainText(
      "Are you sure you wish to delete this group?",
    );

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/community/groups/") &&
          response.url().endsWith("/delete") &&
          response.ok(),
      ),
      adminCommunityPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: updatedValues.name })).toHaveCount(0);
  });

  test("admin can search community groups and clear the filter", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();

    const searchInput = dashboardContent.getByPlaceholder("Search groups");
    await searchInput.fill("Observability");

    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/community/groups?ts_query=Observability") &&
          response.ok(),
      ),
      searchInput.press("Enter"),
    ]);

    await expect(adminCommunityPage).toHaveURL(/tab=groups.*ts_query=Observability/);
    await expect(
      dashboardContent.locator("tr", { hasText: "Observability Guild" }),
    ).toBeVisible();
    await expect(
      dashboardContent.locator("tr", { hasText: "Platform Ops Meetup" }),
    ).toHaveCount(0);

    await searchInput.fill("");
    await searchInput.fill("No matching group");
    await searchInput.press("Enter");

    await expect(
      dashboardContent
        .locator('div.text-xl.lg\\:text-2xl.mb-4:visible')
        .filter({ hasText: "No groups found matching your search." }),
    ).toBeVisible();

    const clearFilterButton = dashboardContent.locator(
      'button[hx-get="/dashboard/community/groups"]',
    );
    await expect(clearFilterButton).toBeVisible();
    await Promise.all([
      adminCommunityPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().endsWith("/dashboard/community/groups") &&
          response.ok(),
      ),
      clearFilterButton.click(),
    ]);

    await expect(searchInput).toHaveValue("");
    await expect(
      dashboardContent.locator("tr", { hasText: "Platform Ops Meetup" }),
    ).toBeVisible();
    await expect(
      dashboardContent.locator("tr", { hasText: "Observability Guild" }),
    ).toBeVisible();
  });

  test("viewer sees read-only controls on community groups", async ({
    communityViewerPage,
  }) => {
    await navigateToPath(communityViewerPage, "/dashboard/community?tab=groups");

    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Groups", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Group" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Group" }),
    ).toHaveAttribute("title", "Your role cannot add groups.");

    const betaGroupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(betaGroupRow).toBeVisible();

    const actionsButton = betaGroupRow.getByRole("button", {
      name: "Open actions menu for group Inactive Local Chapter",
    });
    await expect(actionsButton).toBeDisabled();
    await expect(actionsButton).toHaveAttribute(
      "title",
      "Your role cannot activate, deactivate, or delete groups.",
    );

    await Promise.all([
      communityViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update`) &&
          response.ok(),
      ),
      betaGroupRow
        .locator(
          `button[hx-get="/dashboard/community/groups/${TEST_GROUP_IDS.community1.beta}/update"]`,
        )
        .click(),
    ]);

    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update groups.", { exact: true }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(dashboardContent.getByRole("button", { name: "Update Group" })).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Update Group" }),
    ).toHaveAttribute("title", "Your role cannot update groups.");
  });
});
