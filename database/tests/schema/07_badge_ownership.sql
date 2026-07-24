-- Tests badge ownership constraints across issuing groups.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set badgeID 'ba070000-0000-0000-0000-000000000001'
\set communityID 'ba070000-0000-0000-0000-000000000002'
\set eventCategoryID 'ba070000-0000-0000-0000-000000000003'
\set eventID 'ba070000-0000-0000-0000-000000000004'
\set groupCategoryID 'ba070000-0000-0000-0000-000000000005'
\set groupID 'ba070000-0000-0000-0000-000000000006'
\set otherGroupID 'ba070000-0000-0000-0000-000000000007'
\set otherStatusListID 'ba070000-0000-0000-0000-000000000008'
\set statusListID 'ba070000-0000-0000-0000-000000000009'
\set userID 'ba070000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge recipient account
insert into "user" (auth_hash, email, email_verified, user_id, username)
values ('ownership-hash', 'ownership@example.test', true, :'userID', 'ownership-user');

-- Issuing community
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    '/mobile',
    '/banner',
    :'communityID',
    'Description',
    'Ownership Community',
    '/logo',
    'ownership-community'
);

-- Shared group category
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Shared event category
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Conferences');

-- Two independent issuing groups
insert into "group" (community_id, group_category_id, group_id, name, slug)
values
    (:'communityID', :'groupCategoryID', :'groupID', 'Ownership Group', 'ownership-group'),
    (:'communityID', :'groupCategoryID', :'otherGroupID', 'Other Group', 'other-group');

-- Badge definition owned by only the second group
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Attend', 'Other badge', :'otherGroupID', 'other.png', 'Other Badge');

-- Event owned by only the second group
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'Other event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'otherGroupID',
    'Other Event',
    'other-event',
    'UTC'
);

-- Status lists owned by their respective groups
insert into badge_status_list (badge_status_list_id, group_id)
values
    (:'statusListID', :'groupID'),
    (:'otherStatusListID', :'otherGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept badge text at every export-safe boundary
select lives_ok(
    format($$
        insert into badge (criteria, description, group_id, image_file_name, name)
        values (repeat('a ', 5000), repeat('a ', 5000), %L, 'boundary.png', repeat('a', 200))
    $$, :'groupID'),
    'Should accept badge text at every boundary'
);

-- Should reject criteria beyond the export-safe boundary
select throws_ok(
    format($$
        insert into badge (criteria, description, group_id, image_file_name, name)
        values (repeat('a ', 5001), 'Description', %L, 'criteria.png', 'Badge')
    $$, :'groupID'),
    '23514',
    'new row for relation "badge" violates check constraint "badge_criteria_chk"',
    'Should reject oversized badge criteria'
);

-- Should reject descriptions beyond the export-safe boundary
select throws_ok(
    format($$
        insert into badge (criteria, description, group_id, image_file_name, name)
        values ('Criteria', repeat('a ', 5001), %L, 'description.png', 'Badge')
    $$, :'groupID'),
    '23514',
    'new row for relation "badge" violates check constraint "badge_description_chk"',
    'Should reject oversized badge descriptions'
);

-- Should reject names beyond the export-safe boundary
select throws_ok(
    format($$
        insert into badge (criteria, description, group_id, image_file_name, name)
        values ('Criteria', 'Description', %L, 'name.png', repeat('a', 201))
    $$, :'groupID'),
    '23514',
    'new row for relation "badge" violates check constraint "badge_name_chk"',
    'Should reject oversized badge names'
);

-- Should reject an award that combines another group's badge definition
select throws_ok(
    format($$
        insert into user_badge (
            badge_id,
            badge_status_list_id,
            display_order,
            group_id,
            snapshot,
            status_list_index,
            user_id
        ) values (
            %L,
            %L,
            0,
            %L,
            '{"name":"Ownership Badge"}',
            0,
            %L
        )
    $$, :'badgeID', :'statusListID', :'groupID', :'userID'),
    '23503',
    'insert or update on table "user_badge" violates foreign key constraint "user_badge_badge_id_group_id_fkey"',
    'Should reject a badge definition owned by another group'
);

-- Should reject an award that combines another group's event
select throws_ok(
    format($$
        insert into user_badge (
            badge_status_list_id,
            display_order,
            event_id,
            group_id,
            snapshot,
            status_list_index,
            user_id
        ) values (
            %L,
            0,
            %L,
            %L,
            '{"name":"Ownership Badge"}',
            0,
            %L
        )
    $$, :'statusListID', :'eventID', :'groupID', :'userID'),
    '23503',
    'insert or update on table "user_badge" violates foreign key constraint "user_badge_event_id_group_id_fkey"',
    'Should reject an event owned by another group'
);

-- Should reject an award that combines another group's status list
select throws_ok(
    format($$
        insert into user_badge (
            badge_status_list_id,
            display_order,
            group_id,
            snapshot,
            status_list_index,
            user_id
        ) values (
            %L,
            0,
            %L,
            '{"name":"Ownership Badge"}',
            0,
            %L
        )
    $$, :'otherStatusListID', :'groupID', :'userID'),
    '23503',
    'insert or update on table "user_badge" violates foreign key constraint "user_badge_badge_status_list_id_group_id_fkey"',
    'Should reject a status list owned by another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
