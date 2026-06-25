import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils.js";

const getSearchSection = (page, title) =>
  page
    .getByRole("heading", { name: title, exact: true })
    .locator("..")
    .locator("..");

test.describe("site search page", () => {
  test("renders aggregated search sections with continue-search links", async ({
    page,
  }) => {
    await navigateToPath(page, "/search?query=AI");

    await expect(
      page.getByRole("heading", { level: 1, name: "Find what you need" }),
    ).toBeVisible();
    const searchInput = page.locator("#site-search-query");
    await expect(searchInput).toBeVisible();
    await expect(searchInput).toHaveValue("AI");
    const searchForm = page.locator("form:has(#site-search-query)");
    await expect(searchForm).toHaveAttribute("hx-get", "/search");
    await expect(searchForm).toHaveAttribute(
      "hx-trigger",
      /input changed delay:300ms/,
    );
    await expect(
      page.getByRole("heading", { name: /Search for/ }),
    ).toContainText('Search for "AI"');

    await expect(page.getByText("total matches")).toBeVisible();

    await expect(getSearchSection(page, "Events")).toBeVisible();
    await expect(getSearchSection(page, "Groups")).toBeVisible();
    await expect(getSearchSection(page, "Jobs")).toBeVisible();
    await expect(getSearchSection(page, "Ecosystem")).toBeVisible();
    await expect(getSearchSection(page, "Reading Brief")).toBeVisible();

    await expect(
      getSearchSection(page, "Events").getByRole("link", { name: "View all" }),
    ).toHaveAttribute(
      "href",
      /\/explore\?alliance\[0\]=goup&entity=events&ts_query=AI/,
    );
    await expect(
      getSearchSection(page, "Groups").getByRole("link", { name: "View all" }),
    ).toHaveAttribute(
      "href",
      /\/explore\?alliance\[0\]=goup&entity=groups&ts_query=AI/,
    );
    await expect(
      getSearchSection(page, "Jobs").getByRole("link", { name: "View all" }),
    ).toHaveAttribute("href", "/jobs?query=AI");
    await expect(
      getSearchSection(page, "Ecosystem").getByRole("link", {
        name: "View all",
      }),
    ).toHaveAttribute("href", "/landscape?query=AI");
  });
});
