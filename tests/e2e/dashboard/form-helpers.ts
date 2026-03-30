import * as path from "node:path";

import { expect } from "@playwright/test";
import type { Locator, Page } from "@playwright/test";

export const TEST_UPLOAD_ASSET_PATHS = {
  alternateBanner: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/community-secondary-banner.svg",
  ),
  alternateBannerMobile: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/community-secondary-banner-mobile.svg",
  ),
  alternateLogo: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/community-secondary-logo.svg",
  ),
  banner: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/community-primary-banner.svg",
  ),
  bannerMobile: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/community-primary-banner-mobile.svg",
  ),
  galleryOne: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/event-photo-1.svg",
  ),
  galleryTwo: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/event-photo-2.svg",
  ),
  logo: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/community-primary-logo.svg",
  ),
  sponsorLogo: path.resolve(
    __dirname,
    "../../../ocg-server/static/images/e2e/sponsor-logo.svg",
  ),
} as const;

export const fillMarkdownEditor = async (
  page: Page,
  editorId: string,
  value: string,
) => {
  await page.locator(`markdown-editor#${editorId} .CodeMirror`).evaluate((element, nextValue) => {
    const codeMirror = (element as HTMLElement & {
      CodeMirror?: {
        focus: () => void;
        save: () => void;
        setValue: (value: string) => void;
      };
    }).CodeMirror;

    codeMirror?.focus();
    codeMirror?.setValue(nextValue);
    codeMirror?.save();
  }, value);
};

export const uploadImageField = async (
  page: Page,
  fieldName: string,
  filePath: string,
) => {
  const imageField = page.locator(`image-field[name="${fieldName}"]`);

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes("/images") &&
        response.status() === 201,
    ),
    imageField.locator('input[type="file"]').setInputFiles(filePath),
  ]);

  await expect(imageField.locator(`input[name="${fieldName}"]`)).toHaveValue(/\/images\//);
};

export const setImageFieldValue = async (
  page: Page,
  fieldName: string,
  value: string,
) => {
  const imageField = page.locator(`image-field[name="${fieldName}"]`);

  await imageField.evaluate((element, nextValue) => {
    const field = element as HTMLElement & { value?: string };
    const name = field.getAttribute("name");

    field.setAttribute("value", nextValue);
    field.value = nextValue;

    if (name) {
      const input = field.querySelector(`input[name="${name}"]`) as HTMLInputElement | null;

      if (input) {
        input.value = nextValue;
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
      }
    }

    field.dispatchEvent(
      new CustomEvent("image-change", {
        detail: { value: nextValue },
        bubbles: true,
        composed: true,
      }),
    );
  }, value);

  await expect(imageField.locator(`input[name="${fieldName}"]`)).toHaveValue(value);
};

export const uploadGalleryImages = async (
  page: Page,
  fieldName: string,
  filePaths: string[],
) => {
  const galleryField = page.locator(`gallery-field[field-name="${fieldName}"]`);
  const fileInput = galleryField.locator('input[type="file"]');
  const initialImageCount = await galleryField.locator(`input[name="${fieldName}[]"]`).count();

  for (const filePath of filePaths) {
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/images") &&
          response.status() === 201,
      ),
      fileInput.setInputFiles(filePath),
    ]);
  }

  await expect(galleryField.locator(`input[name="${fieldName}[]"]`)).toHaveCount(
    initialImageCount + filePaths.length,
  );
};

export const fillMultipleInputs = async (
  component: Locator,
  values: string[],
  label = "Tag",
) => {
  const addButton = component.getByRole("button", { name: `Add ${label}` });

  for (let index = 1; index < values.length; index += 1) {
    await addButton.click();
  }

  const inputs = component.locator("input.input-primary");
  for (const [index, value] of values.entries()) {
    await inputs.nth(index).fill(value);
  }
};

export const fillKeyValueInputs = async (
  component: Locator,
  items: Array<{ key: string; value: string }>,
) => {
  const addButton = component.getByRole("button", { name: "Add Link" });

  for (let index = 1; index < items.length; index += 1) {
    await addButton.click();
  }

  const inputs = component.locator("input.input-primary");
  for (const [index, item] of items.entries()) {
    await inputs.nth(index * 2).fill(item.key);
    await inputs.nth(index * 2 + 1).fill(item.value);
  }
};

export const fillGroupLocation = async (
  page: Page,
  values: {
    city: string;
    countryCode: string;
    countryName: string;
    latitude: string;
    longitude: string;
    state: string;
  },
) => {
  await page.locator("#group-location-search-city").fill(values.city);
  await page.locator("#group-location-search-state").fill(values.state);
  await page.locator("#group-location-search-country_name").fill(values.countryName);
  await page.locator("#group-location-search-latitude").fill(values.latitude);
  await page.locator("#group-location-search-longitude").fill(values.longitude);
  await page.locator("#group-location-search-country_code").evaluate((element, value) => {
    const input = element as HTMLInputElement;
    input.value = value;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }, values.countryCode);
};

export const fillEventVenue = async (
  page: Page,
  values: {
    address: string;
    city: string;
    latitude: string;
    longitude: string;
    name: string;
    zipCode: string;
  },
) => {
  await page.locator("#location-search-venue_name").fill(values.name);
  await page.locator("#location-search-venue_address").fill(values.address);
  await page.locator("#location-search-venue_city").fill(values.city);
  await page.locator("#location-search-venue_zip_code").fill(values.zipCode);
  await page.locator("#location-search-latitude").fill(values.latitude);
  await page.locator("#location-search-longitude").fill(values.longitude);
};
