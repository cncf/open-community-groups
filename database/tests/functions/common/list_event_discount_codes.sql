-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set discountCodeFixedID '00000000-0000-0000-0000-000000000051'
\set discountCodePercentageID '00000000-0000-0000-0000-000000000052'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set eventNoDiscountCodesID '00000000-0000-0000-0000-000000000022'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'community', 'Community', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'G1', 'g1');

-- Event category
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

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
) values
    (:'eventID', :'groupID', 'Event with discount codes', 'event-with-discount-codes', 'd', 'UTC', :'eventCategoryID', 'virtual', true),
    (:'eventNoDiscountCodesID', :'groupID', 'Event without discount codes', 'event-without-discount-codes', 'd', 'UTC', :'eventCategoryID', 'virtual', true);

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
