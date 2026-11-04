import { readFileSync } from "node:fs";

import { expect, test } from "../../fixtures.js";

import { getSeedClock, queryE2eDatabase } from "../../database.js";
import {
  TEST_CALENDAR_EVENTS,
  TEST_COHOSTED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAMES,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
} from "../../seed.js";
import {
  buildE2eUrl,
  dismissAlert,
  getIntroSection,
  getPageOverflow,
  getSectionByHeading,
  getSectionLink,
  navigateToGroup,
  sendCloseRequest,
  swipeHorizontally,
} from "../../utils.js";

// Owner group credited on co-host group event cards.
const COHOSTED_EVENT_OWNER_GROUP_NAME = TEST_GROUP_NAMES.epsilon;

// Only the dashboard-only empty group has no upcoming events, and the desktop case toggles
// it, so the phone case renders the template's own markup inside a seeded card.
const GROUP_TEMPLATE = readFileSync(
  new URL("../../../../ocg-server/templates/group/page.html", import.meta.url),
  "utf8",
);
const NO_UPCOMING_EVENTS_MARKUP = GROUP_TEMPLATE.slice(
  GROUP_TEMPLATE.indexOf('<div class="flex flex-col gap-3 relative">'),
  GROUP_TEMPLATE.indexOf("{% endif -%}\n</div>\n</div>\n</div>\n{# End next event section"),
);

test.describe("group page", () => {
  test.beforeEach(async ({ page }) => {
    // Load the primary group page before each assertion.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
  });

  test("renders summary sections and seeded upcoming content", async ({ page }) => {
    // Verify the group header summary content.
    await expect(page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha })).toBeVisible();
    await expect(page.locator("breadcrumb-nav")).toBeVisible();
    await expect(page.getByText("North America", { exact: true })).toBeVisible();
    await expect(page.getByText(/\d+\s+members/, { exact: false })).toBeVisible();

    // Verify the next event link points to the first upcoming event.
    const expectedNextEventSlug = queryE2eDatabase(`
      with target_group as (
        select group_id, community_id
        from "group"
        where group_id = '${TEST_GROUP_IDS.community1.alpha}'::uuid
        and active = true
        and deleted = false
      ),
      scoped_groups as (
        select tg.group_id
        from target_group tg

        union all

        select child.group_id
        from "group" child
        join target_group tg on child.parent_group_id = tg.group_id
        where child.community_id = tg.community_id
        and child.active = true
        and child.deleted = false
      )
      select e.slug
      from event e
      join scoped_groups sg using (group_id)
      where e.deleted = false
      and e.published = true
      and e.test_event = false
      and e.event_kind_id = any(array['in-person', 'virtual', 'hybrid']::text[])
      and e.starts_at is not null
      and e.starts_at > now()
      and e.canceled = false
      order by e.starts_at asc, e.event_id asc
      limit 1
    `);
    expect(expectedNextEventSlug).not.toBe("");
    await expect(page.getByText("Next event", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "See details" })).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${expectedNextEventSlug}`,
    );

    // Verify the fallback location summary is shown.
    await expect(page.getByText("Location", { exact: true })).toBeVisible();
    await expect(page.getByText("Location not provided", { exact: true })).toBeVisible();

    // Verify the upcoming events section includes the expected events.
    await expect(page.getByText("Upcoming Events", { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[2], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.beta[1], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.beta[2], { exact: true })).toBeVisible();

    // Verify the past events section includes historical events.
    await expect(page.getByText("Past Events", { exact: true })).toBeVisible();
    await expect(page.getByText("Past Event For Filtering", { exact: true })).toBeVisible();
  });

  test("empty group page omits optional collection sections", async ({ adminCommunityPage, page }) => {
    // Activate the dashboard-only empty group for the public-page assertion.
    const groupId = TEST_GROUP_IDS.community1.empty;
    const activatePath = `/dashboard/community/groups/${groupId}/activate`;
    const deactivatePath = `/dashboard/community/groups/${groupId}/deactivate`;
    const activateResponse = await adminCommunityPage.request.put(buildE2eUrl(activatePath));
    expect(activateResponse.ok()).toBeTruthy();

    try {
      // Load the temporary public group without events, members, or sponsors.
      await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.empty);

      // Verify the summary fallback and zero member copy remain explicit.
      await expect(
        page.getByRole("heading", {
          level: 1,
          name: TEST_GROUP_NAMES.empty,
        }),
      ).toBeVisible();
      await expect(page.getByText("No upcoming events scheduled", { exact: true })).toBeVisible();
      await expect(page.getByText("0 members", { exact: true })).toBeVisible();

      // Verify absent collections do not render empty public sections.
      await expect(page.getByText("Upcoming Events", { exact: true })).toHaveCount(0);
      await expect(page.getByText("Past Events", { exact: true })).toHaveCount(0);
      await expect(page.getByText("Sponsors", { exact: true })).toHaveCount(0);
    } finally {
      // Restore the empty group to dashboard-only visibility.
      const deactivateResponse = await adminCommunityPage.request.put(buildE2eUrl(deactivatePath));
      expect(deactivateResponse.ok()).toBeTruthy();
    }
  });

  test("social links swap between mobile and desktop variants at the md breakpoint", async ({ page }) => {
    // Load the gamma group that carries seeded social links.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.gamma);

    // Find the desktop and mobile social link variants.
    const desktopWebsiteLink = page.locator('div.hidden.md\\:flex a[title="Website"]');
    const mobileWebsiteLink = page.locator('div.md\\:hidden a[title="Website"]');

    // Verify only the desktop variant shows from the md breakpoint up.
    await expect(desktopWebsiteLink).toBeVisible();
    await expect(desktopWebsiteLink).toHaveAttribute("href", "https://example.com/e2e-observability-guild");
    await expect(page.locator('div.hidden.md\\:flex a[title="Twitter"]')).toBeVisible();
    await expect(mobileWebsiteLink).toBeHidden();

    // Verify only the mobile variant shows below the md breakpoint.
    await page.setViewportSize({ width: 767, height: 900 });
    await expect(mobileWebsiteLink).toBeVisible();
    await expect(desktopWebsiteLink).toBeHidden();
  });

  test("group logo is shown only from the md breakpoint up", async ({ page }) => {
    // Target the header logo container that hides on mobile viewports.
    const logoContainer = page.locator("div.md\\:row-span-2");
    await expect(logoContainer).toBeVisible();

    // Verify the logo container disappears below the md breakpoint.
    await page.setViewportSize({ width: 767, height: 900 });
    await expect(logoContainer).toBeHidden();
  });

  test("renders organizers and sponsors sections from seeded data", async ({ page }) => {
    // Verify public organizers are rendered.
    await expect(page.getByText("Organizers", { exact: true })).toBeVisible();
    await expect(page.getByText("E2E Organizer One", { exact: true })).toBeVisible();

    // Verify visible sponsors render while hidden sponsors stay hidden.
    await expect(page.getByText("Sponsors", { exact: true })).toBeVisible();
    await expect(page.getByText("Hidden Sponsor", { exact: true })).toHaveCount(0);

    // Verify the visible sponsor links to its public website.
    await expect(page.getByText("Tech Corp", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "Tech Corp" })).toHaveAttribute(
      "href",
      "https://techcorp.example.com",
    );
  });

  test("renders group metadata, canonical URL, and accessible images", async ({ page }) => {
    // Ensure the group page is fully loaded before checking head metadata.
    await expect(page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha })).toBeVisible();

    // Verify the group page title and canonical public URL.
    await expect(page).toHaveTitle(TEST_GROUP_NAMES.alpha);
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
      "href",
      buildE2eUrl(`/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`),
    );
    await expect(page.locator('meta[property="og:type"]')).toHaveAttribute("content", "website");
    await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
      "content",
      TEST_GROUP_NAMES.alpha,
    );
    await expect(page.locator('meta[property="og:url"]')).toHaveAttribute(
      "content",
      buildE2eUrl(`/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`),
    );
    await expect(page.locator('meta[property="og:description"]')).toHaveAttribute(
      "content",
      `${TEST_COMMUNITY_TITLE} community in Open Community Groups, where Open Source communities thrive.`,
    );
    await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
      "content",
      /\/images\/og\/[a-f0-9]{64}\.png$/,
    );
    await expect(page.locator('meta[property="og:image:alt"]')).toHaveAttribute(
      "content",
      TEST_GROUP_NAMES.alpha,
    );
    await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute("content", "summary_large_image");

    // Verify seeded description, membership date, and sponsor image metadata.
    await expect(
      page.getByText("Primary meetup used for end-to-end dashboard and site coverage.", { exact: true }),
    ).toBeVisible();
    await expect(page.getByText(/\d+ members/)).toBeVisible();
    // The group was created when the seed loaded, so its month follows the seed clock.
    const seedMonth = new Intl.DateTimeFormat("en-US", {
      month: "long",
      timeZone: "UTC",
      year: "numeric",
    }).format(getSeedClock(TEST_CALENDAR_EVENTS.thisMonth.id).monthStart);
    await expect(page.getByText(seedMonth, { exact: true })).toBeVisible();
    await expect(page.getByAltText("Tech Corp logo")).toBeVisible();
  });

  test("group page sends its page-view beacon", async ({ page }) => {
    // Read the rendered group identifier before watching its analytics endpoint.
    const groupId = await page
      .locator('[data-page-view][data-entity-type="group"]')
      .getAttribute("data-entity-id");
    expect(groupId).toBeTruthy();
    const pageViewRequestPromise = page.waitForRequest(
      (request) =>
        request.method() === "POST" && new URL(request.url()).pathname === `/groups/${groupId}/views`,
    );

    // Reload the page and verify the beacon targets the current group.
    await page.reload();
    const pageViewRequest = await pageViewRequestPromise;
    expect(new URL(pageViewRequest.url()).pathname).toBe(`/groups/${groupId}/views`);
  });

  test("share modal exposes destinations, Escape dismissal, and copy feedback", async ({ page }) => {
    // Open the group actions menu and launch the share dialog. The trigger is
    // a details summary, so target it directly instead of a button role.
    const actionsButton = page.locator("details[data-group-actions-menu] summary");
    await actionsButton.click();
    const shareButton = page.locator("share-modal").getByRole("button", {
      name: "Share",
    });
    await shareButton.click();

    // Verify every share destination uses the canonical group URL.
    const shareDialog = page.getByRole("dialog", { name: "Share" });
    const expectedGroupUrl = buildE2eUrl(
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`,
    );
    await expect(shareDialog).toBeVisible();
    await expect(page.locator("body")).toHaveCSS("overflow", "hidden");
    for (const destination of ["Email", "X", "Facebook", "WhatsApp", "Reddit", "LinkedIn", "Bluesky"]) {
      // Verify the current platform receives the same public group URL.
      await expect(shareDialog.getByRole("button", { name: destination })).toHaveAttribute(
        "data-url",
        expectedGroupUrl,
      );
    }

    // Close with Escape and verify the global scroll lock is released.
    await page.keyboard.press("Escape");
    await expect(shareDialog).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");

    // Replace clipboard writes locally so copy behavior stays deterministic.
    await page.evaluate(() => {
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          writeText: async (value) => {
            window.__copiedShareUrl = value;
          },
        },
      });
    });

    // Reopen the dialog and copy the canonical group URL.
    await actionsButton.click();
    await shareButton.click();
    await page
      .getByRole("dialog", { name: "Share" })
      .getByRole("button", {
        name: "Copy link",
      })
      .click();

    // Verify copy feedback, the copied value, and modal cleanup.
    await expect(page.getByText("Link copied to clipboard!", { exact: true })).toBeVisible();
    expect(await page.evaluate(() => window.__copiedShareUrl)).toBe(expectedGroupUrl);
    await expect(page.getByRole("dialog", { name: "Share" })).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
  });

  test("failed share copy keeps the dialog open for retry", async ({ page }) => {
    // Replace clipboard writes with a deterministic rejection.
    await page.evaluate(() => {
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          writeText: async () => {
            throw new Error("Clipboard unavailable");
          },
        },
      });
    });

    // Open the group share dialog and attempt to copy its link.
    await page.locator("details[data-group-actions-menu] summary").click();
    await page.locator("share-modal").getByRole("button", { name: "Share" }).click();
    const shareDialog = page.getByRole("dialog", { name: "Share" });
    await shareDialog.getByRole("button", { name: "Copy link" }).click();

    // Verify error feedback preserves the dialog and its retry action.
    await expect(page.getByText("Failed to copy link. Please try again.", { exact: true })).toBeVisible();
    await expect(shareDialog).toBeVisible();
    await expect(shareDialog.getByRole("button", { name: "Copy link" })).toBeEnabled();
    await expect(page.locator("body")).toHaveCSS("overflow", "hidden");

    // Close the dialog and verify its scroll lock is released.
    await dismissAlert(page, { message: "Failed to copy link. Please try again." });
    await shareDialog.getByRole("button", { name: "Close modal" }).click();
    await expect(shareDialog).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
  });

  test("organizer profile modal closes with Escape and restores focus", async ({ page }) => {
    // Find the organizer profile trigger.
    const organizerButton = page.getByRole("button", {
      name: "View E2E Organizer One's profile",
    });

    // Open the profile with the keyboard.
    await organizerButton.focus();
    await organizerButton.press("Enter");

    // Find the dialog and verify its organizer and badge content.
    const profileDialog = page.getByRole("dialog");
    await expect(profileDialog).toBeVisible();
    await expect(profileDialog).toContainText("E2E Organizer One");
    await expect(profileDialog.getByRole("link", { name: "View Host badge credential" })).toHaveAttribute(
      "href",
      /\/badges\/credentials\//,
    );

    // Close the dialog and verify focus returns to its trigger.
    await page.keyboard.press("Escape");
    await expect(profileDialog).toBeHidden();
    await expect(organizerButton).toBeFocused();
  });

  test("renders seeded parent and subgroup links", async ({ page }) => {
    // Verify the parent group shows its seeded child relationship.
    await expect(page.getByText("Subgroups", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: TEST_GROUP_NAMES.beta, exact: true })).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.beta}`,
    );

    // Load the child group page before checking the parent relationship.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.beta);

    // Verify the child group links back to its parent group.
    await expect(page.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.beta })).toBeVisible();
    await expect(page.getByText("Parent group", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: TEST_GROUP_NAMES.alpha, exact: true })).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`,
    );
  });
});

test.describe("group page - co-hosted events", () => {
  test("co-host group page credits the owner and links to the owner event page", async ({ page }) => {
    const ownerEventPath = `/${TEST_COMMUNITY_NAME_2}/group/${TEST_GROUP_SLUGS.community2.epsilon}/event/${TEST_COHOSTED_EVENT.slug}`;

    // Load the seeded co-host group page.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.gamma);

    // Verify the next event links to the owner community event page with co-host credit.
    const nextEventSection = page
      .getByText("Next event", { exact: true })
      .locator("xpath=ancestor::div[contains(@class, 'rounded-lg')][1]");
    await expect(nextEventSection.getByRole("link", { name: "See details" })).toHaveAttribute(
      "href",
      ownerEventPath,
    );
    await expect(nextEventSection.getByText(/^Co-hosted with /u).first()).toBeAttached();

    // Verify the upcoming card names the owner group instead of the category.
    const eventCard = page.locator(`a[href="${ownerEventPath}"]`, { hasText: TEST_COHOSTED_EVENT.name });
    await expect(eventCard).toBeVisible();
    await expect(eventCard).toContainText(`Hosted by ${COHOSTED_EVENT_OWNER_GROUP_NAME}`);
  });
});

test.describe("group page - responsive links", () => {
  test("see all events links use the group-scoped explore filters on desktop", async ({ page }) => {
    // Load the group page before checking scoped explore links.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    // Set up expected upcoming href.
    const expectedUpcomingHref =
      `/explore?entity=events&group[0]=${TEST_GROUP_SLUGS.community1.alpha}` +
      `&group[1]=${TEST_GROUP_SLUGS.community1.beta}` +
      `&community[0]=${TEST_COMMUNITY_NAME}`;

    // Verify the desktop upcoming link keeps group and community filters.
    await expect(getSectionLink(page, "Upcoming Events", "See all events", "desktop")).toHaveAttribute(
      "href",
      expectedUpcomingHref,
    );

    // Verify the desktop past link keeps filters and historical date range.
    await expect(getSectionLink(page, "Past Events", "See all events", "desktop")).toHaveAttribute(
      "href",
      new RegExp(
        String.raw`^/explore\?entity=events&group\[0\]=${TEST_GROUP_SLUGS.community1.alpha}` +
          String.raw`&group\[1\]=${TEST_GROUP_SLUGS.community1.beta}` +
          String.raw`&community\[0\]=${TEST_COMMUNITY_NAME}&date_from=1900-01-01` +
          String.raw`&sort_direction=desc&date_to=\d{4}-\d{2}-\d{2}$`,
      ),
    );
  });

  test("see all events links are available on mobile @mobile", async ({ page }) => {
    // Load the group page before checking mobile links.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    // Verify each heading carries a pill that keeps the group filters.
    const upcomingLink = getSectionLink(page, "Upcoming Events", "See all upcoming events", "mobile");
    const pastLink = getSectionLink(page, "Past Events", "See all past events", "mobile");
    await expect(upcomingLink).toHaveText("See all");
    await expect(upcomingLink).toHaveAttribute(
      "href",
      `/explore?entity=events&group[0]=${TEST_GROUP_SLUGS.community1.alpha}` +
        `&group[1]=${TEST_GROUP_SLUGS.community1.beta}` +
        `&community[0]=${TEST_COMMUNITY_NAME}`,
    );
    await expect(pastLink).toHaveText("See all");
    await expect(pastLink).toHaveAttribute("href", /date_from=1900-01-01&sort_direction=desc/);

    // Verify the bottom links give way to the pills.
    await expect(
      getSectionByHeading(page, "Upcoming Events").locator("div.md\\:hidden").getByRole("link"),
    ).toHaveCount(0);

    // Verify the past pill reaches the past list.
    await pastLink.click();
    await expect(page).toHaveURL(/\/explore\?.*date_from=1900-01-01/);
  });
});

test.describe("group page - phone layout", () => {
  /**
   * Finds the card that holds a Next event or Location eyebrow.
   * @param {import("@playwright/test").Page} page - Page under test.
   * @param {string} eyebrow - Exact eyebrow text.
   * @returns {import("@playwright/test").Locator} Card element.
   */
  const getSummaryCard = (page, eyebrow) =>
    page
      .getByText(eyebrow, { exact: true })
      .locator("xpath=ancestor::div[contains(@class, 'rounded-lg')][1]");

  test("summary keeps the logo and title above a filled Join and the Share pill @mobile", async ({
    page,
  }) => {
    // Load the group signed out.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const summary = getIntroSection(page);
    const join = summary.getByRole("button", { name: "Join group" });
    const share = summary.getByRole("button", { name: "Share" });

    // Verify desktop's logo and title stay, and the three-dots menu goes.
    await expect(summary.locator("div.md\\:row-span-2")).toBeVisible();
    await expect(summary.getByRole("heading", { level: 1, name: TEST_GROUP_NAMES.alpha })).toBeVisible();
    await expect(summary.locator("details[data-group-actions-menu]")).toBeHidden();

    // Verify Join is the page's filled main action.
    await expect(join).toBeVisible();
    await expect(join).toHaveCSS("color", "rgb(255, 255, 255)");
    await expect(join).not.toHaveCSS("background-color", "rgb(255, 255, 255)");
    await expect(share).toHaveCSS("background-color", "rgb(255, 255, 255)");

    // Verify both pills share one 44px row across the panel's gutters.
    const viewportWidth = page.viewportSize().width;
    const joinBox = await join.boundingBox();
    const shareBox = await share.boundingBox();
    expect(joinBox.height).toBe(44);
    expect(shareBox.height).toBe(44);
    expect(shareBox.y).toBe(joinBox.y);
    expect(joinBox.x).toBe(12);
    expect(joinBox.x + joinBox.width).toBeLessThan(shareBox.x);
    expect(shareBox.x + shareBox.width).toBeCloseTo(viewportWidth - 12, 1);
  });

  test("social links sit above the action row at 44px @mobile", async ({ page }) => {
    // Load the group that carries seeded social links.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.gamma);
    const summary = getIntroSection(page);
    const website = summary.locator('div.md\\:hidden a[title="Website"]');
    await expect(website).toBeVisible();

    // Verify the tap target and icon sizes.
    const websiteBox = await website.boundingBox();
    expect(websiteBox.width).toBe(44);
    expect(websiteBox.height).toBe(44);
    await expect(website.locator(".svg-icon")).toHaveCSS("width", "20px");

    // Verify the links stay above Join, as on desktop.
    const joinBox = await summary.getByRole("button", { name: "Join group" }).boundingBox();
    expect(websiteBox.y + websiteBox.height).toBeLessThanOrEqual(joinBox.y);
  });

  test("social links keep their spacing on wide phones @mobile", async ({ page }) => {
    // Load the group with two social links.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.gamma);
    const links = getIntroSection(page).locator("div.md\\:hidden a");
    await expect(links).toHaveCount(2);

    for (const width of [568, 639, 667, 700]) {
      await test.step(`${width}px`, async () => {
        await page.setViewportSize({ height: 375, width });

        // Verify the columns stop spreading at a normal phone's spacing.
        await expect
          .poll(async () => {
            const firstBox = await links.first().boundingBox();
            const secondBox = await links.last().boundingBox();

            return secondBox.x - (firstBox.x + firstBox.width);
          })
          .toBe(41);
      });
    }
  });

  test("next event and location read as matching cards @mobile", async ({ page }) => {
    // Load the group that has a location and an upcoming event.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.gamma);
    const nextEventCard = getSummaryCard(page, "Next event");
    const locationCard = getSummaryCard(page, "Location");
    await expect(nextEventCard).toBeVisible();
    await expect(locationCard).toBeVisible();

    // Verify the cards share an edge, a width and a frame.
    const nextEventBox = await nextEventCard.boundingBox();
    const locationBox = await locationCard.boundingBox();
    expect(locationBox.x).toBe(nextEventBox.x);
    expect(locationBox.width).toBe(nextEventBox.width);
    expect(locationBox.y - (nextEventBox.y + nextEventBox.height)).toBeCloseTo(12, 1);
    for (const card of [nextEventCard, locationCard]) {
      await expect(card).toHaveCSS("border-top-width", "1px");
      await expect(card).toHaveCSS("border-top-left-radius", "8px");
      await expect(card.locator(":scope > div")).toHaveCSS("padding-top", "12px");
    }

    // Verify the map panel keeps its fixed preview height.
    expect((await locationCard.locator("div.border-dashed").boundingBox()).height).toBe(150);

    // Verify See details reads as the small outlined pill.
    const seeDetails = nextEventCard.getByRole("link", { name: "See details" });
    await expect(seeDetails).toHaveCSS("font-size", "13px");
  });

  test("location card drops out when the group has no map @mobile", async ({ page }) => {
    // Load the group that has no location.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    // Verify Next event stays and the empty Location card goes.
    await expect(getSummaryCard(page, "Next event")).toBeVisible();
    await expect(page.getByText("Location", { exact: true })).toBeHidden();
    await expect(page.getByText("Location not provided", { exact: true })).toBeHidden();
  });

  test("no upcoming events keeps the card with one plain message @mobile", async ({ page }) => {
    // Render the empty state in a seeded Next event card.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const nextEventCard = getSummaryCard(page, "Next event");
    const panel = nextEventCard.locator("div.border-dashed");
    await panel.evaluate((element, markup) => {
      element.innerHTML = markup;
    }, NO_UPCOMING_EVENTS_MARKUP);

    // Verify the message flows in the panel at the phone size.
    const message = panel.getByText("No upcoming events scheduled", { exact: true });
    await expect(message).toBeVisible();
    await expect(message).toHaveCSS("font-size", "16px");
    await expect(message.locator("..")).toHaveCSS("position", "static");

    // Verify the skeleton bars go and the panel shrinks to its message.
    await expect(panel.locator(".bg-stone-100")).toHaveCount(3);
    await expect(panel.locator(".bg-stone-100:visible")).toHaveCount(0);
    expect((await panel.boundingBox()).height).toBeLessThan(108);
  });

  test("gallery tile opens the lightbox and a swipe changes the image @mobile", async ({ owned, page }) => {
    // Give a group two photos, which no seeded group has.
    const groupId = TEST_GROUP_IDS.community1.alpha;
    queryE2eDatabase(`
      update "group"
      set photos_urls = array['/static/images/e2e/event-banner.svg', '/static/images/e2e/event-logo.svg']
      where group_id = '${groupId}';
    `);
    owned.defer(() =>
      queryE2eDatabase(`update "group" set photos_urls = null where group_id = '${groupId}';`),
    );
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    // Open the lightbox from the second tile.
    const gallery = page.locator("images-gallery");
    const lightbox = gallery.locator(".modal");
    const activeSlideImage = lightbox.locator(".z-30.translate-x-0 img");
    const imageName = `Group ${TEST_GROUP_NAMES.alpha} image`;
    await gallery.getByRole("button", { name: `Open ${imageName} 2` }).tap();
    await expect(lightbox).not.toHaveClass(/opacity-0/);
    await expect(activeSlideImage).toHaveAttribute("alt", `${imageName} 2`);

    // Verify a swipe moves to the other image.
    await swipeHorizontally(page, 300, 150);
    await expect(activeSlideImage).toHaveAttribute("alt", `${imageName} 1`);
  });

  test("section titles pin as headings under the header @mobile", async ({ page }) => {
    // Load the group with every seeded section.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const viewportWidth = page.viewportSize().width;

    // Verify each title sits in a full-width strip.
    for (const title of [
      "About this group",
      "Subgroups",
      "Upcoming Events",
      "Past Events",
      "Organizers",
      "Sponsors",
    ]) {
      const strip = page.locator(".section-strip", { hasText: title });
      await expect(strip).toHaveCSS("position", "sticky");
      await expect(strip).toHaveCSS("font-size", "15px");
      const stripBox = await strip.boundingBox();
      expect(stripBox.x).toBe(0);
      expect(stripBox.width).toBe(viewportWidth);
    }

    // Scroll into the Upcoming Events section.
    const upcomingStrip = page.locator(".section-strip", { hasText: "Upcoming Events" });
    await upcomingStrip.evaluate((element) => {
      window.scrollTo(0, window.scrollY + element.getBoundingClientRect().top + 40);
    });

    // Verify the heading pins under the header with its See all pill.
    await expect
      .poll(() => upcomingStrip.evaluate((element) => element.getBoundingClientRect().top))
      .toBe(63);
    await expect(upcomingStrip.getByRole("link", { name: "See all upcoming events" })).toBeInViewport();
  });

  test("upcoming list stops at three cards @mobile", async ({ page }) => {
    // Load the group with more than three upcoming events.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const upcomingGrid = getSectionByHeading(page, "Upcoming Events").locator(":scope > div.grid");

    // Verify the rest stay behind See all.
    expect(await upcomingGrid.locator(":scope > *").count()).toBeGreaterThan(3);
    await expect(upcomingGrid.locator(":scope > *:visible")).toHaveCount(3);
  });

  test("about text shows read more only while clipped @mobile", async ({ page }) => {
    // Load the group with a short seeded description.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const description = page.locator(".read-more-body");
    const toggle = page.getByRole("button", { name: "Read more" });
    await expect(description).toBeVisible();

    // Verify the short description has nothing to expand.
    await expect(toggle).toBeHidden();

    // Grow the description past three lines.
    await description.evaluate((element) => {
      element.firstElementChild.textContent = "Long group description. ".repeat(40);
    });

    // Verify it clips at three lines behind the toggle.
    await expect(toggle).toBeVisible();
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(await description.evaluate((element) => element.clientHeight)).toBe(72);

    // Verify the toggle opens the text.
    await toggle.click();
    await expect(page.getByRole("button", { name: "Read less" })).toHaveAttribute("aria-expanded", "true");
    expect(await description.evaluate((element) => element.clientHeight)).toBeGreaterThan(72);
  });

  test("action row and cards fit narrow phones without overflow @mobile", async ({ page }) => {
    // Load the group with social links, a map and upcoming events.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.gamma);
    const summary = getIntroSection(page);
    const share = summary.getByRole("button", { name: "Share" });

    // Give the legend a long region, which no seeded group has.
    await summary.locator("span.tracking-wide").evaluate((legend) => {
      legend.textContent = "Asia Pacific, Middle East and North Africa Regional Chapters";
    });

    for (const width of [320, 360, 402]) {
      await test.step(`${width}px`, async () => {
        await page.setViewportSize({ height: 640, width });

        // Verify the page holds its width and Share stays inside the gutter.
        await expect.poll(() => getPageOverflow(page)).toBeLessThanOrEqual(0);
        const shareBox = await share.boundingBox();
        expect(shareBox.x + shareBox.width).toBeLessThanOrEqual(width - 12);
      });
    }
  });
});

test.describe("group page - share and profile sheets", () => {
  /**
   * Stubs the system share before the page loads and records its calls.
   * @param {import("@playwright/test").Page} page - Page under test.
   * @param {string|null} rejection - DOMException name to reject with, or null to succeed.
   * @returns {Promise<void>} Resolves once the stub is registered.
   */
  const stubSystemShare = (page, rejection) =>
    page.addInitScript((rejectionName) => {
      window.shareCalls = [];
      Object.defineProperty(navigator, "canShare", { configurable: true, value: () => true });
      Object.defineProperty(navigator, "share", {
        configurable: true,
        value: async (data) => {
          window.shareCalls.push(data);
          if (rejectionName) {
            throw new DOMException("Stubbed share result", rejectionName);
          }
        },
      });
    }, rejection);

  /**
   * Loads the group and returns its Share pill.
   * @param {import("@playwright/test").Page} page - Page under test.
   * @returns {Promise<import("@playwright/test").Locator>} Share pill button.
   */
  const openGroupWithSharePill = async (page) => {
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    return page.locator('share-modal[trigger-variant="pill"]').getByRole("button", { name: "Share" });
  };

  /**
   * Verifies a sheet panel rests on the bottom edge of the screen.
   * @param {import("@playwright/test").Locator} dialog - Open dialog.
   * @returns {Promise<void>} Resolves once the panel has settled.
   */
  const expectBottomSheet = async (dialog) => {
    const panel = dialog.locator(".sheet-panel");
    await expect(panel).toHaveAttribute("data-sheet-drag", "");
    await expect
      .poll(() =>
        panel.evaluate((element) => Math.round(window.innerHeight - element.getBoundingClientRect().bottom)),
      )
      .toBe(0);
  };

  test("share pill hands off to the system share and opens nothing @mobile", async ({ page }) => {
    // Load the page with a working system share.
    await stubSystemShare(page, null);
    const sharePill = await openGroupWithSharePill(page);

    // Tap the pill.
    await sharePill.click();

    // Verify the system share got the canonical URL and the modal stayed closed.
    await expect.poll(() => page.evaluate(() => window.shareCalls.length)).toBe(1);
    const [shareCall] = await page.evaluate(() => window.shareCalls);
    expect(shareCall).toEqual({
      title: TEST_GROUP_NAMES.alpha,
      url: buildE2eUrl(`/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`),
    });
    await expect(page.getByRole("dialog", { name: "Share" })).toHaveCount(0);
  });

  test("share pill does nothing when the person cancels the system share @mobile", async ({ page }) => {
    // Load the page with a system share the person dismisses.
    await stubSystemShare(page, "AbortError");
    const sharePill = await openGroupWithSharePill(page);

    // Tap the pill.
    await sharePill.click();

    // Verify cancelling opens no fallback.
    await expect.poll(() => page.evaluate(() => window.shareCalls.length)).toBe(1);
    await expect(page.getByRole("dialog", { name: "Share" })).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
  });

  test("share pill falls back to the sheet when the system share fails @mobile", async ({ page }) => {
    // Load the page with a failing system share.
    await stubSystemShare(page, "NotAllowedError");
    const sharePill = await openGroupWithSharePill(page);

    // Tap the pill.
    await sharePill.click();

    // Verify the share sheet opens as the fallback.
    await expect.poll(() => page.evaluate(() => window.shareCalls.length)).toBe(1);
    await expectBottomSheet(page.getByRole("dialog", { name: "Share" }));
  });

  test("share pill opens the sheet without system share, and Back-style close releases it @mobile", async ({
    page,
  }) => {
    // Load the page without the system share.
    await page.addInitScript(() => {
      delete Navigator.prototype.canShare;
      delete Navigator.prototype.share;
    });
    const sharePill = await openGroupWithSharePill(page);
    const historyLength = await page.evaluate(() => window.history.length);

    // Tap the pill.
    await sharePill.click();
    const shareDialog = page.getByRole("dialog", { name: "Share" });
    await expectBottomSheet(shareDialog);
    await expect(page.locator("body")).toHaveCSS("overflow", "hidden");

    // Reach the CloseWatcher past the sheet's own Escape handler.
    await sendCloseRequest(page);

    // Verify the sheet closed and history did not move.
    await expect(shareDialog).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
    expect(await page.evaluate(() => window.history.length)).toBe(historyLength);
  });

  test("share sheet closes when dragged past the threshold @mobile", async ({ page }) => {
    // Open the share sheet.
    await page.addInitScript(() => {
      delete Navigator.prototype.canShare;
      delete Navigator.prototype.share;
    });
    const sharePill = await openGroupWithSharePill(page);
    await sharePill.click();
    const shareDialog = page.getByRole("dialog", { name: "Share" });
    await expectBottomSheet(shareDialog);

    // Drag the title row down from its start, away from the close button.
    const box = await shareDialog.locator(".sheet-grab").boundingBox();
    await page.mouse.move(box.x + 60, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 60, box.y + box.height / 2 + 200, { steps: 4 });
    await page.mouse.up();

    // Verify the drag closed the sheet through its real close path.
    await expect(shareDialog).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
  });

  test("organizer card shows a chevron and opens the profile as a sheet @mobile", async ({ page }) => {
    // Load the group and find the organizer card.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const organizerCard = page.getByRole("button", { name: "View E2E Organizer One's profile" });
    await expect(organizerCard.locator(".icon-arrow-right")).toBeVisible();
    const historyLength = await page.evaluate(() => window.history.length);

    // Open the profile.
    await organizerCard.click();

    // Verify the sheet keeps the dialog name while the title leaves the head.
    const profileDialog = page.getByRole("dialog", { name: /^User/ });
    await expectBottomSheet(profileDialog);
    await expect(profileDialog).toContainText("E2E Organizer One");
    await expect
      .poll(() =>
        profileDialog
          .getByRole("button", { name: "Close modal" })
          .evaluate((element) => element.getBoundingClientRect().height),
      )
      .toBe(44);

    // Reach the CloseWatcher past the sheet's own Escape handler.
    await sendCloseRequest(page);

    // Verify the sheet closed and history did not move.
    await expect(profileDialog).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
    expect(await page.evaluate(() => window.history.length)).toBe(historyLength);
  });
});
