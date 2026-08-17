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
    'Automatic tax readiness event listing tests',
    'Automatic Tax Readiness Event Listing',
    'https://example.com/logo.png',
    'automatic-tax-readiness-event-listing'
), (
    'https://example.com/other-banner-mobile.png',
    'https://example.com/other-banner.png',
    :'otherCommunityID',
    'Other community',
    'Other Community',
    'https://example.com/other-logo.png',
    'other-automatic-tax-readiness-event-listing'
);

-- Group category shared by the readiness fixture groups
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Event category shared by the readiness fixture events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Conference');

-- Active and deleted groups used to verify group scoping
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug,
    active,
    deleted
) values (
    :'communityID',
    :'groupCategoryID',
    :'activeGroupID',
    'Active Group',
    'active-group',
    true,
    false
), (
    :'communityID',
    :'groupCategoryID',
    :'deletedGroupID',
    'Deleted Group',
    'deleted-group',
    false,
    true
);

-- Purpose-built event rows covering every readiness eligibility rule
insert into event (
    canceled,
    deleted,
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
    false, false, 'Eligible future event', current_timestamp + interval '2 days',
    :'eventCategoryID', :'eligibleEventID', 'in-person', :'activeGroupID',
    'Eligible Event', 'USD', true, 'eligible-event',
    current_timestamp + interval '1 day', 'automatic', 'UTC'
), (
    false, false, 'Eligible undated event', null,
    :'eventCategoryID', :'undatedEventID', 'in-person', :'activeGroupID',
    'Undated Event', 'USD', true, 'undated-event', null, 'automatic', 'UTC'
), (
    true, false, 'Canceled event', current_timestamp + interval '2 days',
    :'eventCategoryID', :'canceledEventID', 'in-person', :'activeGroupID',
    'Canceled Event', 'USD', false, 'canceled-event',
    current_timestamp + interval '1 day', 'automatic', 'UTC'
), (
    false, true, 'Deleted event', current_timestamp + interval '2 days',
    :'eventCategoryID', :'deletedEventID', 'in-person', :'activeGroupID',
    'Deleted Event', 'USD', false, 'deleted-event',
    current_timestamp + interval '1 day', 'automatic', 'UTC'
), (
    false, false, 'Event owned by a deleted group', current_timestamp + interval '2 days',
    :'eventCategoryID', :'deletedGroupEventID', 'in-person', :'deletedGroupID',
    'Deleted Group Event', 'USD', true, 'deleted-group-event',
    current_timestamp + interval '1 day', 'automatic', 'UTC'
), (
    false, false, 'Free event', current_timestamp + interval '2 days',
    :'eventCategoryID', :'freeEventID', 'in-person', :'activeGroupID',
    'Free Event', null, true, 'free-event',
    current_timestamp + interval '1 day', 'automatic', 'UTC'
), (
    false, false, 'Manual-tax event', current_timestamp + interval '2 days',
    :'eventCategoryID', :'manualEventID', 'in-person', :'activeGroupID',
    'Manual Event', 'USD', true, 'manual-event',
    current_timestamp + interval '1 day', 'manual', 'UTC'
), (
    false, false, 'Past event', current_timestamp - interval '1 day',
    :'eventCategoryID', :'pastEventID', 'in-person', :'activeGroupID',
    'Past Event', 'USD', true, 'past-event',
    current_timestamp - interval '2 days', 'automatic', 'UTC'
), (
    false, false, 'Unpublished event', current_timestamp + interval '2 days',
    :'eventCategoryID', :'unpublishedEventID', 'in-person', :'activeGroupID',
    'Unpublished Event', 'USD', false, 'unpublished-event',
    current_timestamp + interval '1 day', 'automatic', 'UTC'
);

-- Ticket tiers used to distinguish paid-capable and free events
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    (:'eligibleEventID', '5f040000-0000-0000-0000-000000000020', 1, 10, 'General'),
    (:'undatedEventID', '5f040000-0000-0000-0000-000000000021', 1, 10, 'General'),
    (:'canceledEventID', '5f040000-0000-0000-0000-000000000022', 1, 10, 'General'),
    (:'deletedEventID', '5f040000-0000-0000-0000-000000000023', 1, 10, 'General'),
    (:'deletedGroupEventID', '5f040000-0000-0000-0000-000000000024', 1, 10, 'General'),
    (:'freeEventID', '5f040000-0000-0000-0000-000000000025', 1, 10, 'General'),
    (:'manualEventID', '5f040000-0000-0000-0000-000000000026', 1, 10, 'General'),
    (:'pastEventID', '5f040000-0000-0000-0000-000000000027', 1, 10, 'General'),
    (:'unpublishedEventID', '5f040000-0000-0000-0000-000000000028', 1, 10, 'General');

-- Price windows used to distinguish paid-capable and free events
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (2500, '5f040000-0000-0000-0000-000000000030', '5f040000-0000-0000-0000-000000000020'),
    (2500, '5f040000-0000-0000-0000-000000000031', '5f040000-0000-0000-0000-000000000021'),
    (2500, '5f040000-0000-0000-0000-000000000032', '5f040000-0000-0000-0000-000000000022'),
    (2500, '5f040000-0000-0000-0000-000000000033', '5f040000-0000-0000-0000-000000000023'),
    (2500, '5f040000-0000-0000-0000-000000000034', '5f040000-0000-0000-0000-000000000024'),
    (0, '5f040000-0000-0000-0000-000000000035', '5f040000-0000-0000-0000-000000000025'),
    (2500, '5f040000-0000-0000-0000-000000000036', '5f040000-0000-0000-0000-000000000026'),
    (2500, '5f040000-0000-0000-0000-000000000037', '5f040000-0000-0000-0000-000000000027'),
    (2500, '5f040000-0000-0000-0000-000000000038', '5f040000-0000-0000-0000-000000000028');

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
