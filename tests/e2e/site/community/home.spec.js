import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_AD_BANNER_LINK_URL_2,
  TEST_COMMUNITY_AD_BANNER_URL_2,
  TEST_COMMUNITY_BANNER_MOBILE_URL,
  TEST_COMMUNITY_BANNER_URL,
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_COMMUNITY_TITLE,
  TEST_COMMUNITY_TITLE_2,
  TEST_EVENT_NAMES,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
} from "../../seed.js";
import {
  buildE2eUrl,
  getSectionByHeading,
  getSectionLink,
  navigateToCommunityHome,
  navigateToGroup,
} from "../../utils.js";
import {
  expectLatestGroupsSection,
  expectNumericStats,
  expectPaidEventPriceBadges,
  expectUpcomingEventSections,
} from "../common/helpers.js";

const EXPLORE_LINK_VIEWPORTS = [
  { name: "desktop", width: 1280 },
  { name: "mobile", width: 375 },
];

const COMMUNITY_FILTER = `&community[0]=${TEST_COMMUNITY_NAME}`;
const EXPLORE_LATEST_GROUPS_PATH = `/explore?entity=groups&sort_by=date${COMMUNITY_FILTER}`;

const EXPLORE_SECTION_LINKS = [
  {
    heading: "upcoming in-person events",
    linkName: "Explore all events",
    href: `/explore?entity=events&kind[0]=in-person&kind[1]=hybrid${COMMUNITY_FILTER}`,
  },
  {
    heading: "upcoming virtual events",
    linkName: "Explore all events",
    href: `/explore?entity=events&kind[0]=virtual&kind[1]=hybrid${COMMUNITY_FILTER}`,
  },
  {
    heading: "Latest groups added",
    linkName: "Explore all groups",
    href: EXPLORE_LATEST_GROUPS_PATH,
  },
];

test.describe("community home page", () => {
  test("community without active groups omits collection sections", async ({
    adminSecondaryCommunityPage,
    page,
  }) => {
    // Prepare the secondary-community groups for temporary deactivation.
    const groupIds = Object.values(TEST_GROUP_IDS.community2);
    const deactivatedGroupIds = [];
    try {
      // Deactivate each seeded secondary-community group.
      for (const groupId of groupIds) {
        const response = await adminSecondaryCommunityPage.request.put(
          buildE2eUrl(`/dashboard/community/groups/${groupId}/deactivate`),
        );
        expect(response.ok()).toBeTruthy();
        deactivatedGroupIds.push(groupId);
      }

      // Load the active community after its public collections become empty.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME_2);
      await expect(
        page.getByRole("heading", {
          level: 1,
          name: TEST_COMMUNITY_TITLE_2,
        }),
      ).toBeVisible();

      // Verify absent collections do not render empty public sections.
      await expect(page.getByText("Latest groups added", { exact: true })).toHaveCount(0);
      await expect(page.getByText("upcoming in-person events", { exact: true })).toHaveCount(0);
      await expect(page.getByText("upcoming virtual events", { exact: true })).toHaveCount(0);
    } finally {
      // Restore every group changed by this scenario for later public tests.
      for (const groupId of deactivatedGroupIds) {
        const response = await adminSecondaryCommunityPage.request.put(
          buildE2eUrl(`/dashboard/community/groups/${groupId}/activate`),
        );
        expect(response.ok()).toBeTruthy();
      }
    }
  });

  test("community social links and new group instructions render from seeds", async ({ page }) => {
    // Load the secondary community that carries seeded social links.
    await navigateToCommunityHome(page, TEST_COMMUNITY_NAME_2);

    // Verify each seeded social link exposes its destination.
    const mainContent = page.locator("#main-content");
    await expect(mainContent.getByRole("link", { name: "Twitter", exact: true })).toHaveAttribute(
      "href",
      "https://twitter.com/e2e-devex",
    );
    await expect(mainContent.getByRole("link", { name: "GitHub", exact: true })).toHaveAttribute(
      "href",
      "https://github.com/e2e-devex",
    );
    await expect(mainContent.getByRole("link", { name: "LinkedIn", exact: true })).toHaveAttribute(
      "href",
      "https://linkedin.com/company/e2e-devex",
    );

    // Verify the seeded new group instructions block renders as markdown.
    await expect(page.getByText("New groups", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Open an issue in our GitHub organization to propose a new group.", { exact: true }),
    ).toBeVisible();
  });

  test.describe("default viewport", () => {
    test.beforeEach(async ({ page }) => {
      // Load the community home page before each default viewport assertion.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("about section renders with heading and CTA link", async ({ page }) => {
      // Verify the about section exposes its community explore CTA.
      await expect(page.getByText("About this community")).toBeVisible();

      // Target the community explore CTA link.
      const ctaLink = page.getByRole("link", {
        name: "Explore community groups and events",
      });
      await expect(ctaLink).toBeVisible();
      await expect(ctaLink).toHaveAttribute("href", /\/explore/);
    });

    test("about section renders with seeded description", async ({ page }) => {
      // Verify the about section includes the seeded community description.
      await expect(page.getByText(TEST_COMMUNITY_DESCRIPTION, { exact: true })).toBeVisible();
    });

    test("page metadata and event cards expose complete seeded contracts", async ({ page }) => {
      // Verify the community page title, canonical URL, and responsive banners.
      await expect(page).toHaveTitle(`${TEST_COMMUNITY_TITLE} community`);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
        "href",
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}`),
      );
      await expect(page.getByAltText("Banner")).toHaveCount(2);

      // Verify social previews use the canonical community contract.
      await expect(page.locator('meta[property="og:type"]')).toHaveAttribute("content", "website");
      await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
        "content",
        `${TEST_COMMUNITY_TITLE} community`,
      );
      await expect(page.locator('meta[property="og:url"]')).toHaveAttribute(
        "content",
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}`),
      );
      await expect(page.locator('meta[property="og:description"]')).toHaveAttribute(
        "content",
        "Open Community Groups, where Open Source communities thrive.",
      );
      await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
        "content",
        /\/images\/og\/[a-f0-9]{64}\.png$/,
      );
      await expect(page.locator('meta[property="og:image:alt"]')).toHaveAttribute(
        "content",
        TEST_COMMUNITY_TITLE,
      );
      await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
        "content",
        "summary_large_image",
      );

      // Find the in-person event card and verify its group, venue, and date.
      const inPersonEventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[0] }).first();
      await expect(inPersonEventCard).toContainText(TEST_GROUP_NAMES.alpha);
      await expect(inPersonEventCard).toContainText("Tech Conference Center, New York");
      await expect(inPersonEventCard).toContainText(/\w{3} \d{1,2}, \d{4}/);

      // Find the virtual event card and verify its location label.
      const virtualEventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[1] }).first();
      await expect(virtualEventCard).toContainText("Virtual");

      // Find the hybrid event card and verify its fallback metadata.
      const hybridEventCard = page.getByRole("link").filter({ hasText: TEST_EVENT_NAMES.alpha[2] }).first();
      await expect(hybridEventCard).toContainText("No location provided");
      await expect(hybridEventCard).toContainText("hybrid");
    });

    test("community page sends its page-view beacon", async ({ page }) => {
      // Read the rendered community identifier before watching its analytics endpoint.
      const communityId = await page
        .locator('[data-page-view][data-entity-type="community"]')
        .getAttribute("data-entity-id");
      expect(communityId).toBeTruthy();
      const pageViewRequestPromise = page.waitForRequest(
        (request) =>
          request.method() === "POST" &&
          new URL(request.url()).pathname === `/communities/${communityId}/views`,
      );

      // Reload the page and verify the beacon targets the current community.
      await page.reload();
      const pageViewRequest = await pageViewRequestPromise;
      expect(new URL(pageViewRequest.url()).pathname).toBe(`/communities/${communityId}/views`);
    });

    test("CTA link includes community filter parameter", async ({ page }) => {
      // Target the community explore CTA link.
      const ctaLink = page.getByRole("link", {
        name: "Explore community groups and events",
      });

      // Verify the CTA keeps the current community filter.
      await expect(ctaLink).toHaveAttribute("href", `/explore?community[0]=${TEST_COMMUNITY_NAME}`);
    });

    test("breadcrumb navigation displays community name", async ({ page }) => {
      // Verify the community breadcrumb renders in the page header.
      const breadcrumb = page.locator("breadcrumb-nav");
      await expect(breadcrumb).toBeVisible();
    });

    test("breadcrumb has correct banner and items attributes", async ({ page }) => {
      // Target the community breadcrumb data attributes.
      const breadcrumb = page.locator("breadcrumb-nav");
      await expect(breadcrumb).toHaveAttribute("banner-url", TEST_COMMUNITY_BANNER_URL);
      await expect(breadcrumb).toHaveAttribute("banner-mobile-url", TEST_COMMUNITY_BANNER_MOBILE_URL);

      // Set up items attr.
      const itemsAttr = await breadcrumb.getAttribute("items");

      // Verify breadcrumb metadata includes the community title.
      expect(itemsAttr).toContain(TEST_COMMUNITY_TITLE);
    });

    test("listing sections show seeded events, prices, and groups", async ({ page }) => {
      // Verify the shared public listing sections render seeded content.
      await expectUpcomingEventSections(page, {
        inPerson: [TEST_EVENT_NAMES.alpha[0], TEST_EVENT_NAMES.gamma[0]],
        virtual: [TEST_EVENT_NAMES.alpha[1], TEST_EVENT_NAMES.beta[1], TEST_EVENT_NAMES.gamma[1]],
      });
      await expectPaidEventPriceBadges(page);
      await expectLatestGroupsSection(
        page,
        ["alpha", "beta", "gamma"].map((key) => ({
          href: `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1[key]}`,
          name: TEST_GROUP_NAMES[key],
        })),
      );
    });
  });

  test.describe("explore links", () => {
    for (const viewport of EXPLORE_LINK_VIEWPORTS) {
      test(`explore events and groups links route correctly on ${viewport.name}`, async ({ page }) => {
        // Load the community home page at the requested viewport.
        await page.setViewportSize({ width: viewport.width, height: 900 });
        await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

        // Verify each section link keeps the community filter and matches its preview.
        for (const { heading, linkName, href } of EXPLORE_SECTION_LINKS) {
          const sectionLink = getSectionLink(page, heading, linkName);
          await expect(sectionLink).toBeVisible();
          await expect(sectionLink).toHaveAttribute("href", href);
        }
      });
    }
  });

  test.describe("desktop viewport", () => {
    test.beforeEach(async ({ page }) => {
      // Load the community home page before each desktop assertion.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("stats strip displays numeric values at lg breakpoint", async ({ page }) => {
      // Verify the desktop stats strip shows a number for every stat.
      await expectNumericStats(page, "community", "desktop");
    });

    test("advertisement banner links to the seeded destination", async ({ page }) => {
      // Load the secondary community with the seeded advertisement banner.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME_2);

      // Target the linked advertisement by its accessible image name.
      const advertisementLink = page.getByRole("link", {
        name: `${TEST_COMMUNITY_TITLE_2} advertisement`,
      });
      const advertisementImage = advertisementLink.getByRole("img", {
        name: `${TEST_COMMUNITY_TITLE_2} advertisement`,
      });

      // Verify the advertisement exposes its seeded image and destination.
      await expect(advertisementLink).toBeVisible();
      await expect(advertisementLink).toHaveAttribute("href", TEST_COMMUNITY_AD_BANNER_LINK_URL_2);
      await expect(advertisementImage).toHaveAttribute("src", TEST_COMMUNITY_AD_BANNER_URL_2);
    });

    test("inline advertisement banner is hidden below the md breakpoint", async ({ page }) => {
      // Load the secondary community with the seeded advertisement banner.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME_2);

      // Target the inline advertisement by its accessible image name.
      const advertisementImage = page.getByRole("img", {
        name: `${TEST_COMMUNITY_TITLE_2} advertisement`,
      });
      await expect(advertisementImage).toBeVisible();

      // Verify the inline advertisement disappears below the md breakpoint.
      await page.setViewportSize({ width: 767, height: 900 });
      await expect(advertisementImage).toBeHidden();
    });

    test("advertisement dismissal persists for the current banner content", async ({ page }) => {
      // Load a secondary-community group page with a clean banner preference.
      await page.evaluate(() => {
        Object.keys(localStorage)
          .filter((key) => key.startsWith("ocg:ad-banner:hidden"))
          .forEach((key) => localStorage.removeItem(key));
      });
      await navigateToGroup(page, TEST_COMMUNITY_NAME_2, TEST_GROUP_SLUGS.community2.delta);

      // Close the visible banner and verify its content-scoped preference.
      const advertisementBanner = page.locator('[data-ad-banner="floating"]');
      await expect(advertisementBanner).toBeVisible();
      await page.getByRole("button", { name: "Close advertisement banner" }).click();
      await expect(advertisementBanner).toBeHidden();
      const storedDismissals = await page.evaluate(() =>
        Object.entries(localStorage).filter(
          ([key, value]) => key.startsWith("ocg:ad-banner:hidden") && value === "true",
        ),
      );
      expect(storedDismissals).toHaveLength(1);

      // Reload the same content and verify it remains dismissed.
      await page.reload();
      await expect(page.locator('[data-ad-banner="floating"]')).toBeHidden();
    });

    test("advertisement hides when its image cannot load", async ({ page }) => {
      // Fail the seeded advertisement image before loading the group page.
      await page.route("**/static/images/e2e/event-banner.svg", (route) =>
        route.fulfill({
          body: "",
          contentType: "image/svg+xml",
          status: 404,
        }),
      );
      await navigateToGroup(page, TEST_COMMUNITY_NAME_2, TEST_GROUP_SLUGS.community2.delta);

      // Verify broken advertisement content is not presented to visitors.
      const advertisementBanner = page.locator('[data-ad-banner="floating"]');
      await expect(advertisementBanner).toBeAttached();
      await expect(advertisementBanner).toBeHidden();
    });
  });

  test.describe("mobile viewport @mobile", () => {
    test.beforeEach(async ({ page }) => {
      // Load the community home page before each mobile assertion.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);
    });

    test("stats strip displays numeric values below lg breakpoint", async ({ page }) => {
      // Verify the mobile stats strip shows a number for every stat.
      await expectNumericStats(page, "community", "mobile");
    });

    test("stats box keeps its four cells in a two by two", async ({ page }) => {
      // Measure the mobile stat cells.
      const cells = await page
        .locator(".stat-box > *")
        .evaluateAll((elements) => elements.map((element) => element.getBoundingClientRect()));

      // Verify two columns of two rows inside the box.
      expect(cells).toHaveLength(4);
      expect(cells[0].top).toBe(cells[1].top);
      expect(cells[2].top).toBe(cells[3].top);
      expect(cells[0].left).toBe(cells[2].left);
      expect(cells[1].left).toBeGreaterThan(cells[0].left);
      expect(cells[2].top).toBeGreaterThan(cells[0].top);
    });

    test("about heading stays visible as a section strip", async ({ page }) => {
      // Verify the visible heading the sr-only h1 does not replace.
      const heading = page.getByText("About this community", { exact: true });
      await expect(heading).toBeVisible();
      await expect(heading).toHaveCSS("position", "sticky");
      await expect(heading).toHaveCSS("text-transform", "uppercase");
    });

    test("long unbroken name stays inside the breadcrumb trigger", async ({ page }) => {
      // Serve the page with a name that cannot wrap, on the narrowest phone.
      const longName = "Community".repeat(14);
      await page.route(buildE2eUrl(`/${TEST_COMMUNITY_NAME}`), async (route) => {
        const response = await route.fetch();
        const body = (await response.text()).replaceAll(TEST_COMMUNITY_TITLE, longName);
        await route.fulfill({ body, response });
      });
      await page.setViewportSize({ height: 640, width: 320 });
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME);

      // Verify the trigger holds the name without widening the page.
      const trigger = page
        .getByRole("navigation", { name: "Breadcrumb" })
        .locator('button[aria-haspopup="listbox"]');
      await expect(trigger).toContainText(longName);
      const triggerBox = await trigger.boundingBox();
      expect(triggerBox.x + triggerBox.width).toBeLessThanOrEqual(320);
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
      );
      expect(overflow).toBeLessThanOrEqual(0);
    });

    test("read more shows only while the description is clipped", async ({ page }) => {
      const description = page.locator(".community-description");
      const toggle = page.getByRole("button", { name: "Read more" });

      // Verify the seeded short description has nothing to expand.
      await expect(description).toContainText(TEST_COMMUNITY_DESCRIPTION);
      await expect(toggle).toBeHidden();

      // Grow the description past seven lines.
      await description.evaluate((element) => {
        element.firstElementChild.textContent = "Long community description. ".repeat(40);
      });

      // Verify it clips at seven lines behind the toggle, whose hit area reaches the touch minimum.
      await expect(toggle).toBeVisible();
      await expect(toggle).toHaveAttribute("aria-expanded", "false");
      expect(await description.evaluate((element) => element.clientHeight)).toBe(168);
      const hitAreaHeight = await toggle.evaluate((element) =>
        Number.parseFloat(getComputedStyle(element, "::after").height),
      );
      expect(hitAreaHeight).toBeGreaterThanOrEqual(44);

      // Expand it, then collapse it again.
      await toggle.click();
      const collapse = page.getByRole("button", { name: "Read less" });
      await expect(collapse).toHaveAttribute("aria-expanded", "true");
      expect(await description.evaluate((element) => element.clientHeight)).toBeGreaterThan(168);
      await collapse.click();
      await expect(toggle).toHaveAttribute("aria-expanded", "false");
      expect(await description.evaluate((element) => element.clientHeight)).toBe(168);
    });

    test("read more fades the clipped edge and drops a leading margin", async ({ page }) => {
      const description = page.locator(".community-description");
      const toggle = page.getByRole("button", { name: "Read more" });

      // Lead the description with a heading and grow it past seven lines.
      await description.evaluate((element) => {
        element.innerHTML = `<h2>Heading</h2><p>${"Long community description. ".repeat(40)}</p>`;
      });
      await expect(toggle).toBeVisible();

      // Verify the heading starts at the top and the clip edge fades.
      await expect(description.locator("h2")).toHaveCSS("margin-top", "0px");
      await expect(description).toHaveCSS("mask-image", /linear-gradient/);

      // Verify the open text carries no fade.
      await toggle.click();
      await expect(description).toHaveCSS("mask-image", "none");
    });

    test("see all replaces the explore link beside the groups heading", async ({ page }) => {
      const section = getSectionByHeading(page, "Latest groups added");
      const seeAll = section.getByRole("link", { name: "See all latest groups added" });

      // Verify the phone link is the only way to the list in this section.
      await expect(seeAll).toHaveText("See all");
      await expect(seeAll).toHaveCSS("text-transform", "none");
      await expect(section.getByRole("link", { name: "Explore all groups" })).toHaveCount(0);

      // Verify it keeps the community filter.
      await expect(seeAll).toHaveAttribute("href", EXPLORE_LATEST_GROUPS_PATH);
    });

    test("see all latest groups opens Explore sorted by date", async ({ page }) => {
      const seeAll = page.getByRole("link", { name: "See all latest groups added" });

      // Follow the pill to the groups Explore view.
      await seeAll.tap();
      await expect(page).toHaveURL(/\/explore\?entity=groups&sort_by=date/);

      // Verify the list keeps the newest-first order of the preview.
      await expect(page.getByRole("combobox", { name: "Sort by" })).toHaveValue("date");
    });

    test("new groups stays hidden and the about actions fill the width", async ({ page }) => {
      // Load the secondary community, the one with new group instructions and social links.
      await navigateToCommunityHome(page, TEST_COMMUNITY_NAME_2);

      // Verify the block is rendered but hidden on phones.
      const newGroups = page.getByText("New groups", { exact: true });
      await expect(newGroups).toHaveCount(1);
      await expect(newGroups).toBeHidden();

      // Verify social links reach the tap target size.
      const socialBox = await page
        .getByRole("main")
        .getByRole("link", { name: "GitHub", exact: true })
        .boundingBox();
      expect(socialBox.width).toBe(44);
      expect(socialBox.height).toBe(44);

      // Verify the explore pill spans the panel's text column.
      const exploreLink = page.getByRole("link", { name: "Explore community groups and events" });
      const exploreBox = await exploreLink.boundingBox();
      const { width } = page.viewportSize();
      expect(exploreBox.x).toBe(12);
      expect(exploreBox.width).toBe(width - 24);
      expect(exploreBox.height).toBe(48);
    });
  });
});
