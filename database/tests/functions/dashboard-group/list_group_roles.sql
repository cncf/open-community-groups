-- Tests the group role catalog and its stable ordering.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all roles ordered by group_role_id
select is(
    list_group_roles()::jsonb,
    '[
        {
            "group_role_id": "admin",
            "display_name": "Admin"
        },
        {
            "group_role_id": "check-in-manager",
            "display_name": "Check-In Manager"
        },
        {
            "group_role_id": "events-manager",
            "display_name": "Events Manager"
        },
        {
            "group_role_id": "viewer",
            "display_name": "Viewer"
        }
    ]'::jsonb,
    'Should return all roles ordered by group_role_id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
