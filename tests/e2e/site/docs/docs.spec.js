import { expect, test } from "../../fixtures.js";

import { enableDesktopVersion } from "../../snapshots.js";
import { navigateToPath, waitForHtmxSettle } from "../../utils.js";

// Docsify's anchor scroll takes 500ms, and no event marks its end.
const ANCHOR_SCROLL_END_MS = 700;
// Header 64, strip 44 and a gap of 8 (`static/js/site/docs/interactions.js`).
const PHONE_ANCHOR_OFFSET_PX = 116;

test.describe("site docs page", () => {
  test("loads the docs shell and documentation navigation", async ({ page }) => {
    // Load the docs page before checking the embedded docs shell.
    await navigateToPath(page, "/docs");

    // Find the docs root.
    const docsRoot = page.locator(".ocg-docs-root");

    // Verify loads the docs shell and documentation navigation.
    await expect(docsRoot).toHaveAttribute("data-ocg-docs", "/static/docs/index.html#/");
    await expect(docsRoot).toBeVisible();

    // Assert the expected content is visible.
    await expect(page.locator(".ocg-docs-root .sidebar-nav")).toBeVisible({
      timeout: 15000,
    });
    await expect(page.locator(".ocg-docs-root .content")).toBeVisible({
      timeout: 15000,
    });
  });

  test("sidebar navigation updates content, title, hash, and browser history", async ({ page }) => {
    // Load documentation before following a sidebar destination.
    await navigateToPath(page, "/docs");

    // Find the Quickstart link and verify its hash destination.
    const docsRoot = page.locator(".ocg-docs-root");
    const quickstartLink = docsRoot
      .locator(".sidebar-nav")
      .getByRole("link", { name: "Quickstart", exact: true })
      .first();
    await expect(quickstartLink).toHaveAttribute("href", "#/getting-started/quickstart");
    await quickstartLink.click();

    // Verify navigation updates the URL, title, and rendered document.
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
    await expect(page).toHaveTitle("Quickstart");
    await expect(docsRoot.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible();

    // Return through browser history and verify the overview is restored.
    await page.goBack();
    await expect(page).toHaveURL(/\/docs#\/$/);
    await expect(page).toHaveTitle("Overview");
  });

  test("deep links open the requested document on initial load", async ({ page }) => {
    // Load documentation directly through a non-root hash destination.
    await navigateToPath(page, "/docs#/getting-started/quickstart");

    // Verify the requested document renders without extra navigation.
    const docsRoot = page.locator(".ocg-docs-root");
    await expect(page).toHaveTitle("Quickstart");
    await expect(docsRoot.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });

    // Verify the sidebar highlights the deep-linked destination.
    const quickstartItem = docsRoot
      .locator(".sidebar-nav li.active")
      .getByRole("link", { name: "Quickstart", exact: true });
    await expect(quickstartItem).toBeVisible();
  });

  test("tables on a later page stay enhanced after the user menu lands late", async ({ page }) => {
    // Hold the user menu until Docsify has replaced the app node.
    const releaseUserMenu = await holdUserMenu(page);
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });

    // Land the user menu, whose swap must leave the mount alone.
    const userMenuResponse = page.waitForResponse("**/section/user-menu");
    releaseUserMenu();
    await userMenuResponse;
    await waitForHtmxSettle(page);

    // Verify the mount still enhances the tables of the next page.
    await page
      .locator(".ocg-docs-root .sidebar-nav")
      .getByRole("link", { name: "Overview", exact: true })
      .click();
    await expect(page).toHaveURL(/\/docs#\/$/);
    await expect(page.locator(".markdown-section table.ocg-mobile-card-table").first()).toBeVisible();
  });

  test("the docs still navigate after Back from a boosted page", async ({ page }) => {
    // Leave the docs through a boosted link, so Back restores an HTMX snapshot.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });
    await waitForHtmxSettle(page);
    await page
      .getByRole("navigation", { name: "Main navigation" })
      .getByRole("link", { name: "Explore" })
      .click();
    await expect(page).toHaveURL(/\/explore/);

    // Wait for the reload that replaces the snapshot's dead markup.
    const reloaded = page.waitForEvent("load");
    await page.goBack();
    await reloaded;
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);

    // Verify the sidebar renders the next page.
    await page
      .locator(".ocg-docs-root .sidebar-nav")
      .getByRole("link", { name: "Badges", exact: true })
      .click();
    await expect(page).toHaveURL(/\/docs#\/guides\/badges$/);
    await expect(page.getByRole("heading", { name: "Badges Guide", level: 1 })).toBeVisible();
  });

  test("the docs render after Back on an HTMX cache miss", async ({ page }) => {
    // Leave the docs, then empty the cache, as ten later pages would evict their entry.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });
    await leaveThroughBoostedLink(page);
    await page.evaluate(() => window.sessionStorage.removeItem("htmx-history-cache"));

    // Wait for the reload that replaces the server's markup, which Docsify would never fill.
    const reloaded = page.waitForEvent("load");
    await page.goBack();
    await reloaded;
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
    await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });

    // Verify the sidebar renders the next page.
    await sidebarGuideLink(page, "badges").click();
    await expect(page.getByRole("heading", { name: "Badges Guide", level: 1 })).toBeVisible();
  });

  test("Back from a boosted page returns to the reader's place", async ({ page }) => {
    // Read part of a guide, then leave through a boosted link.
    await openGroupDashboardGuide(page);
    await scrollPageTo(page, 1500);
    await leaveThroughBoostedLink(page);

    // Verify Back lands where the reader was.
    await goBackWithReload(page);
    await expect(page).toHaveURL(/\/docs#\/guides\/group-dashboard$/);
    await expectPageScroll(page, 1500);
  });

  test("Back onto a saved docs entry returns to the reader's place", async ({ page }) => {
    // Give the guide's entry HTMX state, so Back onto it restores and reloads.
    await openGroupDashboardGuide(page);
    await leaveThroughBoostedLink(page);
    await goBackWithReload(page);

    // Read part of the guide, then move to another page and scroll that one too.
    await expect(page.getByRole("heading", { name: "Group Dashboard Guide", level: 1 })).toBeVisible({
      timeout: 15000,
    });
    await scrollPageTo(page, 1200);
    await sidebarGuideLink(page, "badges").click();
    await expect(page.getByRole("heading", { name: "Badges Guide", level: 1 })).toBeVisible();
    await scrollPageTo(page, 300);

    // Verify the guide gets its own place back, not the page just left.
    await goBackWithReload(page);
    await expect(page).toHaveURL(/\/docs#\/guides\/group-dashboard$/);
    await expectPageScroll(page, 1200);
  });

  test("a fresh visit to a page left further down starts at the top", async ({ page }) => {
    // Leave a position behind.
    await openGroupDashboardGuide(page);
    await scrollPageTo(page, 1500);
    await leaveThroughBoostedLink(page);

    // Verify a new visit to the same URL ignores it.
    await openGroupDashboardGuide(page);
    await expectPageScroll(page, 0);
  });

  test("a deep link keeps its anchor and Back keeps the reader's place over it", async ({ page }) => {
    // Load a section directly and verify Docsify scrolls to it.
    await navigateToPath(page, "/docs#/guides/group-dashboard?id=utm-tracking");
    const section = page.locator("#utm-tracking");
    await expect(section).toBeVisible({ timeout: 15000 });
    await page.waitForTimeout(ANCHOR_SCROLL_END_MS);
    expect(await page.evaluate(() => window.scrollY)).toBeGreaterThan(1000);

    // Scroll away from the section, then leave and come Back.
    await scrollPageTo(page, 700);
    await leaveThroughBoostedLink(page);
    await goBackWithReload(page);
    await expect(section).toBeVisible({ timeout: 15000 });
    await expectPageScroll(page, 700);

    // Verify the position outlasts the anchor scroll Docsify starts on load.
    await page.waitForTimeout(ANCHOR_SCROLL_END_MS);
    await expectPageScroll(page, 700);
  });

  test("the toggle keeps Docsify's name at 375px with a fine pointer", async ({ page }) => {
    // Load the docs below the phone width on a device the phone query leaves out.
    await page.setViewportSize({ height: 667, width: 375 });
    await navigateToPath(page, "/docs");
    const toggle = page.locator(".ocg-docs-root").getByRole("button", { name: "Menu" });
    await expect(toggle).toBeVisible({ timeout: 15000 });

    // Verify the phone state stays off the toggle and the page, open or closed.
    await expect(toggle).not.toHaveAttribute("aria-expanded");
    await toggle.click();
    await expect(page.locator("body")).toHaveClass(/\bclose\b/);
    await expect(toggle).not.toHaveAttribute("aria-expanded");
    await expect(page.locator(".ocg-docs-root .content")).not.toHaveAttribute("inert");
  });

  test("documentation remains navigable on mobile @mobile", async ({ page }) => {
    // Load documentation using the mobile project viewport.
    await navigateToPath(page, "/docs");

    // Verify the mobile menu and overview content remain available.
    const docsRoot = page.locator(".ocg-docs-root");
    const contentsButton = docsRoot.getByRole("button", { name: "Contents" });
    const overviewHeading = docsRoot.getByRole("heading", {
      name: "Open Community Groups Documentation",
      level: 1,
    });
    await expect(contentsButton).toBeVisible();
    await expect(overviewHeading).toBeVisible({ timeout: 15000 });

    // Open the sidebar and verify mirrored shell state and destinations.
    await contentsButton.click();
    await expect(page.locator("body")).toHaveClass(/\bclose\b/);
    await expect(docsRoot).toHaveClass(/\bclose\b/);
    const troubleshootingLink = docsRoot.getByRole("link", { name: "Troubleshooting", exact: true }).first();
    await expect(troubleshootingLink).toBeVisible();
    await expect(troubleshootingLink).toHaveAttribute("href", "#/support/troubleshooting");

    // Dismiss the sidebar through the strip, the root's only part left above the sheet.
    await docsRoot.locator("[data-docs-strip]").click({ position: { x: 16, y: 22 } });
    await expect(page.locator("body")).not.toHaveClass(/\bclose\b/);
    await expect(docsRoot).not.toHaveClass(/\bclose\b/);

    // Reopen the sidebar and navigate to a documentation page.
    await contentsButton.click();
    const quickstartLink = docsRoot
      .locator(".sidebar-nav")
      .getByRole("link", { name: "Quickstart", exact: true })
      .first();
    await quickstartLink.click();

    // Verify mobile navigation updates the route and rendered document.
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
    await expect(page).toHaveTitle("Quickstart");
    await expect(docsRoot.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible();
  });

  test("a page reached with the sheet closed keeps its title @mobile", async ({ page }) => {
    // Load a guide directly, so Docsify renders behind the hidden sheet.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });
    await expect(page).toHaveTitle("Quickstart");

    // Verify a section deep link takes its page's title and the overview its own.
    await page.goto("about:blank");
    await navigateToPath(page, "/docs#/guides/public-site?id=join-groups");
    await expect(page.getByRole("heading", { name: "Join Groups", level: 2 })).toBeVisible({
      timeout: 15000,
    });
    await expect(page).toHaveTitle("Public Site");
    await page.goto("about:blank");
    await navigateToPath(page, "/docs");
    await expect(page).toHaveTitle("Overview");
  });

  test("Contents stays usable when the user menu lands late @mobile", async ({ page }) => {
    // Hold the user menu, whose swap must leave the mount alone.
    const releaseUserMenu = await holdUserMenu(page);

    // Open a guide, the only kind of page with sub-rows, and then its Contents.
    await navigateToPath(page, "/docs#/guides/public-site");
    const { contentsButton, sheet } = await openContents(page);

    // Verify the sheet rises from the bottom edge and stops under the strip.
    const viewport = page.viewportSize();
    const sheetBox = await sheet.boundingBox();
    const stripBox = await page.locator("[data-docs-strip]").boundingBox();
    expect(sheetBox.x).toBe(0);
    expect(sheetBox.width).toBe(viewport.width);
    expect(sheetBox.y + sheetBox.height).toBeCloseTo(viewport.height, 0);
    expect(sheetBox.y).toBeGreaterThanOrEqual(stripBox.y + stripBox.height - 1);

    // Verify the toggle stays on the strip, above the sheet.
    const toggleBox = await contentsButton.boundingBox();
    expect(toggleBox.height).toBe(44);
    expect(toggleBox.y).toBeLessThan(sheetBox.y);
    expect(toggleBox.x + toggleBox.width).toBeCloseTo(viewport.width, 0);

    // Verify sub-rows sit past their parent and reach 44px.
    const parentRow = sheet.getByRole("link", { name: "Public Site", exact: true });
    const subRow = sheet.getByRole("link", { name: "Join Groups", exact: true });
    await expect(subRow).toBeVisible();
    const [parentPadding, subPadding] = await Promise.all(
      [parentRow, subRow].map((row) =>
        row.evaluate((link) => parseFloat(getComputedStyle(link).paddingLeft)),
      ),
    );
    expect(subPadding).toBeGreaterThan(parentPadding);
    expect((await subRow.boundingBox()).height).toBeGreaterThanOrEqual(44);

    // Land the user menu with the sheet still open.
    const userMenuResponse = page.waitForResponse("**/section/user-menu");
    releaseUserMenu();
    await userMenuResponse;
    await waitForHtmxSettle(page);
    await expect(page.locator("body")).toHaveClass(/\bclose\b/);

    // Verify the toggle closes the sheet and a close request still works afterwards.
    await contentsButton.click();
    await expect(sheet).toBeHidden();
    await contentsButton.click();
    await expect(sheet).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();

    // Verify the tables of a page reached after the swap still stack.
    await contentsButton.click();
    await sheet.getByRole("link", { name: "Overview", exact: true }).click();
    await expect(page).toHaveURL(/\/docs#\/$/);
    await expect(page.locator(".markdown-section table.ocg-mobile-card-table").first()).toBeVisible();
  });

  test("a close request closes Contents and leaves the page and history alone @mobile", async ({ page }) => {
    // Open Contents on a guide.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    const { contentsButton, sheet } = await openContents(page);
    const historyLength = await page.evaluate(() => window.history.length);

    // Verify a tap on a section label leaves the sheet open.
    await sheet.getByText("Getting Started", { exact: true }).click();
    await expect(sheet).toBeVisible();

    // Verify Escape, which drives CloseWatcher in Chromium, closes the sheet in place.
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
    expect(await page.evaluate(() => window.history.length)).toBe(historyLength);

    // Verify focus returns to the toggle and the page scrolls again.
    await expect(contentsButton).toBeFocused();
    await expect(page.locator("html")).not.toHaveCSS("overflow-y", "hidden");
  });

  test("Escape closes Contents where CloseWatcher is missing @mobile", async ({ page }) => {
    // Take the API away, so only the key handler can close the sheet.
    await page.addInitScript(() => {
      delete window.CloseWatcher;
    });

    // Open Contents on a guide.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    const { contentsButton, sheet } = await openContents(page);

    // Verify the key closes the sheet and focus returns to the toggle.
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();
    await expect(contentsButton).toBeFocused();
  });

  test("Back behind Contents closes it where CloseWatcher is missing @mobile", async ({ page }) => {
    // Take the API away, so Back goes to the page behind the sheet.
    await page.addInitScript(() => {
      delete window.CloseWatcher;
    });

    // Reach a second guide, so Back has a Docs page to go to, and open Contents over it.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    const first = await openContents(page);
    await first.sheet.getByRole("link", { name: "Badges", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Badges Guide", level: 1 })).toBeVisible();
    const { contentsButton, sheet } = await openContents(page);

    // Verify the page changes and the sheet leaves with its state.
    await page.goBack();
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
    await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible();
    await expect(sheet).toBeHidden();
    await expect(contentsButton).toHaveAttribute("aria-expanded", "false");
    await expect(page.locator(".ocg-docs-root .content")).not.toHaveAttribute("inert", "");
  });

  test("Contents exposes its state and shuts off the page behind it @mobile", async ({ page }) => {
    // Load a guide with the sheet closed.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    const docsRoot = page.locator(".ocg-docs-root");
    const content = docsRoot.locator(".content");
    await expect(docsRoot.getByRole("button", { name: "Contents" })).toHaveAttribute(
      "aria-expanded",
      "false",
      { timeout: 15000 },
    );
    await expect(content).not.toHaveAttribute("inert");

    // Verify an open sheet reports its state and leaves the page out of reach.
    const { contentsButton, sheet } = await openContents(page);
    await expect(contentsButton).toHaveAttribute("aria-expanded", "true");
    await expect(content).toHaveAttribute("inert", "");

    // Verify a tap outside the sheet undoes both and returns focus to the toggle.
    await docsRoot.locator("[data-docs-strip]").click({ position: { x: 16, y: 22 } });
    await expect(sheet).toBeHidden();
    await expect(contentsButton).toHaveAttribute("aria-expanded", "false");
    await expect(content).not.toHaveAttribute("inert");
    await expect(contentsButton).toBeFocused();
  });

  test("the toggle follows the phone query @mobile", async ({ page }) => {
    // Load a guide in portrait with Contents open.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    const { contentsButton } = await openContents(page);
    const content = page.locator(".ocg-docs-root .content");

    // Verify a rotation out of the phone query takes the phone state off the toggle and the page.
    await page.setViewportSize({ height: 390, width: 844 });
    const landscapeToggle = page.locator(".ocg-docs-root").getByRole("button", { name: "Menu" });
    await expect(landscapeToggle).toBeVisible();
    await expect(landscapeToggle).not.toHaveAttribute("aria-expanded");
    await expect(content).not.toHaveAttribute("inert");

    // Verify rotating back adopts the sheet, still open.
    await page.setViewportSize({ height: 844, width: 390 });
    await expect(contentsButton).toHaveAttribute("aria-expanded", "true");
    await expect(content).toHaveAttribute("inert", "");
  });

  test("Back returns to the previous guide after a Contents link @mobile", async ({ page }) => {
    // Move between two guides through Contents.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    const { sheet } = await openContents(page);
    await sheet.getByRole("link", { name: "Badges", exact: true }).click();
    await expect(page).toHaveURL(/\/docs#\/guides\/badges$/);
    await expect(sheet).toBeHidden();

    // Verify Back returns to the previous guide.
    await page.goBack();
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);
  });

  test("Contents still works after Back from a boosted page @mobile", async ({ page }) => {
    // Leave the docs through a boosted link, so Back restores an HTMX snapshot.
    await navigateToPath(page, "/docs#/getting-started/quickstart");
    await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
      timeout: 15000,
    });
    await page.locator('#user-dropdown-button[data-logged-in="false"]').click();
    await page.locator("#user-dropdown").getByRole("menuitem", { name: "Explore" }).click();
    await expect(page).toHaveURL(/\/explore/);

    // Wait for the reload that replaces the snapshot's dead toggle.
    const reloaded = page.waitForEvent("load");
    await page.goBack();
    await reloaded;
    await expect(page).toHaveURL(/\/docs#\/getting-started\/quickstart$/);

    // Verify the sheet opens and navigates.
    const { sheet } = await openContents(page);
    await sheet.getByRole("link", { name: "Badges", exact: true }).click();
    await expect(page).toHaveURL(/\/docs#\/guides\/badges$/);
  });

  for (const { name, heldUserMenu } of [
    { heldUserMenu: true, name: "the user menu swap" },
    { heldUserMenu: false, name: "the first pageshow" },
  ]) {
    test(`a page loaded in landscape gets the phone shell after ${name} @mobile`, async ({ page }) => {
      // Hold the user menu until Docsify has replaced the app node.
      const releaseUserMenu = heldUserMenu ? await holdUserMenu(page) : () => {};

      // Load a guide above the phone query.
      await page.setViewportSize({ height: 390, width: 844 });
      await navigateToPath(page, "/docs#/getting-started/quickstart");
      await expect(page.getByRole("heading", { name: "Quickstart", level: 1 })).toBeVisible({
        timeout: 15000,
      });
      const userMenuResponse = heldUserMenu ? page.waitForResponse("**/section/user-menu") : null;
      releaseUserMenu();
      await userMenuResponse;
      await waitForHtmxSettle(page);

      // Mark the document, so the rotation below can show it needed no reload.
      await page.evaluate(() => {
        window.docsLoadedInLandscape = true;
      });

      // Rotate and wait for the offset, which only the surviving mount can write.
      await page.setViewportSize({ height: 844, width: 390 });
      await page.waitForFunction((offset) => window.$docsify?.topMargin === offset, PHONE_ANCHOR_OFFSET_PX);
      expect(await page.evaluate(() => window.docsLoadedInLandscape)).toBe(true);

      // Verify a close request closes Contents.
      const { contentsButton, sheet } = await openContents(page);
      await page.keyboard.press("Escape");
      await expect(sheet).toBeHidden();

      // Verify a link closes it too, and the page it reaches keeps its title and stacked tables.
      await contentsButton.click();
      await sheet.getByRole("link", { name: "Overview", exact: true }).click();
      await expect(sheet).toBeHidden();
      await expect(page).toHaveURL(/\/docs#\/$/);
      await expect(page).toHaveTitle("Overview");
      await expect(page.locator(".markdown-section table.ocg-mobile-card-table").first()).toBeVisible();
    });
  }

  test("anchors land below the strip @mobile", async ({ page }) => {
    // Follow a sub-row on a guide once its screenshots stop moving the page.
    await navigateToPath(page, "/docs#/guides/public-site");
    const { sheet } = await openContents(page);
    await page.waitForFunction(() => [...document.images].every((image) => image.complete));
    await sheet.getByRole("link", { name: "Join Groups", exact: true }).click();

    // Verify the heading lands at the offset, clear of the pinned strip.
    const heading = page.getByRole("heading", { name: "Join Groups", level: 2 });
    const strip = page.locator("[data-docs-strip]");
    await expect(page).toHaveURL(/id=join-groups$/);
    await expect.poll(async () => Math.round((await heading.boundingBox()).y)).toBe(PHONE_ANCHOR_OFFSET_PX);
    const stripBox = await strip.boundingBox();
    expect((await heading.boundingBox()).y).toBeGreaterThanOrEqual(stripBox.y + stripBox.height);

    // Verify a deep link clears it too; images loading later may push the heading further down.
    await page.goto("about:blank");
    await navigateToPath(page, "/docs#/guides/public-site?id=join-groups");
    await expect(heading).toBeVisible({ timeout: 15000 });
    await expect
      .poll(async () => (await heading.boundingBox()).y)
      .toBeGreaterThanOrEqual(stripBox.y + stripBox.height);
  });

  test("the strip title and Contents stay level while the strip is pinned @mobile", async ({ page }) => {
    // Pin the strip by reading down a guide.
    await navigateToPath(page, "/docs#/guides/public-site");
    const toggle = page.locator(".ocg-docs-root").getByRole("button", { name: "Contents" });
    await expect(toggle).toBeVisible();
    await page.evaluate(() => window.scrollTo({ behavior: "instant", top: 600 }));

    // Verify the title and the fixed toggle share a centre line.
    const title = page.locator("[data-docs-strip] .section-strip-title");
    const [titleBox, toggleBox] = await Promise.all([title.boundingBox(), toggle.boundingBox()]);
    expect(titleBox.y + titleBox.height / 2).toBe(toggleBox.y + toggleBox.height / 2);
  });

  test("Contents opens on the current page on a short screen @mobile", async ({ page }) => {
    // Open a page low in the list on a screen too short to show it.
    await page.setViewportSize({ height: 568, width: 320 });
    await navigateToPath(page, "/docs#/support/troubleshooting");
    const { sheet } = await openContents(page);

    // Verify the current row is on screen without scrolling the sheet by hand.
    await expect(sheet.getByRole("link", { name: "Troubleshooting", exact: true })).toBeInViewport();
  });

  test("tables stack full bleed at 320px @mobile", async ({ page }) => {
    // Load the overview, which carries a table, at the narrowest phone.
    await page.setViewportSize({ width: 320, height: 568 });
    await navigateToPath(page, "/docs");
    const table = page.locator(".markdown-section table.ocg-mobile-card-table").first();
    await expect(table).toBeVisible({ timeout: 15000 });

    // Verify the table reaches both edges and the page does not scroll sideways.
    const box = await table.boundingBox();
    expect(box.x).toBe(0);
    expect(box.width).toBe(320);
    // Mobile emulation grows innerWidth with the content, so only clientWidth can show overflow.
    const { clientWidth, scrollWidth } = await page.evaluate(() => ({
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }));
    expect(scrollWidth).toBeLessThanOrEqual(clientWidth);
  });

  test("long inline code wraps inside the page at 320px @mobile", async ({ page }) => {
    // Load a deployment guide with long URLs at the narrowest phone.
    await page.setViewportSize({ width: 320, height: 568 });
    await navigateToPath(page, "/docs#/zoom-deployment");
    const code = page
      .locator(".markdown-section :not(pre) > code")
      .filter({ hasText: "YOUR_OCG_BASE_URL" })
      .first();
    await expect(code).toBeVisible({ timeout: 15000 });

    // Verify the code ends before the page edge, where it would be clipped.
    const box = await code.boundingBox();
    expect(box.x + box.width).toBeLessThanOrEqual(320);
  });

  test("the desktop version keeps the desktop docs on a phone @mobile", async ({ page }) => {
    // Load the docs in the desktop version.
    await enableDesktopVersion(page);
    await navigateToPath(page, "/docs");

    // Verify the sidebar stays beside the content, with no strip or toggle.
    await expect(page.locator(".ocg-docs-root .sidebar-nav")).toBeVisible({ timeout: 15000 });
    await expect(page.locator("[data-docs-strip]")).toBeHidden();
    await expect(page.locator(".ocg-docs-root .sidebar-toggle")).toBeHidden();
  });
});

/**
 * Holds the user menu response until the returned callback runs.
 * @param {import("@playwright/test").Page} page - Page about to load the docs.
 * @returns {Promise<() => void>} Releases the response.
 */
const holdUserMenu = async (page) => {
  let release;
  const held = new Promise((resolve) => {
    release = resolve;
  });
  await page.route("**/section/user-menu", async (route) => {
    await held;
    await route.continue();
  });
  return release;
};

/**
 * Asserts the page scroll position.
 * @param {import("@playwright/test").Page} page - Page showing the docs.
 * @param {number} scrollY - Expected position.
 */
const expectPageScroll = async (page, scrollY) => {
  await expect.poll(() => page.evaluate(() => Math.round(window.scrollY))).toBe(scrollY);
};

/**
 * Goes Back onto a docs entry and waits for the reload that replaces HTMX's restore.
 * @param {import("@playwright/test").Page} page - Page showing another page.
 */
const goBackWithReload = async (page) => {
  const reloaded = page.waitForEvent("load");
  await page.goBack();
  await reloaded;
};

/**
 * Leaves the docs through a boosted link, without the scroll a real click would make to reach it.
 * @param {import("@playwright/test").Page} page - Page showing the docs.
 */
const leaveThroughBoostedLink = async (page) => {
  await waitForHtmxSettle(page);
  await page
    .getByRole("navigation", { name: "Main navigation" })
    .getByRole("link", { name: "Explore" })
    .dispatchEvent("click");
  await expect(page).toHaveURL(/\/explore/);
};

/**
 * Opens the Group Dashboard guide, which is long enough to scroll.
 * @param {import("@playwright/test").Page} page - Playwright page.
 */
const openGroupDashboardGuide = async (page) => {
  await navigateToPath(page, "/docs#/guides/group-dashboard");
  await expect(page.getByRole("heading", { name: "Group Dashboard Guide", level: 1 })).toBeVisible({
    timeout: 15000,
  });
};

/**
 * Scrolls the page and waits for the position to take.
 * @param {import("@playwright/test").Page} page - Page showing the docs.
 * @param {number} scrollY - Target position.
 */
const scrollPageTo = async (page, scrollY) => {
  await page.evaluate((top) => window.scrollTo(0, top), scrollY);
  await expectPageScroll(page, scrollY);
};

/**
 * Finds a guide's link in the sidebar. The name alone can also match a section of the open guide.
 * @param {import("@playwright/test").Page} page - Page showing the docs.
 * @param {string} slug - Guide slug.
 * @returns {import("@playwright/test").Locator} Sidebar link.
 */
const sidebarGuideLink = (page, slug) =>
  page.locator(`.ocg-docs-root .sidebar-nav a[href="#/guides/${slug}"]`);

/**
 * Waits for the docs to render and opens the Contents sheet.
 * @param {import("@playwright/test").Page} page - Page showing the docs.
 * @returns {Promise<{
 *   contentsButton: import("@playwright/test").Locator,
 *   sheet: import("@playwright/test").Locator,
 * }>} Toggle and sheet.
 */
const openContents = async (page) => {
  const docsRoot = page.locator(".ocg-docs-root");
  const contentsButton = docsRoot.getByRole("button", { name: "Contents" });
  const sheet = docsRoot.locator(".sidebar");
  await expect(docsRoot.getByRole("heading", { level: 1 }).first()).toBeVisible({ timeout: 15000 });
  await contentsButton.click();
  await expect(sheet).toBeVisible();

  // Wait for the slide to finish, so callers can measure the sheet.
  await expect(sheet).toHaveCSS("transform", "none");
  return { contentsButton, sheet };
};
