-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(100);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000003'
\set event4ID '00000000-0000-0000-0000-000000000004'
\set event5ID '00000000-0000-0000-0000-000000000005'
\set event6ID '00000000-0000-0000-0000-000000000006'
\set event7ID '00000000-0000-0000-0000-000000000007'
\set event8ID '00000000-0000-0000-0000-000000000008'
\set event9ID '00000000-0000-0000-0000-000000000009'
\set event10ID '00000000-0000-0000-0000-000000000010'
\set event11ID '00000000-0000-0000-0000-000000000013'
\set event12ID '00000000-0000-0000-0000-000000000014'
\set event13ID '00000000-0000-0000-0000-000000000015'
\set event14ID '00000000-0000-0000-0000-000000000016'
\set event15ID '00000000-0000-0000-0000-000000000017'
\set event16ID '00000000-0000-0000-0000-000000000018'
\set event17ID '00000000-0000-0000-0000-000000000019'
\set event18ID '00000000-0000-0000-0000-000000000020'
\set event19ID '00000000-0000-0000-0000-000000000025'
\set event20ID '00000000-0000-0000-0000-000000000027'
\set event21ID '00000000-0000-0000-0000-000000000028'
\set event22ID '00000000-0000-0000-0000-000000000029'
\set event23ID '00000000-0000-0000-0000-000000000030'
\set event24ID '00000000-0000-0000-0000-000000000031'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set invalidUserID '99999999-9999-9999-9999-999999999999'
\set label1ID '00000000-0000-0000-0000-000000000401'
\set label2ID '00000000-0000-0000-0000-000000000402'
\set label3ID '00000000-0000-0000-0000-000000000403'
\set label4ID '00000000-0000-0000-0000-000000000404'
\set meeting1ID '00000000-0000-0000-0000-000000000301'
\set meeting2ID '00000000-0000-0000-0000-000000000302'
\set meeting3ID '00000000-0000-0000-0000-000000000303'
\set session1ID '00000000-0000-0000-0000-000000000101'
\set session2ID '00000000-0000-0000-0000-000000000102'
\set session3ID '00000000-0000-0000-0000-000000000103'
\set sponsorNewID '00000000-0000-0000-0000-000000000062'
\set sponsorOrigID '00000000-0000-0000-0000-000000000061'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'
\set user3ID '00000000-0000-0000-0000-000000000022'
\set user4ID '00000000-0000-0000-0000-000000000023'
\set user5ID '00000000-0000-0000-0000-000000000024'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'community1ID', 'test-community', 'Test Community', 'A test community for testing purposes', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Users
insert into "user" (user_id, auth_hash, email, username, name) values
    (:'user1ID', 'hash1', 'host1@example.com', 'host1', 'Host One'),
    (:'user2ID', 'hash2', 'host2@example.com', 'host2', 'Host Two'),
    (:'user3ID', 'hash3', 'speaker1@example.com', 'speaker1', 'Speaker One'),
    (:'user4ID', 'hash4', 'waitlist1@example.com', 'waitlist1', 'Waitlist One'),
    (:'user5ID', 'hash5', 'waitlist2@example.com', 'waitlist2', 'Waitlist Two');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values
    (:'category1ID', 'Conference', :'community1ID'),
    (:'category2ID', 'Workshop', :'community1ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values ('00000000-0000-0000-0000-000000000010', 'Technology', :'community1ID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group1ID',
    :'community1ID',
    'Test Group',
    'abc1234',
    'A test group',
    '00000000-0000-0000-0000-000000000010'
);

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', null),
    (:'sponsorNewID',  :'group1ID', 'NewSponsor Inc',   'https://example.com/newsponsor.png', 'https://newsponsor.com');

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
insert into event_speaker (event_id, user_id, featured) values (:'event1ID', :'user1ID', true);
insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'event1ID', :'sponsorOrigID', 'Bronze');

-- Event with meeting_in_sync=false for testing preservation
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
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync,
    published,
    starts_at,
    ends_at
) values (
    :'event5ID',
    :'group1ID',
    'Event With Pending Sync',
    'ghi9abc',
    'This event has a pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    100,
    'zoom',
    true,
    false,
    true,
    '2030-03-01 10:00:00-05',
    '2030-03-01 12:00:00-05'
);

-- Event meeting for meeting_in_sync=false preservation
insert into meeting (
    event_id,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id,
    recording_url
) values (
    :'event5ID',
    'https://zoom.us/j/event-pending-sync',
    :'meeting2ID',
    'zoom',
    'event-pending-sync',
    'https://zoom.example/event-pending-recording'
);

-- Published dateless event for waitlist promotion checks
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
    waitlist_enabled
) values (
    :'event13ID',
    :'group1ID',
    'Published Dateless Event',
    'dateless-waitlist',
    'Published event without dates for waitlist promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
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
    published
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
    true
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

-- Published dateless event used when waitlist is disabled for new joins
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
    waitlist_enabled
) values (
    :'event16ID',
    :'group1ID',
    'Dateless Waitlist Disabled Event',
    'dateless-waitlist-disabled',
    'Published dateless event for disabled waitlist promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    2,
    true,
    true
);

-- Published dateless event used when capacity becomes unlimited
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
    waitlist_enabled
) values (
    :'event17ID',
    :'group1ID',
    'Dateless Unlimited Event',
    'dateless-unlimited',
    'Published dateless event for unlimited capacity promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
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

-- Unticketed event used for ticketing payload validation checks
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
    'Ticketing Payload Event',
    'ticketing-payload',
    'Unticketed event used for ticketing payload validation checks',
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

-- Event with session having meeting_in_sync=false
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
    ends_at
) values (
    :'event6ID',
    :'group1ID',
    'Event With Session Pending Sync',
    'jkl2def',
    'This event has a session with pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2030-04-01 09:00:00-04',
    '2030-04-01 17:00:00-04'
);

insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync
) values (
    :'session1ID',
    :'event6ID',
    'Session With Pending Sync',
    'Session description',
    '2030-04-01 10:00:00-04',
    '2030-04-01 11:00:00-04',
    'virtual',
    'zoom',
    true,
    false
);

-- Session meeting for meeting_in_sync=false preservation
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id,
    recording_url,
    session_id
) values (
    'https://zoom.us/j/session-pending-sync',
    :'meeting3ID',
    'zoom',
    'session-pending-sync',
    'https://zoom.example/session-pending-recording',
    :'session1ID'
);

-- Event with session that has a meeting (for orphan test)
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
    :'event7ID',
    :'group1ID',
    'Event For Session Removal Test',
    'mno3ghi',
    'This event has a session with a meeting',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2030-05-01 09:00:00-04',
    '2030-05-01 17:00:00-04',
    true
);

insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync
) values (
    :'session2ID',
    :'event7ID',
    'Session To Be Removed',
    'Session description',
    '2030-05-01 10:00:00-04',
    '2030-05-01 11:00:00-04',
    'virtual',
    'zoom',
    true,
    true
);

insert into meeting (join_url, meeting_id, meeting_provider_id, provider_meeting_id, session_id)
values ('https://zoom.us/j/123123123', :'meeting1ID', 'zoom', '123123123', :'session2ID');

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

-- Past Event (for testing past updates)
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

    description_short,
    photos_urls,
    tags,
    venue_name
) values (
    :'event8ID',
    :'group1ID',
    'Past Event',
    'stu5mno',
    'This event already happened',
    'America/New_York',
    :'category1ID',
    'in-person',
    '2020-01-01 10:00:00-05',
    '2020-01-01 12:00:00-05',

    'Original short description',
    array['https://example.com/original-photo.jpg'],
    array['original', 'tags'],
    'Original Venue'
);

-- Live Event (started in the past, ends in the future)
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
    ends_at
) values (
    :'event9ID',
    :'group1ID',
    'Live Event',
    'vwx6pqr',
    'This event is currently live',
    'UTC',
    :'category1ID',
    'in-person',
    current_timestamp - interval '1 hour',
    current_timestamp + interval '2 hours'
);

-- Session already completed while the live event is still ongoing
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested
) values (
    :'session3ID',
    :'event9ID',
    'Completed Live Event Session',
    current_timestamp - interval '45 minutes',
    current_timestamp - interval '15 minutes',
    'virtual',
    'zoom',
    true
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

-- Event Waitlist (for waitlist promotion tests)
insert into event_waitlist (event_id, user_id, created_at) values
    (:'event13ID', :'user3ID', current_timestamp),
    (:'event15ID', :'user4ID', current_timestamp),
    (:'event15ID', :'user5ID', current_timestamp + interval '1 minute'),
    (:'event16ID', :'user1ID', current_timestamp + interval '2 minutes'),
    (:'event17ID', :'user4ID', current_timestamp + interval '3 minutes'),
    (:'event17ID', :'user5ID', current_timestamp + interval '4 minutes'),
    (:'event20ID', :'user4ID', current_timestamp + interval '5 minutes'),
    (:'event23ID', :'user5ID', current_timestamp + interval '6 minutes');

-- Event invitation requests (for attendee approval transition tests)
insert into event_invitation_request (event_id, user_id)
values (:'event24ID', :'user5ID');

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
    payment_currency_code
) values (
    :'event19ID',
    :'group1ID',
    'Paid Event',
    'paid-event',
    'Event seeded for ticketing preservation tests',
    'UTC',
    :'category1ID',
    'virtual',
    10,
    'USD'
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
    '00000000-0000-0000-0000-000000000026'::uuid,
    :'group1ID',
    'Other Paid Event',
    'other-paid-event',
    'Event seeded for ticketing ownership tests',
    'UTC',
    :'category1ID',
    'virtual',
    'USD'
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '00000000-0000-0000-0000-000000000091'::uuid,
    true,
    :'event19ID',
    1,
    10,
    'General'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '00000000-0000-0000-0000-000000000094'::uuid,
    2500,
    '00000000-0000-0000-0000-000000000091'::uuid
);

insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    '00000000-0000-0000-0000-000000000095'::uuid,
    true,
    500,
    'SAVE20',
    :'event19ID',
    'fixed_amount',
    'Launch'
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '00000000-0000-0000-0000-000000000111'::uuid,
    true,
    :'event21ID',
    1,
    10,
    'Protected General'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '00000000-0000-0000-0000-000000000112'::uuid,
    2500,
    '00000000-0000-0000-0000-000000000111'::uuid
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '00000000-0000-0000-0000-000000000114'::uuid,
    true,
    :'event21ID',
    2,
    5,
    'Protected VIP'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '00000000-0000-0000-0000-000000000115'::uuid,
    5000,
    '00000000-0000-0000-0000-000000000114'::uuid
);

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
    '00000000-0000-0000-0000-000000000113'::uuid,
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
    '00000000-0000-0000-0000-000000000097'::uuid,
    true,
    '00000000-0000-0000-0000-000000000026'::uuid,
    1,
    25,
    'Other Event General'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '00000000-0000-0000-0000-000000000098'::uuid,
    3000,
    '00000000-0000-0000-0000-000000000097'::uuid
);

insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    '00000000-0000-0000-0000-000000000099'::uuid,
    true,
    250,
    'OTHER25',
    '00000000-0000-0000-0000-000000000026'::uuid,
    'fixed_amount',
    'Other launch'
);

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
    2500,
    'USD',
    'PROTECT5',
    '00000000-0000-0000-0000-000000000113'::uuid,
    :'event21ID',
    '00000000-0000-0000-0000-000000000111'::uuid,
    'completed',
    'Protected General',
    :'user1ID'
);

-- Event CFS Labels
insert into event_cfs_label (event_cfs_label_id, event_id, color, name) values
    (:'label1ID', :'event12ID', '#CCFBF1', 'track / backend'),
    (:'label2ID', :'event12ID', '#FEE2E2', 'track / frontend');
insert into event_cfs_label (event_cfs_label_id, event_id, color, name) values
    (:'label3ID', :'event18ID', '#CCFBF1', 'track / backend'),
    (:'label4ID', :'event18ID', '#FEE2E2', 'track / frontend');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update basic fields and clear hosts/sponsors/sessions when not provided
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{
            "name": "Updated Event Name",
            "description": "Updated description",
            "timezone": "America/Los_Angeles",
            "category_id": "00000000-0000-0000-0000-000000000012",
            "kind_id": "virtual",
            "capacity": 100,
            "starts_at": "2030-02-01T14:00:00",
            "ends_at": "2030-02-01T16:00:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true
        }'::jsonb
    )$$,
    'Should execute basic update and clear omitted hosts, sponsors, and sessions'
);
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'cfs_labels'
    )),
    '{
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
        "timezone": "America/Los_Angeles",

        "attendee_approval_required": false,
        "capacity": 100,
        "remaining_capacity": 100,
        "ends_at": 1896220800,
        "event_reminder_enabled": true,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "meeting_in_sync": false,
        "meeting_provider": "zoom",
        "meeting_requested": true,
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
            '00000000-0000-0000-0000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000002'::uuid,
            '00000000-0000-0000-0000-000000000003'::uuid,
            'event',
            '00000000-0000-0000-0000-000000000003'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should preserve ticketing fields when payload omits payment controls
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000025'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "meeting_requested": false
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
                "event_discount_code_id": "00000000-0000-0000-0000-000000000095",
                "kind": "fixed_amount",
                "title": "Launch"
            }
        ],
        "payment_currency_code": "USD",
        "ticket_types": [
            {
                "active": true,
                "current_price": {
                    "amount_minor": 2500
                },
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000091",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000094"
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

-- Should throw error when discount codes remain without ticket types
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000025'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "payment_currency_code": null,
            "ticket_types": null
        }'::jsonb
    )$$,
    'discount_codes require ticket_types',
    'Should throw error when discount codes remain after ticket types are cleared'
);

-- Should throw error when payment currency remains without ticket types
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000025'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "discount_codes": null,
            "ticket_types": null
        }'::jsonb
    )$$,
    'payment_currency_code requires ticket_types',
    'Should throw error when payment currency remains after ticket types are cleared'
);

-- Should throw error when a ticket type identifier belongs to another event
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000025'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000097",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000100"
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
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000025'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000091",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000098"
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
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000028'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000111",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000115"
                        }
                    ],
                    "seats_total": 10,
                    "title": "Protected General"
                },
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000114",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000115"
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
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000025'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 250,
                    "code": "OTHER25",
                    "event_discount_code_id": "00000000-0000-0000-0000-000000000099",
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

-- Should throw error when ticketed events omit payment_currency_code
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000029'::uuid,
        '{
            "name": "Ticketing Payload Event",
            "description": "Unticketed event used for ticketing payload validation checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000131",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000132"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require payment_currency_code',
    'Should reject ticketed events when payment_currency_code is omitted'
);

-- Should throw error when waitlist remains enabled for ticketed events
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000029'::uuid,
        '{
            "name": "Ticketing Payload Event",
            "description": "Unticketed event used for ticketing payload validation checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000133",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000134"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ],
            "waitlist_enabled": true
        }'::jsonb
    )$$,
    'waitlist cannot be enabled for ticketed events',
    'Should reject ticketed events when waitlist_enabled stays true'
);

-- Should reject disabling attendee approval while invitation requests are pending
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000031'::uuid,
        '{
            "name": "Approval Request Event",
            "description": "Approval-required event used for invitation request checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "attendee_approval_required": false
        }'::jsonb
    )$$,
    'approval-required events with pending invitation requests cannot disable approval',
    'Should reject disabling attendee approval while invitation requests are pending'
);

-- Should reject enabling attendee approval while waitlist entries exist
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000030'::uuid,
        '{
            "name": "Ticketing Waitlist Event",
            "description": "Published event used for ticketing conversion waitlist checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
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
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000028'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000111",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000112"
                        }
                    ],
                    "seats_total": 0,
                    "title": "Protected General"
                }
            ]
        }'::jsonb
    )$$,
    'ticket type seats_total (0) cannot be less than current number of purchased seats (1)',
    'Should reject seat totals below the current purchased inventory for a ticket type'
);

-- Should throw error when purchased ticket types are removed
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000028'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": []
        }'::jsonb
    )$$,
    'ticket types with purchases cannot be removed; deactivate them instead',
    'Should reject removing ticket types that already have purchases'
);

-- Should throw error when discount code total_available drops below redemptions
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000028'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 500,
                    "code": "PROTECT5",
                    "event_discount_code_id": "00000000-0000-0000-0000-000000000113",
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
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000028'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "discount_codes": [],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'discount codes with redemptions cannot be removed; deactivate them instead',
    'Should reject removing discount codes that already have redemptions'
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
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{
            "name": "Fully Updated Event",
            "description": "Fully updated description",
            "timezone": "Asia/Tokyo",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "hybrid",
            "meeting_requested": false,
            "banner_url": "https://example.com/new-banner.jpg",
            "capacity": 200,
            "description_short": "Updated short description",
            "starts_at": "2030-02-01T14:00:00",
            "ends_at": "2030-02-01T16:00:00",
            "logo_url": "https://example.com/new-logo.png",
            "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
            "meeting_join_url": "https://youtube.com/new-live",
            "meeting_recording_url": "https://youtube.com/new-recording",
            "meetup_url": "https://meetup.com/new-event",
            "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
            "registration_required": false,
            "tags": ["updated", "event", "tags"],
            "venue_address": "456 New St",
            "venue_city": "Tokyo",
            "venue_country_code": "JP",
            "venue_country_name": "Japan",
            "venue_name": "New Venue",
            "venue_state": "TK",
            "venue_zip_code": "100-0001",
            "hosts": ["00000000-0000-0000-0000-000000000021", "00000000-0000-0000-0000-000000000022"],
            "speakers": [
                {"user_id": "00000000-0000-0000-0000-000000000021", "featured": true},
                {"user_id": "00000000-0000-0000-0000-000000000022", "featured": false}
            ],
            "sponsors": [{"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Platinum"}],
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
                    "speakers": [{"user_id": "00000000-0000-0000-0000-000000000021", "featured": true}]
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
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions' - 'cfs_labels'
    )),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Fully updated description",
        "hosts": [
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2"},
            {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1"}
        ],
        "speakers": [
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2", "featured": true},
            {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1", "featured": false}
        ],
        "kind": "hybrid",
        "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
        "meeting_in_sync": false,
        "meeting_requested": false,
        "name": "Fully Updated Event",
        "published": false,
        "slug": "def5678",
        "timezone": "Asia/Tokyo",
        "attendee_approval_required": false,
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "remaining_capacity": 200,
        "description_short": "Updated short description",
        "starts_at": 1896152400,
        "ends_at": 1896159600,
        "logo_url": "https://example.com/new-logo.png",
        "meeting_join_url": "https://youtube.com/new-live",
        "meeting_recording_url": "https://youtube.com/new-recording",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "registration_required": false,
        "event_reminder_enabled": true,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "tags": ["updated", "event", "tags"],
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_country_code": "JP",
        "venue_country_name": "Japan",
        "venue_name": "New Venue",
        "venue_state": "TK",
        "venue_zip_code": "100-0001",
        "waitlist_count": 0,
        "waitlist_enabled": false,
        "sponsors": [
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Platinum", "logo_url": "https://example.com/newsponsor.png", "name": "NewSponsor Inc", "website_url": "https://newsponsor.com"}
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
                    {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2", "featured": true}
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
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000014'::uuid,
        '{
            "name": "Event With Labels",
            "description": "Event seeded for CFS labels update tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
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
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000020'::uuid,
        '{
            "name": "Event With Labels For Upsert",
            "description": "Event seeded for CFS labels upsert tests",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "cfs_description": "Updated CFS description",
            "cfs_enabled": true,
            "cfs_starts_at": "2029-12-22T00:00:00",
            "cfs_ends_at": "2030-01-07T00:00:00",
            "starts_at": "2030-01-15T10:00:00",
            "ends_at": "2030-01-15T12:00:00",
            "cfs_labels": [
                {
                    "event_cfs_label_id": "00000000-0000-0000-0000-000000000403",
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
        '00000000-0000-0000-0000-000000000099'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Won''t Work", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should preserve meeting_in_sync=false when updating unrelated fields
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description - unrelated to meeting",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "capacity": 100,
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute unrelated update with pending event meeting sync'
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should keep event meeting_in_sync=false after unrelated update'
);

-- Should keep meeting_in_sync=false when meeting_requested changes to false
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "meeting_requested": false,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute update when event meeting_requested changes to false'
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should keep event meeting_in_sync=false when meeting_requested changes to false'
);

-- Should persist event recording override for automatic meetings
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description with recording override",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "capacity": 100,
            "kind_id": "virtual",
            "meeting_provider_id": "zoom",
            "meeting_recording_url": "https://youtube.com/watch?v=event-override",
            "meeting_requested": true,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute update when automatic event meeting recording override is provided'
);
select is(
    (select meeting_recording_url from event where event_id = :'event5ID'::uuid),
    'https://youtube.com/watch?v=event-override',
    'Should persist event recording override for automatic meetings'
);

-- Should clear event recording override and fall back to synced meeting recording
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description with cleared recording override",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "capacity": 100,
            "kind_id": "virtual",
            "meeting_provider_id": "zoom",
            "meeting_recording_url": "",
            "meeting_requested": true,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute update when automatic event meeting recording override is cleared'
);
select is(
    (
        select get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event5ID'::uuid
        )::jsonb->>'meeting_recording_url'
    ),
    'https://zoom.example/event-pending-recording',
    'Should fall back to synced event meeting recording after clearing override'
);

-- Should preserve session meeting_in_sync=false when updating unrelated fields
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000006'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description - unrelated to session meeting",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "00000000-0000-0000-0000-000000000101",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description - unrelated to meeting",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true
                }
            ]
        }'::jsonb
    )$$,
    'Should execute unrelated update with pending session meeting sync'
);
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'Should keep session meeting_in_sync=false after unrelated update'
);

-- Should keep session meeting_in_sync=false when meeting_requested changes to false
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000006'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "00000000-0000-0000-0000-000000000101",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_requested": false
                }
            ]
        }'::jsonb
    )$$,
    'Should execute update when session meeting_requested changes to false'
);
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'Should keep session meeting_in_sync=false when meeting_requested changes to false'
);

-- Should persist session recording override for automatic meetings
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000006'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description with session recording override",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "00000000-0000-0000-0000-000000000101",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description with recording override",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_provider_id": "zoom",
                    "meeting_recording_url": "https://youtube.com/watch?v=session-override",
                    "meeting_requested": true
                }
            ]
        }'::jsonb
    )$$,
    'Should execute update when automatic session meeting recording override is provided'
);
select is(
    (select meeting_recording_url from session where session_id = :'session1ID'::uuid),
    'https://youtube.com/watch?v=session-override',
    'Should persist session recording override for automatic meetings'
);

-- Should clear session recording override and fall back to synced meeting recording
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000006'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description with cleared session recording override",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "00000000-0000-0000-0000-000000000101",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description with cleared recording override",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_provider_id": "zoom",
                    "meeting_recording_url": "",
                    "meeting_requested": true
                }
            ]
        }'::jsonb
    )$$,
    'Should execute update when automatic session meeting recording override is cleared'
);
select is(
    (
        with payload as (
            select get_event_full(
                :'community1ID'::uuid,
                :'group1ID'::uuid,
                :'event6ID'::uuid
            )::jsonb as event_json
        )
        select session_json->>'meeting_recording_url'
        from payload
        cross join lateral jsonb_each(event_json->'sessions') as day(day, sessions)
        cross join lateral jsonb_array_elements(sessions) as session_json
        where session_json->>'session_id' = :'session1ID'
    ),
    'https://zoom.example/session-pending-recording',
    'Should fall back to synced session meeting recording after clearing override'
);

-- Should throw error when updating cancelled event
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Try to Update Canceled", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when event is canceled'
);

-- Should throw error for invalid host user_id (FK violation)
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Event with Invalid Host", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "hosts": ["99999999-9999-9999-9999-999999999999"]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when host user_id does not exist'
);

-- Should throw error for invalid speaker user_id (FK violation)
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Event with Invalid Speaker", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "speakers": [{"user_id": "99999999-9999-9999-9999-999999999999", "featured": false}]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when speaker user_id does not exist'
);

-- Should verify session exists before update
select ok(
    (select count(*) = 1 from session where session_id = :'session2ID'),
    'Session exists before update'
);
-- Update event without the session (removes it via cascade)
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000007'::uuid,
        '{
            "name": "Event For Session Removal Test",
            "description": "This event has a session with a meeting",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "starts_at": "2030-05-01T09:00:00",
            "ends_at": "2030-05-01T17:00:00",
            "sessions": []
        }'::jsonb
    )$$,
    'Should remove omitted sessions on update'
);
-- Should verify session is deleted and meeting is orphan after update
select is(
    (select count(*) from session where session_id = :'session2ID'),
    0::bigint,
    'Session is deleted after update_event with empty sessions'
);
select is(
    (select jsonb_build_object('meeting_id', meeting_id, 'session_id', session_id) from meeting where meeting_id = :'meeting1ID'),
    jsonb_build_object('meeting_id', :'meeting1ID'::uuid, 'session_id', null),
    'Meeting becomes orphan (session_id set to null) after session deletion'
);

-- Should throw error when event ends_at is in the past
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Past End Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "ends_at": "2020-01-01T12:00:00"}'::jsonb
    )$$,
    'event ends_at cannot be in the past',
    'Should throw error when event ends_at is in the past'
);

-- Should throw error when session ends_at is in the past
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Past End", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Past End Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2020-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at cannot be in the past',
    'Should throw error when session ends_at is in the past'
);

-- Should throw error when event ends_at is before starts_at
select throws_like(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Invalid Range Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00"}'::jsonb
    )$$,
    '%event_check%',
    'Should throw error when event ends_at is before starts_at'
);

-- Should throw error when session ends_at is before starts_at
select throws_like(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Invalid Session Range", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Invalid Session", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    '%session_check%',
    'Should throw error when session ends_at is before starts_at'
);

-- Should throw error when event ends_at is set without starts_at
select throws_like(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "No Start Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "ends_at": "2030-01-01T12:00:00"}'::jsonb
    )$$,
    '%event_check%',
    'Should throw error when event ends_at is set without starts_at'
);

-- Should succeed with event ends_at null when starts_at is null
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "No Dates Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'Should succeed with event ends_at null when starts_at is null'
);

-- Should succeed with session ends_at null when starts_at is set
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session No End", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "No End Session", "starts_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed with session ends_at null when starts_at is set'
);

-- Should succeed with valid future dates for event and sessions
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Future Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Future Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed with valid future dates for event and sessions'
);

-- Should throw error when session starts_at is before event starts_at
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Before Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Early Session", "starts_at": "2030-01-01T09:00:00", "ends_at": "2030-01-01T10:30:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is before event starts_at'
);

-- Should throw error when session starts_at is after event ends_at
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session After Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Late Session", "starts_at": "2030-01-01T13:00:00", "ends_at": "2030-01-01T14:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is after event ends_at'
);

-- Should throw error when session ends_at is after event ends_at
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Exceeds Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Long Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T13:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at must be within event bounds',
    'Should throw error when session ends_at is after event ends_at'
);

-- Should succeed when session is within event bounds
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Within Bounds", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T14:00:00", "sessions": [{"name": "Valid Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T12:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed when session is within event bounds'
);

-- Should update all fields on past events
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Past Event Updated",
            "description": "Updated description for past event",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000012",
            "kind_id": "virtual",
            "capacity": 150,
            "starts_at": "2020-01-02T10:00:00",
            "ends_at": "2020-01-02T12:30:00",
            "banner_mobile_url": "https://example.com/banner-mobile.jpg",
            "banner_url": "https://example.com/banner.jpg",
            "description_short": "Updated short description",
            "logo_url": "https://example.com/logo.png",
            "meetup_url": "https://meetup.com/group/events/123456",
            "meeting_join_url": "https://meet.example.com/room",
            "meeting_provider_id": "zoom",
            "meeting_recording_url": "https://youtube.com/recording",
            "meeting_requested": false,
            "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
            "registration_required": true,
            "tags": ["updated", "past", "event"],
            "venue_address": "123 Updated St",
            "venue_city": "Updated City",
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Updated Venue",
            "venue_state": "CA",
            "venue_zip_code": "12345",
            "hosts": ["00000000-0000-0000-0000-000000000020"],
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000022", "featured": true}],
            "sponsors": [{"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "level": "Gold"}],
            "sessions": [{"name": "Past Session", "starts_at": "2020-01-02T10:30:00", "ends_at": "2020-01-02T11:30:00", "kind": "virtual"}]
        }'::jsonb
    )$$,
    'Should update all fields on past events'
);

-- Verify past event fields were updated
select is(
    (
        select jsonb_build_object(
            'banner_mobile_url', banner_mobile_url,
            'banner_url', banner_url,
            'capacity', capacity,
            'description', description,
            'description_short', description_short,
            'ends_at', ends_at,
            'event_category_id', event_category_id,
            'event_kind_id', event_kind_id,
            'logo_url', logo_url,
            'meeting_join_url', meeting_join_url,
            'meeting_provider_id', meeting_provider_id,
            'meeting_recording_url', meeting_recording_url,
            'meeting_requested', meeting_requested,
            'meetup_url', meetup_url,
            'name', name,
            'photos_urls', photos_urls,
            'registration_required', registration_required,
            'starts_at', starts_at,
            'tags', tags,
            'timezone', timezone,
            'venue_address', venue_address,
            'venue_city', venue_city,
            'venue_country_code', venue_country_code,
            'venue_country_name', venue_country_name,
            'venue_name', venue_name,
            'venue_state', venue_state,
            'venue_zip_code', venue_zip_code
        )
        from event
        where event_id = :'event8ID'::uuid
    ),
    jsonb_build_object(
        'banner_mobile_url', 'https://example.com/banner-mobile.jpg',
        'banner_url', 'https://example.com/banner.jpg',
        'capacity', 150,
        'description', 'Updated description for past event',
        'description_short', 'Updated short description',
        'ends_at', '2020-01-02 12:30:00+00'::timestamptz,
        'event_category_id', :'category2ID'::uuid,
        'event_kind_id', 'virtual',
        'logo_url', 'https://example.com/logo.png',
        'meeting_join_url', 'https://meet.example.com/room',
        'meeting_provider_id', 'zoom',
        'meeting_recording_url', 'https://youtube.com/recording',
        'meeting_requested', false,
        'meetup_url', 'https://meetup.com/group/events/123456',
        'name', 'Past Event Updated',
        'photos_urls', array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
        'registration_required', true,
        'starts_at', '2020-01-02 10:00:00+00'::timestamptz,
        'tags', array['updated', 'past', 'event'],
        'timezone', 'UTC',
        'venue_address', '123 Updated St',
        'venue_city', 'Updated City',
        'venue_country_code', 'US',
        'venue_country_name', 'United States',
        'venue_name', 'Updated Venue',
        'venue_state', 'CA',
        'venue_zip_code', '12345'
    ),
    'Should update past event fields'
);

-- Should update hosts on past events
select is(
    (
        select array_agg(user_id order by user_id)
        from event_host
        where event_id = :'event8ID'::uuid
    ),
    array['00000000-0000-0000-0000-000000000020']::uuid[],
    'Should update hosts on past events'
);

-- Should update speakers on past events
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'featured', featured,
                'user_id', user_id
            )
            order by user_id
        )
        from event_speaker
        where event_id = :'event8ID'::uuid
    ),
    '[{"featured": true, "user_id": "00000000-0000-0000-0000-000000000022"}]'::jsonb,
    'Should update speakers on past events'
);

-- Should update sponsors on past events
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'group_sponsor_id', group_sponsor_id,
                'level', level
            )
            order by group_sponsor_id
        )
        from event_sponsor
        where event_id = :'event8ID'::uuid
    ),
    '[{"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "level": "Gold"}]'::jsonb,
    'Should update sponsors on past events'
);

-- Should update sessions on past events
select is(
    (
        select jsonb_build_object(
            'ends_at', ends_at,
            'name', name,
            'session_kind_id', session_kind_id,
            'starts_at', starts_at
        )
        from session
        where event_id = :'event8ID'::uuid
        limit 1
    ),
    jsonb_build_object(
        'ends_at', '2020-01-02 11:30:00+00'::timestamptz,
        'name', 'Past Session',
        'session_kind_id', 'virtual',
        'starts_at', '2020-01-02 10:30:00+00'::timestamptz
    ),
    'Should update sessions on past events'
);

-- Should throw error when past event ends_at is in the future
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000008'::uuid,
        '{"name": "Future Past Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000012", "kind_id": "virtual", "starts_at": "2020-01-02T10:00:00", "ends_at": "2099-01-02T12:30:00"}'::jsonb
    )$$,
    'event ends_at cannot be in the future',
    'Should throw error when past event ends_at is in the future'
);

-- Should throw error when past event session starts_at is in the future
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000008'::uuid,
        '{"name": "Future Past Session", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000012", "kind_id": "virtual", "starts_at": "2020-01-02T10:00:00", "ends_at": "2020-01-02T12:30:00", "sessions": [{"name": "Future Session", "starts_at": "2099-01-02T10:30:00", "ends_at": "2020-01-02T11:30:00", "kind": "virtual"}]}'::jsonb
    )$$,
    'session starts_at cannot be in the future',
    'Should throw error when past event session starts_at is in the future'
);

-- Should throw error when past event session ends_at is in the future
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000008'::uuid,
        '{"name": "Future Past Session", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000012", "kind_id": "virtual", "starts_at": "2020-01-02T10:00:00", "ends_at": "2020-01-02T12:30:00", "sessions": [{"name": "Future Session", "starts_at": "2020-01-02T10:30:00", "ends_at": "2099-01-02T11:30:00", "kind": "virtual"}]}'::jsonb
    )$$,
    'session ends_at cannot be in the future',
    'Should throw error when past event session ends_at is in the future'
);

-- Should succeed updating live event when starts_at is unchanged
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated',
                'description', 'Updated description',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event9ID', :'category1ID', :'event9ID', :'event9ID'
    ),
    'Should succeed updating live event when starts_at is unchanged'
);

-- Should succeed updating live event when starts_at is moved later (but still in past)
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated Again',
                'description', 'Updated description again',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC' + interval '30 minutes', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event9ID', :'category1ID', :'event9ID', :'event9ID'
    ),
    'Should succeed updating live event when starts_at is moved later (but still in past)'
);

-- Recreate a completed session after the prior live-event updates removed it
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested
) values (
    :'session3ID',
    :'event9ID',
    'Completed Live Event Session',
    (select starts_at from event where event_id = :'event9ID'),
    current_timestamp - interval '5 minutes',
    'virtual',
    'zoom',
    true
);

-- Should update session recording override when the live event has a completed session
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated With Session Override',
                'description', 'Updated description with completed session override',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char(
                    (select starts_at from event where event_id = '%s'::uuid)
                    at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS'
                ),
                'ends_at', to_char(
                    (select ends_at from event where event_id = '%s'::uuid)
                    at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS'
                ),
                'sessions', jsonb_build_array(
                    jsonb_build_object(
                        'session_id', '%s',
                        'name', 'Completed Live Event Session',
                        'starts_at', to_char(
                            (select starts_at from session where session_id = '%s'::uuid)
                            at time zone 'UTC',
                            'YYYY-MM-DD"T"HH24:MI:SS'
                        ),
                        'ends_at', to_char(
                            (select ends_at from session where session_id = '%s'::uuid)
                            at time zone 'UTC',
                            'YYYY-MM-DD"T"HH24:MI:SS'
                        ),
                        'kind', 'virtual',
                        'meeting_provider_id', 'zoom',
                        'meeting_recording_url', 'https://youtube.com/watch?v=live-session-override',
                        'meeting_requested', true
                    )
                )
            )
        )$$,
        :'group1ID',
        :'event9ID',
        :'category1ID',
        :'event9ID',
        :'event9ID',
        :'session3ID',
        :'session3ID',
        :'session3ID'
    ),
    'Should update session recording override when the live event has a completed session'
);
select is(
    (select meeting_recording_url from session where session_id = :'session3ID'::uuid),
    'https://youtube.com/watch?v=live-session-override',
    'Should persist the completed session recording override on a live event update'
);

-- Should throw error when capacity is reduced below attendee count
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000016'::uuid,
        '{"name": "Capacity Validation Event", "description": "Test", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "capacity": 2}'::jsonb
    )$$,
    'event capacity (2) cannot be less than current number of attendees (3)',
    'Should throw error when capacity is reduced below attendee count'
);

-- Should reject ticketing conversion when the event already has attendees
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000016'::uuid,
        '{
            "name": "Capacity Validation Event",
            "description": "Ticketed capacity validation",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "in-person",
            "capacity": 100,
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000095",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000096"
                        }
                    ],
                    "seats_total": 2,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require an empty attendee list',
    'Should reject ticketing conversion before ticket-derived capacity can undercount attendees'
);

-- Should succeed when capacity equals attendee count
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000016'::uuid,
        '{"name": "Capacity Validation Event", "description": "Test capacity equals", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "capacity": 3}'::jsonb
    )$$,
    'Should succeed when capacity equals attendee count'
);

-- Should succeed when capacity exceeds attendee count
select lives_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000016'::uuid,
        '{"name": "Capacity Validation Event", "description": "Test capacity exceeds", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "capacity": 100}'::jsonb
    )$$,
    'Should succeed when capacity exceeds attendee count'
);

-- Should promote waitlisted users when increasing capacity on a waitlist-enabled event
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event15ID'::uuid,
        '{
            "name": "Waitlist Promotion Event",
            "description": "Test capacity promotion",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "in-person",
            "capacity": 5,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00",
            "waitlist_enabled": true
        }'::jsonb
    )::jsonb,
    format('["%s","%s"]', :'user4ID', :'user5ID')::jsonb,
    'Should return promoted waitlist user ids when capacity increase opens seats'
);

-- Should move promoted users into attendees and empty the waitlist
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'event15ID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'event15ID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s","%s","%s","%s"],"waitlist":[]}',
        :'user1ID', :'user2ID', :'user3ID', :'user4ID', :'user5ID'
    )::jsonb,
    'Should move promoted waitlist users into attendees when capacity increases'
);

-- Should reject ticketing conversion when attendees already exist, even if the event also has a waitlist
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000027'::uuid,
        '{
            "name": "Ticketing Conversion Event",
            "description": "Published event used to verify ticketing conversion does not promote waitlist users",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "in-person",
            "capacity": 99,
            "ends_at": "2030-04-01T12:00:00",
            "payment_currency_code": "USD",
            "starts_at": "2030-04-01T10:00:00",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000121",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000122"
                        }
                    ],
                    "seats_total": 2,
                    "title": "General admission"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require an empty attendee list',
    'Should reject ticketing conversion when attendees and queued users still exist'
);

-- Should reject ticketing conversion when the event already has a waitlist
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000030'::uuid,
        '{
            "name": "Ticketing Waitlist Event",
            "description": "Published event used for ticketing conversion waitlist checks",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "in-person",
            "capacity": 99,
            "ends_at": "2030-05-01T12:00:00",
            "payment_currency_code": "USD",
            "starts_at": "2030-05-01T10:00:00",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000141",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000142"
                        }
                    ],
                    "seats_total": 2,
                    "title": "General admission"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events cannot have existing waitlist entries',
    'Should reject ticketing conversion when queued users already exist'
);

-- Should reject ticketing conversion when the event already has attendees
select throws_ok(
    $$select update_event(
        null::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000016'::uuid,
        '{
            "name": "Capacity Validation Event",
            "description": "Published event for attendee floor validation checks",
            "timezone": "America/New_York",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "in-person",
            "capacity": 99,
            "ends_at": "2030-02-10T12:00:00",
            "payment_currency_code": "USD",
            "starts_at": "2030-02-10T10:00:00",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "00000000-0000-0000-0000-000000000181",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000182"
                        }
                    ],
                    "seats_total": 3,
                    "title": "General admission"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require an empty attendee list',
    'Should reject ticketing conversion when confirmed attendees already exist'
);

-- Should keep the event unticketed when attendee-based conversion is rejected
select is(
    list_event_ticket_types(:'event14ID'::uuid),
    null,
    'Should leave ticket types untouched when attendee-based conversion is rejected'
);

-- Should keep attendees and waitlist unchanged when rejected conversion leaves the event untouched
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'event20ID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'event20ID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s"],"waitlist":["%s"]}',
        :'user1ID', :'user4ID'
    )::jsonb,
    'Should leave existing waitlist entries untouched when ticketing conversion is rejected'
);

-- Should promote waitlisted users for a published dateless event when capacity increases
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event13ID'::uuid,
        format(
            '{
                "name": "Published Dateless Event",
                "description": "Published event without dates for waitlist promotion checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "capacity": 2,
                "waitlist_enabled": true
            }',
            :'category1ID'
        )::jsonb
    )::jsonb,
    format('["%s"]', :'user3ID')::jsonb,
    'Should return promoted waitlist user ids when a dateless event gains capacity'
);

-- Should move promoted users into attendees for a published dateless event
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'event13ID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'event13ID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s"],"waitlist":[]}',
        :'user2ID', :'user3ID'
    )::jsonb,
    'Should move promoted users into attendees when a dateless event gains capacity'
);

-- Should continue promoting queued users when waitlist is disabled for new joins
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event16ID'::uuid,
        format(
            '{
                "name": "Dateless Waitlist Disabled Event",
                "description": "Published dateless event for disabled waitlist promotion checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "capacity": 3,
                "waitlist_enabled": false
            }',
            :'category1ID'
        )::jsonb
    )::jsonb,
    format('["%s"]', :'user1ID')::jsonb,
    'Should promote existing waitlist users even when waitlist is disabled for new joins'
);

-- Should leave the queue empty after promoting existing users with waitlist disabled
select is(
    (select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb) from event_waitlist where event_id = :'event16ID'::uuid),
    '[]'::jsonb,
    'Should empty the remaining waitlist after promotion when waitlist is disabled'
);

-- Should promote all queued users when capacity becomes unlimited
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event17ID'::uuid,
        format(
            '{
                "name": "Dateless Unlimited Event",
                "description": "Published dateless event for unlimited capacity promotion checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "capacity": null,
                "waitlist_enabled": false
            }',
            :'category1ID'
        )::jsonb
    )::jsonb,
    format('["%s","%s"]', :'user4ID', :'user5ID')::jsonb,
    'Should promote the full queue when capacity becomes unlimited'
);

-- Should empty the queue when capacity becomes unlimited
select is(
        (
            select jsonb_build_object(
                'attendees', (
                    select jsonb_agg(user_id order by user_id)
                    from event_attendee
                    where event_id = :'event17ID'::uuid
                ),
                'waitlist', (
                    select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                    from event_waitlist
                    where event_id = :'event17ID'::uuid
                )
            )
        ),
    format(
        '{"attendees":["%s","%s","%s"],"waitlist":[]}',
        :'user2ID', :'user4ID', :'user5ID'
    )::jsonb,
    'Should move all waitlisted users into attendees when capacity becomes unlimited'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
