-- Tests projecting the public identity of a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set fullUserID 'f2050000-0000-0000-0000-000000000001'
\set minimalUserID 'f2050000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User with every summary field and private fields that must not leak
select fx_user(:'fullUserID', jsonb_build_object(
    'bio', 'Private bio',
    'company', 'ACME',
    'email', 'public-user-summary-full@example.com',
    'name', 'Full User',
    'photo_url', 'https://example.com/full.png',
    'title', 'Engineer',
    'username', 'public-user-summary-full'
));

-- User with only the required fields
select fx_user(:'minimalUserID', jsonb_build_object(
    'email', 'public-user-summary-minimal@example.com',
    'username', 'public-user-summary-minimal'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include the identity and profile summary fields only
select is(
    (select public_user_summary(u) from "user" u where u.user_id = :'fullUserID'),
    jsonb_build_object(
        'company', 'ACME',
        'name', 'Full User',
        'photo_url', 'https://example.com/full.png',
        'title', 'Engineer',
        'user_id', :'fullUserID',
        'username', 'public-user-summary-full'
    ),
    'Should include the identity and profile summary fields only'
);

-- Should strip missing optional fields
select is(
    (select public_user_summary(u) from "user" u where u.user_id = :'minimalUserID'),
    jsonb_build_object(
        'user_id', :'minimalUserID',
        'username', 'public-user-summary-minimal'
    ),
    'Should strip missing optional fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
