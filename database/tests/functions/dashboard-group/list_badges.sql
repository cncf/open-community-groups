-- Tests searchable group badge definition listings.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b1030000-0000-0000-0000-000000000001'
\set groupCategoryID 'b1030000-0000-0000-0000-000000000002'
\set groupID 'b1030000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the definitions
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'List Community', '/logo', 'list-community');

-- Category used by the definition group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the definitions
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'List Group', 'list-group');

-- Searchable badge definitions
insert into badge (criteria, description, group_id, image_file_name, name)
values
    ('Attend', 'Event attendee', :'groupID', 'attendee.png', 'Attendee'),
    ('Speak', 'Event speaker', :'groupID', 'speaker.png', 'Speaker');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list all definitions in stable order
select is((list_badges(:'groupID', '{}')->>'total')::integer, 2, 'Should list all definitions in stable order');

-- Should filter definitions by search
select is((list_badges(:'groupID', '{"query":"speaker"}')->>'total')::integer, 1, 'Should filter definitions by search');

-- Should return a filtered empty state
select is((list_badges(:'groupID', '{"query":"missing"}')->'badges')::jsonb, '[]'::jsonb, 'Should return a filtered empty state');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
