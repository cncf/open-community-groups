-- Tests updating event configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(51);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '3a390000-0000-0000-0000-000000000001'
\set category2ID '3a390000-0000-0000-0000-000000000002'
\set community1ID '3a390000-0000-0000-0000-000000000003'
\set event1ID '3a390000-0000-0000-0000-000000000004'
\set eventExternalClearID '3a390000-0000-0000-0000-000000000050'
\set eventExternalClearPriceWindowID '3a390000-0000-0000-0000-000000000051'
\set eventExternalClearPurchaseID '3a390000-0000-0000-0000-000000000062'
\set eventExternalClearTicketTypeID '3a390000-0000-0000-0000-000000000052'
\set eventExternalDelistedID '3a390000-0000-0000-0000-00000000005a'
\set eventExternalDelistedPriceWindowID '3a390000-0000-0000-0000-00000000005b'
\set eventExternalDelistedTicketTypeID '3a390000-0000-0000-0000-00000000005c'
\set eventExternalPaidID '3a390000-0000-0000-0000-000000000053'
\set eventExternalPaidPriceWindowID '3a390000-0000-0000-0000-000000000054'
\set eventExternalPaidPurchaseID '3a390000-0000-0000-0000-000000000063'
\set eventExternalPaidTicketTypeID '3a390000-0000-0000-0000-000000000055'
\set eventExternalPendingClearID '3a390000-0000-0000-0000-00000000005e'
\set eventExternalPendingClearPriceWindowID '3a390000-0000-0000-0000-00000000005f'
\set eventExternalPendingClearPurchaseID '3a390000-0000-0000-0000-000000000060'
\set eventExternalPendingClearTicketTypeID '3a390000-0000-0000-0000-000000000061'
\set eventExternalStripeID '3a390000-0000-0000-0000-000000000056'
\set eventExternalStripePriceWindowID '3a390000-0000-0000-0000-000000000057'
\set eventExternalStripeTicketTypeID '3a390000-0000-0000-0000-000000000058'
\set groupDelistedID '3a390000-0000-0000-0000-00000000005d'
\set groupExternalID '3a390000-0000-0000-0000-000000000059'
\set event4ID '3a390000-0000-0000-0000-000000000005'
\set event10ID '3a390000-0000-0000-0000-000000000006'
\set event11ID '3a390000-0000-0000-0000-000000000007'
\set event12ID '3a390000-0000-0000-0000-000000000008'
\set event18ID '3a390000-0000-0000-0000-000000000009'
\set eventFreeToPaidID '3a390000-0000-0000-0000-000000000023'
\set eventFreeToPaidPriceWindowID '3a390000-0000-0000-0000-000000000026'
\set eventFreeToPaidTicketTypeID '3a390000-0000-0000-0000-000000000027'
\set eventManualTaxID '3a390000-0000-0000-0000-000000000041'
\set eventPaidToFreeID '3a390000-0000-0000-0000-000000000024'
\set eventPaidToFreePriceWindowID '3a390000-0000-0000-0000-000000000028'
\set eventPaidToFreeTicketTypeID '3a390000-0000-0000-0000-000000000029'
\set eventPaidToPaidID '3a390000-0000-0000-0000-000000000025'
\set eventPaidToPaidPriceWindowID '3a390000-0000-0000-0000-000000000030'
\set eventPaidToPaidTicketTypeID '3a390000-0000-0000-0000-000000000031'
\set eventTestFreeToPaidID '3a390000-0000-0000-0000-000000000032'
\set eventTestFreeToPaidPriceWindowID '3a390000-0000-0000-0000-000000000033'
\set eventTestFreeToPaidTicketTypeID '3a390000-0000-0000-0000-000000000034'
\set eventTestPaidToLiveID '3a390000-0000-0000-0000-000000000035'
\set eventTestPaidToLivePriceWindowID '3a390000-0000-0000-0000-000000000036'
\set eventTestPaidToLiveTicketTypeID '3a390000-0000-0000-0000-000000000037'
\set eventTestPaidToTestID '3a390000-0000-0000-0000-000000000038'
\set eventTestPaidToTestPriceWindowID '3a390000-0000-0000-0000-000000000039'
\set eventTestPaidToTestTicketTypeID '3a390000-0000-0000-0000-000000000040'
\set eventWaitlistWindowID '3a390000-0000-0000-0000-000000000021'
\set group1ID '3a390000-0000-0000-0000-000000000010'
\set label1ID '3a390000-0000-0000-0000-000000000011'
\set label2ID '3a390000-0000-0000-0000-000000000012'
\set label3ID '3a390000-0000-0000-0000-000000000013'
\set label4ID '3a390000-0000-0000-0000-000000000014'
\set sponsorNewID '3a390000-0000-0000-0000-000000000015'
\set sponsorOrigID '3a390000-0000-0000-0000-000000000016'
\set user1ID '3a390000-0000-0000-0000-000000000009'
\set user2ID '3a390000-0000-0000-0000-000000000017'
\set user3ID '3a390000-0000-0000-0000-000000000018'
\set waitlistUserID '3a390000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist and window limits used by external update scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

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

-- Users
insert into "user" (user_id, auth_hash, email, username, name) values
    (:'user1ID', 'hash1', 'host1@example.com', 'host1', 'Host One'),
    (:'user2ID', 'hash2', 'host2@example.com', 'host2', 'Host Two'),
    (:'user3ID', 'hash3', 'speaker1@example.com', 'speaker1', 'Speaker One'),
    (:'waitlistUserID', 'hash4', 'waitlist@example.com', 'waitlist', 'Waitlist User');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values
    (:'category1ID', 'Conference', :'community1ID'),
    (:'category2ID', 'Workshop', :'community1ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values ('3a390000-0000-0000-0000-000000000006', 'Technology', :'community1ID');

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
    '3a390000-0000-0000-0000-000000000006',
    '{"provider": "stripe", "recipient_id": "acct_update_event", "seller_display_name": "Update Event Fiscal Sponsor"}'::jsonb
);

-- Allowlisted group with external payments enabled for external update scenarios
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'community1ID',
    'KR',
    true,
    '3a390000-0000-0000-0000-000000000006',
    :'groupExternalID',
    'External Update Group',
    'external-update-group'
);

-- Delisted-country group used to reject a preserved external URL
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'community1ID',
    'US',
    true,
    '3a390000-0000-0000-0000-000000000006',
    :'groupDelistedID',
    'Delisted External Group',
    'delisted-external-group'
);

-- Events used for paid-capability transition results
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    payment_currency_code,
    test_event
) values (
    :'eventFreeToPaidID',
    'Free event used for paid transition checks',
    :'category1ID',
    'virtual',
    :'group1ID',
    'Free To Paid',
    'free-to-paid',
    'UTC',

    null,
    false
), (
    :'eventPaidToFreeID',
    'Paid event used for free transition checks',
    :'category1ID',
    'virtual',
    :'group1ID',
    'Paid To Free',
    'paid-to-free',
    'UTC',

    'USD',
    false
), (
    :'eventPaidToPaidID',
    'Paid event used for paid edit checks',
    :'category1ID',
    'virtual',
    :'group1ID',
    'Paid To Paid',
    'paid-to-paid',
    'UTC',

    'USD',
    false
), (
    :'eventTestFreeToPaidID',
    'Free test event promoted while adding paid tickets',
    :'category1ID',
    'virtual',
    :'group1ID',
    'Test Free To Paid',
    'test-free-to-paid',
    'UTC',

    null,
    true
), (
    :'eventTestPaidToLiveID',
    'Paid test event promoted without changing tickets',
    :'category1ID',
    'virtual',
    :'group1ID',
    'Test Paid To Live',
    'test-paid-to-live',
    'UTC',

    'USD',
    true
), (
    :'eventTestPaidToTestID',
    'Paid test event that remains a test event',
    :'category1ID',
    'virtual',
    :'group1ID',
    'Test Paid To Test',
    'test-paid-to-test',
    'UTC',

    'USD',
    true
);

-- Free manual-tax event with a selection that can be explicitly cleared
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    manual_tax_rate_ids,
    name,
    slug,
    tax_behavior,
    tax_calculation_mode,
    timezone
) values (
    :'eventManualTaxID',
    'Free manual-tax event used for selection clearing checks',
    :'category1ID',
    'virtual',
    :'group1ID',
    array['txr_state']::text[],
    'Manual Tax Selection',
    'manual-tax-selection',
    'inclusive',
    'manual',
    'UTC'
);

-- Existing ISO fields exercise updates from the deferred legacy form.
update event
set
    venue_country_code = 'US',
    venue_state_code = 'CA',
    venue_state_name = 'California'
where event_id = :'eventFreeToPaidID';

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', null),
    (
        :'sponsorNewID',
        :'group1ID',
        'NewSponsor Inc',
        'https://example.com/newsponsor.png',
        'https://newsponsor.com'
    );

-- Event
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
    :'event1ID',
    :'group1ID',
    'Original Event',
    'def5678',
    'Original description',
    'America/New_York',
    :'category1ID',
    'in-person'
);

-- Add initial host and sponsor to the event
insert into event_host (event_id, user_id) values (:'event1ID', :'user1ID');

-- Initial speaker synchronized by the event update
insert into event_speaker (event_id, user_id, featured) values (:'event1ID', :'user1ID', true);

-- Initial sponsor synchronized by the event update
insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'event1ID', :'sponsorOrigID', 'Bronze');

-- Canceled Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,

    canceled
) values (
    :'event4ID',
    :'group1ID',
    'Canceled Event',
    'pqr4jkl',
    'This event was canceled',
    'America/New_York',
    :'category1ID',
    'in-person',

    true
);

-- Published event used for reminder evaluation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published
) values (
    :'event10ID',
    :'group1ID',
    'Reminder Event',
    'yz12abc',
    'Published event for reminder evaluation checks',
    'UTC',
    :'category1ID',
    'virtual',
    current_timestamp + interval '2 days',
    current_timestamp + interval '2 days 2 hours',
    true
);

-- Published soon-starting event used for reminder regression checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published
) values (
    :'event11ID',
    :'group1ID',
    'Reminder Event Soon',
    'lmn45op',
    'Published soon event for reminder regression checks',
    'UTC',
    :'category1ID',
    'virtual',
    current_timestamp + interval '10 hours',
    current_timestamp + interval '12 hours',
    true
);

-- Event used for CFS labels update checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    cfs_description,
    cfs_enabled,
    cfs_ends_at,
    cfs_starts_at,
    starts_at,
    ends_at
) values (
    :'event12ID',
    :'group1ID',
    'Event With Labels',
    'opq67rs',
    'Event seeded for CFS labels update tests',
    'UTC',
    :'category1ID',
    'virtual',
    'Initial CFS description',
    true,
    '2030-01-05 00:00:00+00',
    '2029-12-20 00:00:00+00',
    '2030-01-15 10:00:00+00',
    '2030-01-15 12:00:00+00'
);

-- Event used for CFS label upsert checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    cfs_description,
    cfs_enabled,
    cfs_ends_at,
    cfs_starts_at,
    starts_at,
    ends_at
) values (
    :'event18ID',
    :'group1ID',
    'Event With Labels For Upsert',
    'upsert-labels',
    'Event seeded for CFS labels upsert tests',
    'UTC',
    :'category1ID',
    'virtual',
    'Initial CFS description',
    true,
    '2030-01-05 00:00:00+00',
    '2029-12-20 00:00:00+00',
    '2030-01-15 10:00:00+00',
    '2030-01-15 12:00:00+00'
);

-- Live event used for update-driven waitlist promotion checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    registration_starts_at,
    published,
    capacity,
    waitlist_enabled
) values (
    :'eventWaitlistWindowID',
    :'group1ID',
    'Open Only Waitlist Event',
    'open-only-waitlist-event',
    'Event seeded for registration window waitlist update tests',
    'UTC',
    :'category1ID',
    'in-person',
    date_trunc('second', current_timestamp - interval '1 hour'),
    date_trunc('second', current_timestamp + interval '1 hour'),
    date_trunc('second', current_timestamp - interval '2 hours'),
    true,
    1,
    true
);

-- CFS labels seeded for update and upsert checks
insert into event_cfs_label (event_cfs_label_id, event_id, color, name) values
    (:'label1ID', :'event12ID', '#CCFBF1', 'track / backend'),
    (:'label2ID', :'event12ID', '#FEE2E2', 'track / frontend');

-- Existing labels owned by a different event
insert into event_cfs_label (event_cfs_label_id, event_id, color, name) values
    (:'label3ID', :'event18ID', '#CCFBF1', 'track / backend'),
    (:'label4ID', :'event18ID', '#FEE2E2', 'track / frontend');

-- Attendee used by reminder evaluation checks
insert into event_attendee (event_id, user_id)
values (:'event10ID', :'user1ID');

-- Occupied seat and waitlist entry used by update-driven promotion checks
insert into event_attendee (event_id, user_id)
values (:'eventWaitlistWindowID', :'user2ID');

-- Every update fixture uses the unified ticket inventory
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
select
    case e.event_id
        when :'eventFreeToPaidID'::uuid then :'eventFreeToPaidTicketTypeID'::uuid
        when :'eventPaidToFreeID'::uuid then :'eventPaidToFreeTicketTypeID'::uuid
        when :'eventPaidToPaidID'::uuid then :'eventPaidToPaidTicketTypeID'::uuid
        when :'eventTestFreeToPaidID'::uuid then :'eventTestFreeToPaidTicketTypeID'::uuid
        when :'eventTestPaidToLiveID'::uuid then :'eventTestPaidToLiveTicketTypeID'::uuid
        when :'eventTestPaidToTestID'::uuid then :'eventTestPaidToTestTicketTypeID'::uuid
        else gen_random_uuid()
    end,
    e.event_id,
    1,
    coalesce(e.capacity, 100),
    'General Admission'
from event e
where e.group_id = :'group1ID';

-- Price windows defining free and paid update scenarios
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
)
select
    case e.event_id
        when :'eventFreeToPaidID'::uuid then :'eventFreeToPaidPriceWindowID'::uuid
        when :'eventPaidToFreeID'::uuid then :'eventPaidToFreePriceWindowID'::uuid
        when :'eventPaidToPaidID'::uuid then :'eventPaidToPaidPriceWindowID'::uuid
        when :'eventTestFreeToPaidID'::uuid then :'eventTestFreeToPaidPriceWindowID'::uuid
        when :'eventTestPaidToLiveID'::uuid then :'eventTestPaidToLivePriceWindowID'::uuid
        when :'eventTestPaidToTestID'::uuid then :'eventTestPaidToTestPriceWindowID'::uuid
        else gen_random_uuid()
    end,
    case
        when e.event_id in (
            :'eventPaidToFreeID'::uuid,
            :'eventPaidToPaidID'::uuid,
            :'eventTestPaidToLiveID'::uuid,
            :'eventTestPaidToTestID'::uuid
        ) then 1200
        else 0
    end,
    ett.event_ticket_type_id
from event_ticket_type ett
join event e using (event_id)
where e.group_id = :'group1ID';

-- Waitlisted user eligible for promotion after the event update
insert into event_waitlist (event_id, event_ticket_type_id, user_id, created_at)
select
    :'eventWaitlistWindowID',
    (
        select ett.event_ticket_type_id
        from event_ticket_type ett
        where ett.event_id = :'eventWaitlistWindowID'
        order by ett."order", ett.event_ticket_type_id
        limit 1
    ),
    :'waitlistUserID',
    current_timestamp - interval '30 minutes';

-- Paid Stripe-shaped event on the non-external group used to prove leftover URLs clear
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    external_payment_window_hours,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    'Paid event that still carries leftover external fields',
    :'category1ID',
    :'eventExternalClearID',
    'in-person',
    'https://pay.example.test/leftover',
    48,
    :'group1ID',
    'External Clear Event',
    'USD',
    false,
    'external-clear-event',
    'automatic',
    'UTC',
    '123 Main St',
    'San Francisco',
    'US',
    'Community Hall',
    '94105'
);

-- Paid leftover-URL event whose pending hold must keep the live event URL
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    external_payment_window_hours,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    'Paid event whose pending external hold keeps the live URL',
    :'category1ID',
    :'eventExternalPendingClearID',
    'in-person',
    'https://pay.example.test/pending-clear',
    48,
    :'group1ID',
    'External Pending Clear Event',
    'USD',
    false,
    'external-pending-clear-event',
    'automatic',
    'UTC',
    '123 Main St',
    'San Francisco',
    'US',
    'Community Hall',
    '94105'
);

-- Paid event that keeps an external URL after the country leaves the allowlist
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    external_payment_window_hours,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    'Paid event whose group country is no longer allowlisted',
    :'category1ID',
    :'eventExternalDelistedID',
    'in-person',
    'https://pay.example.test/delisted',
    48,
    :'groupDelistedID',
    'External Delisted Event',
    'USD',
    false,
    'external-delisted-event',
    'none',
    'UTC',
    '123 Main St',
    'San Francisco',
    'US',
    'Community Hall',
    '94105'
);

-- Paid external-group event without a URL that stays Stripe until URL is set
insert into event (
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
    tax_behavior,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    'Published Stripe event waiting for an external URL',
    :'category1ID',
    :'eventExternalStripeID',
    'in-person',
    :'groupExternalID',
    'External Stripe Event',
    'KRW',
    true,
    'external-stripe-event',
    current_timestamp + interval '7 days',
    'inclusive',
    'automatic',
    'UTC',
    '1 Test Street',
    'Seoul',
    'KR',
    'Test Hall',
    '00000'
);

-- Paid external-group event already marked with a URL for window and tax updates
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    tax_behavior,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    'External event updated for window and tax normalization',
    :'category1ID',
    :'eventExternalPaidID',
    'in-person',
    'https://pay.example.test/update',
    :'groupExternalID',
    'External Paid Event',
    'KRW',
    false,
    'external-paid-event',
    'exclusive',
    'automatic',
    'UTC',
    '1 Test Street',
    'Seoul',
    'KR',
    'Test Hall',
    '00000'
);

-- Ticket types for the external update fixtures
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'eventExternalClearTicketTypeID', :'eventExternalClearID', 1, 50, 'General Admission'),
    (:'eventExternalDelistedTicketTypeID', :'eventExternalDelistedID', 1, 50, 'General Admission'),
    (:'eventExternalPaidTicketTypeID', :'eventExternalPaidID', 1, 50, 'General Admission'),
    (
        :'eventExternalPendingClearTicketTypeID',
        :'eventExternalPendingClearID',
        1,
        50,
        'General Admission'
    ),
    (:'eventExternalStripeTicketTypeID', :'eventExternalStripeID', 1, 50, 'General Admission');

-- Price windows for the external update fixtures
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'eventExternalClearPriceWindowID', 2500, :'eventExternalClearTicketTypeID'),
    (:'eventExternalDelistedPriceWindowID', 2500, :'eventExternalDelistedTicketTypeID'),
    (:'eventExternalPaidPriceWindowID', 5000, :'eventExternalPaidTicketTypeID'),
    (
        :'eventExternalPendingClearPriceWindowID',
        2500,
        :'eventExternalPendingClearTicketTypeID'
    ),
    (:'eventExternalStripePriceWindowID', 5000, :'eventExternalStripeTicketTypeID');

-- Completed leftover external purchase that must not block clearing the URL
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    2500,
    'external',
    current_timestamp - interval '1 hour',
    'USD',
    :'eventExternalClearID',
    :'eventExternalClearPurchaseID',
    :'eventExternalClearTicketTypeID',
    0,
    0,
    'completed',
    'General Admission',
    :'user1ID'
);

-- Pending leftover external hold that must keep the live event URL
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    2500,
    'external',
    'USD',
    :'eventExternalPendingClearID',
    :'eventExternalPendingClearPurchaseID',
    :'eventExternalPendingClearTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'General Admission',
    :'user1ID'
);

-- Pending external hold on an eligible event whose URL may still change
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    'KRW',
    :'eventExternalPaidID',
    :'eventExternalPaidPurchaseID',
    :'eventExternalPaidTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'General Admission',
    :'user1ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report no paid notification transition for a free-to-free update
select is(
    (select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Updated Event Name",
            "description": "Updated description",
            "timezone": "America/Los_Angeles",
            "category_id": "3a390000-0000-0000-0000-000000000002",
            "kind_id": "virtual",
            "capacity": 100,
            "starts_at": "2030-02-01T14:00:00",
            "ends_at": "2030-02-01T16:00:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true
        }'::jsonb
    )),
    false,
    'Should report no paid notification transition for a free-to-free update'
);

-- Should persist basic update and clear omitted hosts, sponsors, and sessions
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'cfs_labels' - 'ticket_types'
    )),
    '{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Workshop",
        "description": "Updated description",
        "hosts": [],
        "kind": "virtual",
        "logo_url": "https://example.com/logo.png",
        "name": "Updated Event Name",
        "published": false,
        "slug": "def5678",
        "speakers": [],
        "sponsors": [],
        "test_event": false,
        "manual_tax_rate_ids": [],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "timezone": "America/Los_Angeles",

        "attendee_approval_required": false,
        "capacity": 100,
        "remaining_capacity": 100,
        "ends_at": 1896220800,
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "meeting_in_sync": false,
        "meeting_provider": "zoom",
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "meeting_requested": true,
        "registration_questions": [],
        "registration_questions_locked": false,
        "sessions": {},
        "starts_at": 1896213600,
        "waitlist_count": 0,
        "waitlist_enabled": false
    }'::jsonb,
    'Should persist basic update and clear omitted hosts, sponsors, and sessions'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    $$
        values (
            'event_updated',
            null::uuid,
            null::text,
            '3a390000-0000-0000-0000-000000000003'::uuid,
            '3a390000-0000-0000-0000-000000000010'::uuid,
            '3a390000-0000-0000-0000-000000000004'::uuid,
            'event',
            '3a390000-0000-0000-0000-000000000004'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should clear explicitly submitted manual Tax Rate selections on a free event
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventManualTaxID'::uuid,
        '{
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "description": "Free manual-tax event used for selection clearing checks",
            "kind_id": "virtual",
            "manual_tax_rate_ids": [],
            "name": "Manual Tax Selection",
            "tax_behavior": "inclusive",
            "tax_calculation_mode": "manual",
            "timezone": "UTC"
        }'::jsonb
    ),
    false,
    'Should clear explicitly submitted manual Tax Rate selections on a free event'
);

-- Should persist the cleared manual Tax Rate selection
select is(
    (
        select e.manual_tax_rate_ids
        from event e
        where e.event_id = :'eventManualTaxID'::uuid
    ),
    '{}'::text[],
    'Should persist the cleared manual Tax Rate selection'
);

-- Should report a paid notification transition for an invitation-only tier
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventFreeToPaidID'::uuid,
        '{
            "name": "Free To Paid",
            "description": "Free event used for paid transition checks",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                }
            },
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state": "California",
            "venue_zip_code": "94105",
            "ticket_types": [
                {
                    "active": true,
                    "availability": "invitation_only",
                    "event_ticket_type_id": "3a390000-0000-0000-0000-000000000027",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 1500,
                            "event_ticket_price_window_id": "3a390000-0000-0000-0000-000000000026"
                        }
                    ],
                    "seats_total": 100,
                    "title": "Private Admission"
                }
            ]
        }'::jsonb,
        null::jsonb,
        'stripe'
    ),
    true,
    'Should report a paid notification transition for an invitation-only tier'
);

-- Should persist paid capability after a free-to-paid update
select is(
    is_event_paid_capable(:'eventFreeToPaidID'::uuid),
    true,
    'Should persist paid capability after a free-to-paid update'
);

-- Should preserve a code omitted by the deferred legacy form.
select is(
    (select venue_state_code from event where event_id = :'eventFreeToPaidID'::uuid),
    'CA',
    'Should preserve a stored venue state code when unchanged legacy fields omit it'
);

-- Should reject a paid update validated against a stale sponsor
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000023'::uuid,
        '{
            "name": "Free To Paid",
            "description": "Free event used for paid transition checks",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_stale",
                    "seller_display_name": "Stale Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_stale",
                    "seller_display_name": "Stale Sponsor"
                }
            },
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "venue_address": "456 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb,
        null::jsonb,
        'stripe'
    )$$,
    'payment configuration changed during provider validation',
    'Should reject a paid update validated against a stale sponsor'
);

-- Should report no paid notification transition for a paid-to-free update
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventPaidToFreeID'::uuid,
        '{
            "name": "Paid To Free",
            "description": "Paid event used for free transition checks",
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "ticket_types": [
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "3a390000-0000-0000-0000-000000000029",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 0,
                            "event_ticket_price_window_id": "3a390000-0000-0000-0000-000000000028"
                        }
                    ],
                    "seats_total": 100,
                    "title": "General Admission"
                }
            ]
        }'::jsonb,
        null::jsonb,
        'stripe'
    ),
    false,
    'Should report no paid notification transition for a paid-to-free update'
);

-- Should persist free capability after a paid-to-free update
select is(
    is_event_paid_capable(:'eventPaidToFreeID'::uuid),
    false,
    'Should persist free capability after a paid-to-free update'
);

-- Should report no paid notification transition for a paid-to-paid update
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventPaidToPaidID'::uuid,
        '{
            "name": "Paid To Paid",
            "description": "Paid event used for paid edit checks",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                }
            },
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105",
            "ticket_types": [
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "3a390000-0000-0000-0000-000000000031",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 1800,
                            "event_ticket_price_window_id": "3a390000-0000-0000-0000-000000000030"
                        }
                    ],
                    "seats_total": 100,
                    "title": "General Admission"
                }
            ]
        }'::jsonb,
        null::jsonb,
        'stripe'
    ),
    false,
    'Should report no paid notification transition for a paid-to-paid update'
);

-- Should persist paid capability after a paid-to-paid update
select is(
    is_event_paid_capable(:'eventPaidToPaidID'::uuid),
    true,
    'Should persist paid capability after a paid-to-paid update'
);

-- Should report a paid notification transition when a free test event is promoted with paid tickets
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventTestFreeToPaidID'::uuid,
        '{
            "name": "Test Free To Paid",
            "description": "Free test event promoted while adding paid tickets",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                }
            },
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "test_event": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105",
            "ticket_types": [
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "3a390000-0000-0000-0000-000000000034",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 1500,
                            "event_ticket_price_window_id": "3a390000-0000-0000-0000-000000000033"
                        }
                    ],
                    "seats_total": 100,
                    "title": "General Admission"
                }
            ]
        }'::jsonb,
        null::jsonb,
        'stripe'
    ),
    true,
    'Should report a paid notification transition when a free test event is promoted with paid tickets'
);

-- Should persist a non-test paid state after promoting a free test event with paid tickets
select is(
    (
        select jsonb_build_object(
            'paid_capable', is_event_paid_capable(e.event_id),
            'test_event', e.test_event
        )
        from event e
        where e.event_id = :'eventTestFreeToPaidID'::uuid
    ),
    '{"paid_capable": true, "test_event": false}'::jsonb,
    'Should persist a non-test paid state after promoting a free test event with paid tickets'
);

-- Should report a paid notification transition when a paid test event is promoted
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventTestPaidToLiveID'::uuid,
        '{
            "name": "Test Paid To Live",
            "description": "Paid test event promoted without changing tickets",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                }
            },
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "test_event": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb,
        null::jsonb,
        'stripe'
    ),
    true,
    'Should report a paid notification transition when a paid test event is promoted'
);

-- Should persist a non-test paid state after promoting a paid test event
select is(
    (
        select jsonb_build_object(
            'paid_capable', is_event_paid_capable(e.event_id),
            'test_event', e.test_event
        )
        from event e
        where e.event_id = :'eventTestPaidToLiveID'::uuid
    ),
    '{"paid_capable": true, "test_event": false}'::jsonb,
    'Should persist a non-test paid state after promoting a paid test event'
);

-- Should report no paid notification transition while a paid event remains a test event
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventTestPaidToTestID'::uuid,
        '{
            "name": "Test Paid To Test",
            "description": "Paid test event that remains a test event",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_event",
                    "seller_display_name": "Update Event Fiscal Sponsor"
                }
            },
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "test_event": true,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb,
        null::jsonb,
        'stripe'
    ),
    false,
    'Should report no paid notification transition while a paid event remains a test event'
);

-- Should persist the paid test state when the event remains a test event
select is(
    (
        select jsonb_build_object(
            'paid_capable', is_event_paid_capable(e.event_id),
            'test_event', e.test_event
        )
        from event e
        where e.event_id = :'eventTestPaidToTestID'::uuid
    ),
    '{"paid_capable": true, "test_event": true}'::jsonb,
    'Should persist the paid test state when the event remains a test event'
);

-- Should initialize meeting flags for requested event without sessions
select is(
    (
        select jsonb_build_object(
            'meeting_requested', meeting_requested,
            'meeting_in_sync', meeting_in_sync
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "meeting_requested": true,
        "meeting_in_sync": false
    }'::jsonb,
    'Meeting flags are initialized for requested event without sessions'
);

-- Should update all fields (excluding sessions) with full payload
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Fully Updated Event",
            "description": "Fully updated description",
            "timezone": "Asia/Tokyo",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "hybrid",
            "meeting_requested": false,
            "banner_url": "https://example.com/new-banner.jpg",
            "capacity": 200,
            "description_short": "Updated short description",
            "starts_at": "2030-02-01T14:00:00",
            "ends_at": "2030-02-01T16:00:00",
            "logo_url": "https://example.com/new-logo.png",
            "luma_url": "https://luma.com/new-event",
            "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
            "meeting_join_instructions": "Use the event ticket name when joining.",
            "meeting_join_url": "https://youtube.com/new-live",
            "meeting_recording_url": "https://youtube.com/new-recording",
            "meetup_url": "https://meetup.com/new-event",
            "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
            "tags": ["updated", "event", "tags"],
            "test_event": true,
            "venue_address": " 456 New St ",
            "venue_city": " Tokyo ",
            "venue_country_code": " JP ",
            "venue_country_name": " Japan ",
            "venue_name": " New Venue ",
            "venue_state_code": " tk ",
            "venue_state_name": " Tokyo ",
            "venue_zip_code": " 100-0001 ",
            "hosts": ["3a390000-0000-0000-0000-000000000017", "3a390000-0000-0000-0000-000000000018"],
            "speakers": [
                {"user_id": "3a390000-0000-0000-0000-000000000017", "featured": true},
                {"user_id": "3a390000-0000-0000-0000-000000000018", "featured": false}
            ],
            "sponsors": [{"group_sponsor_id": "3a390000-0000-0000-0000-000000000015", "level": "Platinum"}],
            "sessions": [
                {
                    "name": "Updated Session",
                    "description": "This is an updated session",
                    "starts_at": "2030-02-01T14:30:00",
                    "ends_at": "2030-02-01T15:30:00",
                    "kind": "virtual",
                    "meeting_hosts": ["session-althost@example.com"],
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true,
                    "speakers": [{"user_id": "3a390000-0000-0000-0000-000000000017", "featured": true}]
                }
            ]
        }'::jsonb
    )$$,
    'Should update all fields (excluding sessions) with full payload'
);

-- Check event fields except sessions
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions' - 'cfs_labels' - 'ticket_types'
    )),
    '{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Conference",
        "description": "Fully updated description",
        "hosts": [
            {"name": "Host Two", "user_id": "3a390000-0000-0000-0000-000000000017", "username": "host2"},
            {"name": "Speaker One", "user_id": "3a390000-0000-0000-0000-000000000018", "username": "speaker1"}
        ],
        "speakers": [
            {"name": "Host Two", "user_id": "3a390000-0000-0000-0000-000000000017", "username": "host2", "featured": true},
            {"name": "Speaker One", "user_id": "3a390000-0000-0000-0000-000000000018", "username": "speaker1", "featured": false}
        ],
        "kind": "hybrid",
        "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
        "meeting_in_sync": false,
        "meeting_requested": false,
        "name": "Fully Updated Event",
        "published": false,
        "slug": "def5678",
        "timezone": "Asia/Tokyo",
        "test_event": true,
        "attendee_approval_required": false,
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 100,
        "remaining_capacity": 100,
        "description_short": "Updated short description",
        "starts_at": 1896152400,
        "ends_at": 1896159600,
        "logo_url": "https://example.com/new-logo.png",
        "luma_url": "https://luma.com/new-event",
        "meeting_join_instructions": "Use the event ticket name when joining.",
        "meeting_join_url": "https://youtube.com/new-live",
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "meeting_recording_url": "https://youtube.com/new-recording",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "registration_questions": [],
        "registration_questions_locked": false,
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "tags": ["updated", "event", "tags"],
        "manual_tax_rate_ids": [],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_country_code": "JP",
        "venue_country_name": "Japan",
        "venue_name": "New Venue",
        "venue_state_code": "TK",
        "venue_state_name": "Tokyo",
        "venue_zip_code": "100-0001",
        "waitlist_count": 0,
        "waitlist_enabled": false,
        "sponsors": [
            {"group_sponsor_id": "3a390000-0000-0000-0000-000000000015", "level": "Platinum", "logo_url": "https://example.com/newsponsor.png", "name": "NewSponsor Inc", "website_url": "https://newsponsor.com"}
        ]
    }'::jsonb,
    'Should update all fields (excluding sessions)'
);

-- Should contain expected session rows (ignoring session_id)
select ok(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb->'sessions'->'2030-02-01'
    ) @>
        '[
            {
                "name": "Updated Session",
                "description": "This is an updated session",
                "starts_at": 1896154200,
                "ends_at": 1896157800,
                "kind": "virtual",
                "meeting_hosts": ["session-althost@example.com"],
                "meeting_provider": "zoom",
                "meeting_requested": true,
                "speakers": [
                    {"name": "Host Two", "user_id": "3a390000-0000-0000-0000-000000000017", "username": "host2", "featured": true}
                ]
            }
        ]'::jsonb
    ),
    'Sessions contain expected rows (ignoring session_id)'
);

-- Should set meeting_in_sync=false when meeting disabled to trigger deletion
select is(
    (
        select jsonb_build_object(
            'event', jsonb_build_object(
                'meeting_requested', meeting_requested,
                'meeting_in_sync', meeting_in_sync
            ),
            'session', (
                select jsonb_build_object(
                    'meeting_requested', meeting_requested,
                    'meeting_in_sync', meeting_in_sync
                )
                from session
                where event_id = :'event1ID'::uuid
            )
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "event": {
            "meeting_requested": false,
            "meeting_in_sync": false
        },
        "session": {
            "meeting_requested": true,
            "meeting_in_sync": false
        }
    }'::jsonb,
    'Should set meeting_in_sync=false when meeting disabled to trigger deletion'
);

-- Should clear CFS labels when payload omits cfs_labels
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Event With Labels",
            "description": "Event seeded for CFS labels update tests",
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "cfs_description": "Initial CFS description",
            "cfs_enabled": true,
            "cfs_starts_at": "2029-12-20T00:00:00",
            "cfs_ends_at": "2030-01-05T00:00:00",
            "starts_at": "2030-01-15T10:00:00",
            "ends_at": "2030-01-15T12:00:00"
        }'::jsonb
    )$$,
    'Should clear CFS labels when payload omits cfs_labels'
);

-- Should delete all CFS labels when payload omits cfs_labels
select is(
    (select count(*) from event_cfs_label where event_id = :'event12ID'::uuid),
    0::bigint,
    'Should delete all CFS labels when payload omits cfs_labels'
);

-- Should update CFS labels for an event
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000009'::uuid,
        '{
            "name": "Event With Labels For Upsert",
            "description": "Event seeded for CFS labels upsert tests",
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "cfs_description": "Updated CFS description",
            "cfs_enabled": true,
            "cfs_starts_at": "2029-12-22T00:00:00",
            "cfs_ends_at": "2030-01-07T00:00:00",
            "starts_at": "2030-01-15T10:00:00",
            "ends_at": "2030-01-15T12:00:00",
            "cfs_labels": [
                {
                    "event_cfs_label_id": "3a390000-0000-0000-0000-000000000013",
                    "name": "track / ai + ml",
                    "color": "#DBEAFE"
                },
                {
                    "name": "track / web",
                    "color": "#FEE2E2"
                }
            ]
        }'::jsonb
    )$$,
    'Should update CFS labels for an event'
);

-- Should upsert and prune CFS labels in event_cfs_label
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'color', color,
                'name', name
            )
            order by name
        )
        from event_cfs_label
        where event_id = :'event18ID'::uuid
    ),
    '[
        {"color": "#DBEAFE", "name": "track / ai + ml"},
        {"color": "#FEE2E2", "name": "track / web"}
    ]'::jsonb,
    'Should upsert and prune CFS labels in event_cfs_label'
);

-- Should return updated CFS labels in event payload
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'color', label->>'color',
                'name', label->>'name'
            )
            order by label->>'name'
        )
        from jsonb_array_elements(
            get_event_full(
                :'community1ID'::uuid,
                :'group1ID'::uuid,
                :'event18ID'::uuid
            )::jsonb->'cfs_labels'
        ) as label
    ),
    '[
        {"color": "#DBEAFE", "name": "track / ai + ml"},
        {"color": "#FEE2E2", "name": "track / web"}
    ]'::jsonb,
    'Should return updated CFS labels in event payload'
);

-- Should throw error when group_id does not match
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000019'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Won''t Work", "description": "This should fail", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should throw error when updating cancelled event
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Try to Update Canceled", "description": "This should fail", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when event is canceled'
);

-- Should throw error for invalid host user_id (FK violation)
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Event with Invalid Host", "description": "Test", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person", "hosts": ["3a390000-0000-0000-0000-000000000020"]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when host user_id does not exist'
);

-- Should throw error for invalid speaker user_id (FK violation)
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Event with Invalid Speaker", "description": "Test", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person", "speakers": [{"user_id": "3a390000-0000-0000-0000-000000000020", "featured": false}]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when speaker user_id does not exist'
);

-- Should evaluate reminder immediately when published event starts within 24 hours
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Reminder Event Updated',
                'description', 'Reminder evaluation check',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'virtual',
                'event_reminder_enabled', true,
                'starts_at', to_char(current_timestamp + interval '12 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char(current_timestamp + interval '14 hours', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event10ID', :'category1ID'
    ),
    'Should evaluate reminder immediately when published event starts within 24 hours'
);

-- Should mark reminder as evaluated for the updated start date
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'event10ID'),
    (select starts_at from event where event_id = :'event10ID'),
    'Should mark reminder as evaluated for the updated start date'
);

-- Should not evaluate reminder when starts_at remains unchanged inside 24 hours
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Reminder Event Soon Updated',
                'description', 'Reminder regression check',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'virtual',
                'event_reminder_enabled', true,
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event11ID', :'category1ID', :'event11ID', :'event11ID'
    ),
    'Should not evaluate reminder when starts_at remains unchanged inside 24 hours'
);

-- Should keep reminder unevaluated when starts_at remains unchanged inside 24 hours
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'event11ID'),
    null::timestamptz,
    'Should keep reminder unevaluated when starts_at remains unchanged inside 24 hours'
);

-- Should not promote waitlist entries after an open-only registration window reaches the event start
select update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventWaitlistWindowID'::uuid,
        jsonb_build_object(
            'name', 'Open Only Waitlist Event Updated',
            'description', 'Event seeded for registration window waitlist update tests',
            'timezone', 'UTC',
            'category_id', :'category1ID',
            'kind_id', 'in-person',
            'capacity', 2,
            'starts_at', to_char(
                (
                    select starts_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'ends_at', to_char(
                (
                    select ends_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'registration_starts_at', to_char(
                (
                    select registration_starts_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'waitlist_enabled', true
        )
    );

-- Should not promote waitlist entries after an open-only registration window reaches the event start
select pass(
    'Should not promote waitlist entries after an open-only registration window reaches the event start'
);

-- Should keep waitlist entries queued after an open-only registration window reaches the event start
select is(
    (
        select jsonb_agg(user_id order by created_at asc, user_id asc)
        from event_waitlist
        where event_id = :'eventWaitlistWindowID'::uuid
    ),
    format('["%s"]', :'waitlistUserID')::jsonb,
    'Should keep waitlist entries queued after an open-only registration window reaches the event start'
);

-- Should reject a persisted external URL when the group toggle is off
select throws_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "name": "External Clear Event",
                "description": "Paid event that still carries leftover external fields",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "https://pay.example.test/leftover",
                "external_payment_window_hours": 48,
                "payment_currency_code": "USD",
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_zip_code": "94105",
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
                        "seats_total": 50,
                        "title": "General Admission"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            'stripe'
        )$$,
        :'group1ID',
        :'eventExternalClearID',
        :'category1ID',
        :'eventExternalClearTicketTypeID',
        :'eventExternalClearPriceWindowID'
    ),
    'external payments are not available for this event',
    'Should reject a persisted external URL when the group toggle is off'
);

-- Should reject a persisted external URL when the group country is delisted
select throws_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "name": "External Delisted Event",
                "description": "Paid event whose group country is no longer allowlisted",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "https://pay.example.test/delisted",
                "external_payment_window_hours": 48,
                "payment_currency_code": "USD",
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_zip_code": "94105",
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
                        "seats_total": 50,
                        "title": "General Admission"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            'stripe'
        )$$,
        :'groupDelistedID',
        :'eventExternalDelistedID',
        :'category1ID',
        :'eventExternalDelistedTicketTypeID',
        :'eventExternalDelistedPriceWindowID'
    ),
    'external payments are not available for this event',
    'Should reject a persisted external URL when the group country is delisted'
);

-- Should clear a persisted external URL onto Stripe when a recipient is ready
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "_payment_validation": {
                    "expected_payment_recipient": {
                        "provider": "stripe",
                        "recipient_id": "acct_update_event",
                        "seller_display_name": "Update Event Fiscal Sponsor"
                    },
                    "require_automatic_tax": true,
                    "validated_payment_recipient": {
                        "provider": "stripe",
                        "recipient_id": "acct_update_event",
                        "seller_display_name": "Update Event Fiscal Sponsor"
                    }
                },
                "name": "External Clear Event",
                "description": "Paid event that still carries leftover external fields",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "",
                "external_payment_instructions": "",
                "external_payment_window_hours": "",
                "payment_currency_code": "USD",
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_zip_code": "94105",
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
                        "seats_total": 50,
                        "title": "General Admission"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            'stripe'
        )$$,
        :'group1ID',
        :'eventExternalClearID',
        :'category1ID',
        :'eventExternalClearTicketTypeID',
        :'eventExternalClearPriceWindowID'
    ),
    'Should clear a persisted external URL onto Stripe when a recipient is ready'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_instructions', external_payment_instructions,
            'external_payment_url', external_payment_url,
            'external_payment_window_hours', external_payment_window_hours
        )
        from event
        where event_id = :'eventExternalClearID'::uuid
    ),
    '{
        "external_payment_instructions": null,
        "external_payment_url": null,
        "external_payment_window_hours": null
    }'::jsonb,
    'Should clear a persisted external URL onto Stripe when a recipient is ready'
);

-- Should reject clearing an external payment URL while a pending external purchase exists
select throws_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "_payment_validation": {
                    "expected_payment_recipient": {
                        "provider": "stripe",
                        "recipient_id": "acct_update_event",
                        "seller_display_name": "Update Event Fiscal Sponsor"
                    },
                    "require_automatic_tax": true,
                    "validated_payment_recipient": {
                        "provider": "stripe",
                        "recipient_id": "acct_update_event",
                        "seller_display_name": "Update Event Fiscal Sponsor"
                    }
                },
                "name": "External Pending Clear Event",
                "description": "Paid event whose pending external hold keeps the live URL",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "",
                "external_payment_instructions": "",
                "external_payment_window_hours": "",
                "payment_currency_code": "USD",
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_zip_code": "94105",
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
                        "seats_total": 50,
                        "title": "General Admission"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            'stripe'
        )$$,
        :'group1ID',
        :'eventExternalPendingClearID',
        :'category1ID',
        :'eventExternalPendingClearTicketTypeID',
        :'eventExternalPendingClearPriceWindowID'
    ),
    'external payment url cannot be cleared while pending external purchases exist',
    'Should reject clearing an external payment URL while a pending external purchase exists'
);

-- Should reject clearing an external URL when Stripe is not ready
select throws_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "name": "External Delisted Event",
                "description": "Paid event whose group country is no longer allowlisted",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "",
                "payment_currency_code": "USD",
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_zip_code": "94105",
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
                        "seats_total": 50,
                        "title": "General Admission"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            'stripe'
        )$$,
        :'groupDelistedID',
        :'eventExternalDelistedID',
        :'category1ID',
        :'eventExternalDelistedTicketTypeID',
        :'eventExternalDelistedPriceWindowID'
    ),
    'payment configuration changed during provider validation',
    'Should reject clearing an external URL when Stripe is not ready'
);

-- Should reject updating a paid external event without a payment URL
select throws_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            jsonb_build_object(
                'name', 'External Stripe Event',
                'description', 'Published Stripe event waiting for an external URL',
                'timezone', 'UTC',
                'category_id', %L::uuid,
                'kind_id', 'in-person',
                'payment_currency_code', 'KRW',
                'starts_at', to_char(
                    (
                        select starts_at
                        from event
                        where event_id = %L::uuid
                    ) at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS'
                ),
                'venue_address', '1 Test Street',
                'venue_city', 'Seoul',
                'venue_country_code', 'KR',
                'venue_name', 'Test Hall',
                'venue_zip_code', '00000',
                'ticket_types', jsonb_build_array(jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', %L::uuid,
                    'order', 1,
                    'price_windows', jsonb_build_array(jsonb_build_object(
                        'amount_minor', 5500,
                        'event_ticket_price_window_id', %L::uuid
                    )),
                    'seats_total', 50,
                    'title', 'General Admission'
                ))
            ),
            null::jsonb,
            'stripe'
        )$$,
        :'groupExternalID',
        :'eventExternalStripeID',
        :'category1ID',
        :'eventExternalStripeID',
        :'eventExternalStripeTicketTypeID',
        :'eventExternalStripePriceWindowID'
    ),
    'paid-capable events require a valid external payment url',
    'Should reject updating a paid external event without a payment URL'
);

-- Should mark a published Stripe event external when this update sets a payment URL
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            jsonb_build_object(
                'name', 'External Stripe Event',
                'description', 'Published Stripe event waiting for an external URL',
                'timezone', 'UTC',
                'category_id', %L::uuid,
                'kind_id', 'in-person',
                'external_payment_url', 'https://pay.example.test/converted',
                'external_payment_window_hours', 120,
                'payment_currency_code', 'KRW',
                'tax_behavior', 'exclusive',
                'tax_calculation_mode', 'automatic',
                'starts_at', to_char(
                    (
                        select starts_at
                        from event
                        where event_id = %L::uuid
                    ) at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS'
                ),
                'venue_address', '1 Test Street',
                'venue_city', 'Seoul',
                'venue_country_code', 'KR',
                'venue_name', 'Test Hall',
                'venue_zip_code', '00000',
                'ticket_types', jsonb_build_array(jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', %L::uuid,
                    'order', 1,
                    'price_windows', jsonb_build_array(jsonb_build_object(
                        'amount_minor', 5000,
                        'event_ticket_price_window_id', %L::uuid
                    )),
                    'seats_total', 50,
                    'title', 'General Admission'
                ))
            ),
            null::jsonb,
            null
        )$$,
        :'groupExternalID',
        :'eventExternalStripeID',
        :'category1ID',
        :'eventExternalStripeID',
        :'eventExternalStripeTicketTypeID',
        :'eventExternalStripePriceWindowID'
    ),
    'Should mark a published Stripe event external when this update sets a payment URL'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_url', external_payment_url,
            'external_payment_window_hours', external_payment_window_hours,
            'tax_behavior', tax_behavior,
            'tax_calculation_mode', tax_calculation_mode
        )
        from event
        where event_id = :'eventExternalStripeID'::uuid
    ),
    '{
        "external_payment_url": "https://pay.example.test/converted",
        "external_payment_window_hours": 120,
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "none"
    }'::jsonb,
    'Should persist external URL and normalized tax after converting a Stripe event'
);

-- Should normalize tax and accept an overridden window on an external paid update
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "name": "External Paid Event",
                "description": "External event updated for window and tax normalization",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "https://pay.example.test/update",
                "external_payment_window_hours": 96,
                "payment_currency_code": "KRW",
                "tax_behavior": "exclusive",
                "tax_calculation_mode": "automatic",
                "venue_address": "1 Test Street",
                "venue_city": "Seoul",
                "venue_country_code": "KR",
                "venue_name": "Test Hall",
                "venue_zip_code": "00000",
                "ticket_types": [
                    {
                        "active": true,
                        "availability": "public",
                        "event_ticket_type_id": "%s",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 5000,
                                "event_ticket_price_window_id": "%s"
                            }
                        ],
                        "seats_total": 50,
                        "title": "General Admission"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            null
        )$$,
        :'groupExternalID',
        :'eventExternalPaidID',
        :'category1ID',
        :'eventExternalPaidTicketTypeID',
        :'eventExternalPaidPriceWindowID'
    ),
    'Should normalize tax and accept an overridden window on an external paid update'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_window_hours', external_payment_window_hours,
            'tax_behavior', tax_behavior,
            'tax_calculation_mode', tax_calculation_mode
        )
        from event
        where event_id = :'eventExternalPaidID'::uuid
    ),
    '{
        "external_payment_window_hours": 96,
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "none"
    }'::jsonb,
    'Should persist normalized tax and the overridden external window'
);

-- Should reject an external payment window above the configured maximum on update
select throws_ok(
    format(
        $$select update_event(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "name": "External Paid Event",
                "description": "External event updated for window and tax normalization",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "https://pay.example.test/update",
                "external_payment_window_hours": 337,
                "payment_currency_code": "KRW",
                "venue_address": "1 Test Street",
                "venue_city": "Seoul",
                "venue_country_code": "KR",
                "venue_name": "Test Hall",
                "venue_zip_code": "00000",
                "ticket_types": [
                    {
                        "active": true,
                        "availability": "public",
                        "event_ticket_type_id": "%s",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 5000,
                                "event_ticket_price_window_id": "%s"
                            }
                        ],
                        "seats_total": 50,
                        "title": "General Admission"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            null
        )$$,
        :'groupExternalID',
        :'eventExternalPaidID',
        :'category1ID',
        :'eventExternalPaidTicketTypeID',
        :'eventExternalPaidPriceWindowID'
    ),
    'external payment window exceeds the configured maximum',
    'Should reject an external payment window above the configured maximum on update'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
