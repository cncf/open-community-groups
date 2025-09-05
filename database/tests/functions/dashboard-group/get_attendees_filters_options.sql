-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set emptyGroupID '00000000-0000-0000-0000-000000000022'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, host, title, description, header_logo_url, theme)
values (:'communityID', 'c', 'C', 'c.example.org', 't', 'd', 'https://e/logo.png', '{}'::jsonb);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'categoryID', 'G', 'g', true, false),
    (:'emptyGroupID', :'communityID', :'categoryID', 'GE', 'ge', true, false);

-- Events (no starts_at so ordering falls back to name asc: E1 before E2)
insert into event (event_id, name, slug, description, timezone, event_category_id, event_kind_id, group_id, published, canceled, deleted)
values
    (:'event1ID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false),
    (:'event2ID', 'E2', 'e2', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: filters options should include all events for group
select is(
    jsonb_array_length(get_attendees_filters_options(:'groupID'::uuid)::jsonb -> 'events'),
    2,
    'Should return two events in filters options'
);

-- Test: empty group returns empty events array
select is(
    jsonb_array_length(get_attendees_filters_options(:'emptyGroupID'::uuid)::jsonb -> 'events'),
    0,
    'Should return empty events list for empty group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
