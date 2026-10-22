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
\set canceledPriceWindowID '5f040000-0000-0000-0000-000000000032'
\set canceledTicketTypeID '5f040000-0000-0000-0000-000000000022'
\set communityID '5f040000-0000-0000-0000-000000000002'
\set deletedGroupEventID '5f040000-0000-0000-0000-000000000014'
\set deletedGroupID '5f040000-0000-0000-0000-000000000003'
\set deletedGroupPriceWindowID '5f040000-0000-0000-0000-000000000034'
\set deletedGroupTicketTypeID '5f040000-0000-0000-0000-000000000024'
\set eligibleEventID '5f040000-0000-0000-0000-000000000010'
\set eligiblePriceWindowID '5f040000-0000-0000-0000-000000000030'
\set eligibleTicketTypeID '5f040000-0000-0000-0000-000000000020'
\set eventCategoryID '5f040000-0000-0000-0000-000000000004'
\set freeEventID '5f040000-0000-0000-0000-000000000015'
\set freePriceWindowID '5f040000-0000-0000-0000-000000000035'
\set freeTicketTypeID '5f040000-0000-0000-0000-000000000025'
\set groupCategoryID '5f040000-0000-0000-0000-000000000005'
\set manualEventID '5f040000-0000-0000-0000-000000000016'
\set manualPriceWindowID '5f040000-0000-0000-0000-000000000036'
\set manualTicketTypeID '5f040000-0000-0000-0000-000000000026'
\set otherCommunityID '5f040000-0000-0000-0000-000000000006'
\set pastEventID '5f040000-0000-0000-0000-000000000017'
\set pastPriceWindowID '5f040000-0000-0000-0000-000000000037'
\set pastTicketTypeID '5f040000-0000-0000-0000-000000000027'
\set undatedEventID '5f040000-0000-0000-0000-000000000011'
\set undatedPriceWindowID '5f040000-0000-0000-0000-000000000031'
\set undatedTicketTypeID '5f040000-0000-0000-0000-000000000021'
\set unpublishedEventID '5f040000-0000-0000-0000-000000000018'
\set unpublishedPriceWindowID '5f040000-0000-0000-0000-000000000038'
\set unpublishedTicketTypeID '5f040000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the groups
select fx_community(:'communityID');

-- Community used to verify community scoping
select fx_community(:'otherCommunityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group owning the readiness candidates
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID');

-- Deleted group used to verify the deleted group filter
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Canceled published event excluded by the canceled filter
select fx_event(:'canceledEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'automatic'
));

-- Published event owned by the deleted group
select fx_event(:'deletedGroupEventID', :'deletedGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'automatic'
));

-- Upcoming published paid automatic-tax event
select fx_event(:'eligibleEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'automatic'
));

-- Upcoming published event with only free tickets
select fx_event(:'freeEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'automatic'
));

-- Upcoming published paid event using manual tax
select fx_event(:'manualEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'manual'
));

-- Published paid automatic-tax event that already ended
select fx_event(:'pastEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 day',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp - interval '2 days',
    'tax_calculation_mode', 'automatic'
));

-- Undated published paid automatic-tax event
select fx_event(:'undatedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'tax_calculation_mode', 'automatic'
));

-- Unpublished paid automatic-tax event
select fx_event(:'unpublishedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'automatic'
));

-- Ticket type for the canceled event
select fx_event_ticket_type(:'canceledTicketTypeID', :'canceledEventID', jsonb_build_object('seats_total', 10));

-- Ticket type for the deleted group event
select fx_event_ticket_type(:'deletedGroupTicketTypeID', :'deletedGroupEventID', jsonb_build_object('seats_total', 10));

-- Ticket type for the eligible event
select fx_event_ticket_type(:'eligibleTicketTypeID', :'eligibleEventID', jsonb_build_object('seats_total', 10));

-- Ticket type for the free event
select fx_event_ticket_type(:'freeTicketTypeID', :'freeEventID', jsonb_build_object('seats_total', 10));

-- Ticket type for the manual event
select fx_event_ticket_type(:'manualTicketTypeID', :'manualEventID', jsonb_build_object('seats_total', 10));

-- Ticket type for the past event
select fx_event_ticket_type(:'pastTicketTypeID', :'pastEventID', jsonb_build_object('seats_total', 10));

-- Ticket type for the undated event
select fx_event_ticket_type(:'undatedTicketTypeID', :'undatedEventID', jsonb_build_object('seats_total', 10));

-- Ticket type for the unpublished event
select fx_event_ticket_type(:'unpublishedTicketTypeID', :'unpublishedEventID', jsonb_build_object('seats_total', 10));

-- Paid price window for the canceled event
select fx_event_ticket_price_window(:'canceledPriceWindowID', :'canceledTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Paid price window for the deleted group event
select fx_event_ticket_price_window(:'deletedGroupPriceWindowID', :'deletedGroupTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Paid price window for the eligible event
select fx_event_ticket_price_window(:'eligiblePriceWindowID', :'eligibleTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Free price window for the free event
select fx_event_ticket_price_window(:'freePriceWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Paid price window for the manual event
select fx_event_ticket_price_window(:'manualPriceWindowID', :'manualTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Paid price window for the past event
select fx_event_ticket_price_window(:'pastPriceWindowID', :'pastTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Paid price window for the undated event
select fx_event_ticket_price_window(:'undatedPriceWindowID', :'undatedTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Paid price window for the unpublished event
select fx_event_ticket_price_window(:'unpublishedPriceWindowID', :'unpublishedTicketTypeID', jsonb_build_object('amount_minor', 2500));

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
