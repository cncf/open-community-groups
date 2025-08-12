-- Start transaction and plan tests
begin;
select plan(4);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set event1ID '00000000-0000-0000-0000-000000000003'
\set category1ID '00000000-0000-0000-0000-000000000011'

-- Seed community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community for testing purposes',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'category1ID', 'Conference', 'conference', :'community1ID');

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values ('00000000-0000-0000-0000-000000000010', 'Technology', :'community1ID');

-- Seed group
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
    'test-group',
    'A test group',
    '00000000-0000-0000-0000-000000000010'
);

-- Seed event (with published=true to test it gets set to false)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published
) values (
    :'event1ID',
    :'group1ID',
    'Event to Delete',
    'event-to-delete',
    'This event will be deleted',
    'America/New_York',
    :'category1ID',
    'in-person',
    true
);

-- Test delete_event function sets deleted=true
select delete_event('00000000-0000-0000-0000-000000000003'::uuid);

select is(
    (select deleted from event where event_id = :'event1ID'),
    true,
    'delete_event should set deleted=true'
);

-- Test delete_event function sets deleted_at timestamp
select isnt(
    (select deleted_at from event where event_id = :'event1ID'),
    null,
    'delete_event should set deleted_at timestamp'
);

-- Test delete_event function sets published=false
select is(
    (select published from event where event_id = :'event1ID'),
    false,
    'delete_event should set published=false'
);

-- Test event still exists in database (soft delete)
select is(
    (select count(*)::int from event where event_id = :'event1ID'),
    1,
    'delete_event should keep event in database (soft delete)'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;