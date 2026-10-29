import { expect, test } from "../../fixtures.js";
import {
  cleanupEventEnrollment,
  setupCommunityTeamInvitation,
  setupEventInvitation,
  setupGroupTeamInvitation,
} from "../../data-graphs/invitations.js";
import {
  TEST_COMMUNITY_IDS,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_GROUP_IDS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_USER_IDS,
} from "../../seed.js";
import { expectTableColumnsAtViewport, expectTableHeaders, navigateToPath } from "../../utils.js";
import { openAttendeesTab, openInvitationRequestsTab } from "../group/events/attendees-helpers.js";
import {
  openCfsEventSubmissionsTab,
  openDashboardWaitlist,
  openEventUpdateFormByName,
  openPaymentsSection,
} from "../group/events/helpers.js";
import { openRefundsDashboard } from "../group/refunds/helpers.js";
import { openPurchasesDashboard, openUserDashboardPath } from "../user/helpers.js";

const GROUP_EVENTS_HEADERS = ["Name", "Location", "Date", "Type", "Status", "Attendees", "Actions"];

const GROUP_EVENTS_BREAKPOINTS = [
  {
    width: 1024,
    visible: ["Name", "Status", "Actions"],
    hidden: ["Location", "Date", "Type", "Attendees"],
  },
  {
    width: 1280,
    visible: ["Name", "Date", "Type", "Status", "Actions"],
    hidden: ["Location", "Attendees"],
  },
  { width: 1536, visible: GROUP_EVENTS_HEADERS, hidden: [] },
];

const TABLE_EVENT_INVITATION = {
  eventId: TEST_EVENT_IDS.alpha.one,
  userId: TEST_USER_IDS.pending1,
};

/** Removes the owned table event invitation and any enrollment state of its pair. */
const cleanupTableEventInvitation = () => {
  cleanupEventEnrollment(TABLE_EVENT_INVITATION);
};

// One entry per dashboard table; each becomes an independently reported test.
const TABLE_CASES = [
  {
    name: "community event categories",
    fixture: "adminCommunityPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/community?tab=event-categories");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Name", "Events", "Actions"],
    breakpoints: [
      { width: 1024, visible: ["Name", "Actions"], hidden: ["Events"] },
      { width: 1280, visible: ["Name", "Events", "Actions"], hidden: [] },
    ],
  },
  {
    name: "community group categories",
    fixture: "adminCommunityPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/community?tab=group-categories");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Name", "Groups", "Actions"],
    breakpoints: [
      { width: 1024, visible: ["Name", "Actions"], hidden: ["Groups"] },
      { width: 1280, visible: ["Name", "Groups", "Actions"], hidden: [] },
    ],
  },
  {
    name: "community groups",
    fixture: "adminCommunityPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/community?tab=groups");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Name", "Location", "Created", "Category", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Name", "Actions"],
        hidden: ["Location", "Created", "Category"],
      },
      {
        width: 1280,
        visible: ["Name", "Location", "Category", "Actions"],
        hidden: ["Created"],
      },
      {
        width: 1536,
        visible: ["Name", "Location", "Created", "Category", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "community logs",
    fixture: "adminCommunityPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/community?tab=logs");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Action", "Actor", "Target", "Date", "Details"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Action", "Actor", "Date", "Details"],
        hidden: ["Target"],
      },
      {
        width: 1280,
        visible: ["Action", "Actor", "Target", "Date", "Details"],
        hidden: [],
      },
    ],
  },
  {
    name: "community regions",
    fixture: "adminCommunityPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/community?tab=regions");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Name", "Groups", "Actions"],
    breakpoints: [
      { width: 1024, visible: ["Name", "Actions"], hidden: ["Groups"] },
      { width: 1280, visible: ["Name", "Groups", "Actions"], hidden: [] },
    ],
  },
  {
    name: "community team",
    fixture: "adminCommunityPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/community?tab=team");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Member", "Position", "Role", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Member", "Role", "Actions"],
        hidden: ["Position"],
      },
      {
        width: 1280,
        visible: ["Member", "Position", "Role", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group award history",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=awards");

      return page.getByRole("table", { name: "Awards list" });
    },
    headers: ["Recipient", "Badge", "Source", "Awarded", "Status", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Recipient", "Badge", "Awarded", "Status", "Actions"],
        hidden: ["Source"],
      },
      {
        width: 1280,
        visible: ["Recipient", "Badge", "Source", "Awarded", "Status", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group badge definitions",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=badges");

      return page.getByRole("table", { name: "Badges list" });
    },
    headers: ["Badge", "Description", "Actions"],
    breakpoints: [
      { width: 1024, visible: ["Badge", "Actions"], hidden: ["Description"] },
      { width: 1280, visible: ["Badge", "Description", "Actions"], hidden: [] },
    ],
  },
  {
    name: "group event attendees",
    fixture: "organizerGroupPage",
    open: async (page) => {
      const attendeesContent = await openAttendeesTab(
        page,
        TEST_EVENT_NAMES.alpha[0],
        TEST_EVENT_IDS.alpha.one,
      );

      return attendeesContent.getByRole("table", { name: "Attendees list" });
    },
    headers: [
      "Select for email",
      "Attendee",
      "Position",
      "Status",
      "Ticket type",
      "Enrollment Date",
      "Checked In",
      "Actions",
    ],
    breakpoints: [
      {
        width: 1024,
        visible: ["Attendee", "Ticket type", "Checked In", "Actions"],
        hidden: ["Select for email", "Position", "Status", "Enrollment Date"],
      },
      {
        width: 1280,
        visible: ["Attendee", "Ticket type", "Checked In", "Actions"],
        hidden: ["Select for email", "Position", "Status", "Enrollment Date"],
      },
      {
        width: 1536,
        visible: ["Attendee", "Status", "Ticket type", "Checked In", "Actions"],
        hidden: ["Select for email", "Position", "Enrollment Date"],
      },
      {
        width: 1920,
        visible: [
          "Attendee",
          "Position",
          "Status",
          "Ticket type",
          "Enrollment Date",
          "Checked In",
          "Actions",
        ],
        hidden: ["Select for email"],
      },
    ],
  },
  {
    name: "group event discount codes",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=events");
      await openEventUpdateFormByName(page, TEST_PAYMENT_EVENT_NAMES.draft, TEST_PAYMENT_EVENT_IDS.draft);
      await openPaymentsSection(page);

      return page.locator("#discount-codes-ui table");
    },
    headers: ["Name", "Redemptions", "Status", "Availability", "Value", "Code", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Name", "Availability", "Actions"],
        hidden: ["Redemptions", "Status", "Value", "Code"],
      },
      {
        width: 1536,
        visible: ["Name", "Redemptions", "Status", "Availability", "Value", "Code", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group event invitation requests",
    fixture: "organizerGroupPage",
    open: async (page) => {
      const requestsContent = await openInvitationRequestsTab(
        page,
        TEST_REGISTRATION_WINDOW_EVENTS.approvalFuture.name,
        TEST_REGISTRATION_WINDOW_EVENTS.approvalFuture.id,
      );

      return requestsContent.getByRole("table", {
        name: "Invitation requests",
      });
    },
    headers: ["Requester", "Position", "Status", "Offer", "Ticket type", "Requested", "Reviewed", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Requester", "Status", "Actions"],
        hidden: ["Position", "Offer", "Ticket type", "Requested", "Reviewed"],
      },
      {
        width: 1280,
        visible: ["Requester", "Status", "Ticket type", "Actions"],
        hidden: ["Position", "Offer", "Requested", "Reviewed"],
      },
      {
        width: 1536,
        visible: ["Requester", "Status", "Offer", "Ticket type", "Reviewed", "Actions"],
        hidden: ["Position", "Requested"],
      },
      {
        width: 1920,
        visible: [
          "Requester",
          "Position",
          "Status",
          "Offer",
          "Ticket type",
          "Requested",
          "Reviewed",
          "Actions",
        ],
        hidden: [],
      },
    ],
  },
  {
    name: "group event submissions",
    fixture: "eventsManagerGroupPage",
    open: async (page) => {
      const submissionsContent = await openCfsEventSubmissionsTab(page);

      return submissionsContent.getByRole("table");
    },
    headers: ["Speaker", "Proposal", "Status", "Ratings", "Submitted", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Speaker / Proposal", "Status", "Actions"],
        hidden: ["Proposal", "Ratings", "Submitted"],
      },
      {
        width: 1280,
        visible: ["Speaker / Proposal", "Status", "Ratings", "Actions"],
        hidden: ["Proposal", "Submitted"],
      },
      {
        width: 1536,
        visible: ["Speaker", "Proposal", "Status", "Ratings", "Submitted", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group event ticket types",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=events");
      await openEventUpdateFormByName(page, TEST_PAYMENT_EVENT_NAMES.draft, TEST_PAYMENT_EVENT_IDS.draft);
      await openPaymentsSection(page);

      return page.locator("#ticket-types-ui table");
    },
    headers: ["Name", "Price", "Seats", "Status", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Name", "Seats", "Status", "Actions"],
        hidden: ["Price"],
      },
      {
        width: 1280,
        visible: ["Name", "Price", "Seats", "Status", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group event waitlist",
    fixture: "organizerGroupPage",
    open: async (page) => {
      const waitlistContent = await openDashboardWaitlist(page);

      return waitlistContent.getByRole("table", { name: "Waitlist entries" });
    },
    headers: ["Entry", "Position", "Queue", "Enrollment", "Created", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Entry", "Queue", "Actions"],
        hidden: ["Position", "Enrollment", "Created"],
      },
      {
        width: 1280,
        visible: ["Entry", "Queue", "Enrollment", "Actions"],
        hidden: ["Position", "Created"],
      },
      {
        width: 1536,
        visible: ["Entry", "Position", "Queue", "Enrollment", "Actions"],
        hidden: ["Created"],
      },
      {
        width: 1920,
        visible: ["Entry", "Position", "Queue", "Enrollment", "Created", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group events past",
    fixture: "organizerGroupPage",
    open: async (page) => openGroupEventsTable(page, "Past events list", "#past-content"),
    headers: GROUP_EVENTS_HEADERS,
    breakpoints: GROUP_EVENTS_BREAKPOINTS,
  },
  {
    name: "group events upcoming",
    fixture: "organizerGroupPage",
    open: async (page) => openGroupEventsTable(page, "Upcoming events list", "#upcoming-content"),
    headers: GROUP_EVENTS_HEADERS,
    breakpoints: GROUP_EVENTS_BREAKPOINTS,
  },
  {
    name: "group logs",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=logs");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Action", "Actor", "Target", "Date", "Details"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Action", "Actor", "Date", "Details"],
        hidden: ["Target"],
      },
      {
        width: 1280,
        visible: ["Action", "Actor", "Target", "Date", "Details"],
        hidden: [],
      },
    ],
  },
  {
    name: "group members",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=members");

      return page.getByRole("table", { name: "Members list" });
    },
    headers: ["Member", "Position", "Joined"],
    breakpoints: [
      { width: 1024, visible: ["Member", "Position"], hidden: ["Joined"] },
      { width: 1280, visible: ["Member", "Position", "Joined"], hidden: [] },
    ],
  },
  {
    name: "group refunds",
    fixture: "organizerGroupPage",
    open: async (page) => {
      const dashboardContent = await openRefundsDashboard(page);

      return dashboardContent.getByRole("table", { name: "Refunds list" });
    },
    headers: ["Attendee", "Event", "Refund", "Status", "Updated", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Attendee", "Refund", "Actions"],
        hidden: ["Event", "Status", "Updated"],
      },
      {
        width: 1280,
        visible: ["Attendee", "Event", "Refund", "Status", "Actions"],
        hidden: ["Updated"],
      },
      {
        width: 1536,
        visible: ["Attendee", "Event", "Refund", "Status", "Updated", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group sponsors",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=sponsors");

      return page.getByRole("table", { name: "Sponsors list" });
    },
    headers: ["Sponsor", "Website", "Featured", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Sponsor", "Featured", "Actions"],
        hidden: ["Website"],
      },
      {
        width: 1280,
        visible: ["Sponsor", "Website", "Featured", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "group team",
    fixture: "organizerGroupPage",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/group?tab=team");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Member", "Position", "Role", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Member", "Role", "Actions"],
        hidden: ["Position"],
      },
      {
        width: 1280,
        visible: ["Member", "Position", "Role", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user invitation communities",
    fixture: "pending1Page",
    open: async (page) => {
      const invitationsContent = await openPendingInvitationTables(page);

      return invitationsContent.locator("table", {
        has: page.getByRole("columnheader", { name: "Community" }),
      });
    },
    cleanup: cleanupTableEventInvitation,
    headers: ["Community", "Role", "Created", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Community", "Role", "Created", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user invitation events",
    fixture: "pending1Page",
    open: async (page) => {
      const invitationsContent = await openPendingInvitationTables(page);

      return invitationsContent.locator("table", {
        has: page.getByRole("columnheader", { name: "Event" }),
      });
    },
    cleanup: cleanupTableEventInvitation,
    headers: ["Event", "Offer", "Starts", "Expires", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Event", "Offer", "Starts", "Expires", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user invitation groups",
    fixture: "pending1Page",
    open: async (page) => {
      const invitationsContent = await openPendingInvitationTables(page);

      return invitationsContent
        .locator("table", {
          has: page.getByRole("columnheader", { name: "Group", exact: true }),
        })
        .first();
    },
    cleanup: cleanupTableEventInvitation,
    headers: ["Group", "Role", "Created", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Group", "Role", "Created", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user logs",
    fixture: "member1Page",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/user?tab=logs");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Action", "Target", "Date", "Details"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Action", "Date", "Details"],
        hidden: ["Target"],
      },
      {
        width: 1280,
        visible: ["Action", "Target", "Date", "Details"],
        hidden: [],
      },
    ],
  },
  {
    name: "user my events",
    fixture: "member1Page",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/user?tab=events");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Title", "Location", "Date", "Role", "Status", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Title", "Status / role", "Actions"],
        hidden: ["Location", "Date", "Status"],
      },
      {
        width: 1280,
        visible: ["Title", "Date", "Role", "Status", "Actions"],
        hidden: ["Location"],
      },
      {
        width: 1536,
        visible: ["Title", "Location", "Date", "Role", "Status", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user my groups",
    fixture: "member1Page",
    open: async (page) => {
      await navigateToPath(page, "/dashboard/user?tab=groups");

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Group", "Member since", "Role", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Group", "Member since", "Role", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user purchases",
    fixture: "adminCommunityPage",
    open: async (page) => {
      const dashboardContent = await openPurchasesDashboard(page);

      return dashboardContent.getByRole("table");
    },
    headers: ["Event", "Purchased", "Amount", "Status", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Event", "Amount", "Status", "Actions"],
        hidden: ["Purchased"],
      },
      {
        width: 1280,
        visible: ["Event", "Purchased", "Amount", "Status", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user session proposals",
    fixture: "member1Page",
    open: async (page) => {
      await openUserDashboardPath("/dashboard/user?tab=session-proposals", page);

      return page.locator("table", {
        has: page.getByText("Cloud Native Operations Deep Dive", {
          exact: true,
        }),
      });
    },
    headers: ["Proposal", "Co-speaker", "Updated", "Status", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Proposal", "Status", "Actions"],
        hidden: ["Co-speaker", "Updated"],
      },
      {
        width: 1280,
        visible: ["Proposal", "Co-speaker", "Status", "Actions"],
        hidden: ["Updated"],
      },
      {
        width: 1536,
        visible: ["Proposal", "Co-speaker", "Updated", "Status", "Actions"],
        hidden: [],
      },
    ],
  },
  {
    name: "user submissions",
    fixture: "member1Page",
    open: async (page) => {
      await openUserDashboardPath("/dashboard/user?tab=submissions", page);

      return page.locator("#dashboard-content").getByRole("table");
    },
    headers: ["Event", "Proposal", "Status", "Updated", "Actions"],
    breakpoints: [
      {
        width: 1024,
        visible: ["Event", "Proposal", "Actions"],
        hidden: ["Status", "Updated"],
      },
      {
        width: 1280,
        visible: ["Event", "Proposal", "Status", "Actions"],
        hidden: ["Updated"],
      },
      {
        width: 1536,
        visible: ["Event", "Proposal", "Status", "Updated", "Actions"],
        hidden: [],
      },
    ],
  },
];

test.describe("dashboard tables", () => {
  for (const tableCase of TABLE_CASES) {
    test(`${tableCase.name} table exposes every column at its responsive breakpoint`, async ({ pageAs }) => {
      const page = await pageAs(tableCase.fixture);

      await runTableCase(tableCase, page);
    });
  }
});

/** Opens a group events table and returns it after optional past-tab selection. */
const openGroupEventsTable = async (page, tableName, contentSelector) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  if (contentSelector === "#past-content") {
    await page.locator("#past-tab").click();
  }

  const content = page.locator(contentSelector);
  await expect(content).toBeVisible();

  return page.getByRole("table", { name: tableName });
};

/** Prepares pending1's pending invitations and returns the user invitation dashboard content. */
const openPendingInvitationTables = async (page) => {
  setupCommunityTeamInvitation({
    communityId: TEST_COMMUNITY_IDS.community1,
    role: "viewer",
    userId: TEST_USER_IDS.pending1,
  });
  setupGroupTeamInvitation({
    groupId: TEST_GROUP_IDS.community1.beta,
    role: "events-manager",
    userId: TEST_USER_IDS.pending1,
  });
  setupEventInvitation(TABLE_EVENT_INVITATION);
  await openUserDashboardPath("/dashboard/user?tab=invitations", page);

  return page.locator("#dashboard-content");
};

/** Runs a dashboard table case and restores its optional cleanup state. */
const runTableCase = async (tableCase, page) => {
  try {
    tableCase.cleanup?.();
    const table = await tableCase.open(page);

    await expectTableHeaders(table, tableCase.headers);

    for (const { width, visible, hidden } of tableCase.breakpoints) {
      await expectTableColumnsAtViewport(page, table, width, visible, hidden);
    }
  } finally {
    tableCase.cleanup?.();
  }
};
