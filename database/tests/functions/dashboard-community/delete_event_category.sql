-- Tests deleting dashboard community event categories.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c090000-0000-0000-0000-000000000009'
\set communityID '2c090000-0000-0000-0000-000000000001'
\set deletedEventID '2c090000-0000-0000-0000-00000000000b'
\set deletedReferenceEventCategoryID '2c090000-0000-0000-0000-00000000000a'
\set eventID '2c090000-0000-0000-0000-000000000002'
\set foreignEventCategoryID '2c090000-0000-0000-0000-000000000006'
\set groupCategoryID '2c090000-0000-0000-0000-000000000003'
\set groupID '2c090000-0000-0000-0000-000000000004'
\set inUseEventCategoryID '2c090000-0000-0000-0000-000000000005'
\set otherCommunityID '2c090000-0000-0000-0000-000000000008'
\set unusedEventCategoryID '2c090000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the taxonomy under test
select fx_community(:'communityID');

-- Other community owning the foreign event category
select fx_community(:'otherCommunityID');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'delete-event-category-audit-actor'));

-- Event category referenced only by a deleted event
select fx_event_category(:'deletedReferenceEventCategoryID', :'communityID');

-- Event category owned by the other community
select fx_event_category(:'foreignEventCategoryID', :'otherCommunityID');

-- Event category referenced by a live event
select fx_event_category(:'inUseEventCategoryID', :'communityID');

-- Unused event category deleted by the success scenario
select fx_event_category(:'unusedEventCategoryID', :'communityID', jsonb_build_object('name', 'Webinar'));

-- Group category required by the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the referencing events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Deleted event that still references its category
select fx_event(
    :'deletedEventID',
    :'groupID',
    :'deletedReferenceEventCategoryID',
    jsonb_build_object('deleted', true, 'published', false)
);

-- Live event referencing the in-use category
select fx_event(:'eventID', :'groupID', :'inUseEventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting event category referenced by events
select throws_ok(
    format(
        $$ select delete_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'inUseEventCategoryID'
    ),
    'OCG01',
    'cannot delete event category in use by events',
    'Should block deleting event category referenced by events'
);

-- Should block deleting event category referenced only by deleted events
select throws_ok(
    format(
        $$ select delete_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'deletedReferenceEventCategoryID'
    ),
    'OCG01',
    'cannot delete event category in use by events',
    'Should block deleting event category referenced only by deleted events'
);

-- Should delete an unused event category
select lives_ok(
    format(
        $$ select delete_event_category(
        %L::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'actorUserID',
        :'communityID',
        :'unusedEventCategoryID'
    ),
    'Should delete an unused event category'
);
select results_eq(
    format(
        $$
    select count(*)::bigint
    from event_category ec
    where ec.event_category_id = %L::uuid
        $$,
        :'unusedEventCategoryID'
    ),
    $$ values (0::bigint) $$,
    'Unused event category should be deleted'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            details,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'event_category_deleted',
            %L::uuid,
            'delete-event-category-audit-actor',
            %L::uuid,
            '{"name": "Webinar"}'::jsonb,
            'event_category',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'communityID',
        :'unusedEventCategoryID'
    ),
    'Should create the expected audit row'
);

-- Should fail when deleting an event category from another community
select throws_ok(
    format(
        $$ select delete_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'foreignEventCategoryID'
    ),
    'OCG01',
    'event category not found',
    'Should fail when deleting an event category from another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
