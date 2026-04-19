begin;

-- ============================================================================
-- SITE
-- ============================================================================

insert into site (
    site_id,
    title,
    description,
    theme
) values (
    '00000000-0000-0000-0000-000000000000',
    'E2E Test Site',
    'Site for E2E testing',
    '{"primary_color": "#0EA5E9"}'::jsonb
);

-- ============================================================================
-- COMMUNITIES
-- ============================================================================

insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_url,
    banner_mobile_url,
    logo_url
) values (
    '11111111-1111-1111-1111-111111111111',
    'e2e-test-community',
    'Platform Engineering Community',
    'Platform engineering community used for end-to-end coverage.',
    '/static/images/e2e/community-primary-banner.svg',
    '/static/images/e2e/community-primary-banner-mobile.svg',
    '/static/images/e2e/community-primary-logo.svg'
), (
    '11111111-1111-1111-1111-111111111112',
    'e2e-second-community',
    'Developer Experience Community',
    'Developer experience community used for end-to-end coverage.',
    '/static/images/e2e/community-secondary-banner.svg',
    '/static/images/e2e/community-secondary-banner-mobile.svg',
    '/static/images/e2e/community-secondary-logo.svg'
);

-- ============================================================================
-- GROUP CATEGORIES
-- ============================================================================

insert into group_category (group_category_id, name, community_id)
values (
    '22222222-2222-2222-2222-222222222221',
    'E2E Category One',
    '11111111-1111-1111-1111-111111111111'
), (
    '22222222-2222-2222-2222-222222222222',
    'E2E Category Two',
    '11111111-1111-1111-1111-111111111112'
), (
    '22222222-2222-2222-2222-222222222223',
    'E2E Category Unused',
    '11111111-1111-1111-1111-111111111111'
);

-- ============================================================================
-- EVENT CATEGORIES
-- ============================================================================

insert into event_category (event_category_id, name, community_id)
values (
    '33333333-3333-3333-3333-333333333331',
    'General',
    '11111111-1111-1111-1111-111111111111'
), (
    '33333333-3333-3333-3333-333333333332',
    'Meetups',
    '11111111-1111-1111-1111-111111111112'
), (
    '33333333-3333-3333-3333-333333333333',
    'Workshops',
    '11111111-1111-1111-1111-111111111111'
);

-- ============================================================================
-- REGIONS
-- ============================================================================

insert into region (region_id, community_id, name, "order")
values (
    '22222222-2222-2222-2222-222222222301',
    '11111111-1111-1111-1111-111111111111',
    'North America',
    1
), (
    '22222222-2222-2222-2222-222222222302',
    '11111111-1111-1111-1111-111111111111',
    'APAC',
    2
);

-- ============================================================================
-- GROUPS
-- ============================================================================

-- Primary community groups used across the main e2e scenarios
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description,
    region_id,
    active
) values (
    '44444444-4444-4444-4444-444444444441',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Platform Ops Meetup',
    'test-group-alpha',
    'Primary meetup used for end-to-end dashboard and site coverage.',
    '22222222-2222-2222-2222-222222222301',
    true
), (
    '44444444-4444-4444-4444-444444444442',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Inactive Local Chapter',
    'test-group-beta',
    null,
    '22222222-2222-2222-2222-222222222301',
    true
), (
    '44444444-4444-4444-4444-444444444443',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Observability Guild',
    'test-group-gamma',
    null,
    null,
    true
);

-- Secondary community groups used for cross-community coverage
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active
) values (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Delta',
    'second-group-delta',
    true
), (
    '44444444-4444-4444-4444-444444444445',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Epsilon',
    'second-group-epsilon',
    true
), (
    '44444444-4444-4444-4444-444444444446',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Zeta',
    'second-group-zeta',
    true
);

-- Enable payment-ready coverage on the primary group without changing the
-- current payments-disabled e2e server profile.
update "group"
set payment_recipient = '{"provider":"stripe","recipient_id":"acct_e2e_alpha"}'::jsonb
where group_id = '44444444-4444-4444-4444-444444444441';

-- ============================================================================
-- EVENTS
-- ============================================================================

-- Primary group events
-- Upcoming in-person event with full location data
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    venue_name, venue_address, venue_city, venue_state, venue_country_name,
    venue_country_code, venue_zip_code, banner_url, logo_url, capacity,
    registration_required, tags, meetup_url, meeting_join_url, photos_urls
) values (
    '55555555-5555-5555-5555-555555555501',
    'Upcoming In-Person Event',
    'alpha-event-1',
    'Upcoming in-person event used for attendance and dashboard coverage.',
    'Join the primary meetup for end-to-end coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '10 days',
    now() + interval '10 days 2 hours',
    'Tech Conference Center',
    '123 Main Street',
    'New York',
    'NY',
    'United States',
    'US',
    '10001',
    '/static/images/e2e/event-banner.svg',
    '/static/images/e2e/event-logo.svg',
    100,
    true,
    '{"meetup", "tech", "networking"}',
    'https://www.meetup.com/test-group/events/123456789/',
    'https://zoom.us/j/1234567890',
    '{"/static/images/e2e/event-photo-1.svg", "/static/images/e2e/event-photo-2.svg"}'
);

-- Upcoming virtual event with recording
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city,
    meeting_recording_url
) values (
    '55555555-5555-5555-5555-555555555502',
    'Upcoming Virtual Event',
    'alpha-event-2',
    'Upcoming virtual event used for attendee empty-state coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '20 days',
    now() + interval '20 days 2 hours',
    'San Francisco',
    'https://www.youtube.com/watch?v=test123'
);

-- Upcoming hybrid event
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555503',
    'Upcoming Hybrid Event',
    'alpha-event-3',
    'Upcoming hybrid event used for public group-page coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '30 days',
    now() + interval '30 days 2 hours',
    null
);

-- Secondary group events
-- Canceled in-person event for unpublished-state coverage
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city, canceled
) values (
    '55555555-5555-5555-5555-555555555504',
    'Canceled In-Person Event',
    'beta-event-1',
    'Canceled in-person event used for filtering coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444442',
    false,
    now() + interval '11 days',
    now() + interval '11 days 2 hours',
    'Los Angeles',
    true
);

-- Upcoming virtual and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555505',
    'Secondary Virtual Event',
    'beta-event-2',
    'Secondary virtual event for user dashboard filtering coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444442',
    true,
    now() + interval '21 days',
    now() + interval '21 days 2 hours',
    'Los Angeles'
), (
    '55555555-5555-5555-5555-555555555506',
    'Secondary Hybrid Event',
    'beta-event-3',
    'Secondary hybrid event for explore coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444442',
    true,
    now() + interval '31 days',
    now() + interval '31 days 2 hours',
    null
);

-- Search-focused group events
-- In-person, virtual, and hybrid events for search coverage
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555507',
    'Observability In-Person Event',
    'gamma-event-1',
    'In-person event for the observability-focused group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444443',
    true,
    now() + interval '12 days',
    now() + interval '12 days 2 hours',
    'Chicago'
), (
    '55555555-5555-5555-5555-555555555508',
    'Observability Virtual Event',
    'gamma-event-2',
    'Virtual event for the observability-focused group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444443',
    true,
    now() + interval '22 days',
    now() + interval '22 days 2 hours',
    'Chicago'
), (
    '55555555-5555-5555-5555-555555555509',
    'Observability Hybrid Event',
    'gamma-event-3',
    'Hybrid event for the observability-focused group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444443',
    true,
    now() + interval '32 days',
    now() + interval '32 days 2 hours',
    null
);

-- Delta group events
-- Past, virtual, and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555510',
    'Delta Event One',
    'delta-event-1',
    'In-person event for Delta group (past).',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'in-person',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() - interval '13 days',
    now() - interval '13 days' + interval '2 hours'
), (
    '55555555-5555-5555-5555-555555555511',
    'Delta Event Two',
    'delta-event-2',
    'Virtual event for Delta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'virtual',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() + interval '23 days',
    now() + interval '23 days 2 hours'
), (
    '55555555-5555-5555-5555-555555555512',
    'Delta Event Three',
    'delta-event-3',
    'Hybrid event for Delta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'hybrid',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() + interval '33 days',
    now() + interval '33 days 2 hours'
);

-- Epsilon group events
-- Past, virtual, and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555513',
    'Epsilon Event One',
    'epsilon-event-1',
    'In-person event for Epsilon group (past).',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'in-person',
    '44444444-4444-4444-4444-444444444445',
    true,
    now() - interval '14 days',
    now() - interval '14 days' + interval '2 hours'
), (
    '55555555-5555-5555-5555-555555555514',
    'Epsilon Event Two',
    'epsilon-event-2',
    'Virtual event for Epsilon group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'virtual',
    '44444444-4444-4444-4444-444444444445',
    true,
    now() + interval '24 days',
    now() + interval '24 days 2 hours'
), (
    '55555555-5555-5555-5555-555555555515',
    'Epsilon Event Three',
    'epsilon-event-3',
    'Hybrid event for Epsilon group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'hybrid',
    '44444444-4444-4444-4444-444444444445',
    true,
    now() + interval '34 days',
    now() + interval '34 days 2 hours'
);

-- Zeta group events
-- Past, virtual, and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555516',
    'Zeta Event One',
    'zeta-event-1',
    'In-person event for Zeta group (past).',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'in-person',
    '44444444-4444-4444-4444-444444444446',
    true,
    now() - interval '15 days',
    now() - interval '15 days' + interval '2 hours'
), (
    '55555555-5555-5555-5555-555555555517',
    'Zeta Event Two',
    'zeta-event-2',
    'Virtual event for Zeta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'virtual',
    '44444444-4444-4444-4444-444444444446',
    true,
    now() + interval '25 days',
    now() + interval '25 days 2 hours'
), (
    '55555555-5555-5555-5555-555555555518',
    'Zeta Event Three',
    'zeta-event-3',
    'Hybrid event for Zeta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'hybrid',
    '44444444-4444-4444-4444-444444444446',
    true,
    now() + interval '35 days',
    now() + interval '35 days 2 hours'
);

-- Primary group events for CFS, filtering, and waitlist coverage
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at
) values (
    '55555555-5555-5555-5555-555555555519',
    'Event With Active CFS',
    'alpha-cfs-summit',
    'Future event with an active call for speakers.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '45 days',
    now() + interval '45 days 4 hours',
    true,
    'Submit your best talks for our extended speaker program.',
    now() - interval '2 days',
    now() + interval '30 days'
), (
    '55555555-5555-5555-5555-555555555520',
    'Past Event For Filtering',
    'alpha-past-roundup',
    'Past event used for dashboard and user filtering coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() - interval '5 days',
    now() - interval '5 days' + interval '2 hours',
    null,
    null,
    null,
    null
);

insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    capacity, registration_required, waitlist_enabled
) values (
    '55555555-5555-5555-5555-555555555521',
    'Full Event With Waitlist',
    'alpha-waitlist-lab',
    'Future event dedicated to waitlist and attendee coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '60 days',
    now() + interval '60 days 2 hours',
    1,
    true,
    true
);

-- Ticketed payment fixtures reserved for the Playwright suite.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, payment_currency_code, published, starts_at, ends_at,
    registration_required, waitlist_enabled
) values (
    '55555555-5555-5555-5555-555555555522',
    'Ticketed Draft Event',
    'alpha-payments-draft',
    'Ticketed event used for payment editor and validation coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    now() + interval '90 days',
    now() + interval '90 days 3 hours',
    true,
    false
), (
    '55555555-5555-5555-5555-555555555523',
    'Ticketed Refund Review Event',
    'alpha-payments-refunds',
    'Ticketed event used for organizer refund review coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    now() + interval '95 days',
    now() + interval '95 days 2 hours',
    true,
    false
);

-- ============================================================================
-- USERS
-- Password: Password123!
-- Hash generated with Argon2id (password_auth crate default)
-- ============================================================================

insert into "user" (
    user_id, username, email, email_verified, name, password, auth_hash
) values (
    '77777777-7777-7777-7777-777777777701',
    'e2e-admin-1',
    'e2e-admin-1@example.com',
    true,
    'E2E Admin One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2'
), (
    '77777777-7777-7777-7777-777777777702',
    'e2e-admin-2',
    'e2e-admin-2@example.com',
    true,
    'E2E Admin Two',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3'
), (
    '77777777-7777-7777-7777-777777777703',
    'e2e-organizer-1',
    'e2e-organizer-1@example.com',
    true,
    'E2E Organizer One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4'
), (
    '77777777-7777-7777-7777-777777777704',
    'e2e-organizer-2',
    'e2e-organizer-2@example.com',
    true,
    'E2E Organizer Two',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'd4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5'
), (
    '77777777-7777-7777-7777-777777777705',
    'e2e-member-1',
    'e2e-member-1@example.com',
    true,
    'E2E Member One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6'
), (
    '77777777-7777-7777-7777-777777777706',
    'e2e-member-2',
    'e2e-member-2@example.com',
    true,
    'E2E Member Two',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1'
), (
    '77777777-7777-7777-7777-777777777707',
    'e2e-pending-1',
    'e2e-pending-1@example.com',
    true,
    'E2E Pending One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b3'
), (
    '77777777-7777-7777-7777-777777777708',
    'e2e-pending-2',
    'e2e-pending-2@example.com',
    true,
    'E2E Pending Two',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c4'
), (
    '77777777-7777-7777-7777-777777777709',
    'e2e-groups-manager-1',
    'e2e-groups-manager-1@example.com',
    true,
    'E2E Groups Manager One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'c4d5e6f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d5'
), (
    '77777777-7777-7777-7777-777777777710',
    'e2e-community-viewer-1',
    'e2e-community-viewer-1@example.com',
    true,
    'E2E Community Viewer One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'd5e6f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e6'
), (
    '77777777-7777-7777-7777-777777777711',
    'e2e-events-manager-1',
    'e2e-events-manager-1@example.com',
    true,
    'E2E Events Manager One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'e6f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f7'
), (
    '77777777-7777-7777-7777-777777777712',
    'e2e-group-viewer-1',
    'e2e-group-viewer-1@example.com',
    true,
    'E2E Group Viewer One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a2'
);

-- ============================================================================
-- COMMUNITY TEAM
-- Accepted roles and pending invitations for community dashboards
-- ============================================================================

-- Accepted admin for the primary community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777701',
    true,
    'admin'
);

-- Accepted admin for the secondary community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111112',
    '77777777-7777-7777-7777-777777777702',
    true,
    'admin'
);

-- Groups manager for the primary community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777709',
    true,
    'groups-manager'
);

-- Read-only viewer for the primary community dashboard
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777710',
    true,
    'viewer'
);

-- Pending invitation for the primary community team
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777707',
    false,
    'viewer'
);

-- ============================================================================
-- GROUP TEAM
-- Accepted roles and pending invitations for group dashboards
-- ============================================================================

-- Accepted organizer for the primary group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777703',
    true,
    'admin'
);

-- Accepted organizer for the Delta group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444444',
    '77777777-7777-7777-7777-777777777704',
    true,
    'admin'
);

-- Events manager for the primary group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777711',
    true,
    'events-manager'
);

-- Read-only viewer for the primary group dashboard
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777712',
    true,
    'viewer'
);

-- Pending invitation for the secondary group team
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444442',
    '77777777-7777-7777-7777-777777777707',
    false,
    'events-manager'
);

-- Pending viewer invitation for the primary group team
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777708',
    false,
    'viewer'
);

-- ============================================================================
-- GROUP MEMBERS
-- Membership relationships used by site and dashboard flows
-- ============================================================================

-- Member of the primary and secondary groups
insert into group_member (group_id, user_id)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777705'
), (
    '44444444-4444-4444-4444-444444444442',
    '77777777-7777-7777-7777-777777777705'
);

-- Member of the Delta and Epsilon groups
insert into group_member (group_id, user_id)
values (
    '44444444-4444-4444-4444-444444444444',
    '77777777-7777-7777-7777-777777777706'
), (
    '44444444-4444-4444-4444-444444444445',
    '77777777-7777-7777-7777-777777777706'
);

-- ============================================================================
-- EVENT CFS LABELS
-- ============================================================================

insert into event_cfs_label (event_cfs_label_id, event_id, name, color)
values (
    '99999999-9999-9999-9999-999999999701',
    '55555555-5555-5555-5555-555555555519',
    'Platform',
    '#0284C7'
), (
    '99999999-9999-9999-9999-999999999702',
    '55555555-5555-5555-5555-555555555519',
    'Workshop',
    '#16A34A'
);

-- ============================================================================
-- SESSION PROPOSALS
-- ============================================================================

insert into session_proposal (
    session_proposal_id,
    user_id,
    title,
    description,
    session_proposal_level_id,
    duration,
    co_speaker_user_id,
    session_proposal_status_id,
    updated_at
) values (
    '99999999-9999-9999-9999-999999999801',
    '77777777-7777-7777-7777-777777777705',
    'Cloud Native Operations Deep Dive',
    'A ready proposal that has not been submitted yet.',
    'advanced',
    interval '45 minutes',
    null,
    'ready-for-submission',
    now() - interval '3 days'
), (
    '99999999-9999-9999-9999-999999999802',
    '77777777-7777-7777-7777-777777777705',
    'Platform Reliability Patterns',
    'A proposal already submitted to the open CFS event.',
    'intermediate',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '4 days'
), (
    '99999999-9999-9999-9999-999999999803',
    '77777777-7777-7777-7777-777777777705',
    'Observability in Practice',
    'A proposal that needs additional details before approval.',
    'beginner',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '2 days'
), (
    '99999999-9999-9999-9999-999999999804',
    '77777777-7777-7777-7777-777777777705',
    'Scaling Community Workshops',
    'An approved proposal linked to a scheduled session.',
    'intermediate',
    interval '45 minutes',
    null,
    'ready-for-submission',
    now() - interval '1 day'
), (
    '99999999-9999-9999-9999-999999999805',
    '77777777-7777-7777-7777-777777777705',
    'Maintainer Burnout Lessons',
    'A proposal that was reviewed and rejected.',
    'advanced',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '5 days'
), (
    '99999999-9999-9999-9999-999999999806',
    '77777777-7777-7777-7777-777777777705',
    'Speaker Office Hours',
    'A proposal that was submitted and then withdrawn.',
    'beginner',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '6 days'
), (
    '99999999-9999-9999-9999-999999999807',
    '77777777-7777-7777-7777-777777777705',
    'Collaborative Roadmaps',
    'A proposal waiting for the co-speaker response.',
    'intermediate',
    interval '45 minutes',
    '77777777-7777-7777-7777-777777777706',
    'pending-co-speaker-response',
    now() - interval '1 day'
), (
    '99999999-9999-9999-9999-999999999808',
    '77777777-7777-7777-7777-777777777705',
    'Co-Speaker Retrospective',
    'A proposal whose co-speaker declined the invitation.',
    'beginner',
    interval '30 minutes',
    '77777777-7777-7777-7777-777777777706',
    'declined-by-co-speaker',
    now() - interval '7 days'
);

-- ============================================================================
-- CFS SUBMISSIONS
-- ============================================================================

insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message,
    reviewed_by,
    updated_at
) values (
    '99999999-9999-9999-9999-999999999911',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999802',
    'not-reviewed',
    null,
    null,
    now() - interval '4 days'
), (
    '99999999-9999-9999-9999-999999999912',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999803',
    'information-requested',
    'Please add clearer audience outcomes before we continue the review.',
    '77777777-7777-7777-7777-777777777703',
    now() - interval '2 days'
), (
    '99999999-9999-9999-9999-999999999913',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999804',
    'approved',
    null,
    '77777777-7777-7777-7777-777777777703',
    now() - interval '1 day'
), (
    '99999999-9999-9999-9999-999999999914',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999805',
    'rejected',
    null,
    '77777777-7777-7777-7777-777777777703',
    now() - interval '3 days'
), (
    '99999999-9999-9999-9999-999999999915',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999806',
    'withdrawn',
    null,
    null,
    now() - interval '5 hours'
);

insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id)
values (
    '99999999-9999-9999-9999-999999999911',
    '99999999-9999-9999-9999-999999999701'
), (
    '99999999-9999-9999-9999-999999999912',
    '99999999-9999-9999-9999-999999999702'
), (
    '99999999-9999-9999-9999-999999999913',
    '99999999-9999-9999-9999-999999999701'
), (
    '99999999-9999-9999-9999-999999999913',
    '99999999-9999-9999-9999-999999999702'
);

insert into cfs_submission_rating (cfs_submission_id, reviewer_id, stars, comments)
values (
    '99999999-9999-9999-9999-999999999912',
    '77777777-7777-7777-7777-777777777703',
    3,
    'Needs a tighter outline and clearer takeaways.'
), (
    '99999999-9999-9999-9999-999999999913',
    '77777777-7777-7777-7777-777777777703',
    5,
    'Strong structure and audience fit.'
), (
    '99999999-9999-9999-9999-999999999913',
    '77777777-7777-7777-7777-777777777711',
    4,
    'Solid proposal with only minor refinements needed.'
);

-- ============================================================================
-- GROUP SPONSORS
-- ============================================================================

insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (
    '66666666-6666-6666-6666-666666666601',
    '44444444-4444-4444-4444-444444444441',
    'Tech Corp',
    '/static/images/e2e/sponsor-logo.svg',
    'https://techcorp.example.com'
);

-- ============================================================================
-- EVENT SPONSORS
-- ============================================================================

insert into event_sponsor (group_sponsor_id, event_id, level)
values (
    '66666666-6666-6666-6666-666666666601',
    '55555555-5555-5555-5555-555555555501',
    'gold'
);

-- ============================================================================
-- EVENT HOSTS
-- ============================================================================

insert into event_host (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777703'
);

-- ============================================================================
-- EVENT ATTENDEES
-- ============================================================================

insert into event_attendee (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555504',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555520',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555521',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777706'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777707'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777708'
);

-- ============================================================================
-- EVENT TICKETING
-- ============================================================================

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title,
    description
)
values (
    '56555555-5555-5555-5555-555555555521',
    true,
    '55555555-5555-5555-5555-555555555522',
    1,
    30,
    'General admission',
    'Standard paid admission used for ticket editor coverage.'
), (
    '56555555-5555-5555-5555-555555555522',
    true,
    '55555555-5555-5555-5555-555555555522',
    2,
    10,
    'Community ticket',
    'Free community allocation used for zero-price ticket coverage.'
), (
    '56555555-5555-5555-5555-555555555524',
    true,
    '55555555-5555-5555-5555-555555555522',
    3,
    2,
    'Backstage pass',
    'Future sale window used for unavailable ticket coverage.'
), (
    '56555555-5555-5555-5555-555555555523',
    true,
    '55555555-5555-5555-5555-555555555523',
    1,
    5,
    'VIP pass',
    'Paid pass used for organizer refund review coverage.'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id,
    starts_at,
    ends_at
)
values (
    '57555555-5555-5555-5555-555555555521',
    2500,
    '56555555-5555-5555-5555-555555555521',
    null,
    now() + interval '45 days'
), (
    '57555555-5555-5555-5555-555555555522',
    3000,
    '56555555-5555-5555-5555-555555555521',
    now() + interval '45 days',
    null
), (
    '57555555-5555-5555-5555-555555555523',
    0,
    '56555555-5555-5555-5555-555555555522',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555525',
    7000,
    '56555555-5555-5555-5555-555555555524',
    now() + interval '5 days',
    null
), (
    '57555555-5555-5555-5555-555555555524',
    5000,
    '56555555-5555-5555-5555-555555555523',
    null,
    null
);

insert into event_discount_code (
    event_discount_code_id,
    active,
    code,
    event_id,
    kind,
    title,
    amount_minor,
    percentage,
    starts_at,
    ends_at,
    total_available,
    available
)
values (
    '58555555-5555-5555-5555-555555555521',
    true,
    'SAVE10',
    '55555555-5555-5555-5555-555555555522',
    'fixed_amount',
    'Launch savings',
    1000,
    null,
    null,
    null,
    null,
    null
), (
    '58555555-5555-5555-5555-555555555522',
    true,
    'EARLY20',
    '55555555-5555-5555-5555-555555555522',
    'percentage',
    'Early supporter',
    null,
    20,
    null,
    null,
    null,
    null
), (
    '58555555-5555-5555-5555-555555555523',
    true,
    'EXPIRED15',
    '55555555-5555-5555-5555-555555555522',
    'percentage',
    'Expired campaign',
    null,
    15,
    null,
    now() - interval '1 day',
    null,
    null
), (
    '58555555-5555-5555-5555-555555555524',
    true,
    'LIMIT5',
    '55555555-5555-5555-5555-555555555522',
    'fixed_amount',
    'Limited campaign',
    500,
    null,
    null,
    null,
    1,
    0
), (
    '58555555-5555-5555-5555-555555555525',
    true,
    'REVIEW10',
    '55555555-5555-5555-5555-555555555523',
    'fixed_amount',
    'Refund review discount',
    1000,
    null,
    null,
    null,
    1,
    0
);

-- ============================================================================
-- EVENT PURCHASES
-- ============================================================================

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id
)
values (
    '59555555-5555-5555-5555-555555555521',
    4000,
    now() - interval '2 days',
    'USD',
    1000,
    'REVIEW10',
    '58555555-5555-5555-5555-555555555525',
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_pending',
    'https://checkout.stripe.test/cs_e2e_refund_pending',
    'pi_e2e_refund_pending',
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777705'
), (
    '59555555-5555-5555-5555-555555555522',
    5000,
    now() - interval '3 days',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_retry',
    'https://checkout.stripe.test/cs_e2e_refund_retry',
    'pi_e2e_refund_retry',
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777706'
), (
    '59555555-5555-5555-5555-555555555523',
    5000,
    now() - interval '4 days',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_rejected',
    'https://checkout.stripe.test/cs_e2e_refund_rejected',
    'pi_e2e_refund_rejected',
    'completed',
    'VIP pass',
    '77777777-7777-7777-7777-777777777707'
), (
    '59555555-5555-5555-5555-555555555524',
    5000,
    now() - interval '1 day',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_available',
    'https://checkout.stripe.test/cs_e2e_refund_available',
    'pi_e2e_refund_available',
    'completed',
    'VIP pass',
    '77777777-7777-7777-7777-777777777708'
);

-- ============================================================================
-- EVENT REFUND REQUESTS
-- ============================================================================

insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    requested_reason,
    status
)
values (
    '60555555-5555-5555-5555-555555555521',
    '59555555-5555-5555-5555-555555555521',
    '77777777-7777-7777-7777-777777777705',
    'Need to cancel',
    'pending'
), (
    '60555555-5555-5555-5555-555555555522',
    '59555555-5555-5555-5555-555555555522',
    '77777777-7777-7777-7777-777777777706',
    'Schedule conflict',
    'approving'
), (
    '60555555-5555-5555-5555-555555555523',
    '59555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777707',
    'Need a different date',
    'rejected'
);

-- ============================================================================
-- EVENT SPEAKERS
-- ============================================================================

insert into event_speaker (event_id, user_id, featured)
values (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777705',
    true
), (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777706',
    false
);

-- ============================================================================
-- AUDIT LOGS
-- ============================================================================

insert into audit_log (
    audit_log_id,
    action,
    created_at,
    resource_id,
    resource_type,
    actor_user_id,
    actor_username,
    community_id,
    details,
    event_id,
    group_id
) values (
    '88888888-8888-8888-8888-888888888801',
    'community_updated',
    now() - interval '6 hours',
    '11111111-1111-1111-1111-111111111111',
    'community',
    '77777777-7777-7777-7777-777777777701',
    'e2e-admin-1',
    '11111111-1111-1111-1111-111111111111',
    '{}'::jsonb,
    null,
    null
), (
    '88888888-8888-8888-8888-888888888802',
    'group_added',
    now() - interval '5 hours',
    '44444444-4444-4444-4444-444444444443',
    'group',
    '77777777-7777-7777-7777-777777777701',
    'e2e-admin-1',
    '11111111-1111-1111-1111-111111111111',
    '{"region":"North America","status":"Active"}'::jsonb,
    null,
    null
), (
    '88888888-8888-8888-8888-888888888803',
    'group_updated',
    now() - interval '4 hours',
    '44444444-4444-4444-4444-444444444441',
    'group',
    '77777777-7777-7777-7777-777777777703',
    'e2e-organizer-1',
    '11111111-1111-1111-1111-111111111111',
    '{}'::jsonb,
    null,
    '44444444-4444-4444-4444-444444444441'
), (
    '88888888-8888-8888-8888-888888888804',
    'group_sponsor_added',
    now() - interval '3 hours',
    '66666666-6666-6666-6666-666666666601',
    'group_sponsor',
    '77777777-7777-7777-7777-777777777703',
    'e2e-organizer-1',
    '11111111-1111-1111-1111-111111111111',
    '{"tier":"gold","website":"https://techcorp.example.com"}'::jsonb,
    null,
    '44444444-4444-4444-4444-444444444441'
), (
    '88888888-8888-8888-8888-888888888805',
    'user_details_updated',
    now() - interval '2 hours',
    '77777777-7777-7777-7777-777777777705',
    'user',
    '77777777-7777-7777-7777-777777777705',
    'e2e-member-1',
    null,
    '{}'::jsonb,
    null,
    null
), (
    '88888888-8888-8888-8888-888888888806',
    'session_proposal_added',
    now() - interval '1 hour',
    '99999999-9999-9999-9999-999999999801',
    'session_proposal',
    '77777777-7777-7777-7777-777777777705',
    'e2e-member-1',
    null,
    '{"source":"Seeded logs fixture","level":"advanced"}'::jsonb,
    null,
    null
);

-- ============================================================================
-- SESSIONS
-- ============================================================================

insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    description,
    cfs_submission_id
)
values (
    '88888888-8888-8888-8888-888888888801',
    '55555555-5555-5555-5555-555555555501',
    'Opening Keynote',
    'in-person',
    now() + interval '10 days',
    now() + interval '10 days 1 hour',
    'Welcome and introduction to the event.',
    null
), (
    '88888888-8888-8888-8888-888888888802',
    '55555555-5555-5555-5555-555555555501',
    'Technical Workshop',
    'in-person',
    now() + interval '10 days 1 hour',
    now() + interval '10 days 2 hours',
    'Hands-on technical session.',
    null
), (
    '88888888-8888-8888-8888-888888888803',
    '55555555-5555-5555-5555-555555555519',
    'Scaling Community Workshops Session',
    'virtual',
    now() + interval '45 days 1 hour',
    now() + interval '45 days 1 hour 45 minutes',
    'Approved proposal linked into the CFS agenda.',
    '99999999-9999-9999-9999-999999999913'
);

-- ============================================================================
-- SESSION SPEAKERS
-- ============================================================================

insert into session_speaker (session_id, user_id, featured)
values (
    '88888888-8888-8888-8888-888888888801',
    '77777777-7777-7777-7777-777777777705',
    true
), (
    '88888888-8888-8888-8888-888888888803',
    '77777777-7777-7777-7777-777777777705',
    true
);

commit;
