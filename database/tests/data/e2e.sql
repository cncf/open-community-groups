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
    ad_banner_link_url,
    ad_banner_url,
    banner_url,
    banner_mobile_url,
    logo_url
) values (
    '11111111-1111-1111-1111-111111111111',
    'e2e-test-community',
    'Platform Engineering Community',
    'Platform engineering community used for end-to-end coverage.',
    null,
    null,
    '/static/images/e2e/community-primary-banner.svg',
    '/static/images/e2e/community-primary-banner-mobile.svg',
    '/static/images/e2e/community-primary-logo.svg'
), (
    '11111111-1111-1111-1111-111111111112',
    'e2e-second-community',
    'Developer Experience Community',
    'Developer experience community used for end-to-end coverage.',
    'https://example.com/e2e-advertisement',
    '/static/images/e2e/event-banner.svg',
    '/static/images/e2e/community-secondary-banner.svg',
    '/static/images/e2e/community-secondary-banner-mobile.svg',
    '/static/images/e2e/community-secondary-logo.svg'
), (
    '11111111-1111-1111-1111-111111111113',
    'e2e-empty-community',
    'Empty Coverage Community',
    'Dedicated community for empty dashboard states.',
    null,
    null,
    '/static/images/e2e/community-secondary-banner.svg',
    '/static/images/e2e/community-secondary-banner-mobile.svg',
    '/static/images/e2e/community-secondary-logo.svg'
);

update community
set active = false
where community_id = '11111111-1111-1111-1111-111111111113';

-- Public social links and new group instructions for community page coverage.
update community
set twitter_url = 'https://twitter.com/e2e-devex',
    github_url = 'https://github.com/e2e-devex',
    linkedin_url = 'https://linkedin.com/company/e2e-devex',
    new_group_details = 'Open an issue in our GitHub organization to propose a new group.'
where community_id = '11111111-1111-1111-1111-111111111112';

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
    parent_group_id,
    active
) values (
    '44444444-4444-4444-4444-444444444441',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Platform Ops Meetup',
    'test-group-alpha',
    'Primary meetup used for end-to-end dashboard and site coverage.',
    '22222222-2222-2222-2222-222222222301',
    null,
    true
), (
    '44444444-4444-4444-4444-444444444442',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Inactive Local Chapter',
    'test-group-beta',
    null,
    '22222222-2222-2222-2222-222222222301',
    '44444444-4444-4444-4444-444444444441',
    true
), (
    '44444444-4444-4444-4444-444444444443',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Observability Guild',
    'test-group-gamma',
    null,
    null,
    null,
    true
), (
    '44444444-4444-4444-4444-444444444447',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Empty Coverage Group',
    'empty-coverage-group',
    'Dedicated group for empty dashboard states.',
    null,
    null,
    false
);

-- Secondary community groups used for cross-community coverage
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    description,
    slug,
    active
) values (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Delta',
    'Secondary community group used for end-to-end dashboard coverage.',
    'second-group-delta',
    true
), (
    '44444444-4444-4444-4444-444444444445',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Epsilon',
    null,
    'second-group-epsilon',
    true
), (
    '44444444-4444-4444-4444-444444444446',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Zeta',
    null,
    'second-group-zeta',
    true
);

-- Enable payment-ready coverage on the primary group without changing the
-- current payments-disabled e2e server profile.
update "group"
set payment_recipient = '{"provider":"stripe","recipient_id":"acct_e2e_alpha","seller_display_name":"E2E Alpha Fiscal Sponsor"}'::jsonb
where group_id = '44444444-4444-4444-4444-444444444441';

-- Social links for the gamma group used by public page breakpoint coverage.
update "group"
set website_url = 'https://example.com/e2e-observability-guild',
    twitter_url = 'https://twitter.com/e2e-observability'
where group_id = '44444444-4444-4444-4444-444444444443';

-- Location for the gamma group so explore map view renders its marker.
update "group"
set city = 'Seattle',
    location = ST_SetSRID(ST_MakePoint(-122.3321, 47.6062), 4326)
where group_id = '44444444-4444-4444-4444-444444444443';

-- ============================================================================
-- EVENTS
-- ============================================================================

-- Primary group events
-- Upcoming in-person event with full location data
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    venue_name, venue_address, venue_city, venue_state_code, venue_state_name, venue_country_name,
    venue_country_code, venue_zip_code, location, banner_url, logo_url, capacity,
    tags, meetup_url, meeting_join_url, photos_urls
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
    'NY',
    'United States',
    'US',
    '10001',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '/static/images/e2e/event-banner.svg',
    '/static/images/e2e/event-logo.svg',
    100,
    '{"meetup", "tech", "networking"}',
    'https://www.meetup.com/test-group/events/123456789/',
    'https://zoom.us/j/1234567890',
    -- The first photo path intentionally does not exist: e2e tests rely on it
    -- to cover broken gallery image fallback behavior. Do not "fix" it.
    '{"/static/images/e2e/missing-event-gallery-photo.svg", "/static/images/e2e/event-photo-2.svg"}'
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
    cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at,
    meeting_recording_url
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
    now() + interval '30 days',
    null
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
    null,
    'https://recordings.example.test/alpha-past-roundup'
);

-- Publish the past event recording so the public page shows the recording link.
update event
set meeting_recording_published = true
where event_id = '55555555-5555-5555-5555-555555555520';

-- Second past event so the dashboard past events tab can paginate.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555536',
    'Past Pagination Event',
    'alpha-past-pagination',
    'Older past event used for past events pagination coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() - interval '20 days',
    now() - interval '20 days' + interval '2 hours'
);

-- Events reserved for call-for-speakers window coverage.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at
) values (
    '55555555-5555-5555-5555-555555555533',
    'Upcoming Call for Speakers Window',
    'alpha-cfs-upcoming',
    'Future event whose call for speakers has not opened yet.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '400 days',
    now() + interval '400 days 2 hours',
    true,
    'Speaker submissions will open later for this event.',
    now() + interval '300 days',
    now() + interval '330 days'
), (
    '55555555-5555-5555-5555-555555555534',
    'Closed Call for Speakers Window',
    'alpha-cfs-closed',
    'Future event whose call for speakers has already closed.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '400 days',
    now() + interval '400 days 2 hours',
    true,
    'Speaker submissions are closed for this event.',
    now() - interval '30 days',
    now() - interval '5 days'
);

insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    capacity, waitlist_enabled
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
    true
), (
    '55555555-5555-5555-5555-555555555526',
    'Dashboard Waitlist Table Lab',
    'alpha-dashboard-waitlist-lab',
    'Future event dedicated to dashboard waitlist table coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '59 days',
    now() + interval '59 days 2 hours',
    1,
    true
);

-- Events reserved for cancellation lifecycle and canceled invitation history coverage.
insert into event (
    event_id,
    canceled,
    description,
    ends_at,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    registration_questions,
    slug,
    starts_at,
    timezone
)
values (
    '55555555-5555-5555-5555-555555555527',
    false,
    'Future event used to verify attendee state transitions after event cancellation.',
    now() + interval '62 days 2 hours',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'Event Cancellation Lifecycle',
    true,
    '[{"id":"57555555-5555-5555-5555-555555555527","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb,
    'alpha-event-cancellation-lifecycle',
    now() + interval '62 days',
    'UTC'
), (
    '55555555-5555-5555-5555-555555555528',
    true,
    'Canceled event used to preserve canceled invitation history in the dashboard.',
    now() + interval '63 days 2 hours',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'Canceled Invitation History',
    true,
    '[]'::jsonb,
    'alpha-canceled-invitation-history',
    now() + interval '63 days',
    'UTC'
);

-- Published test event for direct event-page badge coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, test_event, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555524',
    'Test Event Page Badge',
    'alpha-test-event-badge',
    'Published test event used for event page badge coverage.',
    'Direct link coverage for test event badges.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() + interval '70 days',
    now() + interval '70 days 2 hours'
);

-- Registration questions event with answered attendees.
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    capacity, registration_questions
) values (
    '55555555-5555-5555-5555-555555555525',
    'Registration Answers Lab',
    'alpha-registration-answers-lab',
    'Future event with realistic registration questions and submitted attendee answers.',
    'Review realistic attendee questionnaire answers in the dashboard.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '80 days',
    now() + interval '80 days 2 hours',
    60,
    '[
        {
            "id": "57555555-5555-5555-5555-555555555501",
            "kind": "free-text",
            "prompt": "What are you hoping to learn from this event?",
            "required": true,
            "options": []
        },
        {
            "id": "57555555-5555-5555-5555-555555555502",
            "kind": "single-select",
            "prompt": "Preferred session format",
            "required": true,
            "options": [
                { "id": "58555555-5555-5555-5555-555555555501", "label": "Hands-on workshop" },
                { "id": "58555555-5555-5555-5555-555555555502", "label": "Panel discussion" },
                { "id": "58555555-5555-5555-5555-555555555503", "label": "Lightning talks" }
            ]
        },
        {
            "id": "57555555-5555-5555-5555-555555555503",
            "kind": "multi-select",
            "prompt": "Topics you want covered",
            "required": true,
            "options": [
                { "id": "58555555-5555-5555-5555-555555555504", "label": "Platform reliability" },
                { "id": "58555555-5555-5555-5555-555555555505", "label": "Developer experience" },
                { "id": "58555555-5555-5555-5555-555555555506", "label": "Security and compliance" },
                { "id": "58555555-5555-5555-5555-555555555507", "label": "Open source governance" }
            ]
        },
        {
            "id": "57555555-5555-5555-5555-555555555504",
            "kind": "free-text",
            "prompt": "Anything the organizers should know?",
            "required": false,
            "options": []
        }
    ]'::jsonb
);

-- Public attendance workflow fixtures for Playwright coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, published, test_event, starts_at, ends_at,
    attendee_approval_required, registration_starts_at, registration_ends_at
) values (
    '55555555-5555-5555-5555-555555555529',
    'Open Public Check-In',
    'alpha-open-public-check-in',
    'Live event used to verify attendee credentials and organizer scanning.',
    'Live event with organizer check-in available.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() - interval '1 hour',
    now() + interval '2 days',
    false,
    null,
    null
), (
    '55555555-5555-5555-5555-555555555530',
    'Approval Required Attendance',
    'alpha-approval-required-attendance',
    'Future event used to verify public invitation request states.',
    'Future event requiring organizer approval.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() + interval '120 days',
    now() + interval '120 days 2 hours',
    true,
    now() - interval '1 day',
    now() + interval '100 days'
);

-- Meeting access details for the live event used in join link coverage.
update event
set meeting_join_url = 'https://meet.example.com/e2e-open-check-in',
    meeting_join_instructions = 'Use the passcode shared with attendees to join the room.'
where event_id = '55555555-5555-5555-5555-555555555529';

-- Public event state fixtures for canceled and unpublished page coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, published, test_event, canceled,
    starts_at, ends_at, cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at,
    meeting_join_url, meeting_join_instructions
) values (
    '55555555-5555-5555-5555-555555555531',
    'Canceled Public Event',
    'alpha-canceled-public-event',
    'Canceled event used to verify unavailable public actions.',
    'Canceled event with public actions disabled.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    true,
    now() + interval '30 days',
    now() + interval '30 days 2 hours',
    true,
    'Speaker submissions would be open if the event were active.',
    now() - interval '1 day',
    now() + interval '10 days',
    'https://meet.example.com/e2e-canceled-event',
    'Join the canceled event using the private meeting room.'
), (
    '55555555-5555-5555-5555-555555555532',
    'Unpublished Public Event',
    'alpha-unpublished-public-event',
    'Unpublished event used to verify public route protection.',
    'Unpublished event hidden from the public site.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    false,
    true,
    false,
    now() + interval '31 days',
    now() + interval '31 days 2 hours',
    false,
    null,
    null,
    null,
    null,
    null
);

-- Multi-day public event used for agenda day tab coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, published, test_event, canceled,
    starts_at, ends_at, cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at,
    meeting_join_url, meeting_join_instructions
) values (
    '55555555-5555-5555-5555-555555555535',
    'Multi Day Summit',
    'alpha-multi-day-summit',
    'Two-day summit used to verify the public multi-day agenda tabs.',
    'Two-day summit with a per-day agenda.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    false,
    now() + interval '40 days',
    now() + interval '41 days 2 hours',
    false,
    null,
    null,
    null,
    null,
    null
);

-- Ticketed payment fixtures reserved for the Playwright suite.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, payment_currency_code, published, starts_at, ends_at,
    waitlist_enabled
) values (
    '55555555-5555-5555-5555-555555555522',
    'Paid Tier Draft Event',
    'alpha-payments-draft',
    'Paid-tier event used for payment editor and validation coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    now() + interval '90 days',
    now() + interval '90 days 3 hours',
    false
), (
    '55555555-5555-5555-5555-555555555523',
    'Paid Tier Refund Review Event',
    'alpha-payments-refunds',
    'Paid-tier event used for organizer refund review coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    now() + interval '95 days',
    now() + interval '95 days 2 hours',
    false
);

-- Manual-tax fixture whose saved provider rate is no longer available.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, payment_currency_code, published, starts_at, ends_at,
    waitlist_enabled, tax_behavior, tax_calculation_mode, manual_tax_rate_ids
) values (
    '55555555-5555-5555-5555-555555555921',
    'Unavailable Manual Tax Rate Lab',
    'alpha-manual-tax-unavailable',
    'Manual-tax event used to verify unavailable saved provider rates.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    false,
    now() + interval '92 days',
    now() + interval '92 days 2 hours',
    false,
    'inclusive',
    'manual',
    array['txr_e2e_unavailable']::text[]
);

-- Registration window fixtures for Playwright coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, capacity,
    waitlist_enabled, attendee_approval_required, registration_starts_at,
    registration_ends_at, registration_questions
) values (
    '55555555-5555-5555-5555-555555555901',
    'Registration Window Paid Closed',
    'alpha-registration-window-paid-closed',
    'Paid event with a closed registration window.',
    'Paid event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '100 days',
    now() + interval '100 days 2 hours',
    null,
    false,
    false,
    now() - interval '10 days',
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555902',
    'Registration Window Paid Future',
    'alpha-registration-window-paid-future',
    'Paid event with registration opening later.',
    'Paid event with future registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '101 days',
    now() + interval '101 days 2 hours',
    null,
    false,
    false,
    now() + interval '1 day',
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555903',
    'Registration Window Paid Open',
    'alpha-registration-window-paid-open',
    'Paid event with registration currently open.',
    'Paid event with open registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '102 days',
    now() + interval '102 days 2 hours',
    null,
    false,
    false,
    now() - interval '1 day',
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555904',
    'Registration Window Free Closed',
    'alpha-registration-window-free-closed',
    'Free event with a closed registration window.',
    'Free event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '103 days',
    now() + interval '103 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555905',
    'Registration Window Approval Closed',
    'alpha-registration-window-approval-closed',
    'Approval-required event with a closed registration window.',
    'Approval-required event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '104 days',
    now() + interval '104 days 2 hours',
    null,
    false,
    true,
    null,
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555906',
    'Registration Window Waitlist Closed',
    'alpha-registration-window-waitlist-closed',
    'Full waitlist event with a closed registration window.',
    'Waitlist event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '105 days',
    now() + interval '105 days 2 hours',
    1,
    true,
    false,
    null,
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555907',
    'Registration Window Close Only Open',
    'alpha-registration-window-close-only-open',
    'Free event with only a future registration close date.',
    'Free event with close-only registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '106 days',
    now() + interval '106 days 2 hours',
    null,
    false,
    false,
    null,
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555908',
    'Registration Window Open Only Closed',
    'alpha-registration-window-open-only-closed',
    'Live event where open-only registration closed at event start.',
    'Free event with open-only registration closed at event start.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    false,
    false,
    now() - interval '10 days',
    null,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555909',
    'Registration Window Questions Closed',
    'alpha-registration-window-questions-closed',
    'Registration questions event with a closed registration window.',
    'Questions event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '107 days',
    now() + interval '107 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[{"id":"57555555-5555-5555-5555-555555555909","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555910',
    'Registration Window Manual Invite Closed',
    'alpha-registration-window-manual-invite-closed',
    'Registration questions event with a manual invite after closing.',
    'Manual invite event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '108 days',
    now() + interval '108 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[{"id":"57555555-5555-5555-5555-555555555910","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555911',
    'Registration Window Pending Payment Closed',
    'alpha-registration-window-pending-payment-closed',
    'Paid questions event with an active pending checkout after closing.',
    'Pending payment event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '109 days',
    now() + interval '109 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[{"id":"57555555-5555-5555-5555-555555555911","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555922',
    'Registration Window Approval Future',
    'alpha-registration-window-approval-future',
    'Approval-required event whose registration window has not opened.',
    'Approval event with future registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '120 days',
    now() + interval '120 days 2 hours',
    null,
    false,
    true,
    now() + interval '1 day',
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555923',
    'Registration Window Price Ended',
    'alpha-registration-window-price-ended',
    'Ticket offer event whose only price window has ended.',
    'Ticket event with ended pricing.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '121 days',
    now() + interval '121 days 2 hours',
    null,
    false,
    true,
    null,
    null,
    '[]'::jsonb
);

-- Ticketing workflow fixtures for payment returns, offers, and request coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, waitlist_enabled, attendee_approval_required,
    registration_questions
) values (
    '55555555-5555-5555-5555-555555555912',
    'Payment Return States Lab',
    'alpha-payment-return-states',
    'Paid event with confirmed and pending checkout return states.',
    'Payment return state coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '110 days',
    now() + interval '110 days 2 hours',
    false,
    false,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555913',
    'Ticket Request Lab',
    'alpha-ticket-request-lab',
    'Approval-required paid event with public and invitation-only tickets.',
    'Public ticket request coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '111 days',
    now() + interval '111 days 2 hours',
    false,
    true,
    '[{"id":"57555555-5555-5555-5555-555555555913","kind":"free-text","prompt":"Why would you like this ticket?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555914',
    'Invitation Request Lifecycle Lab',
    'alpha-invitation-request-lifecycle',
    'Approval-required event with assignable private ticket tiers.',
    'Invitation request lifecycle coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '112 days',
    now() + interval '112 days 2 hours',
    false,
    true,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555915',
    'No Assignable Invitation Tier Lab',
    'alpha-no-assignable-invitation-tier',
    'Approval-required event without an assignable private ticket tier.',
    'Unavailable private tier coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '113 days',
    now() + interval '113 days 2 hours',
    false,
    true,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555916',
    'Paid Event Offers Lab',
    'alpha-paid-event-offers',
    'Paid private-ticket event with pending and checkout-started offers.',
    'Paid dashboard offer coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '114 days',
    now() + interval '114 days 2 hours',
    false,
    false,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555917',
    'Paid Registration Questions Lab',
    'alpha-paid-registration-questions',
    'Paid ticket event that collects registration answers before checkout.',
    'Paid registration question coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '115 days',
    now() + interval '115 days 2 hours',
    false,
    false,
    '[{"id":"57555555-5555-5555-5555-555555555917","kind":"free-text","prompt":"What should the organizers prepare for you?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555918',
    'Sold Out Ticket States Lab',
    'alpha-sold-out-ticket-states',
    'Ticketed event with a sold-out public tier and waiting list.',
    'Sold-out ticket and waitlist coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '116 days',
    now() + interval '116 days 2 hours',
    true,
    false,
    '[{"id":"57555555-5555-5555-5555-555555555918","kind":"free-text","prompt":"What would you like to learn?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555919',
    'Migrated Unlimited Capacity Event',
    'alpha-migrated-unlimited-capacity',
    'Event shaped like an unlimited-capacity event after ticket migration.',
    'Migration-shaped ticket capacity coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '117 days',
    now() + interval '117 days 2 hours',
    false,
    false,
    '[]'::jsonb
);

insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, capacity, waitlist_enabled,
    attendee_approval_required, registration_questions
) values (
    '55555555-5555-5555-5555-555555555920',
    'Refunded Capacity Release Lab',
    'alpha-refunded-capacity-release',
    'One-seat paid event whose finalized refund released its capacity.',
    'Finalized refund capacity coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '118 days',
    now() + interval '118 days 2 hours',
    1,
    false,
    false,
    '[]'::jsonb
);

update event
set
    event_kind_id = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'in-person'
        else 'hybrid'
    end,
    location = ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    payment_currency_code = 'USD',
    venue_address = '123 Payment Way',
    venue_city = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'Chicago'
        else 'New York'
    end,
    venue_country_code = 'US',
    venue_country_name = 'United States',
    venue_name = 'E2E Admission Hall',
    venue_state_code = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'IL'
        else 'NY'
    end,
    venue_state_name = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'IL'
        else 'NY'
    end,
    venue_zip_code = case
        when event_id = '55555555-5555-5555-5555-555555555507' then '60601'
        else '10001'
    end
where event_id in (
    '55555555-5555-5555-5555-555555555506',
    '55555555-5555-5555-5555-555555555507',
    '55555555-5555-5555-5555-555555555522',
    '55555555-5555-5555-5555-555555555523',
    '55555555-5555-5555-5555-555555555901',
    '55555555-5555-5555-5555-555555555902',
    '55555555-5555-5555-5555-555555555903',
    '55555555-5555-5555-5555-555555555911',
    '55555555-5555-5555-5555-555555555912',
    '55555555-5555-5555-5555-555555555913',
    '55555555-5555-5555-5555-555555555914',
    '55555555-5555-5555-5555-555555555916',
    '55555555-5555-5555-5555-555555555917',
    '55555555-5555-5555-5555-555555555918',
    '55555555-5555-5555-5555-555555555920'
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
), (
    '77777777-7777-7777-7777-777777777713',
    'e2e-empty',
    'e2e-empty@example.com',
    true,
    'E2E Empty User',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'a8b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b3'
);

-- Member reserved for group members pagination coverage.
insert into "user" (
    user_id, username, email, email_verified, name, password, auth_hash
) values (
    '77777777-7777-7777-7777-777777777714',
    'e2e-member-3',
    'e2e-member-3@example.com',
    true,
    'E2E Member Three',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'b9c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1c4d5'
);

-- Check-in manager reserved for scanner and manual check-in coverage.
insert into "user" (
    user_id, username, email, email_verified, name, password, auth_hash
) values (
    '77777777-7777-7777-7777-777777777715',
    'e2e-check-in-manager-1',
    'e2e-check-in-manager-1@example.com',
    true,
    'E2E Check-In Manager One',
    '$argon2id$v=19$m=19456,t=2,p=1$gZiV/M1gPc22ElAH/Jh1Hw$CWOrkoo7oJBQ/iyh7uJ0LO2aLEfrHwTWllSAxT0zRno',
    'cad4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3e6'
);

update "user"
set
    bio = 'Member Two profile for dashboard modal coverage.',
    company = 'Platform Ops Lab',
    github_url = 'https://github.com/e2e-member-2',
    provider = '{"linuxfoundation": {"username": "e2e-member-2-lf", "issuer": "private-member-issuer", "subject": "private-member-subject"}}'::jsonb,
    title = 'Member Experience Engineer',
    website_url = 'https://example.com/e2e-member-2'
where user_id = '77777777-7777-7777-7777-777777777706';

update "user"
set
    bio = 'Pending One profile for invitation request modal coverage.',
    company = 'Approval Queue',
    github_url = 'https://github.com/e2e-pending-1',
    provider = '{"linuxfoundation": {"username": "e2e-pending-1-lf", "issuer": "private-pending-issuer", "subject": "private-pending-subject"}}'::jsonb,
    title = 'Community Applicant',
    website_url = 'https://example.com/e2e-pending-1'
where user_id = '77777777-7777-7777-7777-777777777707';

-- ============================================================================
-- BADGES
-- Reusable artwork and definitions for manual badge management testing
-- ============================================================================

-- Import the host badge image from the committed E2E assets
\lo_import 'ocg-server/static/images/e2e/badges/host.png'
\set hostBadgeImageOid :LASTOID

-- Host badge image stored by the database image provider
insert into images (
    file_name,
    content_type,
    created_by,
    data
) values (
    '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png',
    'image/png',
    '77777777-7777-7777-7777-777777777703',
    lo_get(:hostBadgeImageOid)
);

-- Use a stored image for public Open Graph page and serving coverage.
update community
set og_image_url = '/images/7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png'
where community_id = '11111111-1111-1111-1111-111111111111';

-- Remove the temporary host image large object
\lo_unlink :hostBadgeImageOid

-- Import the speaker badge image from the committed E2E assets
\lo_import 'ocg-server/static/images/e2e/badges/speaker.png'
\set speakerBadgeImageOid :LASTOID

-- Speaker badge image stored by the database image provider
insert into images (
    file_name,
    content_type,
    created_by,
    data
) values (
    'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png',
    'image/png',
    '77777777-7777-7777-7777-777777777703',
    lo_get(:speakerBadgeImageOid)
);

-- Remove the temporary speaker image large object
\lo_unlink :speakerBadgeImageOid

-- Disposable badge image copied from committed E2E artwork
insert into images (
    file_name,
    content_type,
    created_by,
    data
)
select
    'e2e-disposable-badge.png',
    content_type,
    created_by,
    data
from images
where file_name = '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png';

-- Removable gallery image copied from committed E2E artwork
insert into images (
    file_name,
    content_type,
    created_by,
    data
)
select
    'e2e-removable-badge.png',
    content_type,
    created_by,
    data
from images
where file_name = 'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png';

-- Host artwork available in the primary group gallery
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab01',
    '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Speaker artwork available in the primary group gallery
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab02',
    'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Disposable artwork used by isolated destructive badge scenarios
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab03',
    'e2e-disposable-badge.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Unreferenced artwork used by the removable gallery scenario
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab04',
    'e2e-removable-badge.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Host badge definition available to the primary group
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab001',
    'Serve as a host for a Platform Ops Meetup event.',
    'Recognizes contributors who host Platform Ops Meetup events.',
    '44444444-4444-4444-4444-444444444441',
    '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png',
    'Host'
);

-- Speaker badge definition available to the primary group
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab002',
    'Speak at a Platform Ops Meetup event.',
    'Recognizes contributors who speak at Platform Ops Meetup events.',
    '44444444-4444-4444-4444-444444444441',
    'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png',
    'Speaker'
);

-- Mentor badge reserved for manager revocation coverage
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab003',
    'Mentor another Platform Ops Meetup contributor.',
    'Recognizes contributors who mentor other group members.',
    '44444444-4444-4444-4444-444444444441',
    'e2e-disposable-badge.png',
    'Mentor'
);

-- Volunteer badge reserved for self-revocation coverage
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab004',
    'Volunteer for a Platform Ops Meetup activity.',
    'Recognizes contributors who volunteer for the group.',
    '44444444-4444-4444-4444-444444444441',
    'e2e-disposable-badge.png',
    'Volunteer'
);

-- Status list shared by the primary group's seeded badge awards
insert into badge_status_list (
    badge_status_list_id,
    allocation_offset,
    allocation_position,
    allocation_stride,
    group_id
) values (
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    8,
    1,
    '44444444-4444-4444-4444-444444444441'
);

-- Active Host badge awarded to the primary group's events manager
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '3 days',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Serve as a host for a Platform Ops Meetup event.",
        "description": "Recognizes contributors who host Platform Ops Meetup events.",
        "image_file_name": "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Host"
    }'::jsonb,
    0,
    'dadadada-dada-dada-dada-dadadadada01',

    'babababa-baba-baba-baba-babababab001',
    null,
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777711'
);

-- Active Speaker badge awarded to the primary group's events manager
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '2 days 12 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    1,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Speak at a Platform Ops Meetup event.",
        "description": "Recognizes contributors who speak at Platform Ops Meetup events.",
        "image_file_name": "eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Speaker"
    }'::jsonb,
    1,
    'dadadada-dada-dada-dada-dadadadada05',

    'babababa-baba-baba-baba-babababab002',
    null,
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777711'
);

-- Active Host badge awarded to the primary event's host
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '4 days',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Serve as a host for a Platform Ops Meetup event.",
        "description": "Recognizes contributors who host Platform Ops Meetup events.",
        "image_file_name": "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Host"
    }'::jsonb,
    2,
    'dadadada-dada-dada-dada-dadadadada02',

    'babababa-baba-baba-baba-babababab001',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777703'
);

-- Active Host badge awarded to the primary event's featured speaker
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '18 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    1,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Serve as a host for a Platform Ops Meetup event.",
        "description": "Recognizes contributors who host Platform Ops Meetup events.",
        "image_file_name": "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Host"
    }'::jsonb,
    3,
    'dadadada-dada-dada-dada-dadadadada06',

    'babababa-baba-baba-baba-babababab001',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777705'
);

-- Active Speaker badge awarded to the primary event's featured speaker
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '2 days',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Speak at a Platform Ops Meetup event.",
        "description": "Recognizes contributors who speak at Platform Ops Meetup events.",
        "image_file_name": "eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Speaker"
    }'::jsonb,
    4,
    'dadadada-dada-dada-dada-dadadadada03',

    'babababa-baba-baba-baba-babababab002',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777705'
);

-- Revoked Speaker badge retained for the primary event's second speaker
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '1 day',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    false,
    '{
        "criteria": "Speak at a Platform Ops Meetup event.",
        "description": "Recognizes contributors who speak at Platform Ops Meetup events.",
        "image_file_name": "eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Speaker"
    }'::jsonb,
    5,
    'dadadada-dada-dada-dada-dadadadada04',

    'babababa-baba-baba-baba-babababab002',
    '55555555-5555-5555-5555-555555555501',
    'Award issued in error',
    now() - interval '12 hours',
    '77777777-7777-7777-7777-777777777703',
    '77777777-7777-7777-7777-777777777706'
);

-- Active Mentor badge reserved for manager revocation coverage
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '6 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    1,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Mentor another Platform Ops Meetup contributor.",
        "description": "Recognizes contributors who mentor other group members.",
        "image_file_name": "e2e-disposable-badge.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Mentor"
    }'::jsonb,
    6,
    'dadadada-dada-dada-dada-dadadadada07',

    'babababa-baba-baba-baba-babababab003',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777706'
);

-- Active Volunteer badge reserved for self-revocation coverage
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '4 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    2,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Volunteer for a Platform Ops Meetup activity.",
        "description": "Recognizes contributors who volunteer for the group.",
        "image_file_name": "e2e-disposable-badge.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Volunteer"
    }'::jsonb,
    7,
    'dadadada-dada-dada-dada-dadadadada08',

    'babababa-baba-baba-baba-babababab004',
    null,
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777706'
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

-- Accepted admin for the dedicated empty-state community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111113',
    '77777777-7777-7777-7777-777777777701',
    true,
    'admin'
);

-- Primary admin can switch to the secondary community in read-only mode.
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111112',
    '77777777-7777-7777-7777-777777777701',
    true,
    'viewer'
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

-- Accepted organizer for the dedicated empty-state group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444447',
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

-- Primary organizer can switch to another group in read-only mode.
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444443',
    '77777777-7777-7777-7777-777777777703',
    true,
    'viewer'
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

-- Check-in manager for the primary group dashboard.
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777715',
    true,
    'check-in-manager'
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

-- Second primary group member so the members tab can paginate.
insert into group_member (group_id, user_id)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777714'
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

insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url, featured)
values
    (
        '66666666-6666-6666-6666-666666666601',
        '44444444-4444-4444-4444-444444444441',
        'Tech Corp',
        '/static/images/e2e/sponsor-logo.svg',
        'https://techcorp.example.com',
        true
    ),
    (
        '66666666-6666-6666-6666-666666666602',
        '44444444-4444-4444-4444-444444444441',
        'Hidden Sponsor',
        '/static/images/e2e/sponsor-logo.svg',
        'https://hidden-sponsor.example.com',
        false
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
-- EVENT ORGANIZERS
-- ============================================================================

insert into event_organizer (event_id, user_id, "order")
select e.event_id, gt.user_id, gt."order"
from event e
join group_team gt on gt.group_id = e.group_id
where e.legacy_id is null
and gt.accepted = true;

-- Specialized admission tiers must exist before enrollment fixtures
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
    20,
    'VIP pass',
    'Paid pass used for organizer refund review coverage.'
), (
    '56555555-5555-5555-5555-555555555525',
    true,
    '55555555-5555-5555-5555-555555555506',
    1,
    20,
    'Hybrid admission pass',
    'Physical admission with virtual access used for the homepage hybrid event price badge.'
), (
    '56555555-5555-5555-5555-555555555526',
    true,
    '55555555-5555-5555-5555-555555555507',
    1,
    30,
    'Observability summit pass',
    'Sellable tier used to show a price badge on the homepage in-person events list.'
), (
    '56555555-5555-5555-5555-555555555901',
    true,
    '55555555-5555-5555-5555-555555555901',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for closed registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555902',
    true,
    '55555555-5555-5555-5555-555555555902',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for future registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555903',
    true,
    '55555555-5555-5555-5555-555555555903',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for open registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555911',
    true,
    '55555555-5555-5555-5555-555555555911',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for pending payment dashboard coverage.'
), (
    '56555555-5555-5555-5555-555555555923',
    true,
    '55555555-5555-5555-5555-555555555923',
    1,
    20,
    'Ended sales pass',
    'Zero-price pass whose only sales window has ended.'
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    availability,
    event_id,
    "order",
    seats_total,
    title,
    description
)
values (
    '56555555-5555-5555-5555-555555555912',
    true,
    'public',
    '55555555-5555-5555-5555-555555555912',
    1,
    20,
    'Payment return pass',
    'Paid admission used for checkout return coverage.'
), (
    '56555555-5555-5555-5555-555555555913',
    true,
    'public',
    '55555555-5555-5555-5555-555555555913',
    1,
    20,
    'Requested conference pass',
    'Public tier attendees can request for organizer approval.'
), (
    '56555555-5555-5555-5555-655555555913',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555913',
    2,
    5,
    'Private supporter pass',
    'Private tier assigned only through organizer offers.'
), (
    '56555555-5555-5555-5555-555555555914',
    true,
    'public',
    '55555555-5555-5555-5555-555555555914',
    1,
    30,
    'General Admission',
    'Free public RSVP tier used to create unscoped requests.'
), (
    '56555555-5555-5555-5555-655555555914',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555914',
    2,
    4,
    'Sponsor allocation',
    'Private sponsor tier available for organizer assignment.'
), (
    '56555555-5555-5555-5555-755555555914',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555914',
    3,
    4,
    'VIP allocation',
    'Private VIP tier available for organizer assignment.'
), (
    '56555555-5555-5555-5555-555555555915',
    true,
    'public',
    '55555555-5555-5555-5555-555555555915',
    1,
    30,
    'General Admission',
    'Free public RSVP tier used to create unscoped requests.'
), (
    '56555555-5555-5555-5555-655555555915',
    false,
    'invitation_only',
    '55555555-5555-5555-5555-555555555915',
    2,
    4,
    'Inactive private allocation',
    'Inactive tier used to explain why no private ticket can be assigned.'
), (
    '56555555-5555-5555-5555-555555555916',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555916',
    1,
    10,
    'Private paid offer',
    'Paid private tier used by dashboard offer claims.'
), (
    '56555555-5555-5555-5555-555555555917',
    true,
    'public',
    '55555555-5555-5555-5555-555555555917',
    1,
    20,
    'Questions conference pass',
    'Paid tier combined with registration questions.'
), (
    '56555555-5555-5555-5555-555555555918',
    true,
    'public',
    '55555555-5555-5555-5555-555555555918',
    1,
    1,
    'Limited conference pass',
    'Sold-out paid tier used for ticket state and waiting-list coverage.'
), (
    '56555555-5555-5555-5555-555555555919',
    true,
    'public',
    '55555555-5555-5555-5555-555555555919',
    1,
    500,
    'General Admission',
    'Migration fallback tier for a formerly unlimited-capacity event.'
), (
    '56555555-5555-5555-5555-555555555920',
    true,
    'public',
    '55555555-5555-5555-5555-555555555920',
    1,
    1,
    'Refunded conference pass',
    'Paid tier whose prior purchase has been fully refunded.'
), (
    '56555555-5555-5555-5555-555555555921',
    true,
    'public',
    '55555555-5555-5555-5555-555555555921',
    1,
    20,
    'Manual tax pass',
    'Paid tier used for unavailable manual Tax Rate coverage.'
);

-- Every other event uses one free General Admission tier
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select
    e.event_id,
    md5(e.event_id::text || ':ticket-type')::uuid,
    1,
    greatest(coalesce(e.capacity, 100), 1),
    'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
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
    '55555555-5555-5555-5555-555555555526',
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
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777712'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555529',
    '77777777-7777-7777-7777-777777777708'
);

-- Keep the scanner fixture credential deterministic for browser injection.
update event_attendee
set check_in_code = '99999999-9999-9999-9999-999999999529'
where event_id = '55555555-5555-5555-5555-555555555529'
and user_id = '77777777-7777-7777-7777-777777777708';

insert into event_attendee (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555912',
    '77777777-7777-7777-7777-777777777711'
), (
    '55555555-5555-5555-5555-555555555918',
    '77777777-7777-7777-7777-777777777703'
);

-- Reviewed invitation requests used by public approval-state coverage.
insert into event_invitation_request (
    event_id,
    user_id,
    status,
    reviewed_at,
    reviewed_by
)
values (
    '55555555-5555-5555-5555-555555555530',
    '77777777-7777-7777-7777-777777777705',
    'accepted',
    now() - interval '1 day',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555530',
    '77777777-7777-7777-7777-777777777708',
    'rejected',
    now() - interval '1 day',
    '77777777-7777-7777-7777-777777777703'
);

-- Pending ticket request with registration answers for dashboard review coverage.
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    registration_answers,
    status,
    user_id
)
values (
    '55555555-5555-5555-5555-555555555913',
    '56555555-5555-5555-5555-555555555913',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555913",
                "value": "I want to learn how community programs can make technical events more welcoming."
            }
        ]
    }'::jsonb,
    'pending',
    '77777777-7777-7777-7777-777777777707'
);

-- Invitation requests used to verify organizer review outside public windows.
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id,
    reviewed_at,
    reviewed_by
)
values (
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    'pending',
    '77777777-7777-7777-7777-777777777707',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    'pending',
    '77777777-7777-7777-7777-777777777708',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    'accepted',
    '77777777-7777-7777-7777-777777777705',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555922',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555922' order by "order" limit 1),
    'pending',
    '77777777-7777-7777-7777-777777777705',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555923',
    '56555555-5555-5555-5555-555555555923',
    'accepted',
    '77777777-7777-7777-7777-777777777707',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777703'
);

-- Claimable approval offer pairing member1's accepted invitation request.
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    '62555555-5555-5555-5555-555555555530',
    '55555555-5555-5555-5555-555555555530',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555530' order by "order" limit 1),
    '2099-12-31 00:00:00+00',
    'approval',
    'pending',
    '77777777-7777-7777-7777-777777777705'
);

insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    '55555555-5555-5555-5555-555555555526',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555526' order by "order" limit 1),
    '77777777-7777-7777-7777-777777777706'
), (
    '55555555-5555-5555-5555-555555555526',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555526' order by "order" limit 1),
    '77777777-7777-7777-7777-777777777707'
);

insert into event_attendee (event_id, user_id, manually_invited, status)
values (
    '55555555-5555-5555-5555-555555555906',
    '77777777-7777-7777-7777-777777777703',
    false,
    'confirmed'
), (
    '55555555-5555-5555-5555-555555555911',
    '77777777-7777-7777-7777-777777777706',
    false,
    'registration-questions-pending'
);

-- Attendees used to verify event cancellation state transitions.
insert into event_attendee (
    event_id,
    user_id,
    checked_in,
    checked_in_at,
    manually_invited,
    status
)
values (
    '55555555-5555-5555-5555-555555555527',
    '77777777-7777-7777-7777-777777777701',
    true,
    now() - interval '1 hour',
    false,
    'confirmed'
);

insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id,
    reviewed_at,
    reviewed_by
)
values (
    '55555555-5555-5555-5555-555555555914',
    null,
    'pending',
    '77777777-7777-7777-7777-777777777707',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-555555555914',
    'pending',
    '77777777-7777-7777-7777-777777777708',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555914',
    null,
    'accepted',
    '77777777-7777-7777-7777-777777777702',
    now() - interval '4 days',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555914',
    null,
    'accepted',
    '77777777-7777-7777-7777-777777777704',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555915',
    null,
    'pending',
    '77777777-7777-7777-7777-777777777710',
    null,
    null
);

-- Claim offers replace the old pending-invitation and pending-question seats
insert into admission_offer (
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
)
values
    (
        '55555555-5555-5555-5555-555555555909',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555909' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'waitlist',
        'pending',
        '77777777-7777-7777-7777-777777777706'
    ),
    (
        '55555555-5555-5555-5555-555555555910',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555910' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'organizer_invitation',
        'pending',
        '77777777-7777-7777-7777-777777777706'
    ),
    (
        '55555555-5555-5555-5555-555555555527',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555527' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'organizer_invitation',
        'pending',
        '77777777-7777-7777-7777-777777777702'
    ),
    (
        '55555555-5555-5555-5555-555555555527',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555527' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'waitlist',
        'pending',
        '77777777-7777-7777-7777-777777777704'
    ),
    (
        '55555555-5555-5555-5555-555555555916',
        '56555555-5555-5555-5555-555555555916',
        current_timestamp + interval '7 days',
        'organizer_invitation',
        'pending',
        '77777777-7777-7777-7777-777777777707'
    ),
    (
        '55555555-5555-5555-5555-555555555916',
        '56555555-5555-5555-5555-555555555916',
        current_timestamp + interval '7 days',
        'waitlist',
        'pending',
        '77777777-7777-7777-7777-777777777705'
    );

-- Offers used by outside-window review and ended-price claim coverage.
insert into admission_offer (
    admission_offer_id,
    created_at,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
)
values (
    '59555555-5555-5555-5555-555555555905',
    current_timestamp - interval '2 days',
    null,
    null,
    null,
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    current_timestamp - interval '1 day',
    'approval',
    'expired',
    null,
    '77777777-7777-7777-7777-777777777705'
), (
    '59555555-5555-5555-5555-555555555923',
    current_timestamp,
    0,
    null,
    0,
    '55555555-5555-5555-5555-555555555923',
    '56555555-5555-5555-5555-555555555923',
    current_timestamp + interval '5 days',
    'approval',
    'pending',
    'Ended sales pass',
    '77777777-7777-7777-7777-777777777707'
), (
    '59555555-5555-5555-6555-555555555923',
    current_timestamp,
    0,
    null,
    0,
    '55555555-5555-5555-5555-555555555923',
    '56555555-5555-5555-5555-555555555923',
    current_timestamp + interval '5 days',
    'waitlist',
    'pending',
    'Ended sales pass',
    '77777777-7777-7777-7777-777777777708'
);

-- Terminal waitlist offers cover unavailable dashboard action reasons.
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
)
values (
    '59555555-5555-5555-5555-555555555520',
    current_timestamp - interval '7 days',
    '55555555-5555-5555-5555-555555555520',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555520'
        order by "order"
        limit 1
    ),
    current_timestamp - interval '6 days',
    'waitlist',
    'expired',
    '77777777-7777-7777-7777-777777777702'
), (
    '59555555-5555-5555-5555-555555555526',
    current_timestamp - interval '2 days',
    '55555555-5555-5555-5555-555555555526',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555526'
        order by "order"
        limit 1
    ),
    current_timestamp - interval '1 day',
    'waitlist',
    'expired',
    '77777777-7777-7777-7777-777777777701'
), (
    '59555555-5555-5555-5555-555555555528',
    current_timestamp - interval '2 days',
    '55555555-5555-5555-5555-555555555528',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555528'
        order by "order"
        limit 1
    ),
    current_timestamp + interval '1 day',
    'waitlist',
    'canceled',
    '77777777-7777-7777-7777-777777777705'
), (
    '59555555-5555-5555-5555-555555555914',
    current_timestamp - interval '3 days',
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-655555555914',
    current_timestamp - interval '2 days',
    'approval',
    'expired',
    '77777777-7777-7777-7777-777777777702'
);

insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
)
values (
    '59555555-5555-5555-5555-655555555914',
    4500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-755555555914',
    current_timestamp + interval '5 days',
    'approval',
    'checkout_pending',
    'VIP allocation',
    '77777777-7777-7777-7777-777777777704'
), (
    '59555555-5555-5555-5555-555555555916',
    4000,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555916',
    '56555555-5555-5555-5555-555555555916',
    current_timestamp + interval '5 days',
    'organizer_invitation',
    'checkout_pending',
    'Private paid offer',
    '77777777-7777-7777-7777-777777777708'
);

-- Canceled invitation retained for attendee history regression coverage.
insert into event_attendee (event_id, user_id, manually_invited, status)
values (
    '55555555-5555-5555-5555-555555555528',
    '77777777-7777-7777-7777-777777777702',
    true,
    'invitation-canceled'
);

-- Attendees used by the refund dashboard operational state matrix.
insert into event_attendee (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777701'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777704'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777709'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777710'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777711'
);

insert into event_attendee (event_id, user_id, registration_answers)
values (
    '55555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777705',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555501",
                "value": "I want practical patterns for incident readiness.\nI am also comparing governance models for our internal platform."
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555502",
                "value": "58555555-5555-5555-5555-555555555501"
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555503",
                "value": [
                    "58555555-5555-5555-5555-555555555504",
                    "58555555-5555-5555-5555-555555555505",
                    "58555555-5555-5555-5555-555555555507"
                ]
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555504",
                "value": "Vegetarian lunch if food is provided."
            }
        ]
    }'::jsonb
), (
    '55555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777706',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555501",
                "value": "I am looking for examples of measuring platform adoption without creating vanity metrics."
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555502",
                "value": "58555555-5555-5555-5555-555555555502"
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555503",
                "value": [
                    "58555555-5555-5555-5555-555555555505",
                    "58555555-5555-5555-5555-555555555506"
                ]
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555504",
                "value": "Please share slides after the event."
            }
        ]
    }'::jsonb
), (
    '55555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777707',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555501",
                "value": "I want to understand how other teams introduce reliability reviews."
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555502",
                "value": "58555555-5555-5555-5555-555555555503"
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555503",
                "value": [
                    "58555555-5555-5555-5555-555555555504",
                    "58555555-5555-5555-5555-555555555506",
                    "58555555-5555-5555-5555-555555555507"
                ]
            }
        ]
    }'::jsonb
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
), (
    '56555555-5555-5555-5555-555555555525',
    true,
    '55555555-5555-5555-5555-555555555506',
    1,
    20,
    'Hybrid admission pass',
    'Physical admission with virtual access used for the homepage hybrid event price badge.'
), (
    '56555555-5555-5555-5555-555555555526',
    true,
    '55555555-5555-5555-5555-555555555507',
    1,
    30,
    'Observability summit pass',
    'Sellable tier used to show a price badge on the homepage in-person events list.'
), (
    '56555555-5555-5555-5555-555555555901',
    true,
    '55555555-5555-5555-5555-555555555901',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for closed registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555902',
    true,
    '55555555-5555-5555-5555-555555555902',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for future registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555903',
    true,
    '55555555-5555-5555-5555-555555555903',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for open registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555911',
    true,
    '55555555-5555-5555-5555-555555555911',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for pending payment dashboard coverage.'
), (
    '56555555-5555-5555-5555-555555555923',
    true,
    '55555555-5555-5555-5555-555555555923',
    1,
    20,
    'Ended sales pass',
    'Zero-price pass whose only sales window has ended.'
)
on conflict (event_ticket_type_id) do nothing;

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
    now() + interval '45 days 1 minute',
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
), (
    '57555555-5555-5555-5555-555555555526',
    1500,
    '56555555-5555-5555-5555-555555555525',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555527',
    2000,
    '56555555-5555-5555-5555-555555555526',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555901',
    2500,
    '56555555-5555-5555-5555-555555555901',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555902',
    2500,
    '56555555-5555-5555-5555-555555555902',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555903',
    2500,
    '56555555-5555-5555-5555-555555555903',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555911',
    2500,
    '56555555-5555-5555-5555-555555555911',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555923',
    0,
    '56555555-5555-5555-5555-555555555923',
    now() - interval '2 days',
    now() - interval '1 day'
), (
    '57555555-5555-5555-5555-555555555912',
    2500,
    '56555555-5555-5555-5555-555555555912',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555913',
    3500,
    '56555555-5555-5555-5555-555555555913',
    null,
    null
), (
    '57555555-5555-5555-5555-655555555913',
    3000,
    '56555555-5555-5555-5555-655555555913',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555914',
    0,
    '56555555-5555-5555-5555-555555555914',
    null,
    null
), (
    '57555555-5555-5555-5555-655555555914',
    0,
    '56555555-5555-5555-5555-655555555914',
    null,
    null
), (
    '57555555-5555-5555-5555-755555555914',
    4500,
    '56555555-5555-5555-5555-755555555914',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555915',
    0,
    '56555555-5555-5555-5555-555555555915',
    null,
    null
), (
    '57555555-5555-5555-5555-655555555915',
    0,
    '56555555-5555-5555-5555-655555555915',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555916',
    4000,
    '56555555-5555-5555-5555-555555555916',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555917',
    3000,
    '56555555-5555-5555-5555-555555555917',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555918',
    3000,
    '56555555-5555-5555-5555-555555555918',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555919',
    0,
    '56555555-5555-5555-5555-555555555919',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555920',
    3000,
    '56555555-5555-5555-5555-555555555920',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555921',
    2500,
    '56555555-5555-5555-5555-555555555921',
    null,
    null
);

-- Default tiers receive one open-ended free price window
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select 0, md5(ett.event_ticket_type_id::text || ':price-window')::uuid, ett.event_ticket_type_id
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
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
    available,
    available_override_active
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
    null,
    false
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
    null,
    false
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
    null,
    false
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
    0,
    true
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
    0,
    true
), (
    '58555555-5555-5555-5555-555555555916',
    true,
    'OFFER25',
    '55555555-5555-5555-5555-555555555916',
    'percentage',
    'Offer claimant discount',
    null,
    25,
    null,
    null,
    null,
    null,
    false
), (
    '58555555-5555-5555-5555-555555555917',
    true,
    'FULLCOMP',
    '55555555-5555-5555-5555-555555555917',
    'percentage',
    'Complimentary registration',
    null,
    100,
    null,
    null,
    null,
    null,
    false
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
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
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
    '77777777-7777-7777-7777-777777777705',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_pending', 4000, 4000, 0
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
    '77777777-7777-7777-7777-777777777706',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_retry', 5000, 5000, 0
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
    '77777777-7777-7777-7777-777777777707',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_rejected', 5000, 5000, 0
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
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_available', 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555525',
    5000,
    now() - interval '5 days',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_approved',
    'https://checkout.stripe.test/cs_e2e_refund_approved',
    'pi_e2e_refund_approved',
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777712',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_approved', 5000, 5000, 0
);

-- Purchases used by the refund dashboard operational state matrix.
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    refunded_at,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_invoice_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555526',
    5000,
    now() - interval '6 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_processing',
    'https://checkout.stripe.test/cs_e2e_refund_processing',
    'pi_e2e_refund_processing',
    null,
    'refund-pending',
    'VIP pass',
    '77777777-7777-7777-7777-777777777704',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_processing', null, 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555527',
    5000,
    now() - interval '7 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_retryable',
    'https://checkout.stripe.test/cs_e2e_refund_retryable',
    'pi_e2e_refund_retryable',
    null,
    'refund-pending',
    'VIP pass',
    '77777777-7777-7777-7777-777777777711',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_retryable', null, 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555528',
    5000,
    now() - interval '8 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_finalized',
    'https://checkout.stripe.test/cs_e2e_refund_finalized',
    'pi_e2e_refund_finalized',
    now() - interval '1 day',
    'refunded',
    'VIP pass',
    '77777777-7777-7777-7777-777777777701',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_finalized', 'in_e2e_refund_finalized', 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555529',
    5000,
    now() - interval '9 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_rejection',
    'https://checkout.stripe.test/cs_e2e_refund_rejection',
    'pi_e2e_refund_rejection',
    null,
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777709',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_rejection', null, 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555530',
    5000,
    now() - interval '10 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_recovery_durable',
    'https://checkout.stripe.test/cs_e2e_refund_recovery_durable',
    'pi_e2e_refund_recovery_durable',
    null,
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777710',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_recovery_durable', null, 5000, 5000, 0
);

-- Durable document history includes past and canceled events independently of
-- the attendee's current event list.
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_invoice_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555541',
    2500,
    now() - interval '6 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555520',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555520'
        order by "order"
        limit 1
    ),
    'stripe',
    'cs_e2e_past_document',
    'https://checkout.stripe.test/cs_e2e_past_document',
    'pi_e2e_past_document',
    'completed',
    'General Admission',
    '77777777-7777-7777-7777-777777777701',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_past_document', 'in_e2e_past_document', 2500, 2500, 0
), (
    '59555555-5555-5555-5555-555555555542',
    3500,
    now() - interval '2 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555531',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555531'
        order by "order"
        limit 1
    ),
    'stripe',
    'cs_e2e_canceled_document',
    'https://checkout.stripe.test/cs_e2e_canceled_document',
    'pi_e2e_canceled_document',
    'refund-recovery-pending',
    'General Admission',
    '77777777-7777-7777-7777-777777777701',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_canceled_document', null, 3500, 3500, 0
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
values (
    '59555555-5555-5555-5555-555555555911',
    2500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555911',
    '56555555-5555-5555-5555-555555555911',
    now() + interval '2 days',
    'stripe',
    'cs_e2e_registration_window_pending',
    'https://example.test/checkout/registration-window-pending',
    'pending',
    'Registration window pass',
    '77777777-7777-7777-7777-777777777706',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
), (
    '59555555-5555-5555-5555-555555555912',
    2500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555522',
    '56555555-5555-5555-5555-555555555521',
    now() + interval '2 days',
    'stripe',
    'cs_e2e_draft_pending',
    'https://example.test/checkout/draft-pending',
    'pending',
    'General admission',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-755555555912',
    2500,
    now() - interval '1 day',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555912',
    '56555555-5555-5555-5555-555555555912',
    'stripe',
    'cs_e2e_payment_return_confirmed',
    'https://checkout.stripe.test/cs_e2e_payment_return_confirmed',
    'pi_e2e_payment_return_confirmed',
    'completed',
    'Payment return pass',
    '77777777-7777-7777-7777-777777777711',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_payment_return_confirmed', 2500, 2500, 0
);

insert into event_purchase (
    event_purchase_id,
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
values (
    '59555555-5555-5555-5555-655555555914',
    '59555555-5555-5555-5555-655555555914',
    4500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-755555555914',
    current_timestamp + interval '5 days',
    'stripe',
    'cs_e2e_invitation_request_checkout',
    'https://example.test/checkout/invitation-request',
    'pending',
    'VIP allocation',
    '77777777-7777-7777-7777-777777777704',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
), (
    '59555555-5555-5555-5555-555555555916',
    '59555555-5555-5555-5555-555555555916',
    4000,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555916',
    '56555555-5555-5555-5555-555555555916',
    current_timestamp + interval '5 days',
    'stripe',
    'cs_e2e_paid_offer_checkout',
    'https://example.test/checkout/paid-offer',
    'pending',
    'Private paid offer',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
values (
    '59555555-5555-5555-5555-655555555912',
    2500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555912',
    '56555555-5555-5555-5555-555555555912',
    current_timestamp + interval '5 days',
    'stripe',
    'cs_e2e_payment_return_pending',
    'https://example.test/checkout/payment-return',
    'pending',
    'Payment return pass',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    refunded_at,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555920',
    3000,
    current_timestamp - interval '5 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555920',
    '56555555-5555-5555-5555-555555555920',
    'stripe',
    'cs_e2e_refunded_capacity',
    'https://checkout.stripe.test/cs_e2e_refunded_capacity',
    'pi_e2e_refunded_capacity',
    current_timestamp - interval '1 day',
    'refunded',
    'Refunded conference pass',
    '77777777-7777-7777-7777-777777777702',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refunded_capacity', 3000, 3000, 0
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555531',
    5000,
    current_timestamp - interval '1 day',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_action_available',
    'https://checkout.stripe.test/cs_e2e_refund_action_available',
    'pi_e2e_refund_action_available',
    'completed',
    'VIP pass',
    '77777777-7777-7777-7777-777777777703',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_action_available', 5000, 5000, 0
);

-- Confirmed attendees own capacity through completed zero-value purchases
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
select
    0,
    null,
    0,
    ea.event_id,
    ett.event_ticket_type_id,
    'completed',
    ett.title,
    ea.user_id
from event_attendee ea
join lateral (
    select ett.event_ticket_type_id, ett.title
    from event_ticket_type ett
    where ett.event_id = ea.event_id
    order by ett."order", ett.event_ticket_type_id
    limit 1
) ett on true
where ea.status = 'confirmed'
and not exists (
    select 1
    from event_purchase ep
    where ep.event_id = ea.event_id
    and ep.user_id = ea.user_id
    and (
        ep.status in (
            'completed',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested'
        )
        or (
            ep.status = 'pending'
            and ep.hold_expires_at > current_timestamp
        )
    )
);

-- ============================================================================
-- EVENT REFUND REQUESTS
-- ============================================================================

-- Refund requests used by attendee and organizer review coverage.
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status,

    requested_reason,
    review_note,
    reviewed_at,
    reviewed_by_user_id
)
values (
    '60555555-5555-5555-5555-555555555521',
    '59555555-5555-5555-5555-555555555521',
    '77777777-7777-7777-7777-777777777705',
    'pending',

    'Need to cancel',
    null,
    null,
    null
), (
    '60555555-5555-5555-5555-555555555522',
    '59555555-5555-5555-5555-555555555522',
    '77777777-7777-7777-7777-777777777706',
    'approving',

    'Schedule conflict',
    'Approved by the organizer',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777701'
), (
    '60555555-5555-5555-5555-555555555523',
    '59555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777707',
    'rejected',

    'Need a different date',
    'The request falls outside the refund policy window.',
    now() - interval '3 days',
    '77777777-7777-7777-7777-777777777701'
), (
    '60555555-5555-5555-5555-555555555524',
    '59555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777712',
    'approved',

    'Refund completed',
    'Approved by the organizer',
    now() - interval '4 days',
    '77777777-7777-7777-7777-777777777701'
), (
    '60555555-5555-5555-5555-555555555529',
    '59555555-5555-5555-5555-555555555529',
    '77777777-7777-7777-7777-777777777709',
    'pending',

    'Duplicate registration',
    null,
    null,
    null
), (
    '60555555-5555-5555-5555-555555555530',
    '59555555-5555-5555-5555-555555555530',
    '77777777-7777-7777-7777-777777777710',
    'approving',

    'Provider completed the refund outside OCG',
    'Approved by the organizer',
    now() - interval '10 days',
    '77777777-7777-7777-7777-777777777701'
);

-- Durable refunds used by recovery and operational state coverage.
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    attempt_count,
    currency_code,
    event_purchase_id,
    event_refund_request_id,
    failure_message,
    finalized_at,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    provider_refund_id,
    status,
    terminal_failure
)
values (
    '61555555-5555-5555-5555-555555555522',
    5000,
    1,
    'USD',
    '59555555-5555-5555-5555-555555555522',
    '60555555-5555-5555-5555-555555555522',
    'Provider refund requires manual recovery',
    null,
    'event-purchase-refund-59555555-5555-5555-5555-555555555522',
    'refund-request-approval',
    now() + interval '100 years',
    'stripe',
    're_e2e_refund_recovery',
    'provider-failed',
    true
), (
    '61555555-5555-5555-5555-555555555526',
    5000,
    1,
    'USD',
    '59555555-5555-5555-5555-555555555526',
    null,
    null,
    null,
    'event-purchase-refund-59555555-5555-5555-5555-555555555526',
    'event-cancellation',
    now() + interval '100 years',
    'stripe',
    're_e2e_refund_processing',
    'provider-pending',
    false
), (
    '61555555-5555-5555-5555-555555555527',
    5000,
    10,
    'USD',
    '59555555-5555-5555-5555-555555555527',
    null,
    'Provider refund attempts exhausted',
    null,
    'event-purchase-refund-59555555-5555-5555-5555-555555555527',
    'event-cancellation',
    now() + interval '100 years',
    'stripe',
    null,
    'provider-failed',
    false
), (
    '61555555-5555-5555-5555-555555555528',
    5000,
    1,
    'USD',
    '59555555-5555-5555-5555-555555555528',
    null,
    null,
    now() - interval '1 day',
    'event-purchase-refund-59555555-5555-5555-5555-555555555528',
    'event-cancellation',
    now() + interval '100 years',
    'stripe',
    're_e2e_refund_finalized',
    'finalized',
    false
), (
    '61555555-5555-5555-5555-555555555530',
    5000,
    1,
    'USD',
    '59555555-5555-5555-5555-555555555530',
    '60555555-5555-5555-5555-555555555530',
    'Provider refund requires external recovery',
    null,
    'event-purchase-refund-59555555-5555-5555-5555-555555555530',
    'refund-request-approval',
    now() + interval '100 years',
    'stripe',
    're_e2e_refund_recovery_durable',
    'provider-failed',
    true
);

-- Exhausted application-fee adjustment shown in the financial recovery queue.
insert into event_purchase_application_fee_adjustment (
    event_purchase_application_fee_adjustment_id,
    amount_minor,
    attempt_count,
    event_purchase_id,
    idempotency_key,
    kind,
    next_attempt_at,
    status,
    updated_at,

    failure_message
)
values (
    '63555555-5555-5555-5555-555555555526',
    500,
    10,
    '59555555-5555-5555-5555-555555555526',
    'event-purchase-application-fee-adjustment-e2e-recovery',
    'purchase-refund',
    now() + interval '100 years',
    'failed',
    now() - interval '20 days',

    'Application fee refund attempts exhausted'
);

-- Credit note lifecycle states shown in the attendee purchase documents.
insert into event_purchase_credit_note (
    event_purchase_credit_note_id,
    amount_minor,
    attempt_count,
    currency_code,
    event_purchase_refund_id,
    idempotency_key,
    next_attempt_at,
    payment_provider_id,
    provider_object_account_id,
    status,
    tax_amount_minor,
    updated_at,

    completed_at,
    provider_credit_note_id,
    provider_hosted_url,
    provider_pdf_url
)
values (
    '62555555-5555-5555-5555-555555555526',
    5000,
    1,
    'USD',
    '61555555-5555-5555-5555-555555555526',
    'event-purchase-credit-note-e2e-processing',
    now() + interval '1 hour',
    'stripe',
    'acct_e2e_alpha',
    'pending',
    0,
    now() - interval '1 hour',

    null,
    null,
    null,
    null
), (
    '62555555-5555-5555-5555-555555555528',
    5000,
    1,
    'USD',
    '61555555-5555-5555-5555-555555555528',
    'event-purchase-credit-note-e2e-issued',
    now() + interval '100 years',
    'stripe',
    'acct_e2e_alpha',
    'issued',
    0,
    now() - interval '1 day',

    now() - interval '1 day',
    'cn_e2e_refund_finalized',
    'https://documents.stripe.test/cn_e2e_refund_finalized',
    'https://documents.stripe.test/cn_e2e_refund_finalized.pdf'
);

-- Exhausted credit note shown in the financial recovery queue.
insert into event_purchase_credit_note (
    event_purchase_credit_note_id,
    amount_minor,
    attempt_count,
    currency_code,
    event_purchase_refund_id,
    idempotency_key,
    next_attempt_at,
    payment_provider_id,
    provider_object_account_id,
    status,
    tax_amount_minor,
    updated_at,

    failure_message
)
values (
    '62555555-5555-5555-5555-555555555527',
    5000,
    10,
    'USD',
    '61555555-5555-5555-5555-555555555527',
    'event-purchase-credit-note-e2e-recovery',
    now() + interval '100 years',
    'stripe',
    'acct_e2e_alpha',
    'failed',
    0,
    now() - interval '21 days',

    'Credit note attempts exhausted'
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
), (
    '88888888-8888-8888-8888-888888888804',
    '55555555-5555-5555-5555-555555555535',
    'Summit Kickoff',
    'virtual',
    now() + interval '40 days',
    now() + interval '40 days 1 hour',
    'First day opening for the multi-day summit.',
    null
), (
    '88888888-8888-8888-8888-888888888805',
    '55555555-5555-5555-5555-555555555535',
    'Summit Wrap-Up',
    'virtual',
    now() + interval '41 days',
    now() + interval '41 days 1 hour',
    'Second day closing for the multi-day summit.',
    null
);

-- Live event session used to verify per-session join links for attendees.
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    description,
    meeting_join_url,
    cfs_submission_id
)
values (
    '88888888-8888-8888-8888-888888888806',
    '55555555-5555-5555-5555-555555555529',
    'Live Check-In Briefing',
    'virtual',
    now() + interval '1 hour',
    now() + interval '2 hours',
    'Session used to verify the attendee-only join link.',
    'https://meet.example.com/e2e-live-briefing',
    null
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
    '88888888-8888-8888-8888-888888888801',
    '77777777-7777-7777-7777-777777777706',
    false
), (
    '88888888-8888-8888-8888-888888888803',
    '77777777-7777-7777-7777-777777777705',
    true
);

commit;
