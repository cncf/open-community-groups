-- Tests resolving the current enrollment state for an event user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6e000000-0000-0000-0000-000000000001'
\set eventCategoryID '6e000000-0000-0000-0000-000000000002'
\set eventID '6e000000-0000-0000-0000-000000000003'
\set groupCategoryID '6e000000-0000-0000-0000-000000000004'
\set groupID '6e000000-0000-0000-0000-000000000005'
\set openEventID '6e000000-0000-0000-0000-000000000006'
\set openPriceWindowID '6e000000-0000-0000-0000-000000000028'
\set openTicketTypeID '6e000000-0000-0000-0000-000000000007'
\set otherCommunityID '6e000000-0000-0000-0000-000000000008'
\set priceWindowID '6e000000-0000-0000-0000-000000000029'
\set ticketTypeID '6e000000-0000-0000-0000-000000000009'
\set attendeeID '6e000000-0000-0000-0000-000000000010'
\set attendeePurchaseID '6e000000-0000-0000-0000-000000000011'
\set expiredOfferID '6e000000-0000-0000-0000-000000000012'
\set expiredUserID '6e000000-0000-0000-0000-000000000013'
\set offerID '6e000000-0000-0000-0000-000000000014'
\set offeredUserID '6e000000-0000-0000-0000-000000000015'
\set openRequestUserID '6e000000-0000-0000-0000-000000000016'
\set pendingPaymentID '6e000000-0000-0000-0000-000000000017'
\set pendingPaymentUserID '6e000000-0000-0000-0000-000000000018'
\set pendingRequestUserID '6e000000-0000-0000-0000-000000000019'
\set refundOfferID '6e000000-0000-0000-0000-000000000020'
\set refundOfferPurchaseID '6e000000-0000-0000-0000-000000000021'
\set refundOfferUserID '6e000000-0000-0000-0000-000000000022'
\set refundPurchaseID '6e000000-0000-0000-0000-000000000023'
\set refundRequestID '6e000000-0000-0000-0000-000000000024'
\set refundUserID '6e000000-0000-0000-0000-000000000025'
\set rejectedRefundPurchaseID '6e000000-0000-0000-0000-000000000030'
\set rejectedRefundRequestID '6e000000-0000-0000-0000-000000000031'
\set rejectedRefundUserID '6e000000-0000-0000-0000-000000000032'
\set rejectedRequestUserID '6e000000-0000-0000-0000-000000000026'
\set waitlistUserID '6e000000-0000-0000-0000-000000000027'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Seed the owning and cross-scope communities.
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values
    (
        'https://example.test/banner-mobile.png',
        'https://example.test/banner.png',
        :'communityID',
        'Enrollment function tests',
        'Enrollment Community',
        'https://example.test/logo.png',
        'enrollment-community'
    ),
    (
        'https://example.test/other-banner-mobile.png',
        'https://example.test/other-banner.png',
        :'otherCommunityID',
        'Other community',
        'Other Community',
        'https://example.test/other-logo.png',
        'other-enrollment-community'
    );

-- Seed the owning group's category.
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Seed the events' category.
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Meetups');

-- Seed the active owning group.
insert into "group" (active, community_id, group_category_id, group_id, name, slug)
values (true, :'communityID', :'groupCategoryID', :'groupID', 'Enrollment Group', 'enrollment');

-- Seed users for each enrollment-state scenario.
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    ('hash', 'attendee@example.test', true, :'attendeeID', 'enrollment-attendee'),
    ('hash', 'expired@example.test', true, :'expiredUserID', 'enrollment-expired'),
    ('hash', 'offered@example.test', true, :'offeredUserID', 'enrollment-offered'),
    ('hash', 'open-request@example.test', true, :'openRequestUserID', 'enrollment-open-request'),
    ('hash', 'payment@example.test', true, :'pendingPaymentUserID', 'enrollment-payment'),
    ('hash', 'request@example.test', true, :'pendingRequestUserID', 'enrollment-request'),
    ('hash', 'refund-offer@example.test', true, :'refundOfferUserID', 'enrollment-refund-offer'),
    ('hash', 'refund@example.test', true, :'refundUserID', 'enrollment-refund'),
    ('hash', 'refund-rejected@example.test', true, :'rejectedRefundUserID', 'enrollment-refund-rejected'),
    ('hash', 'rejected@example.test', true, :'rejectedRequestUserID', 'enrollment-rejected'),
    ('hash', 'waitlist@example.test', true, :'waitlistUserID', 'enrollment-waitlist');

-- Seed approval-enabled and approval-disabled events.
insert into event (
    attendee_approval_required,
    capacity,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone
) values
    (
        true,
        20,
        'Approval event',
        :'eventCategoryID',
        :'eventID',
        'in-person',
        :'groupID',
        'Approval Event',
        'USD',
        true,
        'approval-event',
        '2099-01-01 10:00:00+00',
        'UTC'
    ),
    (
        false,
        10,
        'Open event',
        :'eventCategoryID',
        :'openEventID',
        'in-person',
        :'groupID',
        'Open Event',
        null,
        true,
        'open-event',
        '2099-01-02 10:00:00+00',
        'UTC'
    );

-- Seed one ticket tier for each event.
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    (:'eventID', :'ticketTypeID', 1, 20, 'General admission'),
    (:'openEventID', :'openTicketTypeID', 1, 10, 'General admission');

-- Seed current free price windows for both tiers.
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
values
    (0, :'priceWindowID', :'ticketTypeID'),
    (0, :'openPriceWindowID', :'openTicketTypeID');

-- Seed confirmed attendee states for check-in and refund scenarios.
insert into event_attendee (
    checked_in,
    checked_in_at,
    event_id,
    manually_invited,
    status,
    user_id
) values
    (true, '2026-01-01 10:00:00+00', :'eventID', true, 'confirmed', :'attendeeID'),
    (false, null, :'eventID', false, 'confirmed', :'refundUserID'),
    (false, null, :'eventID', false, 'confirmed', :'rejectedRefundUserID');

-- Seed active, expired, and refund-linked admission offers.
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values
    (
        :'expiredOfferID',
        0,
        '2024-01-01 10:00:00+00',
        null,
        0,
        :'eventID',
        :'ticketTypeID',
        '2025-01-01 10:00:00+00',
        'waitlist',
        'expired',
        'General admission',
        :'expiredUserID'
    ),
    (
        :'offerID',
        0,
        '2026-01-01 10:00:00+00',
        null,
        0,
        :'eventID',
        :'ticketTypeID',
        '2099-01-01 09:00:00+00',
        'organizer_invitation',
        'pending',
        'General admission',
        :'offeredUserID'
    ),
    (
        :'refundOfferID',
        0,
        '2026-01-02 10:00:00+00',
        null,
        0,
        :'eventID',
        :'ticketTypeID',
        '2099-01-01 09:00:00+00',
        'approval',
        'pending',
        'General admission',
        :'refundOfferUserID'
    );

-- Seed completed, pending, and refunding purchase states.
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    provider_checkout_url,
    status,
    ticket_title,
    user_id
) values
    (
        null,
        0,
        '2026-01-01 10:00:00+00',
        null,
        :'eventID',
        :'attendeePurchaseID',
        :'ticketTypeID',
        null,
        null,
        'completed',
        'General admission',
        :'attendeeID'
    ),
    (
        null,
        500,
        null,
        'USD',
        :'eventID',
        :'pendingPaymentID',
        :'ticketTypeID',
        '2099-01-01 09:00:00+00',
        'https://example.test/checkout/resume',
        'pending',
        'General admission',
        :'pendingPaymentUserID'
    ),
    (
        :'refundOfferID',
        0,
        '2026-01-02 11:00:00+00',
        null,
        :'eventID',
        :'refundOfferPurchaseID',
        :'ticketTypeID',
        null,
        null,
        'refund-pending',
        'General admission',
        :'refundOfferUserID'
    ),
    (
        null,
        0,
        '2026-01-03 10:00:00+00',
        null,
        :'eventID',
        :'refundPurchaseID',
        :'ticketTypeID',
        null,
        null,
        'refund-requested',
        'General admission',
        :'refundUserID'
    ),
    (
        null,
        0,
        '2026-01-04 10:00:00+00',
        null,
        :'eventID',
        :'rejectedRefundPurchaseID',
        :'ticketTypeID',
        null,
        null,
        'completed',
        'General admission',
        :'rejectedRefundUserID'
    );

-- Seed a pending refund review for a confirmed attendee.
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values (:'refundPurchaseID', :'refundRequestID', :'refundUserID', 'pending');

-- Seed a rejected refund review with its attendee-visible reason.
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status,

    review_note,
    reviewed_at,
    reviewed_by_user_id
) values (
    :'rejectedRefundPurchaseID',
    :'rejectedRefundRequestID',
    :'rejectedRefundUserID',
    'rejected',

    'Outside the refund policy window',
    '2026-01-04 11:00:00+00',
    :'attendeeID'
);

-- Seed pending, rejected, and approval-disabled invitation requests.
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    reviewed_at,
    reviewed_by,
    status,
    user_id
) values
    (:'eventID', null, null, null, 'pending', :'pendingRequestUserID'),
    (
        :'eventID',
        :'ticketTypeID',
        '2026-01-01 10:00:00+00',
        :'attendeeID',
        'rejected',
        :'rejectedRequestUserID'
    ),
    (:'openEventID', null, null, null, 'pending', :'openRequestUserID');

-- Seed a tier-scoped waitlist entry.
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitlistUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return confirmed attendance and check-in state
select is(
    get_event_enrollment(:'communityID', :'eventID', :'attendeeID')::jsonb,
    '{"is_checked_in": true, "manually_invited": true, "purchase_amount_minor": 0, "refund_request_status": null, "resume_checkout_url": null, "status": "attendee"}'::jsonb,
    'Should return confirmed attendance and check-in state'
);

-- Should return a resumable pending checkout
select is(
    get_event_enrollment(:'communityID', :'eventID', :'pendingPaymentUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": 500, "refund_request_status": null, "resume_checkout_url": "https://example.test/checkout/resume", "status": "pending-payment"}'::jsonb,
    'Should return a resumable pending checkout'
);

-- Should return an active organizer offer
select is(
    get_event_enrollment(:'communityID', :'eventID', :'offeredUserID')::jsonb,
    format(
        '{"admission_offer_id": "%s", "event_ticket_type_id": "%s", "is_checked_in": false, "manually_invited": true, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "invitation-approved"}',
        :'offerID',
        :'ticketTypeID'
    )::jsonb,
    'Should return an active organizer offer'
);

-- Should return a generic pending approval request
select is(
    get_event_enrollment(:'communityID', :'eventID', :'pendingRequestUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "pending-approval"}'::jsonb,
    'Should return a generic pending approval request'
);

-- Should return a rejected approval request
select is(
    get_event_enrollment(:'communityID', :'eventID', :'rejectedRequestUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "rejected"}'::jsonb,
    'Should return a rejected approval request'
);

-- Should return a tier-scoped waitlist entry
select is(
    get_event_enrollment(:'communityID', :'eventID', :'waitlistUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "waitlisted"}'::jsonb,
    'Should return a tier-scoped waitlist entry'
);

-- Should return the latest expired offer state
select is(
    get_event_enrollment(:'communityID', :'eventID', :'expiredUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "offer-expired"}'::jsonb,
    'Should return the latest expired offer state'
);

-- Should suppress offers already linked to a refunding purchase
select is(
    get_event_enrollment(:'communityID', :'eventID', :'refundOfferUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "none"}'::jsonb,
    'Should suppress offers already linked to a refunding purchase'
);

-- Should return the refund request state for an attendee purchase
select is(
    get_event_enrollment(:'communityID', :'eventID', :'refundUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": 0, "refund_request_status": "pending", "resume_checkout_url": null, "status": "attendee"}'::jsonb,
    'Should return the refund request state for an attendee purchase'
);

-- Should return the reason for a rejected refund request
select is(
    get_event_enrollment(:'communityID', :'eventID', :'rejectedRefundUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": 0, "refund_rejection_reason": "Outside the refund policy window", "refund_request_status": "rejected", "resume_checkout_url": null, "status": "attendee"}'::jsonb,
    'Should return the reason for a rejected refund request'
);

-- Should ignore approval requests when approval is disabled
select is(
    get_event_enrollment(:'communityID', :'openEventID', :'openRequestUserID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "none"}'::jsonb,
    'Should ignore approval requests when approval is disabled'
);

-- Should not expose enrollment across communities
select is(
    get_event_enrollment(:'otherCommunityID', :'eventID', :'attendeeID')::jsonb,
    '{"is_checked_in": false, "purchase_amount_minor": null, "refund_request_status": null, "resume_checkout_url": null, "status": "none"}'::jsonb,
    'Should not expose enrollment across communities'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
