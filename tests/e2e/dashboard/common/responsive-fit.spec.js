import { randomUUID } from "node:crypto";

import { expect, test } from "../../fixtures.js";
import { cleanupEventUtmViews, setupEventUtmViews } from "../../data-graphs/analytics.js";
import {
  cleanupBadgeDefinition,
  cleanupCredential,
  setupBadgeDefinition,
  setupCredentialRevocation,
  setupRevocableCredential,
} from "../../data-graphs/badges.js";
import { cleanupCohostEvents, setupCohostEvent } from "../../data-graphs/cohosts.js";
import { cleanupEventsByIds, setupLabeledSessionEvent } from "../../data-graphs/events.js";
import { cleanupTemporaryGroup, setupTemporaryGroup } from "../../data-graphs/groups.js";
import { cleanupInboxConversations, setupInboxConversation } from "../../data-graphs/inbox.js";
import {
  cleanupCommunityTeamInvitation,
  cleanupEventEnrollment,
  cleanupGroupTeamInvitation,
  setupCommunityTeamInvitation,
  setupEventInvitation,
  setupGroupTeamInvitation,
} from "../../data-graphs/invitations.js";
import {
  cleanupOwnedPaymentPurchase,
  setupEventDiscountCode,
  setupExhaustedFinancialWorkGraph,
  setupExhaustedRefundGraph,
} from "../../data-graphs/payments.js";
import { setupEventSessions } from "../../data-graphs/sessions.js";
import {
  TEST_EVENT_SURVEYS,
  cleanupEventSurveys,
  setupOwnedEventSurvey,
  setupOwnedSurveyEvent,
} from "../../data-graphs/surveys.js";
import { cleanupTemporaryUser, setupTemporaryUser } from "../../data-graphs/users.js";
import {
  TEST_COMMUNITY_IDS,
  TEST_EVENT_ANALYTICS,
  TEST_EVENT_CATEGORY_IDS,
  TEST_GROUP_IDS,
  TEST_INBOX_CONVERSATION,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_USER_IDS,
} from "../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../utils.js";
import { openDashboardView } from "../aria-helpers.js";
import {
  addDiscountCode,
  expectSessionLabelsFit,
  openCfsEventSubmissionsTab,
  openCurrentEventEditorSection,
  openEventUpdateFormByName,
  openPaymentsSection,
  showEventEditorSection,
} from "../group/events/helpers.js";

// Classic-scrollbar fit checks (plan §2.1): every case measures its view at the narrowest width of
// each band with a 15px scrollbar taking room from the page, as on Windows and Linux desktops.

// Subpixel rounding allowed when comparing edges.
const EDGE_TOLERANCE_PX = 0.5;

// Narrowest widths of the md, lg and xl bands, the 2xl return width and the review widths of the
// original notes.
const WIDTHS = {
  lg: 1024,
  lgReview: 1027,
  md: 768,
  mdReview: 771,
  xl: 1280,
  xlReview: 1373,
  xxl: 1536,
};

// Widths every case measures, plus the ones that also check 2xl returns or the review widths.
const PAGE_WIDTHS = [WIDTHS.md, WIDTHS.lg, WIDTHS.xl];
const PAGE_WIDTHS_2XL = [...PAGE_WIDTHS, WIDTHS.xxl];
const REVIEW_WIDTHS = [WIDTHS.md, WIDTHS.mdReview, WIDTHS.lg, WIDTHS.lgReview, WIDTHS.xl, WIDTHS.xlReview];

// Smallest width of a table's primary column at every width (fit criterion, plan §2.1).
const PRIMARY_COLUMN_MIN_PX = 160;

// D1 gate (user decision): the award Badge and Source columns keep this content width.
const AWARD_DETAIL_COLUMN_MIN_PX = 80;

// Content width the financial work Event column keeps from xl, where it gets its own column.
const FINANCIAL_EVENT_COLUMN_MIN_PX = 120;

// Viewport height used at every width.
const VIEWPORT_HEIGHT = 900;

// Table header and filter menu font sizes of `.dashboard-table-head` below xl and from xl.
const TABLE_HEAD_FONT_SIZE = { belowXl: "10.4px", xl: "12px" };

// Question option rows font sizes below lg and from lg (E6).
const OPTION_ROW_FONT_SIZE = { belowLg: "12px", lg: "14px" };

// Long data: 44-character names, 60-character titles and emails, 40-character discount codes.
const LONG_NAME_LENGTH = 44;
const LONG_TITLE_LENGTH = 60;
const LONG_DISCOUNT_CODE = "FIT".padEnd(40, "X");

// 44-character name with a fixed rendered width (323px in 12px Inter), for a truncation check whose
// box (298px) a random-suffix name can fit: its hex digits vary its width between ≈285 and ≈322px.
const WIDE_LONG_NAME = "E2E FIT SPEAKER MAXIMILIAN WOLFGANG ANDERSEN";

// Long revocation reason: prose plus one unbroken 60-character token.
const LONG_REVOCATION_REASON = [
  "The credential was issued to the wrong attendee after a check-in mix-up at the registration desk,",
  "so the organizers revoked it and asked the attendee to contact the team for a corrected award.",
  `Reference ${"responsive-fit-reference-".repeat(3)}`.padEnd(70, "x"),
  "Keep this note for the audit review at the end of the quarter.",
].join(" ");

// One case per dashboard view. `setup(owned)` seeds owned long data once, `open(page, data)`
// navigates once and returns the view: `regions` (key regions that must fit the client width),
// `wrappers` (table wrappers or containers that must not overflow), `show(width)` (re-shows a
// client-side editor section after a resize) and any locators `check(page, view, width)` uses.
// `openWidth` is the viewport used to open the view (default: the first width).
const FIT_CASES = [
  // User dashboard.
  {
    name: "user events",
    fixture: "emptyUserPage",
    widths: PAGE_WIDTHS,
    setup: (owned) => {
      const group = trackGroup(owned, {
        memberUserId: TEST_USER_IDS.empty,
        name: longText("E2E Fit events group", LONG_TITLE_LENGTH),
      });
      const event = owned.event({
        attendeeUserIds: [TEST_USER_IDS.empty],
        groupId: group.groupId,
        name: longText("E2E Fit attended event", LONG_TITLE_LENGTH),
        speakerUserIds: [TEST_USER_IDS.empty],
      });

      return { event };
    },
    open: async (page, { event }) => {
      const content = page.locator("#dashboard-content");
      const table = content.getByRole("table");
      await openDashboardView(page, "/dashboard/user?tab=events", { regions: [table] });
      const row = table.locator("tbody tr", { hasText: event.name });
      await expect(row).toBeVisible();

      return { regions: [table], row, wrappers: [table.locator("xpath=..")] };
    },
    check: async (page, { row }, width) => {
      const rowHeader = row.locator('th[scope="row"]');
      await expectMinWidth(rowHeader, PRIMARY_COLUMN_MIN_PX, "event row header");
      await expectInsideCell(row.locator(".custom-badge"), "role and status badges");
      await expectAbove(
        rowHeader.locator(".title-preheader"),
        rowHeader.locator("a").first(),
        "group preheader",
      );
      await annotateWidths("user events", width, {
        event: rowHeader,
        statusRole: row.locator("td").nth(2),
      });
    },
  },
  {
    name: "user groups",
    fixture: "emptyUserPage",
    widths: PAGE_WIDTHS,
    setup: (owned) => ({
      group: trackGroup(owned, {
        memberUserId: TEST_USER_IDS.empty,
        name: longText("E2E Fit member group", LONG_TITLE_LENGTH),
        teamRole: "viewer",
        teamUserId: TEST_USER_IDS.empty,
      }),
    }),
    open: async (page, { group }) => {
      const table = page.locator("#dashboard-content").getByRole("table");
      await openDashboardView(page, "/dashboard/user?tab=groups", { regions: [table] });
      const row = table.locator("tbody tr", { hasText: group.groupName });
      await expect(row).toBeVisible();

      return { regions: [table], row, table, wrappers: [table.locator("xpath=..")] };
    },
    check: async (page, { row, table }, width) => {
      const rowHeader = row.locator('th[scope="row"]');
      const memberSinceLine = rowHeader.getByText(/^\s*Member since/);
      await expectMinWidth(rowHeader, PRIMARY_COLUMN_MIN_PX, "group row header");
      await expectAbove(rowHeader.locator(".title-preheader"), rowHeader.locator("a"), "community preheader");

      // Member since moves from the group cell to its column at lg.
      const memberSinceHeader = table.locator("thead th", { hasText: "Member since" });
      if (width < WIDTHS.lg) {
        await expect(memberSinceLine).toBeVisible();
        await expect(memberSinceHeader).toBeHidden();
      } else {
        await expect(memberSinceLine).toBeHidden();
        await expect(memberSinceHeader).toBeVisible();
      }
    },
  },
  {
    name: "user inbox",
    fixture: "emptyUserPage",
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => {
      const group = trackGroup(owned, { name: longText("E2E Fit inbox group", LONG_TITLE_LENGTH) });
      const event = owned.event({
        groupId: group.groupId,
        name: longText("E2E Fit inbox event", LONG_TITLE_LENGTH),
      });
      const conversation = trackConversation(owned, {
        eventId: event.eventId,
        groupId: group.groupId,
        userId: TEST_USER_IDS.empty,
      });

      return { conversation, event };
    },
    open: (page, { event }) => openInboxList(page, "/dashboard/user?tab=inbox", event.name),
    check: async (page, { row }, width) => {
      await expectInboxStatusFit(row, width);
      const counterpart = row.locator('th[scope="row"]');
      await expectAbove(
        counterpart.locator(".title-preheader"),
        counterpart.locator(".truncate").last(),
        "community preheader",
      );
    },
  },
  {
    name: "user inbox conversation",
    fixture: "member2Page",
    widths: PAGE_WIDTHS,
    open: (page) =>
      openInboxConversation(page, `/dashboard/user?tab=inbox&conversation_id=${TEST_INBOX_CONVERSATION.id}`),
  },
  {
    name: "user invitations",
    fixture: "emptyUserPage",
    widths: PAGE_WIDTHS,
    setup: (owned) => {
      const group = trackGroup(owned, { name: longText("E2E Fit inviting group", LONG_TITLE_LENGTH) });
      // A paid ticket offer, so the Offer cell renders the price badge trigger.
      const event = owned.event({
        groupId: group.groupId,
        name: longText("E2E Fit invited event", LONG_TITLE_LENGTH),
        paymentCurrencyCode: "USD",
        tiers: [{ amountMinor: 5000, key: "general", seats: 10, title: "VIP pass" }],
      });
      const eventInvitation = { eventId: event.eventId, userId: TEST_USER_IDS.empty };
      setupEventInvitation(eventInvitation);
      owned.defer(() => cleanupEventEnrollment(eventInvitation));
      // The group invitation goes with the temporary group's team rows.
      setupGroupTeamInvitation({ groupId: group.groupId, role: "viewer", userId: TEST_USER_IDS.empty });
      const communityInvitation = { communityId: TEST_COMMUNITY_IDS.community1, userId: TEST_USER_IDS.empty };
      setupCommunityTeamInvitation({ ...communityInvitation, role: "viewer" });
      owned.defer(() => cleanupCommunityTeamInvitation(communityInvitation));

      return { event, group };
    },
    open: async (page, { event, group }) => {
      const content = page.locator("#dashboard-content");
      await openDashboardView(page, "/dashboard/user?tab=invitations");
      const eventRow = content.locator("tbody tr", { hasText: event.name });
      const groupRow = content
        .locator("tbody tr", { hasText: group.groupName })
        .filter({ hasNotText: event.name });
      await expect(eventRow).toBeVisible();
      await expect(groupRow).toBeVisible();

      return {
        eventRow,
        groupRow,
        regions: [content.getByRole("table").first()],
        wrappers: [content.getByRole("table").locator("xpath=..")],
      };
    },
    check: async (page, { eventRow, groupRow }, width) => {
      const eventCell = eventRow.locator("th, td").first();
      await expectMinWidth(eventCell, PRIMARY_COLUMN_MIN_PX, "event cell");
      await expectInsideCell(eventRow.locator(".custom-badge"), "offer badges");
      await expectAbove(
        eventCell.locator(".title-preheader"),
        eventCell.locator(".title-preheader + *"),
        "group preheader",
      );

      // Starts and Created move into the name cells below lg.
      const startsLine = eventCell.getByText(/^\s*Starts\b/);
      const createdLine = groupRow
        .locator("th, td")
        .first()
        .getByText(/^\s*Created\b/);
      if (width < WIDTHS.lg) {
        await expect(startsLine).toBeVisible();
        await expect(createdLine).toBeVisible();
      } else {
        await expect(startsLine).toBeHidden();
        await expect(createdLine).toBeHidden();
      }
      await annotateWidths("user invitations", width, {
        event: eventCell,
        offer: eventRow.locator("td").nth(1),
      });
    },
  },
  {
    name: "user logs",
    fixture: "member1Page",
    widths: REVIEW_WIDTHS,
    open: (page) => openAuditLogs(page, "/dashboard/user?tab=logs"),
    check: (page, view, width) => expectAuditLogsFit(page, view, width, "user logs"),
  },
  {
    name: "user purchases",
    fixture: "adminCommunityPage",
    widths: [...REVIEW_WIDTHS, WIDTHS.xxl],
    open: async (page) => {
      const content = page.locator("#dashboard-content");
      const table = content.getByRole("table");
      await openDashboardView(page, "/dashboard/user?tab=purchases", { regions: [table] });
      const canceledRow = table.locator("tbody tr", { hasText: "Canceled Public Event" });
      await expect(canceledRow).toBeVisible();

      return { canceledRow, content, regions: [table], table, wrappers: [content] };
    },
    check: async (page, { canceledRow, table }, width) => {
      for (const rowHeader of await table.locator('tbody th[scope="row"]').all()) {
        await expectMinWidth(rowHeader, PRIMARY_COLUMN_MIN_PX, "purchase row header");
      }
      await expectInsideCell(canceledRow.locator(".custom-badge"), "canceled purchase badges");
      if (width >= WIDTHS.xxl) {
        await expectSameRow(canceledRow.locator(".custom-badge"), "canceled purchase badges");
      }
    },
  },
  {
    name: "user session proposals",
    fixture: "pending2Page",
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => {
      const coSpeaker = trackUser(owned, "fit-co-speaker");
      const invitation = owned.sessionProposal({
        coSpeakerUserId: TEST_USER_IDS.pending2,
        title: longText("E2E Fit co-speaker invite", LONG_TITLE_LENGTH),
        userId: coSpeaker.userId,
      });
      const ownProposal = owned.sessionProposal({
        coSpeakerUserId: coSpeaker.userId,
        title: longText("E2E Fit own proposal", LONG_TITLE_LENGTH),
        userId: TEST_USER_IDS.pending2,
      });

      return { coSpeaker, invitation, ownProposal };
    },
    open: async (page, { coSpeaker, invitation, ownProposal }) => {
      const content = page.locator("#dashboard-content");
      await openDashboardView(page, "/dashboard/user?tab=session-proposals");
      const invitationRow = content.locator("tbody tr", { hasText: invitation.title });
      const proposalRow = content.locator("tbody tr", { hasText: ownProposal.title });
      await expect(invitationRow).toBeVisible();
      await expect(proposalRow).toBeVisible();

      return {
        coSpeaker,
        invitationRow,
        proposalRow,
        regions: [content.getByRole("table").first(), content.getByRole("table").last()],
        wrappers: [content.getByRole("table").locator("xpath=..")],
      };
    },
    check: async (page, { coSpeaker, invitationRow, proposalRow }, width) => {
      // The inviter name truncates instead of widening the invitations table.
      await expectInsideCell(invitationRow.getByRole("button"), "invitation actions");
      const inviterName = invitationRow.locator("td").nth(1).locator(".truncate");
      if (width === WIDTHS.md) {
        await expectTruncated(inviterName, "inviter name");
      }

      // The co-speaker shows under the proposal below xl and in its column from xl.
      const proposalCell = proposalRow.locator("td").first();
      const withLine = proposalCell.getByText(`with ${coSpeaker.name}`);
      if (width < WIDTHS.xl) {
        await expect(withLine).toBeVisible();
        await expectInsideCell(withLine, "co-speaker line");
      } else {
        await expect(withLine).toBeHidden();
        await expectMinWidth(proposalCell, PRIMARY_COLUMN_MIN_PX, "proposal cell");
        await expectMaxWidth(proposalRow.locator("td").nth(1).locator(".max-w-48"), 192, "co-speaker name");
      }
      const statusBadge = proposalRow
        .locator('.custom-badge:has(> [aria-hidden="true"])')
        .filter({ visible: true });
      await expectCompactStatusLabel(statusBadge, width, "proposal status badge");
      await expectSingleLine(proposalRow.locator(".custom-badge").filter({ visible: true }), "status badge");
      await annotateWidths("user session proposals", width, {
        invitedBy: invitationRow.locator("td").nth(1),
        invitationActions: invitationRow.locator("td").last(),
        invitationProposal: invitationRow.locator("td").first(),
        proposal: proposalCell,
      });
    },
  },
  {
    name: "user submissions",
    fixture: "member1Page",
    widths: PAGE_WIDTHS,
    open: async (page) => {
      const table = page.locator("#dashboard-content").getByRole("table");
      await openDashboardView(page, "/dashboard/user?tab=submissions", { regions: [table] });
      const row = table.locator("tr", { hasText: "Observability in Practice" });
      const labelsRow = table.locator("tr", { hasText: "Scaling Community Workshops" });
      await expect(row).toBeVisible();

      return { labelsRow, regions: [table], row, wrappers: [table.locator("xpath=..")] };
    },
    check: async (page, { labelsRow, row }, width) => {
      const labelsTrigger = labelsRow.getByRole("button", { exact: true, name: "2 labels" });
      if (width >= WIDTHS.xl) {
        await expect(labelsTrigger).toBeHidden();
        return;
      }

      // fG6: the compact status and the info button stay inside the Proposal cell, clear of the actions.
      const proposalCell = row.locator("td").nth(1);
      // The cell also shows the session kind chip, so pick the status badge by its full label.
      const statusBadge = proposalCell
        .locator(".custom-badge")
        .filter({ hasText: "Information requested", visible: true });
      const infoButton = row
        .getByRole("button", { name: "View action required details" })
        .filter({ visible: true });
      await expect(statusBadge.locator('[aria-hidden="true"]')).toHaveText("Info requested");
      await expect(statusBadge).toContainText("Information requested");
      await expectCompactStatusLabel(statusBadge, width, "submission status badge");
      await expectInsideCell(statusBadge, "compact status badge");
      await expectInsideCell(infoButton, "action required info button");
      await expectApart(
        statusBadge,
        row.locator("td").last().getByRole("button"),
        "status badge and actions",
      );
      await expectApart(infoButton, row.locator("td").last().getByRole("button"), "info button and actions");
      const { actionsLeft, contentRight } = await row.evaluate((tableRow) => {
        const cells = tableRow.querySelectorAll(":scope > td");
        const rights = [...cells[1].querySelectorAll("*")]
          .filter(
            (element) =>
              element.checkVisibility({ visibilityProperty: true }) &&
              !element.closest("[data-tooltip-panel]"),
          )
          .map((element) => element.getBoundingClientRect().right);

        return {
          actionsLeft: cells[cells.length - 1].getBoundingClientRect().left,
          contentRight: Math.max(...rights),
        };
      });
      expect(contentRight, "proposal content ends before the actions cell").toBeLessThanOrEqual(
        actionsLeft + EDGE_TOLERANCE_PX,
      );

      // Two labels collapse into a tooltip trigger below xl.
      await expect(labelsTrigger).toBeVisible();
      await expect(labelsTrigger).toHaveAttribute(
        "aria-describedby",
        "user-submission-labels-99999999-9999-9999-9999-999999999913",
      );
    },
  },
  {
    name: "user surveys",
    fixture: "emptyUserPage",
    widths: [WIDTHS.md, WIDTHS.mdReview, WIDTHS.lg, WIDTHS.lgReview, WIDTHS.xl, WIDTHS.xlReview],
    setup: (owned) => {
      const event = owned.track(
        setupOwnedSurveyEvent({
          attendeeUserIds: [TEST_USER_IDS.empty],
          name: longText("E2E Fit survey event", LONG_TITLE_LENGTH),
        }),
        ({ id }) => cleanupEventsByIds([id]),
      );
      const survey = setupOwnedEventSurvey({
        eventId: event.id,
        status: "ready",
        title: longText("E2E Fit survey title", LONG_TITLE_LENGTH),
      });

      return { survey };
    },
    open: async (page, { survey }) => {
      const content = page.locator("#dashboard-content");
      const table = content.getByRole("table");
      await openDashboardView(page, "/dashboard/user?tab=surveys", { regions: [table] });
      const row = table.locator(`[data-user-event-survey="${survey.id}"]`);
      await expect(row).toBeVisible();

      return { regions: [table], row, wrappers: [content] };
    },
    check: async (page, { row }, width) => {
      const rowHeader = row.locator('th[scope="row"]');
      await expectMinWidth(rowHeader, PRIMARY_COLUMN_MIN_PX, "survey row header");
      await expectInsideCell(row.locator("td").last().getByRole("button"), "survey action");
      await expectAbove(
        rowHeader.locator(".title-preheader"),
        rowHeader.locator(".title-preheader + div"),
        "event preheader",
      );
      if (width >= WIDTHS.xl) {
        const closingCell = row.locator("td").nth(1);
        await expect(closingCell).toHaveCSS("white-space", "nowrap");
      }
      await annotateWidths("user surveys", width, { survey: rowHeader });
    },
  },

  // Community dashboard.
  {
    name: "community analytics",
    fixture: "adminCommunityPage",
    widths: [...REVIEW_WIDTHS, 1279, WIDTHS.xxl].sort((a, b) => a - b),
    open: async (page) => {
      const tabList = page.getByRole("tablist", { name: "Analytics tabs" });
      await openDashboardView(page, "/dashboard/community?tab=analytics", { regions: [tabList] });

      // The last tab is the rightmost one, the most likely to be clipped or scrolled.
      await tabList.getByRole("tab", { name: "Page views" }).click();
      await expect(tabList.getByRole("tab", { name: "Page views" })).toHaveAttribute("aria-selected", "true");

      return { regions: [], tabList, tabListWrapper: tabList.locator("xpath=..") };
    },
    check: async (page, { tabList, tabListWrapper }, width) => {
      const activeCard = page.locator('[data-analytics-summary] [data-analytics-tab][data-active="true"]');
      if (width < WIDTHS.xl) {
        await expectFitsClientWidth(page, [tabListWrapper]);
        await expectNoHorizontalOverflow(tabListWrapper);
        const fit = await tabListWrapper.evaluate((wrapper) => {
          const activeTab = wrapper.querySelector('[data-active="true"]');
          const box = wrapper.getBoundingClientRect();

          return {
            activeBottom: activeTab.getBoundingClientRect().bottom,
            clientBottom: box.top + wrapper.clientTop + wrapper.clientHeight,
            clientHeight: wrapper.clientHeight,
            listWidth: wrapper.firstElementChild.getBoundingClientRect().width,
            scrollHeight: wrapper.scrollHeight,
          };
        });
        expect(fit.scrollHeight, "the tab bar has no inner vertical scroll").toBeLessThanOrEqual(
          fit.clientHeight,
        );
        expect(fit.activeBottom, "the active tab underline is not clipped").toBeLessThanOrEqual(
          fit.clientBottom + EDGE_TOLERANCE_PX,
        );
        recordMeasurement(`community analytics tab bar at ${width}px: ul ${fit.listWidth}px`);
        return;
      }

      // From xl the summary cards are the tabs; their peak arrow shows only from 2xl.
      await expect(tabList).toBeHidden();
      await expect(activeCard.locator("span.tab-peak")).toHaveCSS(
        "display",
        width >= WIDTHS.xxl ? "block" : "none",
      );
    },
  },
  {
    name: "community contact",
    fixture: "adminCommunityPage",
    widths: REVIEW_WIDTHS,
    open: async (page) => {
      const form = page.locator("#community-contact-form");
      await openDashboardView(page, "/dashboard/community?tab=contact", { regions: [form] });

      return {
        regions: [form],
        wrappers: [page.locator("#community-contact-filters"), page.locator("#community-contact-summary")],
      };
    },
  },
  {
    name: "community groups",
    fixture: "adminCommunityPage",
    widths: [...REVIEW_WIDTHS, WIDTHS.xxl],
    setup: (owned) => ({
      group: trackGroup(owned, {
        active: false,
        name: longText("E2E Fit inactive group", LONG_TITLE_LENGTH),
      }),
    }),
    open: async (page, { group }) => {
      const table = page.locator("#dashboard-content").getByRole("table");
      await openDashboardView(page, "/dashboard/community?tab=groups", { regions: [table] });
      const row = table.locator("tbody tr", { hasText: group.groupName });
      await expect(row).toBeVisible();

      return { regions: [table], row, wrappers: [table.locator("xpath=..")] };
    },
    check: async (page, { row }, width) => {
      const rowHeader = row.locator('th[scope="row"]');
      const preheader = rowHeader.locator(".title-preheader");
      const nameButton = rowHeader.getByRole("button", { name: /^Open group dashboard:/ });
      await expectMinWidth(rowHeader, PRIMARY_COLUMN_MIN_PX, "group row header");
      await expectInsideCell(rowHeader.getByText("Inactive", { exact: true }), "inactive badge");
      if (width < WIDTHS.xl) {
        await expect(preheader).toBeVisible();
        await expectAbove(preheader, nameButton, "category preheader");
      } else {
        await expect(preheader).toBeHidden();
      }
      await annotateWidths("community groups", width, { name: nameButton, rowHeader });
    },
  },
  {
    name: "community logs",
    fixture: "adminCommunityPage",
    widths: REVIEW_WIDTHS,
    open: (page) => openAuditLogs(page, "/dashboard/community?tab=logs"),
    check: (page, view, width) => expectAuditLogsFit(page, view, width, "community logs"),
  },
  {
    name: "community settings",
    fixture: "adminCommunityPage",
    widths: REVIEW_WIDTHS,
    open: async (page) => {
      const galleryField = page.locator('gallery-field[field-name="photos_urls"]');
      await openDashboardView(page, "/dashboard/community?tab=settings", { regions: [galleryField] });

      return {
        galleryGrid: galleryField.locator("div.grid").first(),
        regions: [galleryField],
        toggleTrack: page.locator("label:has(#toggle_group_team_management_restricted) .toggle-track"),
      };
    },
    check: async (page, { galleryGrid, toggleTrack }, width) => {
      await expectNoHorizontalOverflow(galleryGrid);
      if (width < WIDTHS.lg) {
        await expectMinWidth(toggleTrack, 44, "toggle track");
        await expectMaxWidth(toggleTrack, 44, "toggle track");
      }
      if ([WIDTHS.md, WIDTHS.lg].includes(width)) {
        await expectMinWidth(galleryGrid.locator(":scope > div").first(), 128, "gallery tile");
      }
      await annotateWidths("community settings", width, {
        galleryTile: galleryGrid.locator(":scope > div").first(),
        toggleTrack,
      });
    },
  },
  {
    name: "community team",
    fixture: "adminCommunityPage",
    widths: [...REVIEW_WIDTHS, WIDTHS.xxl],
    setup: (owned) => {
      const member = trackUser(owned, "fit-community-team");
      const invitation = { communityId: TEST_COMMUNITY_IDS.community1, userId: member.userId };
      setupCommunityTeamInvitation({ ...invitation, role: "viewer" });
      owned.defer(() => cleanupCommunityTeamInvitation(invitation));

      return { member };
    },
    open: (page, { member }) => openTeamList(page, "/dashboard/community?tab=team", member.name),
    check: (page, view, width) => expectTeamFit(view, width, "community team"),
  },

  // Group dashboard.
  {
    name: "group analytics",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    open: async (page) => {
      await openDashboardView(page, "/dashboard/group?tab=analytics");

      return { regions: [] };
    },
  },
  {
    name: "group awards",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    setup: (owned) => {
      const groupId = TEST_GROUP_IDS.community1.alpha;
      const recipient = trackUser(owned, "fit-awards");
      const event = owned.event({ groupId, name: longText("E2E Fit award event", LONG_TITLE_LENGTH) });
      const badge = owned.track(
        setupBadgeDefinition({ groupId, name: longText("E2E Fit badge", LONG_NAME_LENGTH) }),
        cleanupBadgeDefinition,
      );
      const credentialInput = {
        badgeId: badge.badgeId,
        eventId: event.eventId,
        groupId,
        userId: recipient.userId,
      };
      const revoked = owned.track(setupRevocableCredential(credentialInput), cleanupCredential);
      setupCredentialRevocation({ reason: LONG_REVOCATION_REASON, userBadgeId: revoked.userBadgeId });
      const active = owned.track(setupRevocableCredential(credentialInput), cleanupCredential);

      return { active, badge, revoked };
    },
    open: async (page, { badge }) => {
      const table = page.getByRole("table", { name: "Awards list" });
      await openDashboardView(
        page,
        `/dashboard/group?tab=awards&awards_query=${encodeURIComponent(badge.badgeName)}`,
        {
          regions: [table],
        },
      );
      await expect(table.locator("tbody tr")).toHaveCount(2);

      return {
        regions: [table],
        revokedRow: table.locator("tbody tr").filter({ hasText: "registration desk" }),
        rows: table.locator("tbody tr"),
        wrappers: [table.locator("xpath=..")],
      };
    },
    check: async (page, { revokedRow, rows }, width) => {
      for (const row of await rows.all()) {
        const cells = row.locator("td");
        await expectTruncated(cells.nth(0).locator(".truncate"), "recipient name");
        await expectTruncated(cells.nth(1).locator(".truncate").first(), "badge name");
        await expectInsideCell(row.locator(".truncate").filter({ visible: true }), "truncated award details");
        await expectContentWidth(cells.nth(1), AWARD_DETAIL_COLUMN_MIN_PX, "badge column content");
        if (width >= WIDTHS.xl) {
          await expectTruncated(cells.nth(2).locator(".truncate"), "award source");
          await expectContentWidth(cells.nth(2), AWARD_DETAIL_COLUMN_MIN_PX, "source column content");
        } else {
          // From xl the status is plain text; below xl it is a badge.
          await expectInsideCell(
            row.locator(".custom-badge").filter({ visible: true }),
            "award status badge",
          );
          await expect(cells.nth(1).getByText(/^\s*Awarded \d{4}-\d{2}-\d{2} ·/)).toBeVisible();
        }
      }

      // Revocation details sit in a tooltip trigger below xl.
      if (width < WIDTHS.xl) {
        await expect(revokedRow.getByRole("button", { exact: true, name: "Revoked" })).toBeVisible();
      }

      // D1 gate: the recipient keeps the primary column floor at xl; record every column width.
      const cells = revokedRow.locator("td");
      const widths = await annotateWidths("group awards", width, {
        actions: cells.nth(5),
        awarded: cells.nth(3),
        badge: cells.nth(1),
        recipient: cells.nth(0),
        source: cells.nth(2),
        status: cells.nth(4),
      });
      if (width >= WIDTHS.xl) {
        expect(widths.recipient, "D1 gate: recipient column width at xl").toBeGreaterThanOrEqual(
          PRIMARY_COLUMN_MIN_PX,
        );
      }
    },
  },
  {
    name: "group cohosts",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => {
      const ownerGroup = trackGroup(owned, { name: longText("E2E Fit owner group", LONG_TITLE_LENGTH) });
      const trackCohostEvent = (published) =>
        owned.track(
          setupCohostEvent({
            categoryId: TEST_EVENT_CATEGORY_IDS.general,
            cohosts: [{ groupId: TEST_GROUP_IDS.community1.alpha, status: "pending" }],
            name: longText("E2E Fit co-hosted event", LONG_TITLE_LENGTH),
            ownerGroupId: ownerGroup.groupId,
            published,
          }),
          ({ eventId }) => cleanupCohostEvents([eventId]),
        );
      // Only an unpublished pending invitation can be answered, so only that one shows the actions menu.
      const event = trackCohostEvent(true);
      const respondableEvent = trackCohostEvent(false);

      return { event, ownerGroup, respondableEvent };
    },
    open: async (page, { event, respondableEvent }) => {
      const table = page.getByRole("table", { name: "Co-hosted events list" });
      await openDashboardView(page, "/dashboard/group?tab=cohosts", { regions: [table] });
      const row = table.locator("tbody tr", { hasText: event.name });
      const respondableRow = table.locator("tbody tr", { hasText: respondableEvent.name });
      await expect(row).toBeVisible();
      await expect(respondableRow).toBeVisible();

      return { regions: [table], respondableRow, row, wrappers: [table.locator("xpath=..")] };
    },
    check: async (page, { respondableRow, row }, width) => {
      const rowHeader = row.locator('th[scope="row"]');
      await expectMinWidth(rowHeader, PRIMARY_COLUMN_MIN_PX, "event row header");
      // The long event name truncates in the narrowest band (from 1024 the column can show it whole).
      if (width === WIDTHS.md) {
        await expectTruncated(rowHeader.locator(".truncate").first(), "event name");
      }
      await expectInsideCell(
        row.locator(".truncate, .custom-badge").filter({ visible: true }),
        "row details",
      );
      if (width < WIDTHS.xl) {
        await expectTruncated(rowHeader.locator(".title-preheader"), "owner preheader");
      } else {
        await expect(rowHeader.locator(".title-preheader")).toBeHidden();
        await expectTruncated(row.locator("td").first().locator(".truncate").first(), "owning group");
      }
      await expectInsideViewport(page, respondableRow.locator("summary"), "co-host actions trigger");
      await annotateWidths("group cohosts", width, { event: rowHeader });
    },
  },
  {
    name: "group events list",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => ({
      event: owned.event({
        attendeeUserIds: [TEST_USER_IDS.member1],
        capacity: 120,
        groupId: TEST_GROUP_IDS.community1.alpha,
        name: longText("E2E Fit listed event", LONG_TITLE_LENGTH),
      }),
    }),
    open: async (page, { event }) => {
      const table = page.getByRole("table", { name: "Upcoming events list" });
      await openDashboardView(page, "/dashboard/group?tab=events&events_tab=upcoming&limit=100", {
        regions: [table],
      });
      const row = table.locator("tbody tr", { hasText: event.name });
      await expect(row).toBeVisible();

      return { regions: [table], row, wrappers: [table.locator("xpath=..")] };
    },
    check: async (page, { row }, width) => {
      const rowHeader = row.locator('th[scope="row"]');
      await expectMinWidth(rowHeader, PRIMARY_COLUMN_MIN_PX, "name row header");
      await expectInsideCell(
        rowHeader.locator(".truncate").filter({ visible: true }),
        "name and mobile details",
      );
      await expectMinWidth(row.locator("td").last(), 152 - EDGE_TOLERANCE_PX, "actions cell");

      // D11: no visible sibling wraps or collapses next to the `w-full max-w-0` name.
      const siblings = await row.evaluate((tableRow) => {
        const names = ["location", "date", "type", "status", "attendees", "actions"];

        return [...tableRow.querySelectorAll(":scope > td")].flatMap((cell, index) => {
          if (!cell.checkVisibility()) {
            return [];
          }
          const minWidth = Number.parseFloat(getComputedStyle(cell).minWidth) || 0;
          const width = cell.getBoundingClientRect().width;
          let wraps = false;
          const walker = document.createTreeWalker(cell, NodeFilter.SHOW_TEXT);
          while (walker.nextNode()) {
            const node = walker.currentNode;
            if (node.textContent.trim() === "" || !node.parentElement.checkVisibility()) {
              continue;
            }
            const range = document.createRange();
            range.selectNodeContents(node);
            const tops = new Set(
              [...range.getClientRects()]
                .filter((rect) => rect.width > 0)
                .map((rect) => Math.round(rect.top)),
            );
            wraps ||= tops.size > 1;
          }

          return [
            {
              collapsed: width < minWidth - 0.5 || cell.scrollWidth > cell.clientWidth,
              minWidth,
              name: names[index],
              width: Math.round(width * 10) / 10,
              wraps,
            },
          ];
        });
      });
      const nameWidth = (await rowHeader.boundingBox()).width;
      recordMeasurement(
        `group events list at ${width}px: name ${Math.round(nameWidth)}px, ${siblings
          .map(({ name, width: cellWidth }) => `${name} ${cellWidth}px`)
          .join(", ")}`,
      );
      for (const sibling of siblings) {
        expect(sibling.wraps, `${sibling.name} column wraps at ${width}px`).toBe(false);
        expect(sibling.collapsed, `${sibling.name} column collapses at ${width}px (${sibling.width}px)`).toBe(
          false,
        );
      }
      await expectInsideCell(
        row.locator("td .custom-badge").filter({ visible: true }),
        "type and status badges",
      );
    },
  },
  {
    name: "group inbox",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => {
      const user = trackUser(owned, "fit-inbox");
      const event = owned.event({
        groupId: TEST_GROUP_IDS.community1.alpha,
        name: longText("E2E Fit inbox event", LONG_TITLE_LENGTH),
      });
      trackConversation(owned, {
        eventId: event.eventId,
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: user.userId,
      });

      return { event };
    },
    open: (page, { event }) => openInboxList(page, "/dashboard/group?tab=inbox", event.name),
    check: async (page, { row, table }, width) => {
      await expectInboxStatusFit(row, width);

      // Table header typography: 10.4px below xl, 12px from xl, filter menus included.
      if ([WIDTHS.lg, WIDTHS.xl].includes(width)) {
        const fontSize = width >= WIDTHS.xl ? TABLE_HEAD_FONT_SIZE.xl : TABLE_HEAD_FONT_SIZE.belowXl;
        await expect(table.locator("thead th").first()).toHaveCSS("font-size", fontSize);
        await expect(table.locator("thead summary")).toHaveCSS("font-size", fontSize);
      }
    },
  },
  {
    name: "group inbox conversation",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    open: (page) =>
      openInboxConversation(page, `/dashboard/group?tab=inbox&conversation_id=${TEST_INBOX_CONVERSATION.id}`),
    check: async (page, { conversation }, width) => {
      if (width !== WIDTHS.md) {
        return;
      }

      // D4: the header actions don't cover the status badge at md.
      const statusBadge = conversation.locator(".custom-badge").first();
      await expectApart(
        statusBadge,
        conversation.locator("#inbox-close-button, #inbox-mark-spam-button"),
        "header actions",
      );
    },
  },
  {
    name: "group logs",
    fixture: "organizerGroupPage",
    widths: REVIEW_WIDTHS,
    open: (page) => openAuditLogs(page, "/dashboard/group?tab=logs"),
    check: (page, view, width) => expectAuditLogsFit(page, view, width, "group logs"),
  },
  {
    name: "group members",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    open: (page) => openGroupTable(page, "/dashboard/group?tab=members"),
  },
  {
    name: "group refunds",
    fixture: "organizerGroupPage",
    widths: [...REVIEW_WIDTHS, WIDTHS.xxl],
    setup: (owned) => {
      const event = owned.event({
        groupId: TEST_GROUP_IDS.community1.alpha,
        name: longText("E2E Fit refunds event", LONG_TITLE_LENGTH),
        paymentCurrencyCode: "USD",
        tiers: [{ amountMinor: 5000, key: "general", seats: 10, title: "VIP pass" }],
      });
      const refundUser = trackUser(owned, "fit-refund", { longEmail: true });
      const financialUser = trackUser(owned, "fit-financial", { longEmail: true });
      for (const user of [refundUser, financialUser]) {
        owned.defer(() => cleanupOwnedPaymentPurchase({ eventId: event.eventId, userId: user.userId }));
      }
      setupExhaustedRefundGraph({ eventId: event.eventId, userId: refundUser.userId });
      setupExhaustedFinancialWorkGraph({ eventId: event.eventId, userId: financialUser.userId });

      return { financialUser, refundUser };
    },
    open: async (page, { financialUser, refundUser }) => {
      const refundsTable = page.getByRole("table", { name: "Refunds list" });
      const financialTable = page.getByRole("table", { name: "Financial work needing attention" });
      await openDashboardView(page, "/dashboard/group?tab=refunds&view=attention&limit=20", {
        regions: [refundsTable, financialTable],
      });
      const refundRow = refundsTable.locator("tbody tr", { hasText: refundUser.name });
      const financialRow = financialTable.locator("tbody tr", { hasText: financialUser.name });
      await expect(refundRow).toBeVisible();
      await expect(financialRow).toBeVisible();

      return {
        financialRow,
        refundRow,
        regions: [refundsTable, financialTable],
        wrappers: [refundsTable.locator("xpath=.."), financialTable.locator("xpath=..")],
      };
    },
    check: async (page, { financialRow, refundRow }, width) => {
      // The attempts badge ends before the actions of the main list.
      const attemptsBadge = refundRow
        .locator(".custom-badge")
        .filter({ hasText: "attempts" })
        .filter({ visible: true });
      await expectInsideCell(attemptsBadge, "attempts badge");
      await expectApart(attemptsBadge.first(), refundRow.locator("td").last(), "attempts badge and actions");

      // No financial work cell spills its content, and from xl the Event column keeps a readable share.
      await expectCellsContainContent(financialRow, "financial work row");
      if (width >= WIDTHS.xl) {
        await expectContentWidth(
          financialRow.locator("td").nth(1),
          FINANCIAL_EVENT_COLUMN_MIN_PX,
          "financial work event column content",
        );
      }

      // The w-80 failure tooltip is not clipped by the table wrapper.
      if ([WIDTHS.md, WIDTHS.xl].includes(width)) {
        const trigger = financialRow.getByRole("button", { name: /Needs retry: view last failure for/ });
        await trigger.focus();
        const tooltip = financialRow.getByRole("tooltip");
        await expect(tooltip).toBeVisible();
        await expectInsideViewport(page, tooltip, "financial failure tooltip");
        await trigger.blur();
        await expect(tooltip).toBeHidden();
      }
      await annotateWidths("group refunds", width, {
        financialAmount: financialRow.locator("td").nth(2),
        financialAttendee: financialRow.locator("td").nth(0),
        financialEvent: financialRow.locator("td").nth(1),
        financialStatus: financialRow.locator("td").nth(4),
        refund: refundRow.locator("td").nth(2),
      });
    },
  },
  {
    name: "group sponsors",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    open: (page) => openGroupTable(page, "/dashboard/group?tab=sponsors"),
  },
  {
    name: "group team",
    fixture: "organizerGroupPage",
    widths: [...REVIEW_WIDTHS, WIDTHS.xxl],
    setup: (owned) => {
      const member = trackUser(owned, "fit-group-team");
      const invitation = { groupId: TEST_GROUP_IDS.community1.alpha, userId: member.userId };
      setupGroupTeamInvitation({ ...invitation, role: "viewer" });
      owned.defer(() => cleanupGroupTeamInvitation(invitation));

      return { member };
    },
    open: (page, { member }) => openTeamList(page, "/dashboard/group?tab=team", member.name),
    check: (page, view, width) => expectTeamFit(view, width, "group team"),
  },

  // Group events tab: the event editor body is ≈639px at 1280 with the classic scrollbar.
  {
    name: "event editor analytics",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    setup: (owned) => {
      const event = owned.event({
        groupId: TEST_GROUP_IDS.community1.alpha,
        name: longText("E2E Fit analytics event", LONG_TITLE_LENGTH),
        paymentCurrencyCode: "USD",
        publishedAgo: "10 days",
        startsIn: "-3 days",
        tiers: [{ amountMinor: 5000, key: "general", seats: 10, title: "VIP pass" }],
      });
      owned.defer(() => cleanupEventUtmViews(event.eventId));
      setupEventUtmViews({
        eventId: event.eventId,
        rows: ["a", "b", "c"].map((variant, index) => ({
          campaign: `fit-campaign-${variant}-`.padEnd(50, "c"),
          medium: `fit-medium-${variant}-`.padEnd(50, "m"),
          source: `fit-source-${variant}-`.padEnd(50, "s"),
          total: 5 + index * 5,
        })),
      });
      setupEventDiscountCode({
        active: false,
        code: LONG_DISCOUNT_CODE,
        eventId: event.eventId,
        title: "Responsive fit inactive discount",
      });

      return { event };
    },
    open: async (page, { event }) => {
      const content = await openAnalyticsSection(page, event.name, event.eventId);
      const utmTable = content.locator("table[data-utm-combinations]");
      const discountTable = content.locator("table", {
        has: page.locator("caption", { hasText: "Redemptions count purchases" }),
      });
      await expect(utmTable).toBeVisible();
      await expect(discountTable).toBeVisible();

      return {
        discountTable,
        regions: [content],
        show: () => waitForChartsToFit(content),
        wrappers: [utmTable.locator("xpath=.."), discountTable.locator("xpath=..")],
      };
    },
    check: async (page, { discountTable }) => {
      await expectSingleLine(discountTable.getByText("(inactive)"), "inactive discount marker");
    },
  },
  {
    name: "event editor analytics question options",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    open: async (page) => {
      const content = await openAnalyticsSection(
        page,
        TEST_EVENT_ANALYTICS.pastPaid.name,
        TEST_EVENT_ANALYTICS.pastPaid.id,
      );

      return {
        optionRow: content
          .locator('ul[id^="event-analytics-question-"][id$="-options"] > li > div:first-child')
          .first(),
        regions: [content],
        show: () => waitForChartsToFit(content),
      };
    },
    check: async (page, { optionRow }, width) => {
      await expect(optionRow).toHaveCSS(
        "font-size",
        width >= WIDTHS.lg ? OPTION_ROW_FONT_SIZE.lg : OPTION_ROW_FONT_SIZE.belowLg,
      );
    },
  },
  {
    name: "event editor attendees",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => {
      const attendee = trackUser(owned, "fit-attendee", { longEmail: true });
      const event = owned.event({
        attendeeUserIds: [attendee.userId],
        groupId: TEST_GROUP_IDS.community1.alpha,
        name: longText("E2E Fit attendees event", LONG_TITLE_LENGTH),
      });

      return { attendee, event };
    },
    open: async (page, { attendee, event }) => {
      await openEventUpdateFormByName(page, event.name, event.eventId);
      const content = await openCurrentEventEditorSection(
        page,
        event.eventId,
        "attendees",
        "#attendees-content",
        {
          tableName: "Attendees list",
        },
      );
      const table = content.getByRole("table", { name: "Attendees list" });
      const row = table.locator("tbody tr", { hasText: attendee.name });
      await expect(row).toBeVisible();

      return {
        regions: [content],
        row,
        show: () => waitForChartsToFit(content),
        wrappers: [table.locator("xpath=..")],
      };
    },
    check: async (page, { row }, width) => {
      if (width >= WIDTHS.lg) {
        return;
      }

      // E5: the compact ticket and status block starts at the attendee cell content edge.
      const offset = await row.locator("div.mt-2.min-w-0.lg\\:hidden").evaluate((block) => {
        const cell = block.closest("td");
        const contentLeft =
          cell.getBoundingClientRect().left + Number.parseFloat(getComputedStyle(cell).paddingLeft);

        return {
          offset: block.getBoundingClientRect().left - contentLeft,
          width: block.getBoundingClientRect().width,
        };
      });
      expect(Math.abs(offset.offset), "compact block starts at the cell content edge").toBeLessThanOrEqual(
        EDGE_TOLERANCE_PX,
      );
      recordMeasurement(`event editor attendees at ${width}px: compact block ${offset.width}px`);
    },
  },
  {
    name: "event editor contributors",
    fixture: "organizerGroupPage",
    openWidth: WIDTHS.xl,
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => {
      // The fixed-width name keeps the 768 truncation check independent of the random suffix.
      const speaker = trackUser(owned, "fit-speaker", { name: WIDE_LONG_NAME });
      const event = owned.event({
        groupId: TEST_GROUP_IDS.community1.alpha,
        name: longText("E2E Fit speakers event", LONG_TITLE_LENGTH),
        speakerUserIds: [speaker.userId],
      });
      setupEventSessions({
        eventId: event.eventId,
        sessions: [
          ...["one", "two", "three"].map((index) => ({
            featured: true,
            name: `Responsive fit session ${index} with a long name`.padEnd(40, ".").slice(0, 40),
            speakerUserIds: [speaker.userId],
          })),
          {
            name: `https://example.com/${"responsive-fit-".repeat(3)}`.padEnd(60, "x").slice(0, 60),
            speakerUserIds: [speaker.userId],
          },
        ],
      });

      return { event, speaker };
    },
    open: async (page, { event, speaker }) => {
      await openEventUpdateFormByName(page, event.name, event.eventId);
      await showEventEditorSection(page, "contributors");
      const content = page.locator('[data-content="contributors"]');
      const speakersTable = content.getByRole("table", { name: "Event speakers" });
      const sessionSpeakersTable = content.getByRole("table", { name: "Session-level speakers" });
      await expect(speakersTable.locator("tbody tr", { hasText: speaker.name })).toBeVisible();

      return {
        regions: [content],
        sessionSpeakerRow: sessionSpeakersTable.locator("tbody tr", { hasText: speaker.name }),
        sessionSpeakersTable,
        show: () => showEventEditorSection(page, "contributors"),
        speakerRow: speakersTable.locator("tbody tr", { hasText: speaker.name }),
        speakersTable,
        wrappers: [content.locator("table").locator("xpath=..")],
      };
    },
    check: async (page, { sessionSpeakerRow, sessionSpeakersTable, speakerRow, speakersTable }, width) => {
      for (const row of [speakerRow, sessionSpeakerRow]) {
        // The long name stays on one line inside its cell, and truncates at the narrowest editor
        // width (from 1024 the event speakers name column is wide enough to show it whole).
        const name = row.locator(".truncate.font-medium");
        await expectInsideCell(name, "speaker name");
        await expectSingleLine(name, "speaker name");
        if (width === WIDTHS.md) {
          await expectTruncated(name, "speaker name");
        }
      }
      await expect(speakerRow.locator(".icon-star").filter({ visible: true })).toHaveCount(1);
      if (width === WIDTHS.xl) {
        await expectMinWidth(
          speakersTable.locator("thead th").first(),
          PRIMARY_COLUMN_MIN_PX,
          "speakers name column",
        );
        await expectMinWidth(
          sessionSpeakersTable.locator("thead th").first(),
          PRIMARY_COLUMN_MIN_PX,
          "session speakers name column",
        );
      }
    },
  },
  {
    name: "event editor sessions",
    fixture: "organizerGroupPage",
    openWidth: WIDTHS.xl,
    widths: PAGE_WIDTHS_2XL,
    setup: (owned) => ({
      event: owned.track(setupLabeledSessionEvent({ groupId: TEST_GROUP_IDS.community1.alpha }), (graph) =>
        cleanupEventsByIds([graph.eventId]),
      ),
    }),
    open: async (page, { event }) => {
      await openEventUpdateFormByName(page, event.name, event.eventId);
      await showEventEditorSection(page, "sessions");
      const content = page.locator('[data-content="sessions"]');

      return {
        card: page.locator("sessions-section session-card").filter({ hasText: event.sessionName }),
        labelsCount: event.labelNames.length,
        regions: [content],
        show: () => showEventEditorSection(page, "sessions"),
      };
    },
    check: async (page, { card, labelsCount }, width) => {
      await expectSessionLabelsFit(card, labelsCount);
      const split = await card.evaluate(
        (sessionCard) =>
          `${sessionCard.querySelectorAll("[data-session-labels] [data-session-label]").length} chips + ${sessionCard
            .querySelector("[data-session-labels-more] button")
            ?.textContent.trim()}`,
      );
      recordMeasurement(`event editor sessions at ${width}px: ${split}`);
    },
  },
  {
    name: "event editor submissions",
    fixture: "organizerGroupPage",
    openWidth: WIDTHS.xl,
    widths: PAGE_WIDTHS_2XL,
    open: async (page) => {
      const content = await openCfsEventSubmissionsTab(page);
      const table = content.getByRole("table");
      const labelsRow = table.locator("tr", { hasText: "Scaling Community Workshops" });
      await expect(labelsRow).toBeVisible();

      return {
        labelsRow,
        regions: [content],
        show: () => waitForChartsToFit(content),
        wrappers: [content],
      };
    },
    check: async (page, { labelsRow }, width) => {
      const labelsTrigger = labelsRow.getByRole("button", { exact: true, name: "2 labels" });
      if (width >= WIDTHS.xxl) {
        await expect(labelsTrigger).toBeHidden();
        await expect(labelsRow.getByText("Platform", { exact: true }).filter({ visible: true })).toHaveCount(
          1,
        );
        await expect(labelsRow.getByText("Workshop", { exact: true }).filter({ visible: true })).toHaveCount(
          1,
        );
        return;
      }
      await expect(labelsTrigger).toBeVisible();
      await expectInsideCell(labelsTrigger, "labels trigger");
      await annotateWidths("event editor submissions", width, {
        speaker: labelsTrigger.locator("xpath=ancestor::td[1]"),
      });
    },
  },
  {
    name: "event editor surveys list",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    setup: (owned) => {
      const survey = setupOwnedEventSurvey({
        eventId: TEST_EVENT_SURVEYS.event.id,
        title: "Responsive fit survey ".padEnd(200, "x"),
      });
      owned.defer(() => cleanupEventSurveys([survey.id]));

      return { survey };
    },
    open: async (page, { survey }) => {
      const content = await openSurveysSection(page);
      const table = content.getByRole("table", { name: "Event surveys list" });
      const row = table.locator("tbody tr", { hasText: survey.title.slice(0, 40) });
      await expect(row).toBeVisible();

      return {
        regions: [content],
        row,
        show: () => waitForChartsToFit(content),
        wrappers: [table.locator("xpath=..")],
      };
    },
    check: async (page, { row }, width) => {
      await expectCellsContainContent(row, "long survey row");
      await expectInsideCell(row.locator(".custom-badge"), "state badge");
      await annotateWidths("event editor surveys list", width, { survey: row.locator("th, td").first() });
    },
  },
  {
    name: "event editor survey results",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    open: async (page) => {
      const content = await openSurveysSection(page);
      const { openIdentified } = TEST_EVENT_SURVEYS.surveys;
      await waitForActionResponse(
        page,
        () => content.getByRole("button", { name: `View results: ${openIdentified.title}` }).click(),
        { method: "GET", urlIncludes: `/surveys/${openIdentified.id}/results` },
      );
      await expect(content.locator("[data-survey-responses-label]")).toBeVisible();

      return {
        header: content.locator("header").first(),
        optionRow: content
          .locator('ul[id^="event-survey-question-"][id$="-options"] > li > div:first-child')
          .first(),
        regions: [content],
        show: () => waitForChartsToFit(content),
      };
    },
    check: async (page, { header, optionRow }, width) => {
      await expectInsideBox(header, page.locator("#dashboard-main-content"), "results header");
      await expect(optionRow).toHaveCSS(
        "font-size",
        width >= WIDTHS.lg ? OPTION_ROW_FONT_SIZE.lg : OPTION_ROW_FONT_SIZE.belowLg,
      );
    },
  },
  {
    name: "event editor survey responses",
    fixture: "organizerGroupPage",
    widths: PAGE_WIDTHS,
    open: async (page) => {
      const content = await openSurveysSection(page);
      const { openIdentified } = TEST_EVENT_SURVEYS.surveys;
      await waitForActionResponse(
        page,
        () => content.getByRole("button", { name: `View results: ${openIdentified.title}` }).click(),
        { method: "GET", urlIncludes: `/surveys/${openIdentified.id}/results` },
      );
      await waitForActionResponse(page, () => content.getByRole("button", { name: "Individual" }).click(), {
        method: "GET",
        urlIncludes: `/surveys/${openIdentified.id}/responses`,
      });
      const table = content.getByRole("table");
      await expect(table).toBeVisible();

      return {
        header: content.locator("header").first(),
        regions: [content],
        show: () => waitForChartsToFit(content),
        wrappers: [table.locator("xpath=..")],
      };
    },
    check: async (page, { header }) => {
      await expectInsideBox(header, page.locator("#dashboard-main-content"), "responses header");
    },
  },
  {
    name: "event editor ticketing",
    fixture: "organizerGroupPage",
    openWidth: WIDTHS.xl,
    widths: PAGE_WIDTHS_2XL,
    open: async (page) => {
      // The discount only lives in the unsaved editor, so nothing needs restoring.
      await openEventUpdateFormByName(page, TEST_PAYMENT_EVENT_NAMES.draft, TEST_PAYMENT_EVENT_IDS.draft);
      await openPaymentsSection(page);
      await addDiscountCode(page, {
        code: LONG_DISCOUNT_CODE,
        kind: "percentage",
        percentage: "10",
        title: "A".repeat(120),
      });
      const discountWrapper = page.locator('#discount-codes-ui [data-ticketing-role="table-wrapper"]');
      const discountRow = discountWrapper.locator("tbody tr", { hasText: LONG_DISCOUNT_CODE });
      await expect(discountRow).toBeVisible();

      return {
        discountRow,
        discountWrapper,
        regions: [page.locator('[data-content="payments"]')],
        show: () => showEventEditorSection(page, "payments"),
        wrappers: [discountWrapper, page.locator('#ticket-types-ui [data-ticketing-role="table-wrapper"]')],
      };
    },
    check: async (page, { discountRow, discountWrapper }, width) => {
      await expectMinWidth(
        discountWrapper.locator("thead th").first(),
        PRIMARY_COLUMN_MIN_PX,
        "discount name column",
      );
      expect(await discountRow.innerText(), "the visible row shows the full code").toContain(
        LONG_DISCOUNT_CODE,
      );
      await expectCellsContainContent(discountRow, "long discount code row");
      await annotateWidths("event editor ticketing", width, {
        discountName: discountWrapper.locator("thead th").first(),
        ticketTypesTable: page.locator("#ticket-types-ui table"),
      });
    },
  },
  {
    name: "event add editor ticketing",
    fixture: "organizerGroupPage",
    openWidth: WIDTHS.xl,
    widths: [WIDTHS.xl, WIDTHS.xxl],
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=events");
      await page.locator("#dashboard-content").getByRole("button", { name: "Add Event" }).click();
      await expect(page.locator("#name")).toBeVisible();
      await openPaymentsSection(page);
      const ticketTypesWrapper = page.locator('#ticket-types-ui [data-ticketing-role="table-wrapper"]');
      // The first tbody is the hidden empty state; the default ticket type renders in the next one.
      await expect(
        ticketTypesWrapper.locator('tbody:not([data-ticketing-role="empty-state"]) tr').first(),
      ).toBeVisible();

      return {
        regions: [page.locator('[data-content="payments"]')],
        ticketTypesWrapper,
        wrappers: [ticketTypesWrapper],
      };
    },
    check: async (page, { ticketTypesWrapper }, width) => {
      await annotateWidths("event add editor ticketing", width, {
        ticketTypesTable: ticketTypesWrapper.locator("table"),
        ticketTypesWrapper,
      });
    },
  },
];

test.use({ launchOptions: { ignoreDefaultArgs: ["--hide-scrollbars"] } });

test.describe("dashboard responsive fit", () => {
  for (const fitCase of FIT_CASES) {
    test(`${fitCase.name} fits every width with the classic scrollbar`, async ({ owned, pageAs }) => {
      // Seed the long data, then open the view once with the classic scrollbar.
      const page = await pageAs(fitCase.fixture);
      await page.addInitScript(addClassicScrollbar);
      await page.setViewportSize({ width: fitCase.openWidth ?? fitCase.widths[0], height: VIEWPORT_HEIGHT });
      const data = fitCase.setup?.(owned) ?? {};
      const view = await fitCase.open(page, data);

      // Measure the view at every width without navigating again.
      for (const width of fitCase.widths) {
        await test.step(`${width}px`, async () => {
          await page.setViewportSize({ width, height: VIEWPORT_HEIGHT });
          await view.show?.(width);
          await expectFitsClientWidth(page, view.regions ?? []);
          for (const wrapper of view.wrappers ?? []) {
            await expectNoHorizontalOverflow(wrapper);
          }
          await fitCase.check?.(page, view, width);
        });
      }
    });
  }
});

/**
 * Init script that gives every page of the context the classic scrollbar: the stylesheet makes the
 * root always scroll vertically, so the 15px scrollbar takes room from the page at every width.
 * The styled width keeps that room on macOS too, where native scrollbars may overlay the page.
 * Runs in the page, so it must stay self-contained.
 */
const addClassicScrollbar = () => {
  document.addEventListener("DOMContentLoaded", () => {
    const style = document.createElement("style");
    style.textContent = "html{overflow-y:scroll}html::-webkit-scrollbar{width:15px}";
    document.head.append(style);
  });
};

/**
 * Records the rounded widths of some elements as a `fit-measurement` annotation and returns them.
 * Hidden elements are recorded as `hidden` and returned as `null`.
 * @param {string} label - View measured.
 * @param {number} width - Viewport width.
 * @param {Record<string, import("@playwright/test").Locator>} elements - Elements by name.
 * @returns {Promise<Record<string, number|null>>}
 */
const annotateWidths = async (label, width, elements) => {
  const widths = {};
  for (const [name, locator] of Object.entries(elements)) {
    const box = (await locator.count()) > 0 ? await locator.first().boundingBox() : null;
    widths[name] = box ? Math.round(box.width * 10) / 10 : null;
  }
  const description = Object.entries(widths)
    .map(([name, value]) => `${name} ${value === null ? "hidden" : `${value}px`}`)
    .join(", ");
  recordMeasurement(`${label} at ${width}px: ${description}`);

  return widths;
};

/**
 * Asserts that one element ends above another starts (a preheader above its title).
 * @param {import("@playwright/test").Locator} upper - Element expected on top.
 * @param {import("@playwright/test").Locator} lower - Element expected below it.
 * @param {string} label - Name used in failure messages.
 */
const expectAbove = async (upper, lower, label) => {
  const [upperBox, lowerBox] = await Promise.all([upper.first().boundingBox(), lower.first().boundingBox()]);
  expect(upperBox, `${label} is rendered`).not.toBeNull();
  expect(lowerBox, `${label} target is rendered`).not.toBeNull();
  expect(upperBox.y + upperBox.height, `${label} sits above its target`).toBeLessThanOrEqual(
    lowerBox.y + EDGE_TOLERANCE_PX,
  );
};

/**
 * Asserts that an element doesn't intersect any rendered element of another locator, which must
 * render at least one.
 * @param {import("@playwright/test").Locator} element - Element that must stay apart.
 * @param {import("@playwright/test").Locator} others - Elements it must not overlap.
 * @param {string} label - Name used in failure messages.
 */
const expectApart = async (element, others, label) => {
  const box = await element.first().boundingBox();
  expect(box, `${label}: element is rendered`).not.toBeNull();
  let compared = 0;
  for (const other of await others.all()) {
    const otherBox = await other.boundingBox();
    if (!otherBox) {
      continue;
    }
    compared += 1;
    const overlaps =
      box.x < otherBox.x + otherBox.width - EDGE_TOLERANCE_PX &&
      otherBox.x < box.x + box.width - EDGE_TOLERANCE_PX &&
      box.y < otherBox.y + otherBox.height - EDGE_TOLERANCE_PX &&
      otherBox.y < box.y + box.height - EDGE_TOLERANCE_PX;
    expect(overlaps, `${label} don't overlap`).toBe(false);
  }
  expect(compared, `${label}: at least one other element is rendered`).toBeGreaterThan(0);
};

/**
 * Checks the audit log table of a view: the Action column keeps the primary width and, at md, the
 * details popover stays inside the client width.
 * @param {import("@playwright/test").Page} page - Page showing the logs.
 * @param {{ firstRow: import("@playwright/test").Locator }} view - View opened by `openAuditLogs`.
 * @param {number} width - Viewport width.
 * @param {string} label - View measured.
 */
const expectAuditLogsFit = async (page, { firstRow }, width, label) => {
  const actionCell = firstRow.getByRole("cell").nth(0);
  await expectMinWidth(actionCell, PRIMARY_COLUMN_MIN_PX, "action cell");
  await annotateWidths(label, width, { action: actionCell });
  if (width !== WIDTHS.md) {
    return;
  }

  await firstRow.getByRole("button", { name: "View log details" }).click();
  const card = firstRow.locator("[data-audit-log-details-card]");
  await expect(card).toBeVisible();
  await expectInsideViewport(page, card, "log details popover");
  await page.keyboard.press("Escape");
  await expect(card).toBeHidden();
};

/**
 * Asserts that every visible element in each cell of a row ends inside the cell, ignoring tooltip
 * panels and dropdowns, which float above the table.
 * @param {import("@playwright/test").Locator} row - Table row.
 * @param {string} label - Name used in failure messages.
 */
const expectCellsContainContent = async (row, label) => {
  const spills = await row.evaluate((tableRow) =>
    [...tableRow.querySelectorAll(":scope > td, :scope > th")].flatMap((cell, index) => {
      if (!cell.checkVisibility()) {
        return [];
      }
      const cellBox = cell.getBoundingClientRect();

      return [...cell.querySelectorAll("*")]
        .filter(
          (element) =>
            element.checkVisibility({ opacityProperty: true, visibilityProperty: true }) &&
            !element.closest("[data-tooltip-panel], .dropdown, .sr-only"),
        )
        .map((element) => element.getBoundingClientRect())
        .filter((box) => box.width > 0 && (box.left < cellBox.left - 0.5 || box.right > cellBox.right + 0.5))
        .map(
          (box) => `cell ${index}: [${box.left}, ${box.right}] outside [${cellBox.left}, ${cellBox.right}]`,
        );
    }),
  );
  expect(spills, `${label} keeps every cell's content inside the cell`).toEqual([]);
};

/**
 * Asserts which label of a compact status badge is shown: the compact copy below xl, with the full
 * label kept only for assistive technology, and the full label from xl.
 * @param {import("@playwright/test").Locator} badge - Visible status badge with a compact label.
 * @param {number} width - Viewport width.
 * @param {string} label - Name used in failure messages.
 */
const expectCompactStatusLabel = async (badge, width, label) => {
  const compact = badge.locator('[aria-hidden="true"]');
  const fullBox = await badge.locator("span:not([aria-hidden])").boundingBox();
  expect(fullBox, `${label}: full label is rendered`).not.toBeNull();
  if (width < WIDTHS.xl) {
    await expect(compact, `${label}: compact label is visible below xl`).toBeVisible();
    expect(fullBox.width, `${label}: full label is visually hidden below xl`).toBeLessThanOrEqual(1);
  } else {
    await expect(compact, `${label}: compact label is hidden from xl`).toBeHidden();
    expect(fullBox.width, `${label}: full label is visible from xl`).toBeGreaterThan(1);
  }
};

/**
 * Asserts the content width (width without horizontal padding) of an element.
 * @param {import("@playwright/test").Locator} locator - Element measured.
 * @param {number} min - Smallest content width in px.
 * @param {string} label - Name used in failure messages.
 */
const expectContentWidth = async (locator, min, label) => {
  const contentWidth = await locator.evaluate((element) => {
    const style = getComputedStyle(element);

    return element.clientWidth - Number.parseFloat(style.paddingLeft) - Number.parseFloat(style.paddingRight);
  });
  expect(contentWidth, `${label} width`).toBeGreaterThanOrEqual(min);
};

/**
 * Asserts that the page fits its client width, which excludes the classic scrollbar: the document
 * doesn't scroll horizontally, and the dashboard header, menu, main content and the given regions
 * end inside it. `expectPageLayout` compares with `innerWidth`, which includes the scrollbar and
 * would let up to 15px of overflow through.
 * @param {import("@playwright/test").Page} page - Dashboard page.
 * @param {import("@playwright/test").Locator[]} regions - Extra key regions of the view.
 */
const expectFitsClientWidth = async (page, regions) => {
  const layout = await page.evaluate(() => {
    const root = document.documentElement;
    const rightEdge = (selector) => document.querySelector(selector)?.getBoundingClientRect().right ?? null;

    return {
      clientWidth: root.clientWidth,
      edges: {
        "dashboard header": rightEdge("#dashboard-header"),
        "dashboard main content": rightEdge("#dashboard-main-content"),
        "dashboard menu": rightEdge("#dashboard-menu-drawer"),
      },
      innerWidth: window.innerWidth,
      scrollWidth: root.scrollWidth,
    };
  });
  const { clientWidth } = layout;

  expect(layout.innerWidth - clientWidth, "the classic scrollbar takes room from the page").toBeGreaterThan(
    0,
  );
  expect(
    layout.scrollWidth,
    `document scrollWidth ${layout.scrollWidth} fits clientWidth ${clientWidth}`,
  ).toBeLessThanOrEqual(clientWidth);
  for (const [name, right] of Object.entries(layout.edges)) {
    expect(right, `${name} is rendered`).not.toBeNull();
    expect(right, `${name} ends inside the ${clientWidth}px client width`).toBeLessThanOrEqual(
      clientWidth + EDGE_TOLERANCE_PX,
    );
  }
  for (const region of regions) {
    await expect(region).toBeVisible();
    const right = await region.evaluate((element) => element.getBoundingClientRect().right);
    expect(right, `${region} ends inside the ${clientWidth}px client width`).toBeLessThanOrEqual(
      clientWidth + EDGE_TOLERANCE_PX,
    );
  }
};

/**
 * Checks the Status cell of an inbox row below xl: the badge and the "From …" cue stay inside the
 * cell, and the cue fits without truncation.
 * @param {import("@playwright/test").Locator} row - Inbox conversation row.
 * @param {number} width - Viewport width.
 */
const expectInboxStatusFit = async (row, width) => {
  if (width >= WIDTHS.xl) {
    return;
  }

  const writer = row.getByText("From organizers", { exact: true });
  await expect(writer).toBeVisible();
  await expectInsideCell(row.locator(".custom-badge"), "inbox status badge");
  await expectInsideCell(writer, "last writer cue");
  const fits = await writer.evaluate((element) => element.scrollWidth <= element.clientWidth);
  expect(fits, "the last writer cue isn't truncated").toBe(true);
};

/**
 * Asserts that one element lies horizontally inside another's box.
 * @param {import("@playwright/test").Locator} inner - Contained element.
 * @param {import("@playwright/test").Locator} outer - Container.
 * @param {string} label - Name used in failure messages.
 */
const expectInsideBox = async (inner, outer, label) => {
  const [innerBox, outerBox] = await Promise.all([inner.boundingBox(), outer.boundingBox()]);
  expect(innerBox, `${label} is rendered`).not.toBeNull();
  expect(innerBox.x, `${label} starts inside its container`).toBeGreaterThanOrEqual(
    outerBox.x - EDGE_TOLERANCE_PX,
  );
  expect(innerBox.x + innerBox.width, `${label} ends inside its container`).toBeLessThanOrEqual(
    outerBox.x + outerBox.width + EDGE_TOLERANCE_PX,
  );
};

/**
 * Asserts that a locator has at least one visible element and that every visible one lies
 * horizontally inside its table cell.
 * @param {import("@playwright/test").Locator} locator - Elements inside table cells.
 * @param {string} label - Name used in failure messages.
 */
const expectInsideCell = async (locator, label) => {
  const { measured, outside } = await locator.evaluateAll((elements) => {
    const visible = elements.filter((element) =>
      element.checkVisibility({ opacityProperty: true, visibilityProperty: true }),
    );

    return {
      measured: visible.length,
      outside: visible.flatMap((element) => {
        const box = element.getBoundingClientRect();
        const cellBox = element.closest("td, th").getBoundingClientRect();
        const inside = box.left >= cellBox.left - 0.5 && box.right <= cellBox.right + 0.5;

        return inside
          ? []
          : [`[${box.left}, ${box.right}] outside the cell [${cellBox.left}, ${cellBox.right}]`];
      }),
    };
  });
  expect(measured, `${label}: at least one visible element is measured`).toBeGreaterThan(0);
  expect(outside, `${label} stay inside their cells`).toEqual([]);
};

/**
 * Asserts that an element lies horizontally inside the client width and below the top edge.
 * @param {import("@playwright/test").Page} page - Page showing the element.
 * @param {import("@playwright/test").Locator} locator - Element, such as a tooltip or popover.
 * @param {string} label - Name used in failure messages.
 */
const expectInsideViewport = async (page, locator, label) => {
  const box = await locator.boundingBox();
  const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);
  expect(box, `${label} is rendered`).not.toBeNull();
  expect(box.x, `${label} starts inside the viewport`).toBeGreaterThanOrEqual(-EDGE_TOLERANCE_PX);
  expect(box.y, `${label} starts below the viewport top`).toBeGreaterThanOrEqual(-EDGE_TOLERANCE_PX);
  expect(box.x + box.width, `${label} ends inside the ${clientWidth}px client width`).toBeLessThanOrEqual(
    clientWidth + EDGE_TOLERANCE_PX,
  );
};

/**
 * Asserts the largest rendered width of an element.
 * @param {import("@playwright/test").Locator} locator - Element measured.
 * @param {number} max - Largest width in px.
 * @param {string} label - Name used in failure messages.
 */
const expectMaxWidth = async (locator, max, label) => {
  const box = await locator.first().boundingBox();
  expect(box, `${label} is rendered`).not.toBeNull();
  expect(box.width, `${label} width`).toBeLessThanOrEqual(max + EDGE_TOLERANCE_PX);
};

/**
 * Asserts the smallest rendered width of an element.
 * @param {import("@playwright/test").Locator} locator - Element measured.
 * @param {number} min - Smallest width in px.
 * @param {string} label - Name used in failure messages.
 */
const expectMinWidth = async (locator, min, label) => {
  const box = await locator.first().boundingBox();
  expect(box, `${label} is rendered`).not.toBeNull();
  expect(box.width, `${label} width`).toBeGreaterThanOrEqual(min);
};

/**
 * Asserts that containers don't overflow horizontally, and that each visible table inside lies
 * within its content box. A scrolling or clipping container must keep its `scrollWidth` inside its
 * `clientWidth`. An `overflow-visible` container lets content spill without scrolling, and its
 * `scrollWidth` also counts hidden tooltip panels that neither scroll nor show, so instead every
 * rendered descendant must end inside its content box.
 * @param {import("@playwright/test").Locator} locator - Table wrappers or containers, one or more.
 */
const expectNoHorizontalOverflow = async (locator) => {
  expect(await locator.count(), `${locator} matches a container`).toBeGreaterThan(0);
  const overflows = await locator.evaluateAll((containers) =>
    containers.flatMap((container, index) => {
      if (!container.checkVisibility()) {
        return [];
      }
      const problems = [];
      const style = getComputedStyle(container);
      const box = container.getBoundingClientRect();
      const left = box.left + container.clientLeft + Number.parseFloat(style.paddingLeft);
      const right =
        box.left + container.clientLeft + container.clientWidth - Number.parseFloat(style.paddingRight);
      if (style.overflowX !== "visible" && container.scrollWidth > container.clientWidth) {
        problems.push(
          `container ${index}: scrollWidth ${container.scrollWidth} > clientWidth ${container.clientWidth}`,
        );
      }
      if (style.overflowX === "visible") {
        // Report only the outermost element that spills.
        const spilled = new Set();
        for (const element of container.querySelectorAll("*")) {
          if (spilled.has(element.parentElement)) {
            spilled.add(element);
            continue;
          }
          const elementBox = element.getBoundingClientRect();
          if (
            elementBox.width <= 1 ||
            !element.checkVisibility({ opacityProperty: true, visibilityProperty: true })
          ) {
            continue;
          }
          // Only the part left visible by clipping ancestors (truncated text) counts.
          let [visibleLeft, visibleRight] = [elementBox.left, elementBox.right];
          for (
            let ancestor = element.parentElement;
            ancestor !== container;
            ancestor = ancestor.parentElement
          ) {
            if (getComputedStyle(ancestor).overflowX !== "visible") {
              const ancestorBox = ancestor.getBoundingClientRect();
              visibleLeft = Math.max(visibleLeft, ancestorBox.left);
              visibleRight = Math.min(visibleRight, ancestorBox.right);
            }
          }
          if (visibleLeft < left - 0.5 || visibleRight > right + 0.5) {
            spilled.add(element);
            problems.push(
              `container ${index}: ${element.tagName.toLowerCase()} [${visibleLeft}, ${visibleRight}] outside the content box [${left}, ${right}]`,
            );
          }
        }
      }
      for (const table of container.querySelectorAll("table")) {
        if (!table.checkVisibility()) {
          continue;
        }
        const tableBox = table.getBoundingClientRect();
        if (tableBox.left < left - 0.5 || tableBox.right > right + 0.5) {
          problems.push(
            `container ${index}: table [${tableBox.left}, ${tableBox.right}] outside the content box [${left}, ${right}]`,
          );
        }
      }

      return problems;
    }),
  );
  expect(overflows, `${locator} keeps its content inside`).toEqual([]);
};

/**
 * Asserts that at least two visible elements share one row (equal top edges).
 * @param {import("@playwright/test").Locator} locator - Elements expected side by side.
 * @param {string} label - Name used in failure messages.
 */
const expectSameRow = async (locator, label) => {
  const tops = await locator.evaluateAll((elements) =>
    elements
      .filter((element) => element.checkVisibility({ opacityProperty: true, visibilityProperty: true }))
      .map((element) => Math.round(element.getBoundingClientRect().top)),
  );
  expect(tops.length, `${label}: at least two visible elements are measured`).toBeGreaterThan(1);
  expect(new Set(tops).size, `${label} share one row (tops ${tops.join(", ")})`).toBe(1);
};

/**
 * Asserts that no visible text node of an element spans more than one line.
 * @param {import("@playwright/test").Locator} locator - Element whose text stays on one line.
 * @param {string} label - Name used in failure messages.
 */
const expectSingleLine = async (locator, label) => {
  const maxLines = await locator.first().evaluate((element) => {
    let lines = 0;
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const parent = node.parentElement;
      if (
        node.textContent.trim() === "" ||
        !parent.checkVisibility() ||
        parent.getBoundingClientRect().width <= 1
      ) {
        continue;
      }
      const range = document.createRange();
      range.selectNodeContents(node);
      const tops = new Set(
        [...range.getClientRects()].filter((rect) => rect.width > 0).map((rect) => Math.round(rect.top)),
      );
      lines = Math.max(lines, tops.size);
    }

    return lines;
  });
  expect(maxLines, `${label} stays on one line`).toBe(1);
};

/**
 * Asserts that an element truncates its text (its content is wider than its box).
 * @param {import("@playwright/test").Locator} locator - Truncating element with long data.
 * @param {string} label - Name used in failure messages.
 */
const expectTruncated = async (locator, label) => {
  await expect(locator.first()).toBeVisible();
  const truncated = await locator.first().evaluate((element) => element.scrollWidth > element.clientWidth);
  expect(truncated, `${label} truncates its long text`).toBe(true);
};

/**
 * Checks a team list with a long pending member: the member name keeps the primary width at xl
 * and 2xl, whichever cell shows the invitation badge.
 * @param {{ row: import("@playwright/test").Locator }} view - View opened by `openTeamList`.
 * @param {number} width - Viewport width.
 * @param {string} label - View measured.
 */
const expectTeamFit = async ({ row }, width, label) => {
  // Position is hidden below xl, so cells are located by DOM index, not by role.
  const name = row.locator("td").nth(0).locator(".font-medium.truncate");
  await expectInsideCell(row.locator(".custom-badge"), "invitation badge");
  if (width >= WIDTHS.xl) {
    await expectMinWidth(name, PRIMARY_COLUMN_MIN_PX, "pending member name");
  }
  await annotateWidths(label, width, { name, role: row.locator("td").nth(2) });
};

/**
 * Builds a unique long text: the prefix, then a 32-character hex token, padded or cut to `length`.
 * Keep prefixes short enough for the token to fit (`length - 33` characters).
 * @param {string} prefix - Readable start of the text.
 * @param {number} length - Exact length.
 * @returns {string}
 */
const longText = (prefix, length) =>
  `${prefix} ${randomUUID().replaceAll("-", "")}`.padEnd(length, "x").slice(0, length);

/**
 * Opens the analytics section of an event editor and waits for its charts.
 * @param {import("@playwright/test").Page} page - Organizer page.
 * @param {string} eventName - Past event name.
 * @param {string} eventId - Event id.
 * @returns {Promise<import("@playwright/test").Locator>} Analytics content.
 */
const openAnalyticsSection = async (page, eventName, eventId) => {
  await openEventUpdateFormByName(page, eventName, eventId, { eventsTab: "past" });
  const content = await openCurrentEventEditorSection(page, eventId, "analytics", "#analytics-content");
  await expect(content).toHaveAttribute("data-analytics-state", "loaded");

  return content;
};

/**
 * Opens an audit logs tab and returns its view.
 * @param {import("@playwright/test").Page} page - Page of a user who sees the logs.
 * @param {string} path - Logs tab path.
 * @returns {Promise<object>} View with the first log row.
 */
const openAuditLogs = async (page, path) => {
  const table = page.locator("#dashboard-content").getByRole("table");
  await openDashboardView(page, path, { regions: [table] });
  const firstRow = table.locator("tr.audit-log-row").first();
  await expect(firstRow).toBeVisible();

  return { firstRow, regions: [table], wrappers: [table.locator("xpath=..")] };
};

/**
 * Opens a group dashboard tab with one table and returns its view.
 * @param {import("@playwright/test").Page} page - Organizer page.
 * @param {string} path - Tab path.
 * @returns {Promise<object>} View with the table as region and its wrapper.
 */
const openGroupTable = async (page, path) => {
  const table = page.locator("#dashboard-content").getByRole("table").first();
  await openDashboardView(page, path, { regions: [table] });

  return { regions: [table], wrappers: [table.locator("xpath=..")] };
};

/**
 * Opens an inbox conversation and returns its view.
 * @param {import("@playwright/test").Page} page - Page of the user or organizer.
 * @param {string} path - Conversation path.
 * @returns {Promise<object>} View with the conversation as region.
 */
const openInboxConversation = async (page, path) => {
  const conversation = page.locator("#inbox-conversation");
  await openDashboardView(page, path, { regions: [conversation] });

  return { conversation, regions: [conversation] };
};

/**
 * Opens an inbox list and returns the view of one conversation row.
 * @param {import("@playwright/test").Page} page - Page of the user or organizer.
 * @param {string} path - Inbox tab path.
 * @param {string} eventName - Event of the conversation.
 * @returns {Promise<object>} View with the table and the row.
 */
const openInboxList = async (page, path, eventName) => {
  const table = page.getByRole("table", { name: "Inbox conversations" });
  await openDashboardView(page, path, { regions: [table] });
  const row = table.locator("[data-inbox-conversation-row]", { hasText: eventName });
  await expect(row).toBeVisible();

  return { regions: [table], row, table, wrappers: [table.locator("xpath=..")] };
};

/**
 * Opens the surveys section of the seeded survey event.
 * @param {import("@playwright/test").Page} page - Organizer page.
 * @returns {Promise<import("@playwright/test").Locator>} Surveys content.
 */
const openSurveysSection = async (page) => {
  const { event } = TEST_EVENT_SURVEYS;
  await openEventUpdateFormByName(page, event.name, event.id, { eventsTab: "past" });

  return openCurrentEventEditorSection(page, event.id, "surveys", "#surveys-content", {
    tableName: "Event surveys list",
  });
};

/**
 * Opens a team list and returns the view of one member row.
 * @param {import("@playwright/test").Page} page - Page of a team admin.
 * @param {string} path - Team tab path.
 * @param {string} memberName - Member shown in the row.
 * @returns {Promise<object>} View with the table and the row.
 */
const openTeamList = async (page, path, memberName) => {
  const table = page.locator("#dashboard-content").getByRole("table");
  await openDashboardView(page, path, { regions: [table] });
  const row = table.locator("tbody tr", { hasText: memberName });
  await expect(row).toBeVisible();

  return { regions: [table], row, wrappers: [table.locator("xpath=..")] };
};

/**
 * Records one measurement as a `fit-measurement` annotation of the running test.
 * @param {string} description - What was measured and its value.
 */
const recordMeasurement = (description) => {
  test.info().annotations.push({ type: "fit-measurement", description });
};

/**
 * Inserts an owned inbox conversation of a user with a group, answered by the first organizer,
 * so the list shows "From organizers", the longest last writer cue.
 * @param {object} owned - `owned` fixture.
 * @param {{ eventId: string, groupId: string, userId: string }} input - Conversation shape.
 * @returns {{ id: string, messageIds: string[] }}
 */
const trackConversation = (owned, { eventId, groupId, userId }) =>
  owned.track(
    setupInboxConversation({
      eventId,
      groupId,
      messages: [
        { body: "Could you share the accessibility details of the venue before the event?" },
        { authorUserId: TEST_USER_IDS.organizer1, body: "Yes, the venue is step-free.", kind: "group-reply" },
      ],
      status: "answered",
      userId,
    }),
    ({ id }) => cleanupInboxConversations([id]),
  );

/**
 * Creates an owned temporary group and releases it, with its events, at teardown.
 * @param {object} owned - `owned` fixture.
 * @param {object} options - `setupTemporaryGroup` options.
 * @returns {{ groupId: string, groupName: string, slug: string }}
 */
const trackGroup = (owned, options) =>
  owned.track(setupTemporaryGroup(options), ({ groupId }) => cleanupTemporaryGroup(groupId));

/**
 * Creates an owned temporary user with a 44-character name (and a 60-character email when asked)
 * and releases it at teardown.
 * @param {object} owned - `owned` fixture.
 * @param {string} label - Username label.
 * @param {{ longEmail?: boolean, name?: string }} [options] - Whether the email has 60 characters,
 *   and a name replacing the random 44-character one.
 * @returns {{ email: string, name: string, userId: string }}
 */
const trackUser = (
  owned,
  label,
  { longEmail = false, name = longText("E2E Fit Ann", LONG_NAME_LENGTH) } = {},
) =>
  owned.track(
    setupTemporaryUser({
      email: longEmail
        ? `${`fit-${randomUUID().replaceAll("-", "")}`.padEnd(48, "x")}@example.com`
        : undefined,
      label,
      name,
    }),
    ({ userId }) => cleanupTemporaryUser(userId),
  );

/**
 * Waits until every chart in a container has followed its container size. Charts resize through a
 * debounced resize observer (`common/charts/stats.js`), so right after a viewport change their
 * canvas may still have the previous width.
 * @param {import("@playwright/test").Locator} content - Container with the charts.
 */
const waitForChartsToFit = async (content) => {
  await expect(content).toBeVisible();
  await expect
    .poll(() =>
      content.evaluate((element) =>
        [...element.querySelectorAll("[_echarts_instance_]")]
          .filter((chart) => chart.checkVisibility())
          .filter((chart) => {
            const chartRight = chart.getBoundingClientRect().right;

            return [...chart.querySelectorAll("canvas, svg")].some(
              (surface) => surface.getBoundingClientRect().right > chartRight + 0.5,
            );
          })
          .map((chart) => chart.id),
      ),
    )
    .toEqual([]);
};
