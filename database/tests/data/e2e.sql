begin;

delete from event
where event_id in (
    '55555555-5555-5555-5555-555555555555',
    '66666666-6666-6666-6666-666666666666'
);
delete from "group" where group_id = '44444444-4444-4444-4444-444444444444';
delete from event_category where event_category_id = '33333333-3333-3333-3333-333333333333';
delete from group_category where group_category_id = '22222222-2222-2222-2222-222222222222';
delete from community where community_id = '11111111-1111-1111-1111-111111111111';
delete from site where site_id = '00000000-0000-0000-0000-000000000000';

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
);

insert into group_category (group_category_id, name, community_id)
values (
    '22222222-2222-2222-2222-222222222222',
    'E2E Category',
    '11111111-1111-1111-1111-111111111111'
);

insert into event_category (event_category_id, name, slug, community_id)
values (
    '33333333-3333-3333-3333-333333333333',
    'General',
    'general',
    '11111111-1111-1111-1111-111111111111'
);

insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active
) values (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    'E2E Test Group',
    'test-group',
    true
);

insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at
) values (
    '55555555-5555-5555-5555-555555555555',
    'E2E Test Event',
    'test-event',
    'Primary event for Playwright E2E tests.',
    'UTC',
    '33333333-3333-3333-3333-333333333333',
    'in-person',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() + interval '10 days',
    now() + interval '10 days 2 hours'
);

insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at
) values (
    '66666666-6666-6666-6666-666666666666',
    'E2E Search Event',
    'search-event',
    'Secondary event for search coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333333',
    'virtual',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() + interval '20 days',
    now() + interval '20 days 2 hours'
);

commit;
