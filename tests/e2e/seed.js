/**
 * Read-only seed catalog: identifiers and names from database/tests/data/e2e.sql. Never mutate these rows.
 */
export const TEST_COMMUNITY_NAME = process.env.OCG_E2E_COMMUNITY_NAME || "e2e-test-community";
export const TEST_COMMUNITY_NAME_2 = "e2e-second-community";
export const TEST_COMMUNITY_IDS = {
  community1: "11111111-1111-1111-1111-111111111111",
  community2: "11111111-1111-1111-1111-111111111112",
  empty: "11111111-1111-1111-1111-111111111113",
};
export const TEST_GROUP_SLUG = process.env.OCG_E2E_GROUP_SLUG || "test-group-alpha";
export const TEST_EVENT_SLUG = process.env.OCG_E2E_EVENT_SLUG || "alpha-event-1";
export const TEST_GROUP_NAME = "Platform Ops Meetup";
export const TEST_EVENT_NAME = "Upcoming In-Person Event";
export const TEST_CANCELED_PUBLIC_EVENT = {
  id: "55555555-5555-5555-5555-555555555531",
  name: "Canceled Public Event",
  slug: "alpha-canceled-public-event",
};
export const TEST_APPROVAL_REQUIRED_EVENT = {
  id: "55555555-5555-5555-5555-555555555530",
  name: "Approval Required Attendance",
  offerId: "62555555-5555-5555-5555-555555555530",
  slug: "alpha-approval-required-attendance",
};
export const TEST_EVENT_PAGE_BADGE_EVENT = {
  id: "55555555-5555-5555-5555-555555555524",
  name: "Test Event Page Badge",
  slug: "alpha-test-event-badge",
};
export const TEST_EVENT_CANCELLATION = {
  id: "55555555-5555-5555-5555-555555555527",
  name: "Event Cancellation Lifecycle",
  slug: "alpha-event-cancellation-lifecycle",
};
export const TEST_CALENDAR_EVENTS = {
  nextMonth: {
    id: "55555555-5555-5555-5555-555555555938",
    name: "Alpha Calendar Next Month",
    slug: "alpha-calendar-next-month",
  },
  thisMonth: {
    id: "55555555-5555-5555-5555-555555555937",
    name: "Alpha Calendar This Month",
    slug: "alpha-calendar-this-month",
  },
};
export const TEST_CFS_WINDOW_EVENTS = {
  closed: {
    id: "55555555-5555-5555-5555-555555555534",
    name: "Closed Call for Speakers Window",
    slug: "alpha-cfs-closed",
  },
  upcoming: {
    id: "55555555-5555-5555-5555-555555555533",
    name: "Upcoming Call for Speakers Window",
    slug: "alpha-cfs-upcoming",
  },
};
export const TEST_INVITATION_CANCELLATION = {
  id: "55555555-5555-5555-5555-555555555528",
  name: "Canceled Invitation History",
  slug: "alpha-canceled-invitation-history",
};
export const TEST_OPEN_CHECK_IN_EVENT = {
  id: "55555555-5555-5555-5555-555555555529",
  name: "Open Public Check-In",
  slug: "alpha-open-public-check-in",
};
export const TEST_MULTI_DAY_EVENT = {
  id: "55555555-5555-5555-5555-555555555535",
  name: "Multi Day Summit",
  slug: "alpha-multi-day-summit",
};
export const TEST_UNPUBLISHED_EVENT = {
  id: "55555555-5555-5555-5555-555555555532",
  name: "Unpublished Public Event",
  slug: "alpha-unpublished-public-event",
};
export const TEST_REGISTRATION_QUESTIONS_EVENT = {
  id: "55555555-5555-5555-5555-555555555525",
  name: "Registration Answers Lab",
  slug: "alpha-registration-answers-lab",
};
export const TEST_REGISTRATION_WINDOW_EVENTS = {
  approvalClosed: {
    id: "55555555-5555-5555-5555-555555555905",
    name: "Registration Window Approval Closed",
    slug: "alpha-registration-window-approval-closed",
  },
  approvalFuture: {
    id: "55555555-5555-5555-5555-555555555922",
    name: "Registration Window Approval Future",
    slug: "alpha-registration-window-approval-future",
  },
  closeOnlyOpen: {
    id: "55555555-5555-5555-5555-555555555907",
    name: "Registration Window Close Only Open",
    slug: "alpha-registration-window-close-only-open",
  },
  freeClosed: {
    id: "55555555-5555-5555-5555-555555555904",
    name: "Registration Window Free Closed",
    slug: "alpha-registration-window-free-closed",
  },
  openOnlyClosed: {
    id: "55555555-5555-5555-5555-555555555908",
    name: "Registration Window Open Only Closed",
    slug: "alpha-registration-window-open-only-closed",
  },
  pendingPaymentClosed: {
    id: "55555555-5555-5555-5555-555555555911",
    name: "Registration Window Pending Payment Closed",
    slug: "alpha-registration-window-pending-payment-closed",
  },
  questionsClosed: {
    id: "55555555-5555-5555-5555-555555555909",
    name: "Registration Window Questions Closed",
    slug: "alpha-registration-window-questions-closed",
  },
  questionsManualInviteClosed: {
    id: "55555555-5555-5555-5555-555555555910",
    name: "Registration Window Manual Invite Closed",
    slug: "alpha-registration-window-manual-invite-closed",
  },
  paidClosed: {
    id: "55555555-5555-5555-5555-555555555901",
    name: "Registration Window Paid Closed",
    slug: "alpha-registration-window-paid-closed",
  },
  paidFuture: {
    id: "55555555-5555-5555-5555-555555555902",
    name: "Registration Window Paid Future",
    slug: "alpha-registration-window-paid-future",
  },
  paidOpen: {
    id: "55555555-5555-5555-5555-555555555903",
    name: "Registration Window Paid Open",
    slug: "alpha-registration-window-paid-open",
  },
  priceEnded: {
    id: "55555555-5555-5555-5555-555555555923",
    name: "Registration Window Price Ended",
    slug: "alpha-registration-window-price-ended",
  },
  waitlistClosed: {
    id: "55555555-5555-5555-5555-555555555906",
    name: "Registration Window Waitlist Closed",
    slug: "alpha-registration-window-waitlist-closed",
  },
};
export const TEST_SEARCH_QUERY = "Test";
export const TEST_SITE_TITLE = "E2E Test Site";
export const TEST_COMMUNITY_TITLE = "Platform Engineering Community";
export const TEST_COMMUNITY_TITLE_2 = "Developer Experience Community";

/** Community details for assertions. */
export const TEST_COMMUNITY_DESCRIPTION = "Platform engineering community used for end-to-end coverage.";
export const TEST_COMMUNITY_AD_BANNER_LINK_URL_2 = "https://example.com/e2e-advertisement";
export const TEST_COMMUNITY_AD_BANNER_URL_2 = "/static/images/e2e/event-banner.svg";
export const TEST_COMMUNITY_BANNER_URL = "/static/images/e2e/community-primary-banner.svg";
export const TEST_COMMUNITY_BANNER_MOBILE_URL = "/static/images/e2e/community-primary-banner-mobile.svg";

/** Group names organized by community. */
export const TEST_GROUP_NAMES = {
  alpha: "Platform Ops Meetup",
  beta: "Inactive Local Chapter",
  empty: "Empty Coverage Group",
  externalPayments: "External Payments Lab",
  gamma: "Observability Guild",
};

/** Event names organized by group. */
export const TEST_EVENT_NAMES = {
  alpha: ["Upcoming In-Person Event", "Upcoming Virtual Event", "Upcoming Hybrid Event"],
  beta: ["Canceled In-Person Event", "Secondary Virtual Event", "Secondary Hybrid Event"],
  gamma: ["Observability In-Person Event", "Observability Virtual Event", "Observability Hybrid Event"],
};

/** Group slugs organized by community. */
export const TEST_GROUP_SLUGS = {
  community1: {
    alpha: "test-group-alpha",
    beta: "test-group-beta",
    empty: "empty-coverage-group",
    externalPayments: "external-payments-lab",
    gamma: "test-group-gamma",
  },
  community2: {
    delta: "second-group-delta",
    epsilon: "second-group-epsilon",
    zeta: "second-group-zeta",
  },
};

/** Group ids organized by community. */
export const TEST_GROUP_IDS = {
  community1: {
    alpha: "44444444-4444-4444-4444-444444444441",
    beta: "44444444-4444-4444-4444-444444444442",
    empty: "44444444-4444-4444-4444-444444444447",
    externalPayments: "44444444-4444-4444-4444-444444444448",
    gamma: "44444444-4444-4444-4444-444444444443",
  },
  community2: {
    delta: "44444444-4444-4444-4444-444444444444",
    epsilon: "44444444-4444-4444-4444-444444444445",
    zeta: "44444444-4444-4444-4444-444444444446",
  },
};

/** Event ids organized by seeded coverage area. */
export const TEST_EVENT_IDS = {
  alpha: {
    one: "55555555-5555-5555-5555-555555555501",
    two: "55555555-5555-5555-5555-555555555502",
    cfsSummit: "55555555-5555-5555-5555-555555555519",
    pastFiltering: "55555555-5555-5555-5555-555555555520",
    waitlistLab: "55555555-5555-5555-5555-555555555521",
    dashboardWaitlist: "55555555-5555-5555-5555-555555555526",
  },
};

/** Dashboard waitlist invitation fixture with spare seats on one free tier. */
export const TEST_WAITLIST_INVITE_EVENT = {
  id: "55555555-5555-5555-5555-555555555537",
  name: "Dashboard Waitlist Invite Lab",
  // Sold-out tier that holds the queue and the expired offer.
  queuedTicketTypeId: "56555555-5555-5555-5555-555555555537",
  // Tier with spare seats that organizers assign from the waitlist.
  inviteTicketTypeId: "56555555-5555-5555-5555-555555555538",
  // Seeded offers that must survive fixture restoration.
  expiredOfferId: "59555555-5555-5555-5555-555555555537",
  claimedOfferId: "59555555-5555-5555-5555-555555555538",
};

/** Payment-specific event ids used by the future Playwright payment suite. */
export const TEST_PAYMENT_EVENT_IDS = {
  draft: "55555555-5555-5555-5555-555555555522",
  refunds: "55555555-5555-5555-5555-555555555523",
};

/** Payment-specific event names used by the future Playwright payment suite. */
export const TEST_PAYMENT_EVENT_NAMES = {
  draft: "Paid Tier Draft Event",
  refunds: "Paid Tier Refund Review Event",
};

/** Payment-specific event slugs used by the future Playwright payment suite. */
export const TEST_PAYMENT_EVENT_SLUGS = {
  draft: "alpha-payments-draft",
  refunds: "alpha-payments-refunds",
};

/** Stripe webhook fixtures with isolated mutable state. */
export const TEST_WEBHOOK_EVENTS = {
  expire: {
    id: "55555555-5555-5555-5555-555555555940",
    name: "Stripe Webhook Expire Lab",
    slug: "alpha-webhook-expire",
    completedPurchaseId: "59555555-5555-5555-5555-555555555940",
    connectedAccount: "acct_e2e_alpha",
    pendingPurchaseId: "59555555-5555-5555-5555-555555555941",
    providerCheckoutSessionId: "cs_e2e_webhook_expire",
    ticketTypeId: "56555555-5555-5555-5555-555555555940",
  },
  invoice: {
    id: "55555555-5555-5555-5555-555555555941",
    name: "Stripe Webhook Invoice Lab",
    slug: "alpha-webhook-invoice",
    connectedAccount: "acct_e2e_alpha",
    providerInvoiceHostedUrl: "https://invoices.stripe.test/in_e2e_webhook_invoice",
    providerInvoiceId: "in_e2e_webhook_invoice",
    providerInvoicePdfUrl: "https://invoices.stripe.test/in_e2e_webhook_invoice.pdf",
    purchaseId: "59555555-5555-5555-5555-555555555942",
    ticketTypeId: "56555555-5555-5555-5555-555555555941",
  },
  refund: {
    id: "55555555-5555-5555-5555-555555555942",
    name: "Stripe Webhook Refund Lab",
    slug: "alpha-webhook-refund",
    connectedAccount: "acct_e2e_alpha",
    paymentJobId: "64555555-5555-5555-5555-555555555940",
    providerPaymentReference: "pi_e2e_webhook_refund",
    providerRefundId: "re_e2e_webhook",
    purchaseId: "59555555-5555-5555-5555-555555555943",
    refundId: "61555555-5555-5555-5555-555555555940",
    refundRequestId: "60555555-5555-5555-5555-555555555940",
    ticketTypeId: "56555555-5555-5555-5555-555555555942",
  },
};

/** Exhausted payment job identifiers used by refund dashboard coverage. */
export const TEST_FINANCIAL_WORK_JOB_IDS = {
  applicationFeeAdjustment: "64555555-5555-5555-5555-555555555531",
  creditNote: "64555555-5555-5555-5555-555555555534",
  exhaustedRefund: "64555555-5555-5555-5555-555555555527",
};

/** Seeded purchase document identifiers used by dashboard coverage. */
export const TEST_PURCHASE_DOCUMENT_IDS = {
  creditNote: "62555555-5555-5555-5555-555555555528",
  purchase: "59555555-5555-5555-5555-555555555528",
};

/** Ticketing workflow events with isolated mutable state. */
export const TEST_TICKETING_EVENTS = {
  invitationRequests: {
    id: "55555555-5555-5555-5555-555555555914",
    name: "Invitation Request Lifecycle Lab",
    slug: "alpha-invitation-request-lifecycle",
  },
  manualTaxUnavailable: {
    id: "55555555-5555-5555-5555-555555555921",
    name: "Unavailable Manual Tax Rate Lab",
    slug: "alpha-manual-tax-unavailable",
  },
  migratedCapacity: {
    id: "55555555-5555-5555-5555-555555555919",
    name: "Migrated Unlimited Capacity Event",
    slug: "alpha-migrated-unlimited-capacity",
  },
  noAssignableTier: {
    id: "55555555-5555-5555-5555-555555555915",
    name: "No Assignable Invitation Tier Lab",
    slug: "alpha-no-assignable-invitation-tier",
  },
  paidOffers: {
    id: "55555555-5555-5555-5555-555555555916",
    name: "Paid Event Offers Lab",
    slug: "alpha-paid-event-offers",
  },
  paidQuestions: {
    id: "55555555-5555-5555-5555-555555555917",
    name: "Paid Registration Questions Lab",
    slug: "alpha-paid-registration-questions",
  },
  paymentReturn: {
    id: "55555555-5555-5555-5555-555555555912",
    name: "Payment Return States Lab",
    slug: "alpha-payment-return-states",
  },
  refundedCapacity: {
    id: "55555555-5555-5555-5555-555555555920",
    name: "Refunded Capacity Release Lab",
    slug: "alpha-refunded-capacity-release",
  },
  soldOut: {
    id: "55555555-5555-5555-5555-555555555918",
    name: "Sold Out Ticket States Lab",
    slug: "alpha-sold-out-ticket-states",
  },
  ticketRequest: {
    id: "55555555-5555-5555-5555-555555555913",
    name: "Ticket Request Lab",
    slug: "alpha-ticket-request-lab",
  },
};

/** Isolated events used by the external payment E2E journeys. */
export const TEST_EXTERNAL_PAYMENT_EVENTS = {
  capacity: {
    id: "55555555-5555-5555-5555-555555555925",
    name: "External Payment Capacity Lab",
    slug: "external-payment-capacity",
    ticketTypeId: "56555555-5555-5555-5555-555555555925",
  },
  copyFree: {
    id: "55555555-5555-5555-5555-555555555927",
    name: "External Payment Free Ticket Lab",
    slug: "external-payment-free-ticket-lab",
  },
  invitation: {
    id: "55555555-5555-5555-5555-555555555926",
    name: "External Payment Invitation Lab",
    slug: "external-payment-invitation",
    ticketTypeId: "56555555-5555-5555-5555-555555555926",
  },
  lifecycle: {
    discountCode: "EXTERNALFREE",
    id: "55555555-5555-5555-5555-555555555924",
    name: "External Payment Lifecycle Lab",
    slug: "external-payment-lifecycle",
    ticketTypeId: "56555555-5555-5555-5555-555555555924",
  },
};

/** Isolated meeting events used by Zoom webhook and rendering coverage. */
export const TEST_MEETING_EVENTS = {
  error: {
    id: "55555555-5555-5555-5555-555555555946",
    name: "Zoom Error Sync Lab",
    slug: "alpha-zoom-error",
  },
  live: {
    id: "55555555-5555-5555-5555-555555555944",
    name: "Zoom Live Join Lab",
    slug: "alpha-zoom-live",
  },
  pending: {
    id: "55555555-5555-5555-5555-555555555945",
    name: "Zoom Pending Sync Lab",
    slug: "alpha-zoom-pending",
  },
  publicRecording: {
    id: "55555555-5555-5555-5555-555555555947",
    name: "Zoom Public Recording Lab",
    slug: "alpha-zoom-public-recording",
  },
  recording: {
    id: "55555555-5555-5555-5555-555555555943",
    name: "Zoom Recording Webhook Lab",
    slug: "alpha-zoom-recording",
  },
  unpublishedRecording: {
    id: "55555555-5555-5555-5555-555555555948",
    name: "Zoom Unpublished Recording Lab",
    slug: "alpha-zoom-unpublished-recording",
  },
};

/** Seeded Zoom meeting rows and URLs used by meeting E2E specs. */
export const TEST_MEETINGS = {
  errorMessage: "Zoom returned rate limit during provisioning.",
  live: {
    id: "88888888-8888-8888-8888-888888888944",
    joinUrl: "https://zoom.us/j/912345678902",
    providerMeetingId: "912345678902",
  },
  publicRecording: {
    finalRecordingUrl: "https://recordings.example.test/alpha-zoom-public-recording",
    id: "88888888-8888-8888-8888-888888888947",
    joinUrl: "https://zoom.us/j/912345678903",
    providerMeetingId: "912345678903",
  },
  recording: {
    id: "88888888-8888-8888-8888-888888888943",
    joinUrl: "https://zoom.us/j/912345678901",
    providerMeetingId: "912345678901",
    webhookRecordingUrl: "https://recordings.example.test/alpha-zoom-webhook-recording",
  },
  unpublishedRecording: {
    finalRecordingUrl: "https://recordings.example.test/alpha-zoom-unpublished-recording",
    id: "88888888-8888-8888-8888-888888888948",
    joinUrl: "https://zoom.us/j/912345678904",
    providerMeetingId: "912345678904",
  },
};

/** Seeded Stripe recipient stored on the alpha group for payment-ready coverage. */
export const TEST_PAYMENT_GROUP_RECIPIENT = "acct_e2e_alpha";

/** Event slugs organized by group. */
export const TEST_EVENT_SLUGS = {
  alpha: ["alpha-event-1", "alpha-event-2", "alpha-event-3"],
  beta: ["beta-event-1", "beta-event-2", "beta-event-3"],
  gamma: ["gamma-event-1", "gamma-event-2", "gamma-event-3"],
  delta: ["delta-event-1", "delta-event-2", "delta-event-3"],
  epsilon: ["epsilon-event-1", "epsilon-event-2", "epsilon-event-3"],
  zeta: ["zeta-event-1", "zeta-event-2", "zeta-event-3"],
  alphaDashboard: ["alpha-cfs-summit", "alpha-past-roundup"],
};

/** Pre-seeded user ids for state resets and dashboard assertions. */
export const TEST_USER_IDS = {
  checkInManager1: "77777777-7777-7777-7777-777777777715",
  communityGroupsManager1: "77777777-7777-7777-7777-777777777709",
  member1: "77777777-7777-7777-7777-777777777705",
  member2: "77777777-7777-7777-7777-777777777706",
  organizer1: "77777777-7777-7777-7777-777777777703",
  pending1: "77777777-7777-7777-7777-777777777707",
  pending2: "77777777-7777-7777-7777-777777777708",
};

/** Pre-seeded user credentials for e2e tests. */
export const TEST_USER_CREDENTIALS = {
  admin1: { username: "e2e-admin-1", password: "Password123!" },
  admin2: { username: "e2e-admin-2", password: "Password123!" },
  empty: { username: "e2e-empty", password: "Password123!" },
  organizer1: { username: "e2e-organizer-1", password: "Password123!" },
  organizer2: { username: "e2e-organizer-2", password: "Password123!" },
  member1: { username: "e2e-member-1", password: "Password123!" },
  member2: { username: "e2e-member-2", password: "Password123!" },
  pending1: { username: "e2e-pending-1", password: "Password123!" },
  pending2: { username: "e2e-pending-2", password: "Password123!" },
  groupsManager1: {
    username: "e2e-groups-manager-1",
    password: "Password123!",
  },
  checkInManager1: {
    username: "e2e-check-in-manager-1",
    password: "Password123!",
  },
  communityViewer1: {
    username: "e2e-community-viewer-1",
    password: "Password123!",
  },
  eventsManager1: {
    username: "e2e-events-manager-1",
    password: "Password123!",
  },
  groupViewer1: {
    username: "e2e-group-viewer-1",
    password: "Password123!",
  },
};
