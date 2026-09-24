-- Tests inserting event co-host audit rows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5030000-0000-0000-0000-000000000001'
\set communityID 'e5030000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5030000-0000-0000-0000-000000000003'
\set eventID 'e5030000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5030000-0000-0000-0000-000000000005'
\set groupID 'e5030000-0000-0000-0000-000000000006'
\set invitationID 'e5030000-0000-0000-0000-000000000007'
\set userID 'e5030000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_user(:'userID', jsonb_build_object('username', 'cohost-auditor'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert owner and co-host scoped audit rows
select lives_ok(
    format($$select insert_event_cohost_audit(
        'event_cohost_invited',
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        'pending'
    )$$, :'userID', :'eventID', :'groupID', :'cohostGroupID', :'invitationID'),
    'Should insert owner and co-host scoped audit rows'
);

select results_eq(
    $$
        select action, actor_username, group_id, resource_type, resource_id, details
        from audit_log
        order by group_id
    $$,
    format(
        $$
        values
            (
                'event_cohost_invited',
                'cohost-auditor',
                %L::uuid,
                'event',
                %L::uuid,
                '{"cohost_group_id":"%s","from_status":null,"invitation_id":"%s","owner_group_id":"%s","to_status":"pending"}'::jsonb
            ),
            (
                'event_cohost_invited',
                'cohost-auditor',
                %L::uuid,
                'event',
                %L::uuid,
                '{"cohost_group_id":"%s","from_status":null,"invitation_id":"%s","owner_group_id":"%s","to_status":"pending"}'::jsonb
            )
        $$,
        :'cohostGroupID',
        :'eventID',
        :'cohostGroupID',
        :'invitationID',
        :'groupID',
        :'groupID',
        :'eventID',
        :'cohostGroupID',
        :'invitationID',
        :'groupID'
    ),
    'Should insert owner and co-host scoped audit rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
