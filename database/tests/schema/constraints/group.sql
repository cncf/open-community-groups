-- Tests group constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0b10000-0000-0000-0000-000000000001'
\set groupCategoryID 'c0b10000-0000-0000-0000-000000000002'
\set groupID 'c0b10000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the group
select fx_community(:'communityID');

-- Group category used by the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group receiving the UTM values written by the constraint scenarios
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept 20 UTM values of 50 characters per list
select lives_ok(
    format(
        $$
            update "group"
            set
                utm_campaigns = array(select repeat('c', 49) || mod(i, 10) from generate_series(0, 19) i),
                utm_mediums = array(select repeat('m', 49) || mod(i, 10) from generate_series(0, 19) i),
                utm_sources = array(select repeat('s', 49) || mod(i, 10) from generate_series(0, 19) i)
            where group_id = %L::uuid
        $$,
        :'groupID'
    ),
    'Should accept 20 UTM values of 50 characters per list'
);

-- Should reject more than 20 UTM campaigns
select throws_ok(
    format(
        $$update "group" set utm_campaigns = array(select 'value-' || i from generate_series(1, 21) i) where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_campaigns_chk"',
    'Should reject more than 20 UTM campaigns'
);

-- Should reject UTM campaigns with values longer than 50 characters
select throws_ok(
    format(
        $$update "group" set utm_campaigns = array[repeat('v', 51)] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_campaigns_chk"',
    'Should reject UTM campaigns with values longer than 50 characters'
);

-- Should reject UTM campaigns with values with unsupported characters
select throws_ok(
    format(
        $$update "group" set utm_campaigns = array['Spring Launch'] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_campaigns_chk"',
    'Should reject UTM campaigns with values with unsupported characters'
);

-- Should reject UTM campaigns with values containing commas
select throws_ok(
    format(
        $$update "group" set utm_campaigns = array['spring,launch'] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_campaigns_chk"',
    'Should reject UTM campaigns with values containing commas'
);

-- Should reject UTM campaigns with null values
select throws_ok(
    format(
        $$update "group" set utm_campaigns = array['valid', null] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_campaigns_chk"',
    'Should reject UTM campaigns with null values'
);

-- Should reject more than 20 UTM mediums
select throws_ok(
    format(
        $$update "group" set utm_mediums = array(select 'value-' || i from generate_series(1, 21) i) where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_mediums_chk"',
    'Should reject more than 20 UTM mediums'
);

-- Should reject UTM mediums with values longer than 50 characters
select throws_ok(
    format(
        $$update "group" set utm_mediums = array[repeat('v', 51)] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_mediums_chk"',
    'Should reject UTM mediums with values longer than 50 characters'
);

-- Should reject UTM mediums with values with unsupported characters
select throws_ok(
    format(
        $$update "group" set utm_mediums = array['Spring Launch'] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_mediums_chk"',
    'Should reject UTM mediums with values with unsupported characters'
);

-- Should reject UTM mediums with values containing commas
select throws_ok(
    format(
        $$update "group" set utm_mediums = array['spring,launch'] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_mediums_chk"',
    'Should reject UTM mediums with values containing commas'
);

-- Should reject UTM mediums with null values
select throws_ok(
    format(
        $$update "group" set utm_mediums = array['valid', null] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_mediums_chk"',
    'Should reject UTM mediums with null values'
);

-- Should reject more than 20 UTM sources
select throws_ok(
    format(
        $$update "group" set utm_sources = array(select 'value-' || i from generate_series(1, 21) i) where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_sources_chk"',
    'Should reject more than 20 UTM sources'
);

-- Should reject UTM sources with values longer than 50 characters
select throws_ok(
    format(
        $$update "group" set utm_sources = array[repeat('v', 51)] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_sources_chk"',
    'Should reject UTM sources with values longer than 50 characters'
);

-- Should reject UTM sources with values with unsupported characters
select throws_ok(
    format(
        $$update "group" set utm_sources = array['Spring Launch'] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_sources_chk"',
    'Should reject UTM sources with values with unsupported characters'
);

-- Should reject UTM sources with values containing commas
select throws_ok(
    format(
        $$update "group" set utm_sources = array['spring,launch'] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_sources_chk"',
    'Should reject UTM sources with values containing commas'
);

-- Should reject UTM sources with null values
select throws_ok(
    format(
        $$update "group" set utm_sources = array['valid', null] where group_id = %L::uuid$$,
        :'groupID'
    ),
    '23514',
    'new row for relation "group" violates check constraint "group_utm_sources_chk"',
    'Should reject UTM sources with null values'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
