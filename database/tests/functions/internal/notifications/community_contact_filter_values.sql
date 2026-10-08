-- Tests parsing community contact filters into filter values.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '8a120000-0000-0000-0000-000000000001'
\set regionID '8a120000-0000-0000-0000-000000000002'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should parse empty filter lists as empty values
select results_eq(
    $$
        select group_category_ids, include_no_region, region_ids, roles
        from community_contact_filter_values(
            '{"group_category_ids": [], "regions": [], "roles": []}'::jsonb
        )
    $$,
    $$ values ('{}'::uuid[], false, '{}'::uuid[], '{}'::text[]) $$,
    'Should parse empty filter lists as empty values'
);

-- Should parse missing filter lists as empty values
select results_eq(
    $$
        select group_category_ids, include_no_region, region_ids, roles
        from community_contact_filter_values('{}'::jsonb)
    $$,
    $$ values ('{}'::uuid[], false, '{}'::uuid[], '{}'::text[]) $$,
    'Should parse missing filter lists as empty values'
);

-- Should parse selected values and split the no region option from regions
select results_eq(
    format(
        $$
            select group_category_ids, include_no_region, region_ids, roles
            from community_contact_filter_values(
                jsonb_build_object(
                    'group_category_ids', jsonb_build_array(%1$L),
                    'regions', jsonb_build_array('none', %2$L),
                    'roles', jsonb_build_array('admin', 'viewer')
                )
            )
        $$,
        :'categoryID',
        :'regionID'
    ),
    format(
        $$ values (array[%1$L]::uuid[], true, array[%2$L]::uuid[], array['admin', 'viewer']::text[]) $$,
        :'categoryID',
        :'regionID'
    ),
    'Should parse selected values and split the no region option from regions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
