-- Tests listing group events that require automatic-tax readiness.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID '5f040000-0000-0000-0000-000000000001'
\set canceledEventID '5f040000-0000-0000-0000-000000000012'
\set communityID '5f040000-0000-0000-0000-000000000002'
\set deletedEventID '5f040000-0000-0000-0000-000000000013'
\set deletedGroupEventID '5f040000-0000-0000-0000-000000000014'
\set deletedGroupID '5f040000-0000-0000-0000-000000000003'
\set eligibleEventID '5f040000-0000-0000-0000-000000000010'
\set eventCategoryID '5f040000-0000-0000-0000-000000000004'
\set freeEventID '5f040000-0000-0000-0000-000000000015'
\set groupCategoryID '5f040000-0000-0000-0000-000000000005'
\set manualEventID '5f040000-0000-0000-0000-000000000016'
\set otherCommunityID '5f040000-0000-0000-0000-000000000006'
\set pastEventID '5f040000-0000-0000-0000-000000000017'
\set undatedEventID '5f040000-0000-0000-0000-000000000011'
\set unpublishedEventID '5f040000-0000-0000-0000-000000000018'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID');

-- Active and deleted groups used to verify group scoping
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Purpose-built event rows covering every readiness eligibility rule
select fx_event(:'eligibleEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'undatedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'canceledEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'deletedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'deletedGroupEventID', :'deletedGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'freeEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'manualEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'manual'
));
select fx_event(:'pastEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 day',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp - interval '2 days'
));
select fx_event(:'unpublishedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '1 day'
));

-- Ticket tiers used to distinguish paid-capable and free events
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000020', :'eligibleEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000021', :'undatedEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000022', :'canceledEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000023', :'deletedEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000024', :'deletedGroupEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000025', :'freeEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000026', :'manualEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000027', :'pastEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type('5f040000-0000-0000-0000-000000000028', :'unpublishedEventID', jsonb_build_object('seats_total', 10));

-- Price windows used to distinguish paid-capable and free events
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000030', '5f040000-0000-0000-0000-000000000020', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000031', '5f040000-0000-0000-0000-000000000021', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000032', '5f040000-0000-0000-0000-000000000022', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000033', '5f040000-0000-0000-0000-000000000023', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000034', '5f040000-0000-0000-0000-000000000024', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000035', '5f040000-0000-0000-0000-000000000025', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000036', '5f040000-0000-0000-0000-000000000026', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000037', '5f040000-0000-0000-0000-000000000027', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window('5f040000-0000-0000-0000-000000000038', '5f040000-0000-0000-0000-000000000028', jsonb_build_object('amount_minor', 2500));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore events owned by a deleted group
select is(
    list_group_automatic_tax_readiness_event_ids(:'communityID', :'deletedGroupID'),
    '{}'::uuid[],
    'Should ignore events owned by a deleted group'
);

-- Should keep groups scoped to the selected community
select is(
    list_group_automatic_tax_readiness_event_ids(:'otherCommunityID', :'activeGroupID'),
    '{}'::uuid[],
    'Should keep groups scoped to the selected community'
);

-- Should list only current published paid automatic-tax events
select is(
    list_group_automatic_tax_readiness_event_ids(:'communityID', :'activeGroupID'),
    array[:'eligibleEventID'::uuid, :'undatedEventID'::uuid],
    'Should list only current published paid automatic-tax events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
