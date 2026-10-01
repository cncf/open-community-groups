-- Tests community redirect settings constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityInvalidID 'c0020000-0000-0000-0000-000000000001'
\set communityPathID 'c0020000-0000-0000-0000-000000000002'
\set communityValidID 'c0020000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community used by the relative legacy URL scenario
select fx_community(:'communityInvalidID');

-- Community used by the legacy URL with path scenario
select fx_community(:'communityPathID');

-- Community used by the absolute legacy origin URL scenario
select fx_community(:'communityValidID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept absolute legacy origin URLs
select lives_ok(
    format(
        $$
            insert into community_redirect_settings (community_id, base_legacy_url)
            values (%L::uuid, 'https://legacy.example.org')
        $$,
        :'communityValidID'
    ),
    'Should accept absolute legacy origin URLs'
);

-- Should reject legacy URLs with paths
select throws_ok(
    format(
        $$
            insert into community_redirect_settings (community_id, base_legacy_url)
            values (%L::uuid, 'https://legacy.example.org/path')
        $$,
        :'communityPathID'
    ),
    '23514',
    'new row for relation "community_redirect_settings" violates check constraint "community_redirect_settings_base_legacy_url_chk"',
    'Should reject legacy URLs with paths'
);

-- Should reject relative legacy URLs
select throws_ok(
    format(
        $$
            insert into community_redirect_settings (community_id, base_legacy_url)
            values (%L::uuid, 'legacy.example.org')
        $$,
        :'communityInvalidID'
    ),
    '23514',
    'new row for relation "community_redirect_settings" violates check constraint "community_redirect_settings_base_legacy_url_chk"',
    'Should reject relative legacy URLs'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
