import { existsSync, readFileSync } from "node:fs";
import { expect } from "@playwright/test";

/** Waits for the page to finish the visual work needed before snapshotting. */
const waitForVisualReady = async (page) => {
  await page.waitForLoadState("networkidle");
  await page.evaluate(async () => {
    await document.fonts.ready;
    await new Promise((resolve) => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => resolve());
      });
    });
  });
};

/** Waits for image elements inside the snapshot target to settle. */
const waitForVisualImages = async (region) => {
  await region.locator("img").evaluateAll(async (elements) => {
    await Promise.all(
      elements.map(async (element) => {
        const imageElement = element;
        const settlePromise =
          typeof imageElement.decode === "function"
            ? imageElement.decode().catch(() => undefined)
            : imageElement.complete
              ? Promise.resolve()
              : new Promise((resolve) => {
                  imageElement.addEventListener("load", () => resolve(), {
                    once: true,
                  });
                  imageElement.addEventListener("error", () => resolve(), {
                    once: true,
                  });
                });

        await Promise.race([
          settlePromise,
          new Promise((resolve) => {
            window.setTimeout(resolve, 1500);
          }),
        ]);
      }),
    );
  });
};

/** Reads the dimensions from a PNG snapshot header. */
const getPngDimensions = (filePath) => {
  if (!existsSync(filePath)) {
    return null;
  }

  const imageBuffer = readFileSync(filePath);

  if (imageBuffer.length < 24 || imageBuffer.toString("ascii", 1, 4) !== "PNG") {
    return null;
  }

  return {
    width: imageBuffer.readUInt32BE(16),
    height: imageBuffer.readUInt32BE(20),
  };
};

/** Checks whether a region is close enough to a snapshot for clipped capture. */
const hasTinySnapshotDimensionDrift = (regionBox, snapshotDimensions) =>
  Math.abs(snapshotDimensions.width - Math.round(regionBox.width)) <= 2 &&
  Math.abs(snapshotDimensions.height - Math.round(regionBox.height)) <= 2;

/** Returns a screenshot clip box constrained to the viewport and document. */
const getClippedScreenshotBox = async (page, regionBox, snapshotDimensions) => {
  const viewportSize = page.viewportSize();
  const documentSize = await page.evaluate(() => ({
    height: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
    width: Math.max(document.body.scrollWidth, document.documentElement.scrollWidth),
  }));
  const maxX = Math.max(
    0,
    Math.min(viewportSize?.width ?? documentSize.width, documentSize.width) - snapshotDimensions.width,
  );
  const maxY = Math.max(
    0,
    Math.min(viewportSize?.height ?? documentSize.height, documentSize.height) - snapshotDimensions.height,
  );

  return {
    x: Math.min(Math.max(0, regionBox.x), maxX),
    y: Math.min(Math.max(0, regionBox.y), maxY),
    width: snapshotDimensions.width,
    height: snapshotDimensions.height,
  };
};

/** Selects the community about block without including the following sections. */
export const getCommunityAboutSection = (page) => page.locator(".community-description").locator("..");

/** Selects the stable home jumbotron content without outer container padding. */
export const getHomeJumbotronContent = (page) =>
  page.getByRole("heading", { level: 1 }).locator("xpath=ancestor::div[contains(@class,'text-center')][1]");

/** Selects the explore search row above the results list. */
export const getExploreSearchRow = (page, searchPlaceholder) =>
  page.getByPlaceholder(searchPlaceholder).locator("xpath=ancestor::div[contains(@class,'items-center')][1]");

/** Selects the explore controls row above the results list. */
export const getExploreControlsRow = (page) =>
  page.locator("#results").locator("xpath=ancestor::div[contains(@class,'justify-between')][1]");

/** Waits for a page to settle before taking a visual snapshot. */
export const expectPageScreenshot = async (page, screenshotName, screenshotOptions = {}) => {
  await waitForVisualReady(page);
  await waitForVisualImages(page.locator("body"));

  await expect(page).toHaveScreenshot(screenshotName, {
    animations: "disabled",
    caret: "hide",
    fullPage: true,
    ...screenshotOptions,
  });
};

/** Waits for a stable region and snapshots only that locator. */
export const expectRegionScreenshot = async (page, region, screenshotName, screenshotOptions = {}) => {
  const {
    mask,
    maxDiffPixels,
    maxDiffPixelRatio,
    testInfo,
    useClippedPageScreenshot = false,
  } = screenshotOptions;
  const clippedPageScreenshotDiffRatio = useClippedPageScreenshot ? 0.08 : undefined;
  const snapshotDiffOptions = {
    ...(maxDiffPixels === undefined ? {} : { maxDiffPixels }),
    ...((maxDiffPixelRatio ?? clippedPageScreenshotDiffRatio) === undefined
      ? {}
      : {
          maxDiffPixelRatio: maxDiffPixelRatio ?? clippedPageScreenshotDiffRatio,
        }),
  };

  await waitForVisualReady(page);
  await expect(region).toBeVisible();
  await region.scrollIntoViewIfNeeded();
  await waitForVisualImages(region);

  if (testInfo) {
    const snapshotDimensions = getPngDimensions(testInfo.snapshotPath(screenshotName));
    const regionBox = await region.boundingBox();
    const shouldUseClippedPageScreenshot =
      useClippedPageScreenshot ||
      (snapshotDimensions && regionBox && hasTinySnapshotDimensionDrift(regionBox, snapshotDimensions));

    if (shouldUseClippedPageScreenshot && snapshotDimensions && regionBox) {
      const clip = await getClippedScreenshotBox(page, regionBox, snapshotDimensions);

      await expect(page).toHaveScreenshot(screenshotName, {
        animations: "disabled",
        caret: "hide",
        mask,
        clip,
        scale: "css",
        ...snapshotDiffOptions,
      });

      return;
    }
  }

  await expect(region).toHaveScreenshot(screenshotName, {
    animations: "disabled",
    caret: "hide",
    mask,
    ...snapshotDiffOptions,
  });
};
