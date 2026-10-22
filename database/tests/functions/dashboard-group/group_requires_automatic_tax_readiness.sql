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
\set canceledPriceWindowID '5f030000-0000-0000-0000-000000000034'
\set canceledTicketTypeID '5f030000-0000-0000-0000-000000000024'
\set communityID '5f030000-0000-0000-0000-000000000001'
\set eventCategoryID '5f030000-0000-0000-0000-000000000002'
\set freeEventID '5f030000-0000-0000-0000-000000000008'
\set freeGroupID '5f030000-0000-0000-0000-000000000014'
\set freePriceWindowID '5f030000-0000-0000-0000-000000000032'
\set freeTicketTypeID '5f030000-0000-0000-0000-000000000022'
\set futureEventID '5f030000-0000-0000-0000-000000000003'
\set futurePriceWindowID '5f030000-0000-0000-0000-000000000030'
\set futureTicketTypeID '5f030000-0000-0000-0000-000000000020'
\set groupCategoryID '5f030000-0000-0000-0000-000000000004'
\set groupID '5f030000-0000-0000-0000-000000000005'
\set manualEventID '5f030000-0000-0000-0000-000000000007'
\set manualGroupID '5f030000-0000-0000-0000-000000000013'
\set manualPriceWindowID '5f030000-0000-0000-0000-000000000031'
\set manualTicketTypeID '5f030000-0000-0000-0000-000000000021'
\set openEventID '5f030000-0000-0000-0000-000000000012'
\set openGroupID '5f030000-0000-0000-0000-000000000018'
\set openPriceWindowID '5f030000-0000-0000-0000-000000000036'
\set openTicketTypeID '5f030000-0000-0000-0000-000000000026'
\set otherCommunityID '5f030000-0000-0000-0000-000000000006'
\set pastEventID '5f030000-0000-0000-0000-000000000011'
\set pastGroupID '5f030000-0000-0000-0000-000000000017'
\set pastPriceWindowID '5f030000-0000-0000-0000-000000000035'
\set pastTicketTypeID '5f030000-0000-0000-0000-000000000025'
\set unknownGroupID '5f030000-0000-0000-0000-000000000099'
\set unpublishedEventID '5f030000-0000-0000-0000-000000000009'
\set unpublishedGroupID '5f030000-0000-0000-0000-000000000015'
\set unpublishedPriceWindowID '5f030000-0000-0000-0000-000000000033'
\set unpublishedTicketTypeID '5f030000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'manualGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'freeGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'unpublishedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'canceledGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'pastGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'openGroupID', :'communityID', :'groupCategoryID');

-- Purpose-built event rows for each readiness branch
select fx_event(:'futureEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 day',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp
));
select fx_event(:'manualEventID', :'manualGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 day',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp,
    'tax_calculation_mode', 'manual'
));
select fx_event(:'freeEventID', :'freeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 day',
    'published', true,
    'starts_at', current_timestamp
));
select fx_event(:'unpublishedEventID', :'unpublishedGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 day',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp
));
select fx_event(:'canceledEventID', :'canceledGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp + interval '1 day',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp
));
select fx_event(:'pastEventID', :'pastGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 day',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp - interval '2 days'
));
select fx_event(:'openEventID', :'openGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true
));

-- Ticket tiers that make every row except the free event paid-capable
select fx_event_ticket_type(:'futureTicketTypeID', :'futureEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'manualTicketTypeID', :'manualEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'freeTicketTypeID', :'freeEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'unpublishedTicketTypeID', :'unpublishedEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'canceledTicketTypeID', :'canceledEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'pastTicketTypeID', :'pastEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'openTicketTypeID', :'openEventID', jsonb_build_object('seats_total', 10));

-- Price windows that make every ticket tier except the free event paid-capable
select fx_event_ticket_price_window(:'futurePriceWindowID', :'futureTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'manualPriceWindowID', :'manualTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'freePriceWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'unpublishedPriceWindowID', :'unpublishedTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'canceledPriceWindowID', :'canceledTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'pastPriceWindowID', :'pastTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'openPriceWindowID', :'openTicketTypeID', jsonb_build_object('amount_minor', 2500));

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
    group_requires_automatic_tax_readiness(:'communityID', :'unknownGroupID'),
    false,
    'Should return false for an unknown group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
