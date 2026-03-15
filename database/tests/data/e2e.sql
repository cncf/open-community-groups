begin;

-- ============================================================================
-- CLEANUP - Delete in correct order for FK constraints
-- ============================================================================

delete from cfs_submission_label where cfs_submission_id in (
    '99999999-9999-9999-9999-999999999911',
    '99999999-9999-9999-9999-999999999912',
    '99999999-9999-9999-9999-999999999913',
    '99999999-9999-9999-9999-999999999914',
    '99999999-9999-9999-9999-999999999915'
);

delete from cfs_submission_rating where cfs_submission_id in (
    '99999999-9999-9999-9999-999999999911',
    '99999999-9999-9999-9999-999999999912',
    '99999999-9999-9999-9999-999999999913',
    '99999999-9999-9999-9999-999999999914',
    '99999999-9999-9999-9999-999999999915'
);

delete from group_member where user_id in (
    '77777777-7777-7777-7777-777777777701',
    '77777777-7777-7777-7777-777777777702',
    '77777777-7777-7777-7777-777777777703',
    '77777777-7777-7777-7777-777777777704',
    '77777777-7777-7777-7777-777777777705',
    '77777777-7777-7777-7777-777777777706',
    '77777777-7777-7777-7777-777777777707',
    '77777777-7777-7777-7777-777777777708',
    '77777777-7777-7777-7777-777777777709',
    '77777777-7777-7777-7777-777777777710',
    '77777777-7777-7777-7777-777777777711',
    '77777777-7777-7777-7777-777777777712'
);

delete from group_team where user_id in (
    '77777777-7777-7777-7777-777777777701',
    '77777777-7777-7777-7777-777777777702',
    '77777777-7777-7777-7777-777777777703',
    '77777777-7777-7777-7777-777777777704',
    '77777777-7777-7777-7777-777777777705',
    '77777777-7777-7777-7777-777777777706',
    '77777777-7777-7777-7777-777777777707',
    '77777777-7777-7777-7777-777777777708',
    '77777777-7777-7777-7777-777777777709',
    '77777777-7777-7777-7777-777777777710',
    '77777777-7777-7777-7777-777777777711',
    '77777777-7777-7777-7777-777777777712'
);

delete from community_team where user_id in (
    '77777777-7777-7777-7777-777777777701',
    '77777777-7777-7777-7777-777777777702',
    '77777777-7777-7777-7777-777777777703',
    '77777777-7777-7777-7777-777777777704',
    '77777777-7777-7777-7777-777777777705',
    '77777777-7777-7777-7777-777777777706',
    '77777777-7777-7777-7777-777777777707',
    '77777777-7777-7777-7777-777777777708',
    '77777777-7777-7777-7777-777777777709',
    '77777777-7777-7777-7777-777777777710',
    '77777777-7777-7777-7777-777777777711',
    '77777777-7777-7777-7777-777777777712'
);

delete from session_speaker where session_id in (
    '88888888-8888-8888-8888-888888888801',
    '88888888-8888-8888-8888-888888888802',
    '88888888-8888-8888-8888-888888888803'
);

delete from session where session_id in (
    '88888888-8888-8888-8888-888888888801',
    '88888888-8888-8888-8888-888888888802',
    '88888888-8888-8888-8888-888888888803'
);

delete from cfs_submission where cfs_submission_id in (
    '99999999-9999-9999-9999-999999999911',
    '99999999-9999-9999-9999-999999999912',
    '99999999-9999-9999-9999-999999999913',
    '99999999-9999-9999-9999-999999999914',
    '99999999-9999-9999-9999-999999999915'
);

delete from session_proposal where session_proposal_id in (
    '99999999-9999-9999-9999-999999999801',
    '99999999-9999-9999-9999-999999999802',
    '99999999-9999-9999-9999-999999999803',
    '99999999-9999-9999-9999-999999999804',
    '99999999-9999-9999-9999-999999999805',
    '99999999-9999-9999-9999-999999999806',
    '99999999-9999-9999-9999-999999999807',
    '99999999-9999-9999-9999-999999999808'
);

delete from event_speaker where event_id in (
    '55555555-5555-5555-5555-555555555501'
);

delete from event_host where event_id in (
    '55555555-5555-5555-5555-555555555501'
);

delete from event_attendee where event_id in (
    '55555555-5555-5555-5555-555555555501',
    '55555555-5555-5555-5555-555555555504',
    '55555555-5555-5555-5555-555555555519',
    '55555555-5555-5555-5555-555555555520'
);

delete from event_sponsor where event_id in (
    '55555555-5555-5555-5555-555555555501'
);

delete from event_cfs_label where event_id in (
    '55555555-5555-5555-5555-555555555519'
);

delete from "user" where user_id in (
    '77777777-7777-7777-7777-777777777701',
    '77777777-7777-7777-7777-777777777702',
    '77777777-7777-7777-7777-777777777703',
    '77777777-7777-7777-7777-777777777704',
    '77777777-7777-7777-7777-777777777705',
    '77777777-7777-7777-7777-777777777706',
    '77777777-7777-7777-7777-777777777707',
    '77777777-7777-7777-7777-777777777708',
    '77777777-7777-7777-7777-777777777709',
    '77777777-7777-7777-7777-777777777710',
    '77777777-7777-7777-7777-777777777711',
    '77777777-7777-7777-7777-777777777712'
);

delete from group_sponsor where group_sponsor_id in (
    '66666666-6666-6666-6666-666666666601'
);

delete from event where event_id in (
    '55555555-5555-5555-5555-555555555501',
    '55555555-5555-5555-5555-555555555502',
    '55555555-5555-5555-5555-555555555503',
    '55555555-5555-5555-5555-555555555504',
    '55555555-5555-5555-5555-555555555505',
    '55555555-5555-5555-5555-555555555506',
    '55555555-5555-5555-5555-555555555507',
    '55555555-5555-5555-5555-555555555508',
    '55555555-5555-5555-5555-555555555509',
    '55555555-5555-5555-5555-555555555510',
    '55555555-5555-5555-5555-555555555511',
    '55555555-5555-5555-5555-555555555512',
    '55555555-5555-5555-5555-555555555513',
    '55555555-5555-5555-5555-555555555514',
    '55555555-5555-5555-5555-555555555515',
    '55555555-5555-5555-5555-555555555516',
    '55555555-5555-5555-5555-555555555517',
    '55555555-5555-5555-5555-555555555518',
    '55555555-5555-5555-5555-555555555519',
    '55555555-5555-5555-5555-555555555520'
);

delete from "group" where group_id in (
    '44444444-4444-4444-4444-444444444441',
    '44444444-4444-4444-4444-444444444442',
    '44444444-4444-4444-4444-444444444443',
    '44444444-4444-4444-4444-444444444444',
    '44444444-4444-4444-4444-444444444445',
    '44444444-4444-4444-4444-444444444446'
);

delete from event_category where event_category_id in (
    '33333333-3333-3333-3333-333333333331',
    '33333333-3333-3333-3333-333333333332',
    '33333333-3333-3333-3333-333333333333'
);

delete from group_category where group_category_id in (
    '22222222-2222-2222-2222-222222222221',
    '22222222-2222-2222-2222-222222222222',
    '22222222-2222-2222-2222-222222222223'
);

delete from region where region_id in (
    '22222222-2222-2222-2222-222222222301',
    '22222222-2222-2222-2222-222222222302'
);

delete from community where community_id in (
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111112'
);

delete from site where site_id = '00000000-0000-0000-0000-000000000000';

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
-- COMMUNITIES (2)
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
    'E2E Test Community',
    'E2E test community description',
    'https://example.com/banner.png',
    'https://example.com/banner-mobile.png',
    'https://example.com/logo.png'
), (
    '11111111-1111-1111-1111-111111111112',
    'e2e-second-community',
    'E2E Second Community',
    'E2E second community description',
    'https://example.com/banner2.png',
    'https://example.com/banner2-mobile.png',
    'https://example.com/logo2.png'
);

-- ============================================================================
-- GROUP CATEGORIES (2 - one per community)
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
-- EVENT CATEGORIES (2 - one per community)
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
-- REGIONS (2 for community 1)
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
-- GROUPS (6 total - 3 per community)
-- ============================================================================

-- Community 1 groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active
) values (
    '44444444-4444-4444-4444-444444444441',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'E2E Test Group Alpha',
    'test-group-alpha',
    true
), (
    '44444444-4444-4444-4444-444444444442',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'E2E Test Group Beta',
    'test-group-beta',
    true
), (
    '44444444-4444-4444-4444-444444444443',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'E2E Test Group Gamma',
    'test-group-gamma',
    true
);

-- Community 2 groups
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

update "group"
set region_id = '22222222-2222-2222-2222-222222222301'
where group_id in (
    '44444444-4444-4444-4444-444444444441',
    '44444444-4444-4444-4444-444444444442'
);

-- ============================================================================
-- EVENTS (18 total - 3 per group, mixed types)
-- ============================================================================

-- Alpha group events (community 1)
-- Event 1: future in-person event with full location data
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    venue_name, venue_address, venue_city, venue_state, venue_country_name,
    venue_country_code, venue_zip_code, banner_url, logo_url, capacity,
    registration_required, tags, meetup_url, meeting_join_url, photos_urls
) values (
    '55555555-5555-5555-5555-555555555501',
    'Alpha Event One',
    'alpha-event-1',
    'In-person event for Alpha group.',
    'Join us for the Alpha group meetup!',
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
    'https://example.com/event-banner.png',
    'https://example.com/event-logo.png',
    100,
    true,
    '{"meetup", "tech", "networking"}',
    'https://www.meetup.com/test-group/events/123456789/',
    'https://zoom.us/j/1234567890',
    '{"https://example.com/photo1.jpg", "https://example.com/photo2.jpg"}'
);

-- Event 2: future virtual event with recording
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city,
    meeting_recording_url
) values (
    '55555555-5555-5555-5555-555555555502',
    'Alpha Event Two',
    'alpha-event-2',
    'Virtual event for Alpha group.',
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

-- Event 3: future hybrid event
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555503',
    'Alpha Event Three',
    'alpha-event-3',
    'Hybrid event for Alpha group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '30 days',
    now() + interval '30 days 2 hours',
    null
);

-- Beta group events (community 1)
-- Event 1: future in-person event (canceled - must be unpublished)
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city, canceled
) values (
    '55555555-5555-5555-5555-555555555504',
    'Beta Event One',
    'beta-event-1',
    'In-person event for Beta group.',
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

-- Event 2 and 3: future virtual and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555505',
    'Beta Event Two',
    'beta-event-2',
    'Virtual event for Beta group.',
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
    'Beta Event Three',
    'beta-event-3',
    'Hybrid event for Beta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444442',
    true,
    now() + interval '31 days',
    now() + interval '31 days 2 hours',
    null
);

-- Gamma group events (community 1)
-- Event 1: future in-person event
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555507',
    'Gamma Event One',
    'gamma-event-1',
    'In-person event for Gamma group.',
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
    'Gamma Event Two',
    'gamma-event-2',
    'Virtual event for Gamma group.',
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
    'Gamma Event Three',
    'gamma-event-3',
    'Hybrid event for Gamma group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444443',
    true,
    now() + interval '32 days',
    now() + interval '32 days 2 hours',
    null
);

-- Delta group events (community 2)
-- Event 1: past in-person event
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

-- Epsilon group events (community 2)
-- Event 1: past in-person event
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

-- Zeta group events (community 2)
-- Event 1: past in-person event
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

-- Additional Alpha group events for dashboard and CFS coverage
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at
) values (
    '55555555-5555-5555-5555-555555555519',
    'Alpha CFS Summit',
    'alpha-cfs-summit',
    'Future event with an open call for speakers.',
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
    'Alpha Past Roundup',
    'alpha-past-roundup',
    'Past event used for dashboard filtering coverage.',
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

-- ============================================================================
-- USERS (8 total, all email_verified=true)
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
-- COMMUNITY TEAM (admins + pending invitations)
-- ============================================================================

-- Admin 1 is an accepted admin of community 1
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777701',
    true,
    'admin'
);

-- Admin 2 is an accepted admin of community 2
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111112',
    '77777777-7777-7777-7777-777777777702',
    true,
    'admin'
);

-- Groups manager can manage community 1 groups without being a community admin
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777709',
    true,
    'groups-manager'
);

-- Viewer has read-only access to the community dashboard
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777710',
    true,
    'viewer'
);

-- Pending 1 has a pending community 1 team invitation
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777707',
    false,
    'viewer'
);

-- ============================================================================
-- GROUP TEAM (organizers + pending invitations)
-- ============================================================================

-- Organizer 1 is an accepted organizer of Alpha group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777703',
    true,
    'admin'
);

-- Organizer 2 is an accepted organizer of Delta group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444444',
    '77777777-7777-7777-7777-777777777704',
    true,
    'admin'
);

-- Events manager can manage Alpha group events without full admin access
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777711',
    true,
    'events-manager'
);

-- Group viewer has read-only access to Alpha group dashboard pages
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777712',
    true,
    'viewer'
);

-- Pending 2 has a pending Beta group team invitation
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444442',
    '77777777-7777-7777-7777-777777777707',
    false,
    'events-manager'
);

-- Pending 3 has a pending Alpha group team invitation with viewer access
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777708',
    false,
    'viewer'
);

-- ============================================================================
-- GROUP MEMBERS
-- ============================================================================

-- Member 1 is a member of Alpha and Beta groups
insert into group_member (group_id, user_id)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777705'
), (
    '44444444-4444-4444-4444-444444444442',
    '77777777-7777-7777-7777-777777777705'
);

-- Member 2 is a member of Delta and Epsilon groups
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
    'https://example.com/sponsor-logo.png',
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
-- SESSIONS
-- ============================================================================

insert into session (session_id, event_id, name, session_kind_id, starts_at, ends_at, description)
values (
    '88888888-8888-8888-8888-888888888801',
    '55555555-5555-5555-5555-555555555501',
    'Opening Keynote',
    'in-person',
    now() + interval '10 days',
    now() + interval '10 days 1 hour',
    'Welcome and introduction to the event.'
), (
    '88888888-8888-8888-8888-888888888802',
    '55555555-5555-5555-5555-555555555501',
    'Technical Workshop',
    'in-person',
    now() + interval '10 days 1 hour',
    now() + interval '10 days 2 hours',
    'Hands-on technical session.'
), (
    '88888888-8888-8888-8888-888888888803',
    '55555555-5555-5555-5555-555555555519',
    'Scaling Community Workshops Session',
    'virtual',
    now() + interval '45 days 1 hour',
    now() + interval '45 days 1 hour 45 minutes',
    'Approved proposal linked into the CFS agenda.'
);

update session
set cfs_submission_id = '99999999-9999-9999-9999-999999999913'
where session_id = '88888888-8888-8888-8888-888888888803';

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
