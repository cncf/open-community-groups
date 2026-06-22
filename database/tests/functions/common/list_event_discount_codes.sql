-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0c110000-0000-0000-0000-000000000001'
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

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'discount-code-alliance',
    'Discount Code Alliance',
    'Alliance for discount code tests',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name) values
    (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name) values
    (:'eventCategoryID', :'allianceID', 'Meetup');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug) values
    (
        :'groupID',
        :'allianceID',
        :'groupCategoryID',
        'Discount Code Group',
        'discount-code-group'
    );

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published
) values (
    :'eventID',
    :'groupID',
    'Event with discount codes',
    'event-with-discount-codes',
    'Event with discount codes',
    'UTC',
    :'eventCategoryID',
    'virtual',
    true
), (
    :'eventNoDiscountCodesID',
    :'groupID',
    'Event without discount codes',
    'event-without-discount-codes',
    'Event without discount codes',
    'UTC',
    :'eventCategoryID',
    'virtual',
    true
);

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
