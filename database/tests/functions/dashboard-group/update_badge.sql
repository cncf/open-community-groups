-- Tests updating group badge definitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1050000-0000-0000-0000-000000000001'
\set badgeID 'b1050000-0000-0000-0000-000000000002'
\set blankNameBadgeID 'b1050000-0000-0000-0000-000000000006'
\set communityID 'b1050000-0000-0000-0000-000000000003'
\set groupCategoryID 'b1050000-0000-0000-0000-000000000004'
\set groupID 'b1050000-0000-0000-0000-000000000005'
\set otherGroupBadgeID 'b1050000-0000-0000-0000-000000000007'
\set otherGroupID 'b1050000-0000-0000-0000-000000000008'
\set pathBadgeID 'b1050000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline actor, community, group that owns the badges and another group
select fx_user(:'actorID', jsonb_build_object('username', 'actor-update-badge'));
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Existing definition to update
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Old criteria', 'Old description', :'groupID', 'current.png', 'Old name');

-- Definition used by the blank name scenario
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'blankNameBadgeID', 'Blank criteria', 'Blank description', :'groupID', 'current.png', 'Blank name');

-- Definition owned by another group
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'otherGroupBadgeID', 'Other criteria', 'Other description', :'otherGroupID', 'other-only.png', 'Other name');

-- Definition used by the image path normalization scenario
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'pathBadgeID', 'Path criteria', 'Path description', :'groupID', 'current.png', 'Path name');

-- Current and replacement gallery artwork of the group
insert into badge_artwork (file_name, group_id)
values ('current.png', :'groupID'), ('replacement.png', :'groupID');

-- Gallery artwork that only exists in another group
insert into badge_artwork (file_name, group_id)
values ('other-only.png', :'otherGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an image path and store it as the gallery file name
select lives_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"Path criteria","description":"Path description","image_file_name":"/images/badges/replacement.png","name":"Path name"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'pathBadgeID'
    ),
    'Should accept an image path and store it as the gallery file name'
);
select results_eq(
    format(
        $$select image_file_name from badge where badge_id = %L::uuid$$,
        :'pathBadgeID'
    ),
    $$ values ('replacement.png'::text) $$,
    'Should store an image path as the gallery file name'
);

-- Should reject a badge owned by another group
select throws_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"C","description":"D","image_file_name":"replacement.png","name":"N"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'otherGroupBadgeID'
    ),
    'OCG01',
    'badge not found',
    'Should reject a badge owned by another group'
);

-- Should reject a blank name
select throws_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"C","description":"D","image_file_name":"replacement.png","name":"   "}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'blankNameBadgeID'
    ),
    'OCG01',
    'badge fields are invalid',
    'Should reject a blank name'
);

-- Should reject artwork owned by another group
select throws_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"C","description":"D","image_file_name":"other-only.png","name":"N"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID'
    ),
    'OCG01',
    'badge artwork not found',
    'Should reject artwork owned by another group'
);

-- Should reject unknown artwork
select throws_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"C","description":"D","image_file_name":"missing.png","name":"N"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID'
    ),
    'OCG01',
    'badge artwork not found',
    'Should reject unknown artwork'
);

-- Should update the current definition and record audit history
select lives_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"New criteria","description":"New description","image_file_name":"replacement.png","name":"New name"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID'
    ),
    'Should update the current definition and record audit history'
);

-- Should persist updated badge fields
select results_eq(
    format(
        $$
            select criteria, description, image_file_name, name
            from badge
            where badge_id = %L::uuid
        $$,
        :'badgeID'
    ),
    $$ values ('New criteria'::text, 'New description'::text, 'replacement.png'::text, 'New name'::text) $$,
    'Should persist updated badge fields'
);

-- Should create the expected audit row
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                actor_username,
                community_id,
                group_id,
                resource_type,
                resource_id,
                details
            from audit_log
            where resource_id = %L::uuid
        $$,
        :'badgeID'
    ),
    format(
        $$
        values (
            'badge_updated',
            %L::uuid,
            'actor-update-badge'::text,
            %L::uuid,
            %L::uuid,
            'badge',
            %L::uuid,
            '{"badge_name":"New name"}'::jsonb
        )
        $$,
        :'actorID', :'communityID', :'groupID', :'badgeID'
    ),
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
