-- Tests updating event ticketing configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(32);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '3a3c0000-0000-0000-0000-000000000001'
\set community1ID '3a3c0000-0000-0000-0000-000000000002'
\set event13ID '3a3c0000-0000-0000-0000-000000000003'
\set event14ID '3a3c0000-0000-0000-0000-000000000004'
\set event15ID '3a3c0000-0000-0000-0000-000000000005'
\set event16ID '3a3c0000-0000-0000-0000-000000000006'
\set event17ID '3a3c0000-0000-0000-0000-000000000007'
\set event19ID '3a3c0000-0000-0000-0000-000000000008'
\set event20ID '3a3c0000-0000-0000-0000-000000000009'
\set event21ID '3a3c0000-0000-0000-0000-000000000010'
\set event22ID '3a3c0000-0000-0000-0000-000000000011'
\set event23ID '3a3c0000-0000-0000-0000-000000000012'
\set event24ID '3a3c0000-0000-0000-0000-000000000013'
\set eventOverCapacityID '3a3c0000-0000-0000-0000-000000000014'
\set eventPaidTransitionID '3a3c0000-0000-0000-0000-000000000068'
\set eventQuestionsAnsweredID '3a3c0000-0000-0000-0000-000000000015'
\set eventQuestionsHoldID '3a3c0000-0000-0000-0000-000000000056'
\set eventQuestionsID '3a3c0000-0000-0000-0000-000000000016'
\set eventQuestionsPublishedID '3a3c0000-0000-0000-0000-000000000017'
\set eventTicketQueueID '3a3c0000-0000-0000-0000-000000000064'
\set group1ID '3a3c0000-0000-0000-0000-000000000018'
\set questionsAttendeeUserID '3a3c0000-0000-0000-0000-000000000019'
\set questionsCategoryID '3a3c0000-0000-0000-0000-000000000020'
\set questionsCommunityID '3a3c0000-0000-0000-0000-000000000021'
\set questionsEventCategoryID '3a3c0000-0000-0000-0000-000000000022'
\set questionsGroupID '3a3c0000-0000-0000-0000-000000000023'
\set questionsHoldPriceWindowID '3a3c0000-0000-0000-0000-000000000060'
\set questionsHoldPurchaseID '3a3c0000-0000-0000-0000-000000000059'
\set questionsHoldTicketTypeID '3a3c0000-0000-0000-0000-000000000058'
\set questionsHoldUserID '3a3c0000-0000-0000-0000-000000000057'
\set questionsOrganizerUserID '3a3c0000-0000-0000-0000-000000000024'
\set paidTransitionPriceWindowID '3a3c0000-0000-0000-0000-00000000006a'
\set paidTransitionTicketTypeID '3a3c0000-0000-0000-0000-000000000069'
\set ticketQueuePriceWindowID '3a3c0000-0000-0000-0000-000000000065'
\set ticketQueuePurchaseID '3a3c0000-0000-0000-0000-000000000066'
\set ticketQueueTicketTypeID '3a3c0000-0000-0000-0000-000000000067'
\set user1ID '3a3c0000-0000-0000-0000-000000000025'
\set user2ID '3a3c0000-0000-0000-0000-000000000026'
\set user3ID '3a3c0000-0000-0000-0000-000000000027'
\set user4ID '3a3c0000-0000-0000-0000-000000000028'
\set user5ID '3a3c0000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'A test community for testing purposes',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Community for registration-question update tests
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'questionsCommunityID',
    'update-questions-community',
    'Update Questions Community',
    'Desc',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (user_id, auth_hash, email, username, name) values
    (:'user1ID', 'hash1', 'host1@example.com', 'host1', 'Host One'),
    (:'user2ID', 'hash2', 'host2@example.com', 'host2', 'Host Two'),
    (:'user3ID', 'hash3', 'speaker1@example.com', 'speaker1', 'Speaker One'),
    (:'user4ID', 'hash4', 'waitlist1@example.com', 'waitlist1', 'Waitlist One'),
    (:'user5ID', 'hash5', 'waitlist2@example.com', 'waitlist2', 'Waitlist Two'),
    (:'questionsOrganizerUserID', 'rq-hash-1', 'rq-organizer@example.com', 'rq-organizer', null),
    (:'questionsAttendeeUserID', 'rq-hash-2', 'rq-attendee@example.com', 'rq-attendee', null),
    (:'questionsHoldUserID', 'rq-hash-3', 'rq-hold@example.com', 'rq-hold', null);

-- Event Category
insert into event_category (event_category_id, name, community_id)
values
    (:'category1ID', 'Conference', :'community1ID'),
    (:'questionsEventCategoryID', 'General', :'questionsCommunityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values ('3a3c0000-0000-0000-0000-000000000030', 'Technology', :'community1ID');

-- Group category for registration-question update tests
insert into group_category (group_category_id, name, community_id)
values (:'questionsCategoryID', 'Technology', :'questionsCommunityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id,
    payment_recipient
) values (
    :'group1ID',
    :'community1ID',
    'Test Group',
    'abc1234',
    'A test group',
    '3a3c0000-0000-0000-0000-000000000030',
    '{"provider": "stripe", "recipient_id": "acct_update_ticketing", "seller_display_name": "Update Ticketing Fiscal Sponsor"}'::jsonb
);

-- Group for registration-question update tests
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    payment_recipient
) values (
    :'questionsGroupID',
    :'questionsCommunityID',
    :'questionsCategoryID',
    'Update Questions Group',
    'update-questions-group',
    '{"provider": "stripe", "recipient_id": "acct_update_questions", "seller_display_name": "Questions Fiscal Sponsor"}'::jsonb
);

-- Events used to update and lock registration questions
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    starts_at,
    registration_questions,
    payment_currency_code
) values (
    :'eventQuestionsID',
    :'questionsGroupID',
    'Draft Questions Event',
    'draft-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    false,
    '2030-01-01 10:00:00+00',
    '[]'::jsonb,
    null
), (
    :'eventQuestionsPublishedID',
    :'questionsGroupID',
    'Published Questions Event',
    'published-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    true,
    '2030-01-01 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', '3a3c0000-0000-0000-0000-000000000031',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    )),
    null
), (
    :'eventQuestionsAnsweredID',
    :'questionsGroupID',
    'Answered Questions Event',
    'answered-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    false,
    '2030-01-01 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', '3a3c0000-0000-0000-0000-000000000031',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    )),
    null
), (
    :'eventQuestionsHoldID',
    :'questionsGroupID',
    'Held Questions Event',
    'held-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    true,
    '2030-01-01 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', '3a3c0000-0000-0000-0000-000000000031',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    )),
    'USD'
);

-- Published event for waitlist promotion checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    waitlist_enabled
) values (
    :'event13ID',
    :'group1ID',
    'Published Waitlist Event',
    'published-waitlist',
    'Published event for waitlist promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-02-01 10:00:00+00',
    true
);

-- Published event used for attendee floor validation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at
) values (
    :'event14ID',
    :'group1ID',
    'Capacity Validation Event',
    'capacity-validation',
    'Published event for attendee floor validation checks',
    'America/New_York',
    :'category1ID',
    'in-person',
    3,
    true,
    '2030-02-10 10:00:00-05'
);

-- Published event used for waitlist promotion on capacity increase
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    ends_at,
    waitlist_enabled
) values (
    :'event15ID',
    :'group1ID',
    'Waitlist Promotion Event',
    'waitlist-promotion',
    'Published event for waitlist capacity increase promotion checks',
    'America/New_York',
    :'category1ID',
    'in-person',
    3,
    true,
    '2030-03-01 10:00:00-05',
    '2030-03-01 12:00:00-05',
    true
);

-- Published event used when waitlist is disabled for new joins
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    waitlist_enabled
) values (
    :'event16ID',
    :'group1ID',
    'Waitlist Disabled Event',
    'waitlist-disabled',
    'Published event for disabled waitlist promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    2,
    true,
    '2030-02-16 10:00:00+00',
    true
);

-- Published event already over capacity because of a confirmed manual invitation
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at
) values (
    :'eventOverCapacityID',
    :'group1ID',
    'Manual Invite Over Capacity Event',
    'manual-invite-over-capacity',
    'Published event for unchanged over-capacity save checks',
    'UTC',
    :'category1ID',
    'in-person',
    2,
    true,
    '2030-02-12 10:00:00+00'
);

-- Published event used when capacity becomes unlimited
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    waitlist_enabled
) values (
    :'event17ID',
    :'group1ID',
    'Unlimited Event',
    'unlimited-event',
    'Published event for unlimited capacity promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-02-17 10:00:00+00',
    true
);

-- Published event used for ticketing conversion without waitlist promotion
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    ends_at,
    waitlist_enabled
) values (
    :'event20ID',
    :'group1ID',
    'Ticketing Conversion Event',
    'ticketing-conversion',
    'Published event used to verify ticketing conversion does not promote waitlist users',
    'America/New_York',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-04-01 10:00:00-04',
    '2030-04-01 12:00:00-04',
    true
);

-- Event used for admission-tier payload validation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'event22ID',
    :'group1ID',
    'Admission Payload Event',
    'admission-payload',
    'Event used for admission-tier payload validation checks',
    'UTC',
    :'category1ID',
    'virtual'
);

-- Published event used for ticketing conversion waitlist checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    ends_at,
    waitlist_enabled
) values (
    :'event23ID',
    :'group1ID',
    'Ticketing Waitlist Event',
    'ticketing-waitlist',
    'Published event used for ticketing conversion waitlist checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-05-01 10:00:00+00',
    '2030-05-01 12:00:00+00',
    true
);

-- Approval-required event used for invitation request transition checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    attendee_approval_required
) values (
    :'event24ID',
    :'group1ID',
    'Approval Request Event',
    'approval-request',
    'Approval-required event used for invitation request checks',
    'UTC',
    :'category1ID',
    'virtual',
    true
);

-- Paid event used for ticketing preservation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    payment_currency_code,
    venue_address,
    venue_city,
    venue_country_code,
    venue_country_name,
    venue_name,
    venue_state_code,
    venue_state_name,
    venue_zip_code
) values (
    :'event19ID',
    :'group1ID',
    'Paid Event',
    'paid-event',
    'Event seeded for ticketing preservation tests',
    'UTC',
    :'category1ID',
    'in-person',
    10,
    'USD',
    '123 Main St',
    'San Francisco',
    'US',
    'United States',
    'Community Hall',
    'CA',
    'California',
    '94105'
);

-- Paid event used for purchased ticketing guard checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    payment_currency_code
) values (
    :'event21ID',
    :'group1ID',
    'Protected Paid Event',
    'protected-paid-event',
    'Paid event used for purchased ticketing guard checks',
    'UTC',
    :'category1ID',
    'virtual',
    10,
    'USD'
);

-- Separate event used only for ticketing ownership checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    payment_currency_code
) values (
    '3a3c0000-0000-0000-0000-000000000032'::uuid,
    :'group1ID',
    'Other Paid Event',
    'other-paid-event',
    'Event seeded for ticketing ownership tests',
    'UTC',
    :'category1ID',
    'virtual',
    'USD'
);

-- Paid in-person event used for event-kind transition checks
insert into event (
    capacity,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_country_name,
    venue_name,
    venue_state_code,
    venue_state_name,
    venue_zip_code
) values (
    10,
    'Paid event used for event-kind transition checks',
    :'category1ID',
    :'eventPaidTransitionID',
    'in-person',
    :'group1ID',
    'Paid Transition Event',
    'USD',
    'paid-transition-event',
    'UTC',
    '123 Main St',
    'San Francisco',
    'US',
    'United States',
    'Community Hall',
    'CA',
    'California',
    '94105'
);

-- Published ticketed event used to verify tier capacity reconciliation
insert into event (
    capacity,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    published_at,
    slug,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    1,
    'Published event for ticket queue capacity checks',
    :'category1ID',
    :'eventTicketQueueID',
    'virtual',
    :'group1ID',
    'Ticket Queue Capacity Event',
    'USD',
    true,
    current_timestamp,
    'ticket-queue-capacity-event',
    current_timestamp + interval '1 day',
    'UTC',
    true
);

-- Paid tier used for event-kind transition checks
insert into event_ticket_type (
    active,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    true,
    :'eventPaidTransitionID',
    :'paidTransitionTicketTypeID',
    1,
    10,
    'Hybrid admission'
);

insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    2500,
    :'paidTransitionPriceWindowID',
    :'paidTransitionTicketTypeID'
);

-- Ticket type initially owned by the primary ticketed event
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000033'::uuid,
    true,
    :'event19ID',
    1,
    10,
    'General'
);

-- Price window for the primary event ticket type
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000034'::uuid,
    2500,
    '3a3c0000-0000-0000-0000-000000000033'::uuid
);

-- Discount code initially owned by the primary ticketed event
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000035'::uuid,
    true,
    500,
    'SAVE20',
    :'event19ID',
    'fixed_amount',
    'Launch'
);

-- Protected ticket type referenced by a completed purchase
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000036'::uuid,
    true,
    :'event21ID',
    1,
    10,
    'Protected General'
);

-- Price window for the protected general ticket type
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000037'::uuid,
    2500,
    '3a3c0000-0000-0000-0000-000000000036'::uuid
);

-- Second protected ticket type used by synchronization scenarios
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000038'::uuid,
    true,
    :'event21ID',
    2,
    5,
    'Protected VIP'
);

-- Price window for the protected VIP ticket type
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000039'::uuid,
    5000,
    '3a3c0000-0000-0000-0000-000000000038'::uuid
);

-- Protected discount code referenced by a completed purchase
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title,
    total_available
) values (
    '3a3c0000-0000-0000-0000-000000000040'::uuid,
    true,
    500,
    'PROTECT5',
    :'event21ID',
    'fixed_amount',
    'Protected launch',
    5
);

-- Ticketing rows on a different event used for ownership checks
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000041'::uuid,
    true,
    '3a3c0000-0000-0000-0000-000000000032'::uuid,
    1,
    25,
    'Other Event General'
);

-- Price window owned by the other event
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000042'::uuid,
    3000,
    '3a3c0000-0000-0000-0000-000000000041'::uuid
);

-- Full public tier expanded by the capacity reconciliation test
insert into event_ticket_type (
    active,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    true,
    :'eventTicketQueueID',
    :'ticketQueueTicketTypeID',
    1,
    1,
    'Queue General'
);

-- Current price for the capacity reconciliation tier
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    2500,
    :'ticketQueuePriceWindowID',
    :'ticketQueueTicketTypeID'
);

-- Discount code owned by the other event
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000043'::uuid,
    true,
    250,
    'OTHER25',
    '3a3c0000-0000-0000-0000-000000000032'::uuid,
    'fixed_amount',
    'Other launch'
);

-- Ticket type referenced by a pending registration-answer hold
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'questionsHoldTicketTypeID',
    true,
    :'eventQuestionsHoldID',
    1,
    10,
    'Held General'
);

-- Price window for the held ticket type
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'questionsHoldPriceWindowID',
    2500,
    :'questionsHoldTicketTypeID'
);

-- Completed purchase that protects ticketing rows from removal
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    'PROTECT5',
    '3a3c0000-0000-0000-0000-000000000040'::uuid,
    :'event21ID',
    '3a3c0000-0000-0000-0000-000000000036'::uuid,
    'completed',
    'Protected General',
    :'user1ID'
);

-- Completed purchase occupying the capacity reconciliation tier
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'eventTicketQueueID',
    :'ticketQueuePurchaseID',
    :'ticketQueueTicketTypeID',
    'completed',
    'Queue General',
    :'user1ID'
);

-- Pending purchase that retains registration answers during ticketing updates
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'questionsHoldPurchaseID',
    0,
    'USD',
    :'eventQuestionsHoldID',
    :'questionsHoldTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Held General',
    :'questionsHoldUserID'
);

-- Every event uses ticket inventory. Seed a default free tier for events that
-- are not exercising an explicit ticket configuration in this test
insert into event_ticket_type (
    active,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select
    true,
    e.event_id,
    gen_random_uuid(),
    1,
    greatest(coalesce(e.capacity, 100), 1),
    'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free prices for the default ticket tiers
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select
    0,
    gen_random_uuid(),
    ett.event_ticket_type_id
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Event Attendees (for capacity validation and waitlist promotion tests)
insert into event_attendee (event_id, user_id) values
    (:'event13ID', :'user2ID'),
    (:'event14ID', :'user1ID'),
    (:'event14ID', :'user2ID'),
    (:'event14ID', :'user3ID'),
    (:'event15ID', :'user1ID'),
    (:'event15ID', :'user2ID'),
    (:'event15ID', :'user3ID'),
    (:'event16ID', :'user2ID'),
    (:'event16ID', :'user3ID'),
    (:'event17ID', :'user2ID'),
    (:'event20ID', :'user1ID');

-- Over-capacity event attendees with one organizer-controlled manual seat
insert into event_attendee (event_id, user_id, manually_invited, status) values
    (:'eventOverCapacityID', :'user1ID', false, 'confirmed'),
    (:'eventOverCapacityID', :'user2ID', false, 'confirmed'),
    (:'eventOverCapacityID', :'user3ID', true, 'confirmed');

-- Attendee with answers that lock registration questions
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventQuestionsAnsweredID',
    :'questionsAttendeeUserID',
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', '3a3c0000-0000-0000-0000-000000000031',
            'value', 'Answer'
        ))
    ),
    'confirmed'
);

-- Event Waitlist (for waitlist promotion tests)
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
)
select
    waitlisted.created_at,
    waitlisted.event_id,
    (
        select ett.event_ticket_type_id
        from event_ticket_type ett
        where ett.event_id = waitlisted.event_id
        order by ett."order", ett.event_ticket_type_id
        limit 1
    ),
    waitlisted.user_id
from (
    values
        (:'event13ID'::uuid, :'user3ID'::uuid, current_timestamp),
        (:'event15ID'::uuid, :'user4ID'::uuid, current_timestamp),
        (:'event15ID'::uuid, :'user5ID'::uuid, current_timestamp + interval '1 minute'),
        (:'event16ID'::uuid, :'user1ID'::uuid, current_timestamp + interval '2 minutes'),
        (:'event17ID'::uuid, :'user4ID'::uuid, current_timestamp + interval '3 minutes'),
        (:'event17ID'::uuid, :'user5ID'::uuid, current_timestamp + interval '4 minutes'),
        (:'event20ID'::uuid, :'user4ID'::uuid, current_timestamp + interval '5 minutes'),
        (:'event23ID'::uuid, :'user5ID'::uuid, current_timestamp + interval '6 minutes')
) as waitlisted(event_id, user_id, created_at);

-- Tier-specific FIFO queue promoted after ticket capacity increases
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    current_timestamp,
    :'eventTicketQueueID',
    :'ticketQueueTicketTypeID',
    :'user4ID'
);

-- Event invitation requests (for attendee approval transition tests)
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    user_id
)
select
    :'event24ID',
    ett.event_ticket_type_id,
    :'user5ID'
from event_ticket_type ett
where ett.event_id = :'event24ID'
order by ett."order", ett.event_ticket_type_id
limit 1;

-- Test-only overloads keep existing calls focused while supplying server payment configuration.
create function update_event_with_payments(uuid, uuid, uuid, jsonb)
returns void as $$
    select update_event(
        $1,
        $2,
        $3,
        case
            when $4 ? '_payment_validation' then $4
            else $4 || jsonb_build_object(
                '_payment_validation',
                jsonb_build_object(
                    'expected_payment_recipient', g.payment_recipient,
                    'require_automatic_tax', true,
                    'validated_payment_recipient', g.payment_recipient
                )
            )
        end,
        null,
        'stripe'
    )
    from "group" g
    where g.group_id = $2;
$$ language sql;

create function update_event_with_payments(uuid, uuid, uuid, jsonb, jsonb)
returns void as $$
    select update_event(
        $1,
        $2,
        $3,
        case
            when $4 ? '_payment_validation' then $4
            else $4 || jsonb_build_object(
                '_payment_validation',
                jsonb_build_object(
                    'expected_payment_recipient', g.payment_recipient,
                    'require_automatic_tax', true,
                    'validated_payment_recipient', g.payment_recipient
                )
            )
        end,
        $5,
        'stripe'
    )
    from "group" g
    where g.group_id = $2;
$$ language sql;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should preserve ticketing fields when payload omits payment controls
select lives_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "meeting_requested": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'Should preserve ticketing fields when payload omits payment controls'
);
select is(
    (
        select jsonb_build_object(
            'discount_codes', list_event_discount_codes(event_id),
            'payment_currency_code', payment_currency_code,
            'ticket_types', list_event_ticket_types(event_id)
        )
        from event
        where event_id = :'event19ID'::uuid
    ),
    '{
        "discount_codes": [
            {
                "active": true,
                "amount_minor": 500,
                "available_override_active": false,
                "code": "SAVE20",
                "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000035",
                "kind": "fixed_amount",
                "title": "Launch"
            }
        ],
        "payment_currency_code": "USD",
        "ticket_types": [
            {
                "active": true,
                "availability": "public",
                "current_price": {
                    "amount_minor": 2500
                },
                "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000034"
                    }
                ],
                "remaining_seats": 10,
                "seats_total": 10,
                "sold_out": false,
                "title": "General"
            }
        ]
    }'::jsonb,
    'Should keep ticketing fields when payload omits payment controls'
);
select is(
    (select capacity from event where event_id = :'event19ID'::uuid),
    10,
    'Should preserve derived capacity when payload omits payment controls'
);

-- Should allow an in-person paid event to become hybrid
select lives_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000068'::uuid,
        '{
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                }
            },
            "name": "Paid Hybrid Event",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "hybrid",
            "meeting_requested": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'Should allow an in-person paid event to become hybrid'
);

select is(
    (
        select jsonb_build_object(
            'amount_minor', etpw.amount_minor,
            'event_kind_id', e.event_kind_id,
            'payment_currency_code', e.payment_currency_code,
            'venue_address', e.venue_address,
            'venue_city', e.venue_city,
            'venue_country_code', e.venue_country_code,
            'venue_country_name', e.venue_country_name,
            'venue_name', e.venue_name,
            'venue_state_code', e.venue_state_code,
            'venue_state_name', e.venue_state_name,
            'venue_zip_code', e.venue_zip_code
        )
        from event e
        join event_ticket_type ett using (event_id)
        join event_ticket_price_window etpw using (event_ticket_type_id)
        where e.event_id = :'eventPaidTransitionID'::uuid
    ),
    '{
        "amount_minor": 2500,
        "event_kind_id": "hybrid",
        "payment_currency_code": "USD",
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_country_code": "US",
        "venue_country_name": "United States",
        "venue_name": "Community Hall",
        "venue_state_code": "CA",
        "venue_state_name": "California",
        "venue_zip_code": "94105"
    }'::jsonb,
    'Should persist paid hybrid ticketing and its complete physical venue'
);

-- Should reject changing a paid hybrid event to virtual
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000068'::uuid,
        '{
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                }
            },
            "name": "Paid Virtual Event",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "meeting_requested": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should reject changing a paid hybrid event to virtual'
);

-- Should reject unrelated edits after payment setup is lost
select throws_ok(
    $$
        select update_event(
            null::uuid,
            '3a3c0000-0000-0000-0000-000000000018'::uuid,
            '3a3c0000-0000-0000-0000-000000000008'::uuid,
            '{
                "name": "Paid Event Without Payment Setup",
                "description": "Unrelated edits remain available",
                "timezone": "UTC",
                "category_id": "3a3c0000-0000-0000-0000-000000000001",
                "kind_id": "virtual",
                "meeting_requested": false,
                "payment_currency_code": "USD",
                "discount_codes": [
                    {
                        "active": true,
                        "amount_minor": 500,
                        "available_override_active": false,
                        "code": "SAVE20",
                        "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000035",
                        "kind": "fixed_amount",
                        "title": "Launch"
                    }
                ],
                "ticket_types": [
                    {
                        "active": true,
                        "availability": "public",
                        "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 2500,
                                "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000034"
                            }
                        ],
                        "seats_total": 10,
                        "title": "General"
                    }
                ]
            }'::jsonb,
            null,
            null
        )
    $$,
    'payments are not configured on this server',
    'Should reject unrelated edits after payment setup is lost'
);

-- Should reject removing every ticket type
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": null,
            "ticket_types": null
        }'::jsonb
    )$$,
    'events require at least one ticket type',
    'Should reject removing every ticket type'
);

-- Should throw error when a ticket type identifier belongs to another event
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000041",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000044"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticket type does not belong to event',
    'Should reject ticket types whose identifiers belong to another event'
);

-- Should throw error when a ticket price window identifier belongs to another event
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000042"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticket price window does not belong to event',
    'Should reject ticket price windows whose identifiers belong to another event'
);

-- Should throw error when a ticket price window identifier belongs to another ticket type
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000036",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 10,
                    "title": "Protected General"
                },
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000038",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 5,
                    "title": "Protected VIP"
                }
            ]
        }'::jsonb
    )$$,
    'ticket price window does not belong to ticket type',
    'Should reject ticket price windows whose identifiers belong to another ticket type'
);

-- Should throw error when a discount code identifier belongs to another event
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 250,
                    "code": "OTHER25",
                    "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000043",
                    "kind": "fixed_amount",
                    "title": "Other launch"
                }
            ],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'discount code does not belong to event',
    'Should reject discount codes whose identifiers belong to another event'
);

-- Should throw an error when paid tiers omit payment_currency_code
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000011'::uuid,
        '{
            "name": "Admission Payload Event",
            "description": "Event used for admission-tier payload validation checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000047",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000048"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'paid-capable events require payment_currency_code',
    'Should reject paid-capable events when payment_currency_code is omitted'
);

-- Should allow waitlists with paid admission tiers
select lives_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000011'::uuid,
        '{
            "name": "Admission Payload Event",
            "description": "Event used for admission-tier payload validation checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000049",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000050"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ],
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105",
            "waitlist_enabled": true
        }'::jsonb
    )$$,
    'Should allow paid-tier events when waitlist_enabled stays true'
);

-- Should reject disabling attendee approval while invitation requests are pending
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000013'::uuid,
        '{
            "name": "Approval Request Event",
            "description": "Approval-required event used for invitation request checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "attendee_approval_required": false
        }'::jsonb
    )$$,
    'approval-required events with pending invitation requests cannot disable approval',
    'Should reject disabling attendee approval while invitation requests are pending'
);

-- Should reject enabling attendee approval while waitlist entries exist
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000012'::uuid,
        '{
            "name": "Ticketing Waitlist Event",
            "description": "Published event used for ticketing conversion waitlist checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "attendee_approval_required": true,
            "capacity": 1,
            "ends_at": "2030-05-01T12:00:00",
            "starts_at": "2030-05-01T10:00:00",
            "waitlist_enabled": false
        }'::jsonb
    )$$,
    'approval-required events cannot have existing waitlist entries',
    'Should reject enabling attendee approval while queued users already exist'
);

-- Should throw error when ticket seats are reduced below purchased inventory
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000036",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000037"
                        }
                    ],
                    "seats_total": 0,
                    "title": "Protected General"
                },
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000038",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 5,
                    "title": "Protected VIP"
                }
            ]
        }'::jsonb
    )$$,
    'ticket type seats_total (0) cannot be less than current allocated seats (1)',
    'Should reject seat totals below the current purchased inventory for a ticket type'
);

-- Should throw error when purchased ticket types are removed
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000038",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 5,
                    "title": "Protected VIP"
                }
            ]
        }'::jsonb
    )$$,
    'ticket types with purchases cannot be removed; deactivate them instead',
    'Should reject removing ticket types that already have purchases'
);

-- Should throw error when discount code total_available drops below redemptions
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 500,
                    "code": "PROTECT5",
                    "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000040",
                    "kind": "fixed_amount",
                    "title": "Protected launch",
                    "total_available": 0
                }
            ],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'discount code total_available cannot be less than existing redemptions',
    'Should reject lowering discount code availability below existing redemptions'
);

-- Should throw error when redeemed discount codes are removed
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'discount codes with redemptions cannot be removed; deactivate them instead',
    'Should reject removing discount codes that already have redemptions'
);

-- Should reconcile a public ticket queue after tier capacity increases
select lives_ok(
    format($$select update_event_with_payments(
        null::uuid,
        %L::uuid,
        %L::uuid,
        %L::jsonb
    )$$,
        :'group1ID',
        :'eventTicketQueueID',
        format(
            '{
                "name": "Ticket Queue Capacity Event",
                "description": "Published event for ticket queue capacity checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "payment_currency_code": "USD",
                "starts_at": "2030-02-17T10:00:00",
                "ticket_types": [
                    {
                        "active": true,
                        "availability": "public",
                        "event_ticket_type_id": "%s",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 2500,
                                "event_ticket_price_window_id": "%s"
                            }
                        ],
                        "seats_total": 2,
                        "title": "Queue General"
                    }
                ],
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_state_code": "CA",
                "venue_state_name": "California",
                "venue_zip_code": "94105"
            }',
            :'category1ID',
            :'ticketQueueTicketTypeID',
            :'ticketQueuePriceWindowID'
        )
    ),
    'Should update ticket capacity and reconcile its queue'
);

-- Should assign the newly available ticket seat to the FIFO queue head
select is(
    (
        select jsonb_build_object(
            'offer_status', (
                select status
                from admission_offer
                where event_id = :'eventTicketQueueID'::uuid
                and user_id = :'user4ID'::uuid
            ),
            'seats_total', (
                select seats_total
                from event_ticket_type
                where event_ticket_type_id = :'ticketQueueTicketTypeID'::uuid
            ),
            'waitlist_count', (
                select count(*)
                from event_waitlist
                where event_id = :'eventTicketQueueID'::uuid
            )
        )
    ),
    '{"offer_status":"pending","seats_total":2,"waitlist_count":0}'::jsonb,
    'Should promote the ticket queue after capacity increases'
);

-- Should update registration questions while the event is unpublished
select lives_ok(
    $$
        select update_event_with_payments(
            '3a3c0000-0000-0000-0000-000000000024'::uuid,
            '3a3c0000-0000-0000-0000-000000000023'::uuid,
            '3a3c0000-0000-0000-0000-000000000016'::uuid,
            '{"name": "Draft Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Original", "required": true, "options": []}]}'::jsonb
        )
    $$,
    'Should update registration questions while the event is unpublished'
);

-- Should store updated registration questions
select is(
    (
        select registration_questions
        from event
        where event_id = :'eventQuestionsID'::uuid
    ),
    '[{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Original", "required": true, "options": []}]'::jsonb,
    'Should store updated registration questions'
);

-- Should validate registration questions when updating an event
select throws_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000016'::uuid,
        '{"name": "Draft Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "bad", "kind": "free-text", "prompt": "Invalid", "required": true, "options": []}]}'::jsonb
    )$$,
    'questionnaire question id must be a uuid',
    'Should validate registration questions when updating an event'
);

-- Should update registration questions after publish when no answers exist
select lives_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000017'::uuid,
        '{"name": "Published Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'Should update registration questions after publish when no answers exist'
);

-- Should preserve registration questions when answers exist and questions are omitted
select lives_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000015'::uuid,
        '{"name": "Answered Questions Event Updated", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z"}'::jsonb
    )$$,
    'Should preserve registration questions when answers exist and questions are omitted'
);

-- Should reject registration question changes after answers exist
select throws_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000015'::uuid,
        '{"name": "Answered Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'registration questions cannot be changed after attendees have submitted answers',
    'Should reject registration question changes after answers exist'
);

-- Should allow unrelated event edits while checkout holds are active
select lives_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000056'::uuid,
        '{"name": "Held Questions Event Updated", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "venue_address": "123 Main St", "venue_city": "San Francisco", "venue_country_code": "US", "venue_name": "Community Hall", "venue_state_code": "CA", "venue_state_name": "California", "venue_zip_code": "94105"}'::jsonb
    )$$,
    'Should allow unrelated event edits while checkout holds are active'
);

-- Should reject registration question changes while checkout holds are active
select throws_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000056'::uuid,
        '{"name": "Held Questions Event Updated", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'registration questions cannot be changed while checkout holds are active',
    'Should reject registration question changes while checkout holds are active'
);

-- Should clear payment-only configuration when the final positive price is removed
select lives_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "discount_codes": null,
            "ticket_types": [
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 0,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000034"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'Should clear payment-only configuration with the final positive price'
);

-- Should persist the provider-free configuration with its free ticket tier
select results_eq(
    $$
        select
            payment_currency_code,
            (select count(*)::int from event_discount_code where event_id = e.event_id),
            (select count(*)::int from event_ticket_type where event_id = e.event_id)
        from event e
        where event_id = '3a3c0000-0000-0000-0000-000000000008'::uuid
    $$,
    $$ values (null::text, 0::int, 1::int) $$,
    'Should persist provider-free configuration with its free ticket tier'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
