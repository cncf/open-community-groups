-- Tests detecting the single-free-public-tier RSVP shape.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c150000-0000-0000-0000-000000000001'
\set eventCategoryID '0c150000-0000-0000-0000-000000000002'
\set eventInactiveID '0c150000-0000-0000-0000-000000000003'
\set eventMultipleID '0c150000-0000-0000-0000-000000000004'
\set eventNoCurrentPriceID '0c150000-0000-0000-0000-000000000005'
\set eventPaidID '0c150000-0000-0000-0000-000000000006'
\set eventPrivateOnlyID '0c150000-0000-0000-0000-000000000007'
\set eventSimpleID '0c150000-0000-0000-0000-000000000008'
\set groupCategoryID '0c150000-0000-0000-0000-000000000009'
\set groupID '0c150000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for RSVP-shape scenarios
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    :'communityID',
    'Community for RSVP-shape tests',
    'RSVP Shape Community',
    'https://example.com/logo.png',
    'rsvp-shape-community'
);

-- Event category for RSVP-shape scenarios
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Meetup');

-- Group category for RSVP-shape scenarios
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Group for RSVP-shape scenarios
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'RSVP Shape Group',
    'rsvp-shape-group'
);

-- Events covering each public ticket shape
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values
    (
        'Event with an inactive secondary public tier',
        :'eventCategoryID',
        :'eventInactiveID',
        'virtual',
        :'groupID',
        'Inactive Secondary Tier Event',
        'USD',
        'inactive-secondary-tier-event',
        'UTC'
    ),
    (
        'Event with multiple public tiers',
        :'eventCategoryID',
        :'eventMultipleID',
        'virtual',
        :'groupID',
        'Multiple Public Tiers Event',
        'USD',
        'multiple-public-tiers-event',
        'UTC'
    ),
    (
        'Event without a current public price',
        :'eventCategoryID',
        :'eventNoCurrentPriceID',
        'virtual',
        :'groupID',
        'No Current Price Event',
        'USD',
        'no-current-price-event',
        'UTC'
    ),
    (
        'Event with one paid public tier',
        :'eventCategoryID',
        :'eventPaidID',
        'virtual',
        :'groupID',
        'Paid Public Tier Event',
        'USD',
        'paid-public-tier-event',
        'UTC'
    ),
    (
        'Event with only a private tier',
        :'eventCategoryID',
        :'eventPrivateOnlyID',
        'virtual',
        :'groupID',
        'Private Only Event',
        'USD',
        'private-only-event',
        'UTC'
    ),
    (
        'Event with one free public tier and one private tier',
        :'eventCategoryID',
        :'eventSimpleID',
        'virtual',
        :'groupID',
        'Simple RSVP Event',
        'USD',
        'simple-rsvp-event',
        'UTC'
    );

-- Ticket tiers covering active, inactive, public, and private shapes
insert into event_ticket_type (
    active,
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    (true, 'public', :'eventInactiveID', '0c150000-0000-0000-0000-000000000010', 1, 10, 'Active free'),
    (false, 'public', :'eventInactiveID', '0c150000-0000-0000-0000-000000000011', 2, 10, 'Inactive free'),
    (true, 'public', :'eventMultipleID', '0c150000-0000-0000-0000-000000000012', 1, 10, 'Free one'),
    (true, 'public', :'eventMultipleID', '0c150000-0000-0000-0000-000000000013', 2, 10, 'Free two'),
    (true, 'public', :'eventNoCurrentPriceID', '0c150000-0000-0000-0000-000000000014', 1, 10, 'Expired free'),
    (true, 'public', :'eventPaidID', '0c150000-0000-0000-0000-000000000015', 1, 10, 'Paid'),
    (true, 'invitation_only', :'eventPrivateOnlyID', '0c150000-0000-0000-0000-000000000016', 1, 10, 'Private free'),
    (true, 'public', :'eventSimpleID', '0c150000-0000-0000-0000-000000000017', 1, 10, 'General admission'),
    (true, 'invitation_only', :'eventSimpleID', '0c150000-0000-0000-0000-000000000018', 2, 10, 'Private paid');

-- Price windows covering current free, current paid, and expired prices
insert into event_ticket_price_window (
    amount_minor,
    ends_at,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (0, null, '0c150000-0000-0000-0000-000000000020', '0c150000-0000-0000-0000-000000000010'),
    (0, null, '0c150000-0000-0000-0000-000000000021', '0c150000-0000-0000-0000-000000000011'),
    (0, null, '0c150000-0000-0000-0000-000000000022', '0c150000-0000-0000-0000-000000000012'),
    (0, null, '0c150000-0000-0000-0000-000000000023', '0c150000-0000-0000-0000-000000000013'),
    (0, current_timestamp - interval '1 hour', '0c150000-0000-0000-0000-000000000024', '0c150000-0000-0000-0000-000000000014'),
    (2500, null, '0c150000-0000-0000-0000-000000000025', '0c150000-0000-0000-0000-000000000015'),
    (0, null, '0c150000-0000-0000-0000-000000000026', '0c150000-0000-0000-0000-000000000016'),
    (0, null, '0c150000-0000-0000-0000-000000000027', '0c150000-0000-0000-0000-000000000017'),
    (2500, null, '0c150000-0000-0000-0000-000000000028', '0c150000-0000-0000-0000-000000000018');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore inactive public tiers
select ok(
    is_event_simple_rsvp(:'eventInactiveID'::uuid),
    'Should ignore inactive public tiers'
);

-- Should reject multiple active public tiers
select is(
    is_event_simple_rsvp(:'eventMultipleID'::uuid),
    false,
    'Should reject multiple active public tiers'
);

-- Should reject public tiers without a current price
select is(
    is_event_simple_rsvp(:'eventNoCurrentPriceID'::uuid),
    false,
    'Should reject public tiers without a current price'
);

-- Should reject a paid public tier
select is(
    is_event_simple_rsvp(:'eventPaidID'::uuid),
    false,
    'Should reject a paid public tier'
);

-- Should reject events without an active public tier
select is(
    is_event_simple_rsvp(:'eventPrivateOnlyID'::uuid),
    false,
    'Should reject events without an active public tier'
);

-- Should accept one free public tier alongside private tiers
select ok(
    is_event_simple_rsvp(:'eventSimpleID'::uuid),
    'Should accept one free public tier alongside private tiers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
