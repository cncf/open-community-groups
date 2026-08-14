-- Tests group_requires_automatic_tax_readiness.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '5f030000-0000-0000-0000-000000000010'
\set canceledGroupID '5f030000-0000-0000-0000-000000000016'
\set communityID '5f030000-0000-0000-0000-000000000001'
\set eventCategoryID '5f030000-0000-0000-0000-000000000002'
\set freeEventID '5f030000-0000-0000-0000-000000000008'
\set freeGroupID '5f030000-0000-0000-0000-000000000014'
\set futureEventID '5f030000-0000-0000-0000-000000000003'
\set groupCategoryID '5f030000-0000-0000-0000-000000000004'
\set groupID '5f030000-0000-0000-0000-000000000005'
\set manualEventID '5f030000-0000-0000-0000-000000000007'
\set manualGroupID '5f030000-0000-0000-0000-000000000013'
\set openEventID '5f030000-0000-0000-0000-000000000012'
\set openGroupID '5f030000-0000-0000-0000-000000000018'
\set otherCommunityID '5f030000-0000-0000-0000-000000000006'
\set pastEventID '5f030000-0000-0000-0000-000000000011'
\set pastGroupID '5f030000-0000-0000-0000-000000000017'
\set unpublishedEventID '5f030000-0000-0000-0000-000000000009'
\set unpublishedGroupID '5f030000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities used to verify ownership scoping
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
    'Automatic tax readiness tests',
    'Automatic Tax Readiness',
    'https://example.com/logo.png',
    'automatic-tax-readiness'
), (
    'https://example.com/other-banner-mobile.png',
    'https://example.com/other-banner.png',
    :'otherCommunityID',
    'Other community',
    'Other Community',
    'https://example.com/other-logo.png',
    'other-automatic-tax-readiness'
);

-- Group category shared by the readiness fixture groups
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Event category shared by the readiness fixture events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Conference');

-- Group whose current event set is inspected
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Future Automatic Tax Group',
    'future-automatic-tax-group'
), (
    :'communityID', :'groupCategoryID', :'manualGroupID',
    'Manual Tax Group', 'manual-tax-group'
), (
    :'communityID', :'groupCategoryID', :'freeGroupID',
    'Free Event Group', 'free-event-group'
), (
    :'communityID', :'groupCategoryID', :'unpublishedGroupID',
    'Unpublished Event Group', 'unpublished-event-group'
), (
    :'communityID', :'groupCategoryID', :'canceledGroupID',
    'Canceled Event Group', 'canceled-event-group'
), (
    :'communityID', :'groupCategoryID', :'pastGroupID',
    'Past Event Group', 'past-event-group'
), (
    :'communityID', :'groupCategoryID', :'openGroupID',
    'Undated Event Group', 'undated-event-group'
);

-- Purpose-built event rows for each readiness branch
insert into event (
    canceled,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    tax_calculation_mode,
    timezone
) values (
    false,
    'Paid event requiring automatic tax',
    current_timestamp + interval '1 day',
    :'eventCategoryID',
    :'futureEventID',
    'in-person',
    :'groupID',
    'Automatic Tax Event',
    'USD',
    true,
    'automatic-tax-event',
    current_timestamp,
    'automatic',
    'UTC'
), (
    false,
    'Manual-tax paid event',
    current_timestamp + interval '1 day',
    :'eventCategoryID',
    :'manualEventID',
    'in-person',
    :'manualGroupID',
    'Manual Tax Event',
    'USD',
    true,
    'manual-tax-event',
    current_timestamp,
    'manual',
    'UTC'
), (
    false,
    'Free automatic-tax event',
    current_timestamp + interval '1 day',
    :'eventCategoryID',
    :'freeEventID',
    'in-person',
    :'freeGroupID',
    'Free Event',
    null,
    true,
    'free-event',
    current_timestamp,
    'automatic',
    'UTC'
), (
    false,
    'Unpublished automatic-tax paid event',
    current_timestamp + interval '1 day',
    :'eventCategoryID',
    :'unpublishedEventID',
    'in-person',
    :'unpublishedGroupID',
    'Unpublished Event',
    'USD',
    false,
    'unpublished-event',
    current_timestamp,
    'automatic',
    'UTC'
), (
    true,
    'Canceled automatic-tax paid event',
    current_timestamp + interval '1 day',
    :'eventCategoryID',
    :'canceledEventID',
    'in-person',
    :'canceledGroupID',
    'Canceled Event',
    'USD',
    true,
    'canceled-event',
    current_timestamp,
    'automatic',
    'UTC'
), (
    false,
    'Past automatic-tax paid event',
    current_timestamp - interval '1 day',
    :'eventCategoryID',
    :'pastEventID',
    'in-person',
    :'pastGroupID',
    'Past Event',
    'USD',
    true,
    'past-event',
    current_timestamp - interval '2 days',
    'automatic',
    'UTC'
), (
    false,
    'Undated automatic-tax paid event',
    null,
    :'eventCategoryID',
    :'openEventID',
    'in-person',
    :'openGroupID',
    'Undated Event',
    'USD',
    true,
    'undated-event',
    null,
    'automatic',
    'UTC'
);

-- Ticket tiers that make every row except the free event paid-capable
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    (:'futureEventID', '5f030000-0000-0000-0000-000000000020', 1, 10, 'General'),
    (:'manualEventID', '5f030000-0000-0000-0000-000000000021', 1, 10, 'General'),
    (:'freeEventID', '5f030000-0000-0000-0000-000000000022', 1, 10, 'General'),
    (:'unpublishedEventID', '5f030000-0000-0000-0000-000000000023', 1, 10, 'General'),
    (:'canceledEventID', '5f030000-0000-0000-0000-000000000024', 1, 10, 'General'),
    (:'pastEventID', '5f030000-0000-0000-0000-000000000025', 1, 10, 'General'),
    (:'openEventID', '5f030000-0000-0000-0000-000000000026', 1, 10, 'General');

-- Price windows that make every ticket tier except the free event paid-capable
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (2500, '5f030000-0000-0000-0000-000000000030', '5f030000-0000-0000-0000-000000000020'),
    (2500, '5f030000-0000-0000-0000-000000000031', '5f030000-0000-0000-0000-000000000021'),
    (0, '5f030000-0000-0000-0000-000000000032', '5f030000-0000-0000-0000-000000000022'),
    (2500, '5f030000-0000-0000-0000-000000000033', '5f030000-0000-0000-0000-000000000023'),
    (2500, '5f030000-0000-0000-0000-000000000034', '5f030000-0000-0000-0000-000000000024'),
    (2500, '5f030000-0000-0000-0000-000000000035', '5f030000-0000-0000-0000-000000000025'),
    (2500, '5f030000-0000-0000-0000-000000000036', '5f030000-0000-0000-0000-000000000026');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore a canceled automatic-tax paid event
select is(
    group_requires_automatic_tax_readiness(:'communityID', :'canceledGroupID'),
    false,
    'Should ignore a canceled automatic-tax paid event'
);

-- Should ignore a free automatic-tax event
select is(
    group_requires_automatic_tax_readiness(:'communityID', :'freeGroupID'),
    false,
    'Should ignore a free automatic-tax event'
);

-- Should ignore a manual-tax paid event
select is(
    group_requires_automatic_tax_readiness(:'communityID', :'manualGroupID'),
    false,
    'Should ignore a manual-tax paid event'
);

-- Should ignore a past automatic-tax paid event
select is(
    group_requires_automatic_tax_readiness(:'communityID', :'pastGroupID'),
    false,
    'Should ignore a past automatic-tax paid event'
);

-- Should ignore an unpublished automatic-tax paid event
select is(
    group_requires_automatic_tax_readiness(:'communityID', :'unpublishedGroupID'),
    false,
    'Should ignore an unpublished automatic-tax paid event'
);

-- Should keep groups scoped to the selected community
select is(
    group_requires_automatic_tax_readiness(:'otherCommunityID', :'groupID'),
    false,
    'Should keep groups scoped to the selected community'
);

-- Should require Tax readiness for a published future automatic-tax paid event
select is(
    group_requires_automatic_tax_readiness(:'communityID', :'groupID'),
    true,
    'Should require Tax readiness for a published future automatic-tax paid event'
);

-- Should require Tax readiness for a published undated automatic-tax paid event
select is(
    group_requires_automatic_tax_readiness(:'communityID', :'openGroupID'),
    true,
    'Should require Tax readiness for a published undated automatic-tax paid event'
);

-- Should return false for an unknown group
select is(
    group_requires_automatic_tax_readiness(
        :'communityID',
        '5f030000-0000-0000-0000-000000000099'
    ),
    false,
    'Should return false for an unknown group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
