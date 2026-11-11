import { expect } from "@playwright/test";

import { TEST_EVENT_NAMES } from "../../seed.js";
import { getSectionByHeading, getStatsContainer, getStatValue } from "../../utils.js";
import { loadPublicPage, PUBLIC_PAGES } from "./public-pages.js";

// Page the explore filter specs open the filters on.
const EXPLORE_EVENTS_PAGE = PUBLIC_PAGES.find(({ name }) => name === "explore events");

// Page the organizer profile specs open the profile on.
const GROUP_PAGE = PUBLIC_PAGES.find(({ name }) => name === "group");

// Paid seeded events and the starting price each public card shows.
const PAID_EVENT_PRICES = [
  { name: TEST_EVENT_NAMES.gamma[0], price: /From (?:US)?\$20\.00/ },
  { name: TEST_EVENT_NAMES.beta[2], price: /From (?:US)?\$15\.00/ },
];

// Labels rendered by the public stats strip.
const STAT_LABELS = ["Groups", "Members", "Events", "Attendees"];

// Page the account menu specs open the menu on.
const STATS_PAGE = PUBLIC_PAGES.find(({ name }) => name === "statistics");

/**
 * Clicks a control through a DOM event instead of emulated pointer input. In desktop version
 * mode the 1280px layout viewport exceeds the mobile visual viewport, and Chromium's emulated
 * pointer coordinates no longer map onto elements outside the visible area.
 */
export const clickInDesktopMode = (locator) => locator.dispatchEvent("click");

/**
 * Verifies the latest groups section, its explore link, and seeded group cards.
 * @param {import("@playwright/test").Page} page
 * @param {{ href: string, name: string }[]} [groups] Group cards expected in the section.
 */
export const expectLatestGroupsSection = async (page, groups = []) => {
  const section = getSectionByHeading(page, "Latest groups added");
  await expect(section).toBeVisible();
  await expect(
    section.getByRole("link", { name: "Explore all groups" }).filter({ visible: true }),
  ).toHaveCount(1);

  for (const { href, name } of groups) {
    const groupCard = section.locator(`a[href="${href}"]`);
    await expect(groupCard).toBeVisible();
    await expect(groupCard).toContainText(name);
  }
};

/**
 * Verifies every public stat in the stats strip shows a formatted number.
 * @param {import("@playwright/test").Page} page
 * @param {"community" | "site"} pageKind
 * @param {"desktop" | "mobile"} viewport
 */
export const expectNumericStats = async (page, pageKind, viewport) => {
  const statsContainer = getStatsContainer(page, pageKind, viewport);
  await expect(statsContainer).toBeVisible();

  for (const label of STAT_LABELS) {
    await expect(getStatValue(statsContainer, label)).toHaveText(/^\d[\d,]*$/);
  }
};

/**
 * Verifies paid seeded event cards show their starting price.
 * @param {import("@playwright/test").Page} page
 */
export const expectPaidEventPriceBadges = async (page) => {
  for (const { name, price } of PAID_EVENT_PRICES) {
    const eventCard = page.getByRole("link").filter({ hasText: name }).first();
    await expect(eventCard).toContainText(price);
  }
};

/**
 * Verifies both upcoming event sections list the given seeded events.
 * @param {import("@playwright/test").Page} page
 * @param {{ inPerson: string[], virtual: string[] }} eventNames Event titles per section.
 */
export const expectUpcomingEventSections = async (page, { inPerson, virtual }) => {
  const sections = [
    { heading: "upcoming in-person events", names: inPerson },
    { heading: "upcoming virtual events", names: virtual },
  ];

  for (const { heading, names } of sections) {
    const section = getSectionByHeading(page, heading);
    await expect(section).toBeVisible();

    for (const name of names) {
      await expect(section.getByText(name, { exact: true })).toBeVisible();
    }
  }
};

/**
 * Finds the account sheet and its trigger.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Record<string, import("@playwright/test").Locator>} Sheet locators.
 */
export const getAccountSheet = (page) => {
  const userMenu = page.locator("#user-dropdown");
  return {
    closeButton: userMenu.getByRole("menuitem", { name: "Close menu" }),
    userButton: page.locator("#user-dropdown-button"),
    userMenu,
  };
};

/**
 * Loads the statistics page and opens the account menu on it, the account sheet on phones.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<import("@playwright/test").Locator>} Open account menu.
 */
export const openAccountMenuOnStats = async (page) => {
  const { userButton, userMenu } = getAccountSheet(page);

  await loadPublicPage(page, STATS_PAGE);
  await userButton.click();
  await expect(userMenu).toBeVisible();
  return userMenu;
};

/**
 * Loads the explore events page and opens its filters, the filter sheet on phones.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<import("@playwright/test").Locator>} Open filter drawer.
 */
export const openExploreFilters = async (page) => {
  const drawer = page.locator("#drawer-filters");

  await loadPublicPage(page, EXPLORE_EVENTS_PAGE);
  await page.locator("#open-filters").click();
  await expect(page.getByRole("dialog", { name: "Filters" })).toBeVisible();
  return drawer;
};

/**
 * Loads the group page and opens the organizer profile dialog from its organizer card.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<import("@playwright/test").Locator>} Open profile dialog.
 */
export const openOrganizerProfileOnGroup = async (page) => {
  const profileDialog = page.locator('user-info-modal [role="dialog"]');

  await loadPublicPage(page, GROUP_PAGE);
  await page.getByRole("button", { name: /^View profile:\s*E2E Organizer One\b/ }).click();
  await expect(profileDialog).toBeVisible();
  await expect(profileDialog).toContainText("E2E Organizer One");
  return profileDialog;
};
