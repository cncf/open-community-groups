import { expect } from "@playwright/test";

import { TEST_EVENT_NAMES } from "../../seed.js";
import { getSectionByHeading, getStatsContainer, getStatValue } from "../../utils.js";

// Paid seeded events and the starting price each public card shows.
const PAID_EVENT_PRICES = [
  { name: TEST_EVENT_NAMES.gamma[0], price: /From (?:US)?\$20\.00/ },
  { name: TEST_EVENT_NAMES.beta[2], price: /From (?:US)?\$15\.00/ },
];

// Labels rendered by the public stats strip.
const STAT_LABELS = ["Groups", "Members", "Events", "Attendees"];

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
