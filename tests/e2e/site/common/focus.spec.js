import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_NAME } from "../../seed.js";
import {
  expectFocusIndicator,
  navigateToPath,
  navigateToSiteHome,
  pressKeyUntilFocused,
} from "../../utils.js";

// Outline colour of the site-primary focus indicator.
const PRIMARY_OUTLINE = "var(--color-focus)";

test.describe("site focus indicator", () => {
  test("shows the focus outline on explore search, its buttons and the sort select", async ({ page }) => {
    // Load the events explore page in list view.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);
    const searchInput = page.getByPlaceholder("Search events");
    const searchButton = page.getByRole("button", { exact: true, name: "Search" });
    const sortSelect = page.getByRole("combobox", { name: "Sort by" });
    await expect(sortSelect).toBeVisible();

    // Verify the search field, its button and the sort select draw the outline on Tab.
    await expectFocusIndicator(searchInput, () => pressKeyUntilFocused(page, searchInput), {
      outlineColor: PRIMARY_OUTLINE,
    });
    await expectFocusIndicator(searchButton, () => page.keyboard.press("Tab"), {
      outlineColor: PRIMARY_OUTLINE,
    });
    await expectFocusIndicator(sortSelect, () => pressKeyUntilFocused(page, sortSelect), {
      outlineColor: PRIMARY_OUTLINE,
    });
  });

  test("shows a white focus outline on footer links", async ({ page }) => {
    // Load the site home and find the footer links.
    await navigateToSiteHome(page);
    const footer = page.getByRole("contentinfo", { name: "Site footer" });
    const githubLink = footer.getByRole("link", { exact: true, name: "GitHub" });
    const poweredByLink = footer.getByRole("link", { name: "CNCF Open Community Groups" });

    // Start from the powered-by link and walk back to the GitHub link.
    await poweredByLink.focus();
    await expectFocusIndicator(githubLink, () => pressKeyUntilFocused(page, githubLink, "Shift+Tab"), {
      outlineColor: "rgb(255, 255, 255)",
    });

    // Walk forward to the powered-by link.
    await expectFocusIndicator(poweredByLink, () => pressKeyUntilFocused(page, poweredByLink), {
      outlineColor: "rgb(255, 255, 255)",
    });
  });
});
