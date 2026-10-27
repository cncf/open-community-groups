-- Tests searching one scope of the audit log with filters, sorting and pagination.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set aliceID 'ad170000-0000-0000-0000-000000000001'
\set bobID 'ad170000-0000-0000-0000-000000000002'
\set communityAuditID 'ad170000-0000-0000-0000-000000000003'
\set communityID 'ad170000-0000-0000-0000-000000000004'
\set groupAuditID 'ad170000-0000-0000-0000-000000000005'
\set groupCategoryID 'ad170000-0000-0000-0000-000000000006'
\set groupID 'ad170000-0000-0000-0000-000000000007'
\set otherCommunityAuditID 'ad170000-0000-0000-0000-000000000008'
\set otherCommunityID 'ad170000-0000-0000-0000-000000000009'
\set otherGroupAuditID 'ad170000-0000-0000-0000-000000000010'
\set otherGroupCategoryID 'ad170000-0000-0000-0000-000000000011'
\set otherGroupID 'ad170000-0000-0000-0000-000000000012'
\set sponsorAuditID 'ad170000-0000-0000-0000-000000000013'
\set sponsorID 'ad170000-0000-0000-0000-000000000014'
\set wildcardActorID 'ad170000-0000-0000-0000-000000000015'
\set wildcardAuditID 'ad170000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose audit rows are searched
select fx_community(:'communityID');

-- Other community whose audit rows stay out of the community scope
select fx_community(:'otherCommunityID');

-- Actor whose username contains the searched substring
select fx_user(:'aliceID', jsonb_build_object('username', 'alice-search-audit-logs'));

-- Actor matched by the case-insensitive actor filter
select fx_user(:'bobID', jsonb_build_object('username', 'bob-search-audit-logs'));

-- Actor whose username would match an unescaped underscore wildcard
select fx_user(:'wildcardActorID', jsonb_build_object('username', 'userx1-search-audit-logs'));

-- Group category of the searched group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the other group
select fx_group_category(:'otherGroupCategoryID', :'otherCommunityID');

-- Group whose audit rows are searched and whose name is resolved live
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Search Audit Group'));

-- Other group whose audit rows stay out of the group scope
select fx_group(:'otherGroupID', :'otherCommunityID', :'otherGroupCategoryID');

-- Audit rows spread over scopes, actors, actions and day boundaries
insert into audit_log (
    audit_log_id,
    action,
    created_at,
    resource_id,
    resource_type,

    actor_user_id,
    actor_username,
    community_id,
    details,
    group_id
) values
    (
        :'communityAuditID',
        'community_updated',
        '2024-05-01 23:59:59+00',
        :'communityID',
        'community',

        :'aliceID',
        'alice-search-audit-logs',
        :'communityID',
        '{}'::jsonb,
        null
    ),
    (
        :'groupAuditID',
        'group_updated',
        '2024-05-02 00:00:00+00',
        :'groupID',
        'group',

        :'bobID',
        'bob-search-audit-logs',
        :'communityID',
        '{}'::jsonb,
        :'groupID'
    ),
    (
        :'wildcardAuditID',
        'group_updated',
        '2024-05-03 23:59:59+00',
        :'groupID',
        'group',

        :'wildcardActorID',
        'userx1-search-audit-logs',
        :'communityID',
        '{"subject": "Renamed"}'::jsonb,
        :'groupID'
    ),
    (
        :'sponsorAuditID',
        'group_sponsor_deleted',
        '2024-05-04 00:00:00+00',
        :'sponsorID',
        'group_sponsor',

        :'aliceID',
        'alice-search-audit-logs',
        :'communityID',
        '{"name": "Deleted Sponsor"}'::jsonb,
        :'groupID'
    ),
    (
        :'otherCommunityAuditID',
        'community_updated',
        '2024-05-05 10:00:00+00',
        :'otherCommunityID',
        'community',

        :'aliceID',
        'alice-search-audit-logs',
        :'otherCommunityID',
        '{}'::jsonb,
        null
    ),
    (
        :'otherGroupAuditID',
        'group_updated',
        '2024-05-06 10:00:00+00',
        :'otherGroupID',
        'group',

        :'bobID',
        'bob-search-audit-logs',
        :'otherCommunityID',
        '{}'::jsonb,
        :'otherGroupID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should default unsupported sort values to created descending
select is(
    jsonb_path_query_array(
        search_audit_logs(
            :'communityID'::uuid,
            null,
            null,
            array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
            '{"limit": 1, "sort": "resource-asc"}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'sponsorAuditID'),
    'Should default unsupported sort values to created descending'
);

-- Should exclude actions missing from the allowed actions
select is(
    jsonb_path_query_array(
        search_audit_logs(
            :'communityID'::uuid,
            null,
            null,
            array['community_updated', 'group_updated']::text[],
            '{}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'wildcardAuditID', :'groupAuditID', :'communityAuditID'),
    'Should exclude actions missing from the allowed actions'
);

-- Should filter rows by a case-insensitive actor substring
select is(
    jsonb_path_query_array(
        search_audit_logs(
            :'communityID'::uuid,
            null,
            null,
            array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
            '{"actor": "BOB"}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'groupAuditID'),
    'Should filter rows by a case-insensitive actor substring'
);

-- Should filter rows by action
select is(
    jsonb_path_query_array(
        search_audit_logs(
            :'communityID'::uuid,
            null,
            null,
            array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
            '{"action": "group_updated"}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'wildcardAuditID', :'groupAuditID'),
    'Should filter rows by action'
);

-- Should keep only rows created within the UTC date range
select is(
    jsonb_path_query_array(
        search_audit_logs(
            :'communityID'::uuid,
            null,
            null,
            array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
            '{"date_from": "2024-05-02", "date_to": "2024-05-03"}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'wildcardAuditID', :'groupAuditID'),
    'Should keep only rows created within the UTC date range'
);

-- Should reject a search with two scopes
select throws_ok(
    format(
        $$select search_audit_logs(%L::uuid, %L::uuid, null, array['group_updated']::text[], '{}'::jsonb)$$,
        :'communityID',
        :'groupID'
    ),
    'P0001',
    'exactly one audit log scope is required',
    'Should reject a search with two scopes'
);

-- Should reject a search without a scope
select throws_ok(
    $$select search_audit_logs(null, null, null, array['group_updated']::text[], '{}'::jsonb)$$,
    'P0001',
    'exactly one audit log scope is required',
    'Should reject a search without a scope'
);

-- Should render each row with its resource name
select is(
    search_audit_logs(
        null,
        :'groupID'::uuid,
        null,
        array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
        '{"limit": 2}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        format(
            $json$
                [
                    {
                        "action": "group_sponsor_deleted",
                        "actor_username": "alice-search-audit-logs",
                        "audit_log_id": "%s",
                        "created_at": 1714780800,
                        "details": {"name": "Deleted Sponsor"},
                        "resource_id": "%s",
                        "resource_name": "Deleted Sponsor",
                        "resource_type": "group_sponsor"
                    },
                    {
                        "action": "group_updated",
                        "actor_username": "userx1-search-audit-logs",
                        "audit_log_id": "%s",
                        "created_at": 1714780799,
                        "details": {"subject": "Renamed"},
                        "resource_id": "%s",
                        "resource_name": "Search Audit Group",
                        "resource_type": "group"
                    }
                ]
            $json$,
            :'sponsorAuditID',
            :'sponsorID',
            :'wildcardAuditID',
            :'groupID'
        )::jsonb,
        'total',
        3
    ),
    'Should render each row with its resource name'
);

-- Should return rows in ascending order with offset, limit and total
select is(
    (
        select jsonb_build_object(
            'ids', jsonb_path_query_array(page, '$.logs[*].audit_log_id'),
            'total', page->'total'
        )
        from (
            select search_audit_logs(
                :'communityID'::uuid,
                null,
                null,
                array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
                '{"limit": 2, "offset": 1, "sort": "created-asc"}'::jsonb
            )::jsonb as page
        ) result
    ),
    jsonb_build_object(
        'ids', jsonb_build_array(:'groupAuditID', :'wildcardAuditID'),
        'total', 4
    ),
    'Should return rows in ascending order with offset, limit and total'
);

-- Should scope rows to the actor
select is(
    jsonb_path_query_array(
        search_audit_logs(
            null,
            null,
            :'aliceID'::uuid,
            array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
            '{}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'otherCommunityAuditID', :'sponsorAuditID', :'communityAuditID'),
    'Should scope rows to the actor'
);

-- Should scope rows to the community
select is(
    jsonb_path_query_array(
        search_audit_logs(
            :'communityID'::uuid,
            null,
            null,
            array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
            '{}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'sponsorAuditID', :'wildcardAuditID', :'groupAuditID', :'communityAuditID'),
    'Should scope rows to the community'
);

-- Should scope rows to the group
select is(
    jsonb_path_query_array(
        search_audit_logs(
            null,
            :'groupID'::uuid,
            null,
            array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
            '{}'::jsonb
        )::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'sponsorAuditID', :'wildcardAuditID', :'groupAuditID'),
    'Should scope rows to the group'
);

-- Should treat actor filter metacharacters as literal text
select is(
    search_audit_logs(
        :'communityID'::uuid,
        null,
        null,
        array['community_updated', 'group_sponsor_deleted', 'group_updated']::text[],
        '{"actor": "user_1"}'::jsonb
    )::jsonb,
    jsonb_build_object('logs', '[]'::jsonb, 'total', 0),
    'Should treat actor filter metacharacters as literal text'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
