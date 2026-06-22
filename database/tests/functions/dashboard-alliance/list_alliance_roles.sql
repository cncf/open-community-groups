-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all roles ordered by alliance_role_id
select is(
    list_alliance_roles()::jsonb,
    '[
        {
            "alliance_role_id": "admin",
            "display_name": "Admin"
        },
        {
            "alliance_role_id": "groups-manager",
            "display_name": "Groups Manager"
        },
        {
            "alliance_role_id": "viewer",
            "display_name": "Viewer"
        }
    ]'::jsonb,
    'Should return all roles ordered by alliance_role_id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
