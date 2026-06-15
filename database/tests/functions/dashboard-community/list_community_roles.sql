-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all roles ordered by community_role_id
select is(
    list_community_roles()::jsonb,
    '[
        {
            "community_role_id": "admin",
            "display_name": "Admin"
        },
        {
            "community_role_id": "groups-manager",
            "display_name": "Groups Manager"
        },
        {
            "community_role_id": "viewer",
            "display_name": "Viewer"
        }
    ]'::jsonb,
    'Should return all roles ordered by community_role_id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
