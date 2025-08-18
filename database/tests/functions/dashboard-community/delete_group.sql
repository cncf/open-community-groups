-- Start transaction and plan tests
begin;
select plan(5);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set groupAlreadyDeletedID '00000000-0000-0000-0000-000000000022'

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

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed active group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    created_at
) values (
    :'group1ID',
    'Test Group',
    'test-group',
    :'community1ID',
    :'category1ID',
    'Test description',
    '2024-01-15 10:00:00+00'
);

-- Seed already deleted group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    active,
    deleted,
    deleted_at,
    created_at
) values (
    :'groupAlreadyDeletedID',
    'Already Deleted Group',
    'already-deleted-group',
    :'community1ID',
    :'category1ID',
    'Already deleted group description',
    false,
    true,
    '2024-02-15 10:00:00+00',
    '2024-01-15 10:00:00+00'
);

-- Test: delete_group function performs soft delete
select delete_group('00000000-0000-0000-0000-000000000021'::uuid);

select is(
    (select deleted from "group" where group_id = '00000000-0000-0000-0000-000000000021'::uuid),
    true,
    'delete_group should set deleted to true'
);

select ok(
    (select deleted_at from "group" where group_id = '00000000-0000-0000-0000-000000000021'::uuid) is not null,
    'delete_group should set deleted_at timestamp'
);

-- Verify the group still exists in database
select ok(
    exists(select 1 from "group" where group_id = '00000000-0000-0000-0000-000000000021'::uuid),
    'delete_group should perform soft delete (record still exists)'
);

-- Verify active field is set to false when deleting
select is(
    (select active from "group" where group_id = '00000000-0000-0000-0000-000000000021'::uuid),
    false,
    'delete_group should set active to false when deleting'
);

-- Test: delete_group throws error for already deleted group
select throws_ok(
    $$select delete_group('00000000-0000-0000-0000-000000000022'::uuid)$$,
    'P0001',
    'group not found',
    'delete_group should throw error when trying to delete already deleted group'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;