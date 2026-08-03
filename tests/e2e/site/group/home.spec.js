import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  buildE2eUrl,
  getSectionLink,
  navigateToGroup,
} from "../../utils.js";

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
    await expect(page.getByText("Next event", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "See details" })).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`,
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

  test("empty group page omits optional collection sections", async ({
    adminCommunityPage,
    page,
  }) => {
    // Activate the dashboard-only empty group for the public-page assertion.
    const groupId = TEST_GROUP_IDS.community1.empty;
    const activatePath = `/dashboard/community/groups/${groupId}/activate`;
    const deactivatePath = `/dashboard/community/groups/${groupId}/deactivate`;
    const activateResponse = await adminCommunityPage.request.put(
      buildE2eUrl(activatePath),
    );
    expect(activateResponse.ok()).toBeTruthy();

    try {
      // Load the temporary public group without events, members, or sponsors.
      await navigateToGroup(
        page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.empty,
      );

      // Verify the summary fallback and zero member copy remain explicit.
      await expect(
        page.getByRole("heading", {
          level: 1,
          name: TEST_GROUP_NAMES.empty,
        }),
      ).toBeVisible();
      await expect(
        page.getByText("No upcoming events scheduled", { exact: true }),
      ).toBeVisible();
      await expect(page.getByText("0 members", { exact: true })).toBeVisible();

      // Verify absent collections do not render empty public sections.
      await expect(
        page.getByText("Upcoming Events", { exact: true }),
      ).toHaveCount(0);
      await expect(
        page.getByText("Past Events", { exact: true }),
      ).toHaveCount(0);
      await expect(page.getByText("Sponsors", { exact: true })).toHaveCount(0);
    } finally {
      const deactivateResponse = await adminCommunityPage.request.put(
        buildE2eUrl(deactivatePath),
      );
      expect(deactivateResponse.ok()).toBeTruthy();
    }
  });

  test("social links swap between mobile and desktop variants at the md breakpoint", async ({
    page,
  }) => {
    // Load the gamma group that carries seeded social links.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.gamma);

    // Find the desktop and mobile social link variants.
    const desktopWebsiteLink = page.locator('div.hidden.md\\:flex a[title="Website"]');
    const mobileWebsiteLink = page.locator('div.md\\:hidden a[title="Website"]');

    // Verify only the desktop variant shows from the md breakpoint up.
    await expect(desktopWebsiteLink).toBeVisible();
    await expect(desktopWebsiteLink).toHaveAttribute(
      "href",
      "https://example.com/e2e-observability-guild",
    );
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
    await expect(page.locator('meta[property="og:type"]')).toHaveAttribute(
      "content",
      "website",
    );
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
    await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
      "content",
      "summary_large_image",
    );

    // Verify seeded description, membership date, and sponsor image metadata.
    await expect(
      page.getByText("Primary meetup used for end-to-end dashboard and site coverage.", { exact: true }),
    ).toBeVisible();
    await expect(page.getByText(/\d+ members/)).toBeVisible();
    await expect(page.getByText("August 2026", { exact: true })).toBeVisible();
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
    await page.locator(".swal2-confirm").click();
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

    // Verify mobile section links are visible.
    await expect(getSectionLink(page, "Upcoming Events", "See all events", "mobile")).toBeVisible();
    await expect(getSectionLink(page, "Past Events", "See all events", "mobile")).toBeVisible();
  });
});
