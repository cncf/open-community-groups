import { expect, test } from "../../../fixtures.js";

import { fillMarkdownEditor, fillMultipleInputs } from "../../form-helpers.js";
import { TEST_PAYMENT_GROUP_RECIPIENT } from "../../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../../utils.js";

// Group settings page used by the UTM scenarios.
const SETTINGS_PATH = "/dashboard/group?tab=settings";

// UTM lists rendered in the group settings form.
const UTM_FIELDS = [
  { fieldName: "utm_sources", label: "Source" },
  { fieldName: "utm_campaigns", label: "Campaign" },
  { fieldName: "utm_mediums", label: "Medium" },
];

test.describe("group dashboard settings view", () => {
  test("settings form exposes every group configuration area", async ({ organizerGroupPage }) => {
    // Load group settings before checking the complete form contract.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=settings");

    // Find the dashboard and verify every settings section is present.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    for (const sectionName of [
      "Group Details",
      "Location",
      "Social links",
      "Additional Content",
      "Parent group",
      "UTM tracking",
    ]) {
      // Some section titles are repeated by field labels, so target the first.
      await expect(dashboardContent.getByText(sectionName, { exact: true }).first()).toBeVisible();
    }

    // Verify required controls, slug rules, and location fields.
    await expect(organizerGroupPage.locator("#name")).toHaveAttribute("required", "");
    await expect(organizerGroupPage.getByLabel("Pretty URL slug")).toHaveAttribute(
      "pattern",
      "(?!.*--)[a-z0-9](?:[a-z0-9-]{0,48}[a-z0-9])?",
    );
    await expect(organizerGroupPage.getByLabel("Category")).toHaveAttribute("required", "");
    await expect(organizerGroupPage.getByLabel("Region")).toBeVisible();
    await expect(organizerGroupPage.getByLabel("Short Description")).toBeVisible();
    await expect(organizerGroupPage.locator("markdown-editor#description")).toHaveAttribute("required", "");

    // Verify every group image field is available with its required size guidance.
    for (const { helpText, name } of [
      { helpText: "Images must be 360 x 360 px (square).", name: "logo_url" },
      { helpText: "Size required 2428 x 192 px.", name: "banner_url" },
      { helpText: "Size required 1220 x 192 px.", name: "banner_mobile_url" },
      { helpText: "Size required 1200 x 630 px. Format must be PNG, JPEG, or WebP.", name: "og_image_url" },
    ]) {
      const imageField = organizerGroupPage.locator(`image-field[name="${name}"]`);
      await expect(imageField).toBeVisible();
      await expect(imageField).toContainText(helpText);
    }
    await expect(organizerGroupPage.locator('image-field[name="logo_url"]')).not.toContainText(
      "Size required",
    );

    // Verify the group location controls are available.
    await expect(organizerGroupPage.locator("location-search-field#group-location-search")).toBeVisible();
    await expect(
      organizerGroupPage.getByRole("button", {
        name: "Clear location details",
      }),
    ).toBeVisible();

    // Verify every social destination uses a URL input.
    for (const socialLabel of [
      "Website",
      "Bluesky",
      "Facebook",
      "Flickr",
      "GitHub",
      "Instagram",
      "LinkedIn",
      "Slack",
      "X (formerly Twitter)",
      "WeChat",
      "YouTube",
    ]) {
      await expect(organizerGroupPage.getByLabel(socialLabel)).toHaveAttribute("type", "url");
    }

    // Verify the remaining repeatable fields and parent-group restriction.
    await expect(organizerGroupPage.locator('multiple-inputs[field-name="tags"]')).toBeVisible();
    await expect(organizerGroupPage.locator('gallery-field[field-name="photos_urls"]')).toBeVisible();
    await expect(organizerGroupPage.locator('key-value-inputs[field-name="extra_links"]')).toBeVisible();
    await expect(organizerGroupPage.getByLabel("Parent group")).toBeDisabled();

    // Verify every UTM list is named and described by its rules.
    for (const { fieldName, label } of UTM_FIELDS) {
      const utmInput = getUtmInputs(organizerGroupPage, fieldName).getByRole("textbox", {
        name: `${label} 1`,
      });
      await expect(utmInput).toBeVisible();
      await expect(utmInput).toHaveAccessibleDescription(/Up to 20 values of up to 50 lowercase letters/);
    }
    await expect(organizerGroupPage.locator('input[type="hidden"][name="utm_present"]')).toHaveValue("true");
  });

  test("invalid UTM values are blocked before the group settings request", async ({ organizerGroupPage }) => {
    // Track update requests so browser validation can be distinguished from API errors.
    let updateRequests = 0;
    const countUpdateRequests = (request) => {
      if (request.method() === "PUT" && request.url().includes("/dashboard/group/settings/update")) {
        updateRequests += 1;
      }
    };
    organizerGroupPage.on("request", countUpdateRequests);

    for (const { fieldName, label, message, values } of [
      {
        fieldName: "utm_sources",
        label: "Source",
        message: "Use only lowercase letters, numbers, dots, hyphens, and underscores.",
        values: ["Mastodon"],
      },
      {
        fieldName: "utm_campaigns",
        label: "Campaign",
        message: "This value is already in the list.",
        values: ["spring-launch", "spring-launch"],
      },
      {
        fieldName: "utm_mediums",
        label: "Medium",
        message: "This medium is already accepted by default.",
        values: ["email"],
      },
    ]) {
      // Load group settings and enter the invalid UTM values.
      await navigateToPath(organizerGroupPage, SETTINGS_PATH);
      const utmInputs = getUtmInputs(organizerGroupPage, fieldName);
      await fillMultipleInputs(utmInputs, values, label);

      // Submit the form with the invalid value as the last list item.
      const invalidInput = utmInputs.getByRole("textbox", { name: `${label} ${values.length}` });
      await organizerGroupPage.getByRole("button", { name: "Update Group" }).click();

      // Verify the browser blocks the request and reports the invalid value.
      await expect(invalidInput).toBeFocused();
      expect(await invalidInput.evaluate((input) => input.validationMessage)).toBe(message);
      expect(updateRequests).toBe(0);
    }

    // Remove the request listener after the invalid-submit checks.
    organizerGroupPage.off("request", countUpdateRequests);
  });

  test("organizer can save and clear UTM tracking values", async ({ organizerGroupPage }) => {
    // Load group settings and verify the seeded group has no UTM values.
    await navigateToPath(organizerGroupPage, SETTINGS_PATH);
    for (const { fieldName } of UTM_FIELDS) {
      await expect(getSubmittedUtmInputs(organizerGroupPage, fieldName)).toHaveCount(0);
    }

    // Enter UTM values.
    const utmValues = {
      utm_campaigns: ["spring-launch"],
      utm_mediums: ["podcast"],
      utm_sources: ["newsletter", "mastodon"],
    };
    for (const { fieldName, label } of UTM_FIELDS) {
      await fillMultipleInputs(getUtmInputs(organizerGroupPage, fieldName), utmValues[fieldName], label);
    }

    // Save the UTM values and verify the submitted form contract.
    const saveResponse = await saveGroupSettings(organizerGroupPage);
    const savedForm = new URLSearchParams(saveResponse.request().postData() ?? "");
    expect(savedForm.get("utm_present")).toBe("true");
    expect(savedForm.getAll("utm_sources[]")).toEqual(["newsletter", "mastodon"]);
    expect(savedForm.getAll("utm_campaigns[]")).toEqual(["spring-launch"]);
    expect(savedForm.getAll("utm_mediums[]")).toEqual(["podcast"]);

    // Reload group settings and verify the values persisted.
    await navigateToPath(organizerGroupPage, SETTINGS_PATH);
    const sourceInputs = getUtmInputs(organizerGroupPage, "utm_sources");
    await expect(sourceInputs.getByRole("textbox", { name: "Source 1" })).toHaveValue("newsletter");
    await expect(sourceInputs.getByRole("textbox", { name: "Source 2" })).toHaveValue("mastodon");
    await expect(getSubmittedUtmInputs(organizerGroupPage, "utm_campaigns")).toHaveValue("spring-launch");
    await expect(getSubmittedUtmInputs(organizerGroupPage, "utm_mediums")).toHaveValue("podcast");

    // Clear every UTM value to restore the seeded settings.
    for (const { fieldName } of UTM_FIELDS) {
      const valueInputs = getUtmInputs(organizerGroupPage, fieldName).locator("input[data-item-input]");
      for (let index = 0; index < (await valueInputs.count()); index += 1) {
        await valueInputs.nth(index).fill("");
      }
    }
    const clearResponse = await saveGroupSettings(organizerGroupPage);
    const clearedForm = new URLSearchParams(clearResponse.request().postData() ?? "");
    expect(clearedForm.get("utm_present")).toBe("true");
    expect(clearedForm.has("utm_sources[]")).toBe(false);

    // Reload group settings and verify the UTM values were cleared.
    await navigateToPath(organizerGroupPage, SETTINGS_PATH);
    for (const { fieldName } of UTM_FIELDS) {
      await expect(getSubmittedUtmInputs(organizerGroupPage, fieldName)).toHaveCount(0);
    }
  });

  test("invalid pretty slugs are blocked before the group settings request", async ({
    organizerGroupPage,
  }) => {
    // Load group settings before submitting an invalid slug.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=settings");

    // Track update requests so browser validation can be distinguished from API errors.
    const prettySlugInput = organizerGroupPage.getByLabel("Pretty URL slug");
    let updateRequests = 0;
    const countUpdateRequests = (request) => {
      if (request.method() === "PUT" && request.url().includes("/dashboard/group/settings/update")) {
        updateRequests += 1;
      }
    };
    organizerGroupPage.on("request", countUpdateRequests);

    // Submit a slug that violates the field pattern.
    await prettySlugInput.fill("Invalid Group Slug");
    await organizerGroupPage.getByRole("button", { name: "Update Group" }).click();

    // Verify the browser blocks the request and focuses the invalid field.
    await expect(prettySlugInput).toBeFocused();
    expect(await prettySlugInput.evaluate((input) => input.validationMessage)).not.toBe("");
    expect(updateRequests).toBe(0);

    // Remove the request listener after the invalid-submit check.
    organizerGroupPage.off("request", countUpdateRequests);
  });

  test("organizer can update and restore group settings", async ({ organizerGroupPage }) => {
    // Define the settings URL used by the read and submit helpers.
    const settingsPath = "/dashboard/group?tab=settings";

    // Read current group settings values before updating them.
    const readSettingsFormValues = async () => {
      await navigateToPath(organizerGroupPage, settingsPath);

      // Find the settings form.
      const settingsForm = organizerGroupPage.locator("#groups-form");
      await expect(settingsForm).toBeVisible();

      // Find the description editor.
      const descriptionEditor = organizerGroupPage.locator("markdown-editor#description");
      const description =
        (await descriptionEditor.getAttribute("content")) ??
        (await descriptionEditor.locator('textarea[name="description"]').first().inputValue());
      const regionId = await organizerGroupPage.locator("#region_id").inputValue();

      // Return the values used by the caller.
      return {
        categoryId: await organizerGroupPage.locator("#category_id").inputValue(),
        description,
        descriptionShort: await organizerGroupPage.locator("#description_short").inputValue(),
        name: await organizerGroupPage.locator("#name").inputValue(),
        regionId,
        websiteUrl: await organizerGroupPage.locator("#website_url").inputValue(),
      };
    };

    // Submit group settings values and wait for persistence.
    const submitSettings = async ({
      categoryId,
      description,
      descriptionShort,
      name,
      regionId,
      websiteUrl,
    }) => {
      await navigateToPath(organizerGroupPage, settingsPath);
      await organizerGroupPage.locator("#category_id").selectOption(categoryId);
      await organizerGroupPage.locator("#region_id").selectOption(regionId);
      await organizerGroupPage.locator("#name").fill(name);
      await fillMarkdownEditor(organizerGroupPage, "description", description);
      await organizerGroupPage.locator("#description_short").fill(descriptionShort);
      await organizerGroupPage.locator("#website_url").fill(websiteUrl);

      // Click Update Group.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Update Group" }).click(),
        {
          method: "PUT",
          urlIncludes: "/dashboard/group/settings/update",
        },
      );
    };

    // Set up original form values.
    const originalFormValues = await readSettingsFormValues();
    const updatedValues = {
      ...originalFormValues,
      categoryId: originalFormValues.categoryId,
      description: "Updated primary meetup details for group settings coverage.",
      descriptionShort: "Updated short summary for group settings coverage.",
      name: `${originalFormValues.name} Updated`,
      regionId: originalFormValues.regionId,
    };

    // Save the updated settings.
    await submitSettings(updatedValues);

    // Assert the field value was updated.
    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(updatedValues.categoryId);
    await expect(organizerGroupPage.locator("#region_id")).toHaveValue(updatedValues.regionId);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
    await expect(organizerGroupPage.locator("markdown-editor#description")).toHaveAttribute(
      "content",
      updatedValues.description,
    );
    await expect(organizerGroupPage.locator("#website_url")).toHaveValue(updatedValues.websiteUrl);

    // Reload the settings form and verify the short description persisted.
    expect((await readSettingsFormValues()).descriptionShort).toBe(updatedValues.descriptionShort);

    // Restore the original settings.
    await submitSettings(originalFormValues);

    // Assert the field value was updated.
    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(originalFormValues.categoryId);
    await expect(organizerGroupPage.locator("#region_id")).toHaveValue(originalFormValues.regionId);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(originalFormValues.name);
    await expect(organizerGroupPage.locator("markdown-editor#description")).toHaveAttribute(
      "content",
      originalFormValues.description,
    );
    await expect(organizerGroupPage.locator("#website_url")).toHaveValue(originalFormValues.websiteUrl);

    // Reload the settings form and verify the original short description was restored.
    expect((await readSettingsFormValues()).descriptionShort).toBe(originalFormValues.descriptionShort);
  });

  test("viewer sees read-only controls on group settings", async ({ groupViewerPage }) => {
    // Load the group settings tab as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=settings");

    // Find the dashboard content.
    const dashboardContent = groupViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only controls on group settings.
    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update group settings.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    const updateGroupButton = dashboardContent.getByRole("button", {
      name: "Update Group",
    });

    // Dismiss pending group-setting changes when the button is present.
    if ((await updateGroupButton.count()) > 0) {
      await expect(updateGroupButton).toBeDisabled();
      await expect(updateGroupButton).toHaveAttribute("title", "Your role cannot update group settings.");
    }

    // Find the fiscal sponsor inputs.
    const sellerDisplayNameInput = dashboardContent.locator("#payment_recipient_seller_display_name");
    const paymentRecipientInput = dashboardContent.locator("#payment_recipient_recipient_id");

    // Verify the complete fiscal sponsor configuration when payments are enabled.
    if ((await paymentRecipientInput.count()) > 0) {
      await expect(sellerDisplayNameInput).toHaveValue("E2E Alpha Fiscal Sponsor");
      await expect(paymentRecipientInput).toHaveValue(TEST_PAYMENT_GROUP_RECIPIENT);
      return;
    }

    // Assert how many matching elements are shown.
    await expect(paymentRecipientInput).toHaveCount(0);
  });

  test("validates fiscal sponsor field pairs without contacting the provider", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Define the settings URL and fiscal sponsor fields used by the scenario.
    const settingsPath = "/dashboard/group?tab=settings";
    const sellerDisplayNameInput = organizerGroupWithoutPaymentsPage.locator(
      "#payment_recipient_seller_display_name",
    );
    const paymentRecipientInput = organizerGroupWithoutPaymentsPage.locator(
      "#payment_recipient_recipient_id",
    );
    const updatedSellerDisplayName = "E2E Delta Fiscal Sponsor";
    const updatedRecipient = "acct_e2e_delta";

    // Open the settings page for a group without a fiscal sponsor.
    await navigateToPath(organizerGroupWithoutPaymentsPage, settingsPath);
    await expect(paymentRecipientInput).toHaveCount(1);
    await expect(
      organizerGroupWithoutPaymentsPage.getByText("Fiscal Sponsor", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(sellerDisplayNameInput).toHaveValue("");
    await expect(paymentRecipientInput).toHaveValue("");
    const updateGroupButton = organizerGroupWithoutPaymentsPage.getByRole("button", { name: "Update Group" });
    const settingsUpdateRequests = [];
    const collectSettingsUpdateRequest = (request) => {
      if (request.method() === "PUT" && request.url().includes("/dashboard/group/settings/update")) {
        settingsUpdateRequests.push(request);
      }
    };
    organizerGroupWithoutPaymentsPage.on("request", collectSettingsUpdateRequest);

    // Reject a legal seller name without its paired provider account.
    await sellerDisplayNameInput.fill(updatedSellerDisplayName);
    await expect(sellerDisplayNameInput).toHaveAttribute("required", "");
    await expect(paymentRecipientInput).toHaveAttribute("required", "");
    await expect
      .poll(() => paymentRecipientInput.evaluate((input) => input.validity.valueMissing))
      .toBe(true);
    await updateGroupButton.click();
    expect(settingsUpdateRequests).toHaveLength(0);

    // Reject a provider account without its paired legal seller name.
    await navigateToPath(organizerGroupWithoutPaymentsPage, settingsPath);
    await paymentRecipientInput.fill(updatedRecipient);
    await expect(sellerDisplayNameInput).toHaveAttribute("required", "");
    await expect(paymentRecipientInput).toHaveAttribute("required", "");
    await expect
      .poll(() => sellerDisplayNameInput.evaluate((input) => input.validity.valueMissing))
      .toBe(true);
    await updateGroupButton.click();
    expect(settingsUpdateRequests).toHaveLength(0);
    organizerGroupWithoutPaymentsPage.off("request", collectSettingsUpdateRequest);

    // Accept an empty pair without invoking provider readiness.
    await navigateToPath(organizerGroupWithoutPaymentsPage, settingsPath);
    await waitForActionResponse(organizerGroupWithoutPaymentsPage, () => updateGroupButton.click(), {
      method: "PUT",
      urlIncludes: "/dashboard/group/settings/update",
    });
    await expect(sellerDisplayNameInput).toHaveValue("");
    await expect(paymentRecipientInput).toHaveValue("");

    // Accept an unchanged complete pair without invoking provider readiness.
    await navigateToPath(organizerGroupPage, settingsPath);
    const configuredSellerDisplayNameInput = organizerGroupPage.locator(
      "#payment_recipient_seller_display_name",
    );
    const configuredRecipientInput = organizerGroupPage.locator("#payment_recipient_recipient_id");
    await expect(configuredSellerDisplayNameInput).toHaveValue("E2E Alpha Fiscal Sponsor");
    await expect(configuredRecipientInput).toHaveValue(TEST_PAYMENT_GROUP_RECIPIENT);
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Update Group" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/settings/update",
      },
    );
    await expect(configuredSellerDisplayNameInput).toHaveValue("E2E Alpha Fiscal Sponsor");
    await expect(configuredRecipientInput).toHaveValue(TEST_PAYMENT_GROUP_RECIPIENT);
  });
});

/**
 * Finds the hidden inputs submitted for a UTM list.
 * @param {import("@playwright/test").Page} page - Group settings page.
 * @param {string} fieldName - UTM list field name.
 * @returns {import("@playwright/test").Locator} Submitted UTM value inputs.
 */
const getSubmittedUtmInputs = (page, fieldName) =>
  getUtmInputs(page, fieldName).locator(`input[type="hidden"][name="${fieldName}[]"]`);

/**
 * Finds the repeated input component of a UTM list.
 * @param {import("@playwright/test").Page} page - Group settings page.
 * @param {string} fieldName - UTM list field name.
 * @returns {import("@playwright/test").Locator} UTM list component.
 */
const getUtmInputs = (page, fieldName) => page.locator(`multiple-inputs[field-name="${fieldName}"]`);

/**
 * Submits the group settings form and waits for a successful update.
 * @param {import("@playwright/test").Page} page - Group settings page.
 * @returns {Promise<import("@playwright/test").Response>} Settings update response.
 */
const saveGroupSettings = (page) =>
  waitForActionResponse(page, () => page.getByRole("button", { name: "Update Group" }).click(), {
    method: "PUT",
    urlIncludes: "/dashboard/group/settings/update",
  });
