-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c110000-0000-0000-0000-000000000001'
\set discountCodeFixedID '0c110000-0000-0000-0000-000000000002'
\set discountCodePercentageID '0c110000-0000-0000-0000-000000000003'
\set eventCategoryID '0c110000-0000-0000-0000-000000000004'
\set eventID '0c110000-0000-0000-0000-000000000005'
\set eventNoDiscountCodesID '0c110000-0000-0000-0000-000000000006'
\set groupCategoryID '0c110000-0000-0000-0000-000000000007'
\set groupID '0c110000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true
));
select fx_event(:'eventNoDiscountCodesID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true
));

-- Event discount codes
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    ends_at,
    event_id,
    kind,
    starts_at,
    title,
    total_available
) values
    (
        :'discountCodeFixedID',
        500,
        'SAVE5',
        null,
        :'eventID',
        'fixed_amount',
        null,
        'Launch discount',
        25
    );

-- Second discount code used to verify stable listing order
insert into event_discount_code (
    event_discount_code_id,
    available_override_active,
    available,
    code,
    ends_at,
    event_id,
    kind,
    percentage,
    starts_at,
    title
) values
    (
        :'discountCodePercentageID',
        true,
        10,
        'SAVE15',
        '2025-06-30 00:00:00+00',
        :'eventID',
        'percentage',
        15,
        '2025-06-01 00:00:00+00',
        'Alpha discount'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list discount codes sorted by title and omit null fields
select is(
    list_event_discount_codes(:'eventID'::uuid),
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'available', 10,
            'available_override_active', true,
            'code', 'SAVE15',
            'ends_at', '2025-06-30 00:00:00+00'::timestamptz,
            'event_discount_code_id', :'discountCodePercentageID'::uuid,
            'kind', 'percentage',
            'percentage', 15,
            'starts_at', '2025-06-01 00:00:00+00'::timestamptz,
            'title', 'Alpha discount'
        ),
        jsonb_build_object(
            'active', true,
            'amount_minor', 500,
            'available_override_active', false,
            'code', 'SAVE5',
            'event_discount_code_id', :'discountCodeFixedID'::uuid,
            'kind', 'fixed_amount',
            'title', 'Launch discount',
            'total_available', 25
        )
    ),
    'Should list discount codes sorted by title and omit null fields'
);

-- Should return null for events without discount codes
select ok(
    list_event_discount_codes(:'eventNoDiscountCodesID'::uuid) is null,
    'Should return null for events without discount codes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
