-- Tests updating event configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(67);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '3a390000-0000-0000-0000-000000000001'
\set category2ID '3a390000-0000-0000-0000-000000000002'
\set community1ID '3a390000-0000-0000-0000-000000000003'
\set event1ID '3a390000-0000-0000-0000-000000000004'
\set event1PriceWindowID '3a390000-0000-0000-0000-0000000000da'
\set event1TicketTypeID '3a390000-0000-0000-0000-0000000000db'
\set event4ID '3a390000-0000-0000-0000-000000000005'
\set event10ID '3a390000-0000-0000-0000-000000000006'
\set event10PriceWindowID '3a390000-0000-0000-0000-0000000000e0'
\set event10TicketTypeID '3a390000-0000-0000-0000-0000000000e1'
\set event11ID '3a390000-0000-0000-0000-000000000007'
\set event11PriceWindowID '3a390000-0000-0000-0000-0000000000e2'
\set event11TicketTypeID '3a390000-0000-0000-0000-0000000000e3'
\set event12ID '3a390000-0000-0000-0000-000000000008'
\set event12PriceWindowID '3a390000-0000-0000-0000-0000000000e4'
\set event12TicketTypeID '3a390000-0000-0000-0000-0000000000e5'
\set event18ID '3a390000-0000-0000-0000-0000000000c1'
\set event18PriceWindowID '3a390000-0000-0000-0000-0000000000e6'
\set event18TicketTypeID '3a390000-0000-0000-0000-0000000000e7'
\set eventExternalClearID '3a390000-0000-0000-0000-000000000050'
\set eventExternalClearPriceWindowID '3a390000-0000-0000-0000-000000000051'
\set eventExternalClearPurchaseID '3a390000-0000-0000-0000-000000000062'
\set eventExternalClearTicketTypeID '3a390000-0000-0000-0000-000000000052'
\set eventExternalDelistedID '3a390000-0000-0000-0000-00000000005a'
\set eventExternalDelistedPriceWindowID '3a390000-0000-0000-0000-00000000005b'
\set eventExternalDelistedTicketTypeID '3a390000-0000-0000-0000-00000000005c'
\set eventExternalNamelessID '3a390000-0000-0000-0000-000000000066'
\set eventExternalNamelessPriceWindowID '3a390000-0000-0000-0000-000000000067'
\set eventExternalNamelessTicketTypeID '3a390000-0000-0000-0000-000000000068'
\set eventExternalPaidID '3a390000-0000-0000-0000-000000000053'
\set eventExternalPaidPriceWindowID '3a390000-0000-0000-0000-000000000054'
\set eventExternalPaidPurchaseID '3a390000-0000-0000-0000-000000000063'
\set eventExternalPaidTicketTypeID '3a390000-0000-0000-0000-000000000055'
\set eventExternalPendingClearID '3a390000-0000-0000-0000-00000000005e'
\set eventExternalPendingClearPriceWindowID '3a390000-0000-0000-0000-00000000005f'
\set eventExternalPendingClearPurchaseID '3a390000-0000-0000-0000-000000000060'
\set eventExternalPendingClearTicketTypeID '3a390000-0000-0000-0000-000000000061'
\set eventExternalStripeID '3a390000-0000-0000-0000-000000000056'
\set eventExternalStripePriceWindowID '3a390000-0000-0000-0000-000000000057'
\set eventExternalStripeTicketTypeID '3a390000-0000-0000-0000-000000000058'
\set eventFreeToPaidID '3a390000-0000-0000-0000-000000000023'
\set eventFreeToPaidPriceWindowID '3a390000-0000-0000-0000-000000000026'
\set eventFreeToPaidTicketTypeID '3a390000-0000-0000-0000-000000000027'
\set eventLabelRemovedID '3a390000-0000-0000-0000-0000000000a5'
\set eventLabelRemovedPriceWindowID '3a390000-0000-0000-0000-0000000000e8'
\set eventLabelRemovedTicketTypeID '3a390000-0000-0000-0000-0000000000e9'
\set eventLabelStaleID '3a390000-0000-0000-0000-0000000000a6'
\set eventLabelStalePriceWindowID '3a390000-0000-0000-0000-0000000000ea'
\set eventLabelStaleTicketTypeID '3a390000-0000-0000-0000-0000000000eb'
\set eventManualTaxID '3a390000-0000-0000-0000-000000000041'
\set eventManualTaxPriceWindowID '3a390000-0000-0000-0000-0000000000d8'
\set eventManualTaxTicketTypeID '3a390000-0000-0000-0000-0000000000d9'
\set eventOrganizersKeptID '3a390000-0000-0000-0000-0000000000b0'
\set eventOrganizersKeptPriceWindowID '3a390000-0000-0000-0000-0000000000d0'
\set eventOrganizersKeptTicketTypeID '3a390000-0000-0000-0000-0000000000d1'
\set eventOrganizersRejectedID '3a390000-0000-0000-0000-0000000000b1'
\set eventOrganizersRejectedPriceWindowID '3a390000-0000-0000-0000-0000000000d2'
\set eventOrganizersRejectedTicketTypeID '3a390000-0000-0000-0000-0000000000d3'
\set eventOrganizersReplacedID '3a390000-0000-0000-0000-0000000000b2'
\set eventOrganizersReplacedPriceWindowID '3a390000-0000-0000-0000-0000000000d4'
\set eventOrganizersReplacedTicketTypeID '3a390000-0000-0000-0000-0000000000d5'
\set eventOrganizersTeamID '3a390000-0000-0000-0000-0000000000b3'
\set eventOrganizersTeamPriceWindowID '3a390000-0000-0000-0000-0000000000d6'
\set eventOrganizersTeamTicketTypeID '3a390000-0000-0000-0000-0000000000d7'
\set eventPaidToFreeID '3a390000-0000-0000-0000-000000000024'
\set eventPaidToFreePriceWindowID '3a390000-0000-0000-0000-000000000028'
\set eventPaidToFreeTicketTypeID '3a390000-0000-0000-0000-000000000029'
\set eventPaidToPaidID '3a390000-0000-0000-0000-000000000025'
\set eventPaidToPaidPriceWindowID '3a390000-0000-0000-0000-000000000030'
\set eventPaidToPaidTicketTypeID '3a390000-0000-0000-0000-000000000031'
\set eventSessionHostsID '3a390000-0000-0000-0000-000000000064'
\set eventSessionHostsPriceWindowID '3a390000-0000-0000-0000-0000000000de'
\set eventSessionHostsTicketTypeID '3a390000-0000-0000-0000-0000000000df'
\set eventTestFreeToPaidID '3a390000-0000-0000-0000-000000000032'
\set eventTestFreeToPaidPriceWindowID '3a390000-0000-0000-0000-000000000033'
\set eventTestFreeToPaidTicketTypeID '3a390000-0000-0000-0000-000000000034'
\set eventTestPaidToLiveID '3a390000-0000-0000-0000-000000000035'
\set eventTestPaidToLivePriceWindowID '3a390000-0000-0000-0000-000000000036'
\set eventTestPaidToLiveTicketTypeID '3a390000-0000-0000-0000-000000000037'
\set eventTestPaidToTestID '3a390000-0000-0000-0000-000000000038'
\set eventTestPaidToTestPriceWindowID '3a390000-0000-0000-0000-000000000039'
\set eventTestPaidToTestTicketTypeID '3a390000-0000-0000-0000-000000000040'
\set eventWaitlistWindowID '3a390000-0000-0000-0000-000000000021'
\set eventWaitlistWindowPriceWindowID '3a390000-0000-0000-0000-0000000000ec'
\set eventWaitlistWindowTicketTypeID '3a390000-0000-0000-0000-0000000000ed'
\set group1ID '3a390000-0000-0000-0000-000000000010'
\set groupCategoryID '3a390000-0000-0000-0000-0000000000c0'
\set groupDelistedID '3a390000-0000-0000-0000-00000000005d'
\set groupExternalID '3a390000-0000-0000-0000-000000000059'
\set groupExternalNamelessID '3a390000-0000-0000-0000-000000000069'
\set label1ID '3a390000-0000-0000-0000-000000000011'
\set label2ID '3a390000-0000-0000-0000-000000000012'
\set label3ID '3a390000-0000-0000-0000-000000000013'
\set label4ID '3a390000-0000-0000-0000-000000000014'
\set label5ID '3a390000-0000-0000-0000-0000000000a1'
\set labelRemovedID '3a390000-0000-0000-0000-0000000000a2'
\set labelStaleID '3a390000-0000-0000-0000-0000000000a3'
\set labelStaleMissingID '3a390000-0000-0000-0000-0000000000a4'
\set missingGroupID '3a390000-0000-0000-0000-000000000019'
\set missingUserID '3a390000-0000-0000-0000-000000000020'
\set sessionHostsID '3a390000-0000-0000-0000-000000000065'
\set sessionLabelRemovedID '3a390000-0000-0000-0000-0000000000a7'
\set sessionLabelRenameID '3a390000-0000-0000-0000-0000000000a8'
\set sponsorNewID '3a390000-0000-0000-0000-000000000015'
\set sponsorOrigID '3a390000-0000-0000-0000-000000000016'
\set teamMemberID '3a390000-0000-0000-0000-0000000000b4'
\set user1ID '3a390000-0000-0000-0000-000000000009'
\set user2ID '3a390000-0000-0000-0000-000000000017'
\set user3ID '3a390000-0000-0000-0000-000000000018'
\set waitlistUserID '3a390000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'community1ID', jsonb_build_object('logo_url', 'https://example.com/logo.png'));

-- Baseline group category
select fx_group_category(:'groupCategoryID', :'community1ID');

-- Event categories
select fx_event_category(:'category1ID', :'community1ID', jsonb_build_object('name', 'Conference'));
select fx_event_category(:'category2ID', :'community1ID', jsonb_build_object('name', 'Workshop'));

-- Operator allowlist and window limits used by external update scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Users
select fx_user(:'user1ID', jsonb_build_object(
    'email', 'host1-update-event@example.com',
    'username', 'host1-update-event'
));
select fx_user(:'user2ID', jsonb_build_object(
    'email', 'host2-update-event@example.com',
    'name', 'Host Two',
    'username', 'host2-update-event'
));
select fx_user(:'user3ID', jsonb_build_object(
    'name', 'Speaker One',
    'username', 'speaker1-update-event'
));
select fx_user(:'waitlistUserID', jsonb_build_object('username', 'waitlist'));

-- Accepted team member who joined after the team event organizers were stored
select fx_user(:'teamMemberID', jsonb_build_object('username', 'team-member-update-event'));

-- Group
select fx_group(:'group1ID', :'community1ID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_update_event", "seller_display_name": "Update Event Fiscal Sponsor"}'::jsonb));

-- Allowlisted group with external payments enabled for external update scenarios
select fx_group(:'groupExternalID', :'community1ID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co'
));

-- Allowlisted enabled group that kept a Stripe sponsor but never named the external payee
select fx_group(:'groupExternalNamelessID', :'community1ID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_nameless_update", "seller_display_name": "Retained Fiscal Sponsor"}'::jsonb
));

-- Delisted-country group used to reject a preserved external URL
select fx_group(:'groupDelistedID', :'community1ID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co'
));

-- Events used for paid-capability transition results
select fx_event(:'eventFreeToPaidID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Free event used for paid transition checks',
    'event_kind_id', 'virtual',
    'name', 'Free To Paid',
    'slug', 'free-to-paid'
));
select fx_event(:'eventPaidToFreeID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Paid event used for free transition checks',
    'event_kind_id', 'virtual',
    'name', 'Paid To Free',
    'payment_currency_code', 'USD',
    'slug', 'paid-to-free'
));
select fx_event(:'eventPaidToPaidID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Paid event used for paid edit checks',
    'event_kind_id', 'virtual',
    'name', 'Paid To Paid',
    'payment_currency_code', 'USD',
    'slug', 'paid-to-paid'
));
select fx_event(:'eventTestFreeToPaidID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Free test event promoted while adding paid tickets',
    'event_kind_id', 'virtual',
    'name', 'Test Free To Paid',
    'test_event', true
));
select fx_event(:'eventTestPaidToLiveID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Paid test event promoted without changing tickets',
    'event_kind_id', 'virtual',
    'name', 'Test Paid To Live',
    'payment_currency_code', 'USD',
    'test_event', true
));
select fx_event(:'eventTestPaidToTestID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Paid test event that remains a test event',
    'event_kind_id', 'virtual',
    'name', 'Test Paid To Test',
    'payment_currency_code', 'USD',
    'test_event', true
));

-- Event whose stored organizers are kept when the payload omits them
select fx_event(:'eventOrganizersKeptID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for kept organizers tests',
    'name', 'Event With Kept Organizers'
));

-- Event whose stored organizers survive a rejected organizers payload
select fx_event(:'eventOrganizersRejectedID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for rejected organizers tests',
    'name', 'Event With Rejected Organizers'
));

-- Event whose stored organizers are replaced by the payload
select fx_event(:'eventOrganizersReplacedID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for replaced organizers tests',
    'name', 'Event With Replaced Organizers'
));

-- Event whose stored organizers differ from the current group team
select fx_event(:'eventOrganizersTeamID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for team change organizers tests',
    'name', 'Event With Team Organizers'
));

-- Free manual-tax event with a selection that can be explicitly cleared
select fx_event(:'eventManualTaxID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Free manual-tax event used for selection clearing checks',
    'event_kind_id', 'virtual',
    'manual_tax_rate_ids', array['txr_state']::text[],
    'name', 'Manual Tax Selection',
    'tax_calculation_mode', 'manual'
));

-- Existing ISO fields exercise updates from the deferred legacy form.
update event
set
    venue_country_code = 'US',
    venue_state_code = 'CA',
    venue_state_name = 'California'
where event_id = :'eventFreeToPaidID';

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', null),
    (
        :'sponsorNewID',
        :'group1ID',
        'NewSponsor Inc',
        'https://example.com/newsponsor.png',
        'https://newsponsor.com'
    );

-- Event
select fx_event(:'event1ID', :'group1ID', :'category1ID', jsonb_build_object(
    'slug', 'def5678',
    'timezone', 'America/New_York'
));

-- Add initial host and sponsor to the event
insert into event_host (event_id, user_id) values (:'event1ID', :'user1ID');

-- Initial speaker synchronized by the event update
insert into event_speaker (event_id, user_id, featured) values (:'event1ID', :'user1ID', true);

-- Initial sponsor synchronized by the event update
insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'event1ID', :'sponsorOrigID', 'Bronze');

-- Canceled Event
select fx_event(:'event4ID', :'group1ID', :'category1ID', jsonb_build_object(
    'canceled', true,
    'timezone', 'America/New_York'
));

-- Event with a synced session meeting used for host change checks
select fx_event(:'eventSessionHostsID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', '2030-03-01 12:00:00+00',
    'event_kind_id', 'virtual',
    'name', 'Session Hosts Event',
    'starts_at', '2030-03-01 10:00:00+00',
    'timezone', 'UTC'
));

-- Published event used for reminder evaluation checks
select fx_event(:'event10ID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'event_kind_id', 'virtual',
    'name', 'Reminder Event',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Published soon-starting event used for reminder regression checks
select fx_event(:'event11ID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', current_timestamp + interval '12 hours',
    'event_kind_id', 'virtual',
    'name', 'Reminder Event Soon',
    'published', true,
    'starts_at', current_timestamp + interval '10 hours'
));

-- Event whose labels are kept when the payload omits them
select fx_event(:'event12ID', :'group1ID', :'category1ID', jsonb_build_object(
    'cfs_description', 'Initial CFS description',
    'cfs_enabled', true,
    'cfs_ends_at', '2030-01-05 00:00:00+00',
    'cfs_starts_at', '2029-12-20 00:00:00+00',
    'description', 'Event seeded for labels update tests',
    'ends_at', '2030-01-15 12:00:00+00',
    'event_kind_id', 'virtual',
    'name', 'Event With Labels',
    'starts_at', '2030-01-15 10:00:00+00'
));

-- Event whose labels are renamed, added and pruned
select fx_event(:'event18ID', :'group1ID', :'category1ID', jsonb_build_object(
    'cfs_description', 'Initial CFS description',
    'cfs_enabled', true,
    'cfs_ends_at', '2030-01-05 00:00:00+00',
    'cfs_starts_at', '2029-12-20 00:00:00+00',
    'description', 'Event seeded for labels upsert tests',
    'ends_at', '2030-01-15 12:00:00+00',
    'event_kind_id', 'virtual',
    'name', 'Event With Labels For Upsert',
    'starts_at', '2030-01-15 10:00:00+00'
));

-- Event whose removed label is still referenced by a session
select fx_event(:'eventLabelRemovedID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for removed label tests',
    'ends_at', '2030-01-15 12:00:00+00',
    'event_kind_id', 'virtual',
    'name', 'Event With Removed Label',
    'starts_at', '2030-01-15 10:00:00+00'
));

-- Event receiving a stale label identifier
select fx_event(:'eventLabelStaleID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for stale label tests',
    'ends_at', '2030-01-15 12:00:00+00',
    'event_kind_id', 'virtual',
    'name', 'Event With Stale Label',
    'starts_at', '2030-01-15 10:00:00+00'
));

-- Live event used for update-driven waitlist promotion checks
select fx_event(:'eventWaitlistWindowID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for registration window waitlist update tests',
    'ends_at', date_trunc('second', current_timestamp + interval '1 hour'),
    'name', 'Open Only Waitlist Event',
    'published', true,
    'registration_starts_at', date_trunc('second', current_timestamp - interval '2 hours'),
    'starts_at', date_trunc('second', current_timestamp - interval '1 hour'),
    'waitlist_enabled', true
));

-- Labels kept when the payload omits them
insert into event_label (event_label_id, event_id, color, name) values
    (:'label1ID', :'event12ID', '#CCFBF1', 'track / backend'),
    (:'label2ID', :'event12ID', '#FEE2E2', 'track / frontend');

-- Labels renamed, kept and pruned by the payload
insert into event_label (event_label_id, event_id, color, name) values
    (:'label3ID', :'event18ID', '#CCFBF1', 'track / backend'),
    (:'label4ID', :'event18ID', '#FEE2E2', 'track / frontend');

-- Label removed while a session still references it
insert into event_label (event_label_id, event_id, color, name)
values (:'labelRemovedID', :'eventLabelRemovedID', '#CCFBF1', 'track / removed');

-- Label kept when a stale label identifier is rejected
insert into event_label (event_label_id, event_id, color, name)
values (:'labelStaleID', :'eventLabelStaleID', '#CCFBF1', 'track / stale');

-- Attendee used by reminder evaluation checks
insert into event_attendee (event_id, user_id)
values (:'event10ID', :'user1ID');

-- Occupied seat and waitlist entry used by update-driven promotion checks
insert into event_attendee (event_id, user_id)
values (:'eventWaitlistWindowID', :'user2ID');

-- Initial host of the session hosts event
insert into event_host (event_id, user_id) values (:'eventSessionHostsID', :'user1ID');

-- Stored organizers kept when the payload omits them
insert into event_organizer (event_id, user_id, "order") values
    (:'eventOrganizersKeptID', :'user3ID', 1),
    (:'eventOrganizersKeptID', :'user2ID', 2);

-- Stored organizer kept when an invalid organizers payload is rejected
insert into event_organizer (event_id, user_id, "order")
values (:'eventOrganizersRejectedID', :'user1ID', 1);

-- Stored organizer outside the group team, kept by the submitted organizers
insert into event_organizer (event_id, user_id, "order")
values (:'eventOrganizersReplacedID', :'user1ID', 1);

-- Stored organizer who has since left the group team
insert into event_organizer (event_id, user_id, "order")
values (:'eventOrganizersTeamID', :'user1ID', 1);

-- Current accepted group team, which no longer includes the stored organizer
insert into group_team (accepted, group_id, role, user_id)
values (true, :'group1ID', 'viewer', :'teamMemberID');

-- Free ticket tier for the free to paid transition event
select fx_event_ticket_type(:'eventFreeToPaidTicketTypeID', :'eventFreeToPaidID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Paid ticket tier for the paid to free transition event
select fx_event_ticket_type(:'eventPaidToFreeTicketTypeID', :'eventPaidToFreeID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Paid ticket tier for the paid edit event
select fx_event_ticket_type(:'eventPaidToPaidTicketTypeID', :'eventPaidToPaidID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the free test event promoted with paid tickets
select fx_event_ticket_type(:'eventTestFreeToPaidTicketTypeID', :'eventTestFreeToPaidID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Paid ticket tier for the paid test event promoted without ticket changes
select fx_event_ticket_type(:'eventTestPaidToLiveTicketTypeID', :'eventTestPaidToLiveID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Paid ticket tier for the paid test event that remains a test event
select fx_event_ticket_type(:'eventTestPaidToTestTicketTypeID', :'eventTestPaidToTestID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the kept organizers event
select fx_event_ticket_type(:'eventOrganizersKeptTicketTypeID', :'eventOrganizersKeptID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the rejected organizers event
select fx_event_ticket_type(:'eventOrganizersRejectedTicketTypeID', :'eventOrganizersRejectedID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the replaced organizers event
select fx_event_ticket_type(:'eventOrganizersReplacedTicketTypeID', :'eventOrganizersReplacedID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the team organizers event
select fx_event_ticket_type(:'eventOrganizersTeamTicketTypeID', :'eventOrganizersTeamID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the manual-tax selection event
select fx_event_ticket_type(:'eventManualTaxTicketTypeID', :'eventManualTaxID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the base update event
select fx_event_ticket_type(:'event1TicketTypeID', :'event1ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the session hosts event
select fx_event_ticket_type(:'eventSessionHostsTicketTypeID', :'eventSessionHostsID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the reminder event
select fx_event_ticket_type(:'event10TicketTypeID', :'event10ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the soon-starting reminder event
select fx_event_ticket_type(:'event11TicketTypeID', :'event11ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the kept labels event
select fx_event_ticket_type(:'event12TicketTypeID', :'event12ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the labels upsert event
select fx_event_ticket_type(:'event18TicketTypeID', :'event18ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the removed label event
select fx_event_ticket_type(:'eventLabelRemovedTicketTypeID', :'eventLabelRemovedID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the stale label event
select fx_event_ticket_type(:'eventLabelStaleTicketTypeID', :'eventLabelStaleID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Free ticket tier for the waitlist promotion event
select fx_event_ticket_type(:'eventWaitlistWindowTicketTypeID', :'eventWaitlistWindowID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General Admission'
));

-- Current free price for the free to paid transition event tier
select fx_event_ticket_price_window(:'eventFreeToPaidPriceWindowID', :'eventFreeToPaidTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current paid price for the paid to free transition event tier
select fx_event_ticket_price_window(:'eventPaidToFreePriceWindowID', :'eventPaidToFreeTicketTypeID', jsonb_build_object('amount_minor', 1200));

-- Current paid price for the paid edit event tier
select fx_event_ticket_price_window(:'eventPaidToPaidPriceWindowID', :'eventPaidToPaidTicketTypeID', jsonb_build_object('amount_minor', 1200));

-- Current free price for the free test event promoted with paid tickets tier
select fx_event_ticket_price_window(:'eventTestFreeToPaidPriceWindowID', :'eventTestFreeToPaidTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current paid price for the paid test event promoted without ticket changes tier
select fx_event_ticket_price_window(:'eventTestPaidToLivePriceWindowID', :'eventTestPaidToLiveTicketTypeID', jsonb_build_object('amount_minor', 1200));

-- Current paid price for the paid test event that remains a test event tier
select fx_event_ticket_price_window(:'eventTestPaidToTestPriceWindowID', :'eventTestPaidToTestTicketTypeID', jsonb_build_object('amount_minor', 1200));

-- Current free price for the kept organizers event tier
select fx_event_ticket_price_window(:'eventOrganizersKeptPriceWindowID', :'eventOrganizersKeptTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the rejected organizers event tier
select fx_event_ticket_price_window(:'eventOrganizersRejectedPriceWindowID', :'eventOrganizersRejectedTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the replaced organizers event tier
select fx_event_ticket_price_window(:'eventOrganizersReplacedPriceWindowID', :'eventOrganizersReplacedTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the team organizers event tier
select fx_event_ticket_price_window(:'eventOrganizersTeamPriceWindowID', :'eventOrganizersTeamTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the manual-tax selection event tier
select fx_event_ticket_price_window(:'eventManualTaxPriceWindowID', :'eventManualTaxTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the base update event tier
select fx_event_ticket_price_window(:'event1PriceWindowID', :'event1TicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the session hosts event tier
select fx_event_ticket_price_window(:'eventSessionHostsPriceWindowID', :'eventSessionHostsTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the reminder event tier
select fx_event_ticket_price_window(:'event10PriceWindowID', :'event10TicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the soon-starting reminder event tier
select fx_event_ticket_price_window(:'event11PriceWindowID', :'event11TicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the kept labels event tier
select fx_event_ticket_price_window(:'event12PriceWindowID', :'event12TicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the labels upsert event tier
select fx_event_ticket_price_window(:'event18PriceWindowID', :'event18TicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the removed label event tier
select fx_event_ticket_price_window(:'eventLabelRemovedPriceWindowID', :'eventLabelRemovedTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the stale label event tier
select fx_event_ticket_price_window(:'eventLabelStalePriceWindowID', :'eventLabelStaleTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the waitlist promotion event tier
select fx_event_ticket_price_window(:'eventWaitlistWindowPriceWindowID', :'eventWaitlistWindowTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Waitlisted user eligible for promotion after the event update
insert into event_waitlist (event_id, event_ticket_type_id, user_id, created_at)
values (
    :'eventWaitlistWindowID',
    :'eventWaitlistWindowTicketTypeID',
    :'waitlistUserID',
    current_timestamp - interval '30 minutes'
);

-- Session whose provider meeting is in sync with the initial host
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionHostsID',
    :'eventSessionHostsID',
    'Hosted Session',
    'virtual',
    '2030-03-01 10:30:00+00',
    '2030-03-01 11:00:00+00',
    true,
    'zoom',
    true
);

-- Session linked to the label renamed by the payload
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'sessionLabelRenameID', :'event18ID', 'Renamed Label Session', 'virtual', '2030-01-15 10:00:00+00');

-- Session linked to the label removed by the rejected payload
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'sessionLabelRemovedID', :'eventLabelRemovedID', 'Removed Label Session', 'virtual', '2030-01-15 10:00:00+00');

-- Link to the label renamed by the payload
insert into session_label (event_label_id, session_id)
values (:'label3ID', :'sessionLabelRenameID');

-- Link to the label removed by the rejected payload
insert into session_label (event_label_id, session_id)
values (:'labelRemovedID', :'sessionLabelRemovedID');

-- Paid Stripe-shaped event on the non-external group used to prove leftover URLs clear
select fx_event(:'eventExternalClearID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Paid event that still carries leftover external fields',
    'external_payment_url', 'https://pay.example.test/leftover',
    'external_payment_window_hours', 48,
    'name', 'External Clear Event',
    'payment_currency_code', 'USD',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_zip_code', '94105'
));

-- Paid leftover-URL event whose pending hold must keep the live event URL
select fx_event(:'eventExternalPendingClearID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Paid event whose pending external hold keeps the live URL',
    'external_payment_url', 'https://pay.example.test/pending-clear',
    'external_payment_window_hours', 48,
    'name', 'External Pending Clear Event',
    'payment_currency_code', 'USD',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_zip_code', '94105'
));

-- Paid event that keeps an external URL after the country leaves the allowlist
select fx_event(:'eventExternalDelistedID', :'groupDelistedID', :'category1ID', jsonb_build_object(
    'description', 'Paid event whose group country is no longer allowlisted',
    'external_payment_url', 'https://pay.example.test/delisted',
    'external_payment_window_hours', 48,
    'name', 'External Delisted Event',
    'payment_currency_code', 'USD',
    'tax_calculation_mode', 'none',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_zip_code', '94105'
));

-- Paid external-group event without a URL that stays Stripe until URL is set
select fx_event(:'eventExternalStripeID', :'groupExternalID', :'category1ID', jsonb_build_object(
    'description', 'Published Stripe event waiting for an external URL',
    'name', 'External Stripe Event',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Free event in the nameless external group that must not turn paid on Stripe
select fx_event(:'eventExternalNamelessID', :'groupExternalNamelessID', :'category1ID', jsonb_build_object(
    'description', 'Free event in a nameless external group',
    'name', 'Nameless External Group Event',
    'starts_at', current_timestamp + interval '7 days',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Paid external-group event already marked with a URL for window and tax updates
select fx_event(:'eventExternalPaidID', :'groupExternalID', :'category1ID', jsonb_build_object(
    'description', 'External event updated for window and tax normalization',
    'external_payment_url', 'https://pay.example.test/update',
    'name', 'External Paid Event',
    'payment_currency_code', 'KRW',
    'tax_behavior', 'exclusive',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Ticket types for the external update fixtures
select fx_event_ticket_type(:'eventExternalClearTicketTypeID', :'eventExternalClearID', jsonb_build_object(
    'seats_total', 50,
    'title', 'General Admission'
));
select fx_event_ticket_type(:'eventExternalDelistedTicketTypeID', :'eventExternalDelistedID', jsonb_build_object(
    'seats_total', 50,
    'title', 'General Admission'
));
select fx_event_ticket_type(:'eventExternalPaidTicketTypeID', :'eventExternalPaidID', jsonb_build_object(
    'seats_total', 50,
    'title', 'General Admission'
));
select fx_event_ticket_type(:'eventExternalPendingClearTicketTypeID', :'eventExternalPendingClearID', jsonb_build_object(
    'seats_total', 50,
    'title', 'General Admission'
));
select fx_event_ticket_type(:'eventExternalNamelessTicketTypeID', :'eventExternalNamelessID', jsonb_build_object(
    'seats_total', 50,
    'title', 'General Admission'
));
select fx_event_ticket_type(:'eventExternalStripeTicketTypeID', :'eventExternalStripeID', jsonb_build_object(
    'seats_total', 50,
    'title', 'General Admission'
));

-- Price windows for the external update fixtures
select fx_event_ticket_price_window(:'eventExternalClearPriceWindowID', :'eventExternalClearTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'eventExternalDelistedPriceWindowID', :'eventExternalDelistedTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'eventExternalNamelessPriceWindowID', :'eventExternalNamelessTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventExternalPaidPriceWindowID', :'eventExternalPaidTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'eventExternalPendingClearPriceWindowID', :'eventExternalPendingClearTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'eventExternalStripePriceWindowID', :'eventExternalStripeTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- Completed leftover external purchase that must not block clearing the URL
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    2500,
    'external',
    current_timestamp - interval '1 hour',
    'USD',
    :'eventExternalClearID',
    :'eventExternalClearPurchaseID',
    :'eventExternalClearTicketTypeID',
    0,
    0,
    'completed',
    'General Admission',
    :'user1ID'
);

-- Pending leftover external hold that must keep the live event URL
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    2500,
    'external',
    'USD',
    :'eventExternalPendingClearID',
    :'eventExternalPendingClearPurchaseID',
    :'eventExternalPendingClearTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'General Admission',
    :'user1ID'
);

-- Pending external hold on an eligible event whose URL may still change
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    'KRW',
    :'eventExternalPaidID',
    :'eventExternalPaidPurchaseID',
    :'eventExternalPaidTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'General Admission',
    :'user1ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report no paid notification transition for a free-to-free update
select is(
    (select update_event(
        :'user1ID'::uuid,
        :'group1ID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'capacity', 100,
            'category_id', :'category2ID',
            'description', 'Updated description',
            'ends_at', '2030-02-01T16:00:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_requested', true,
            'name', 'Updated Event Name',
            'starts_at', '2030-02-01T14:00:00',
            'timezone', 'America/Los_Angeles'
        )
    )),
    false,
    'Should report no paid notification transition for a free-to-free update'
);

-- Should persist basic update and clear omitted hosts, sponsors, and sessions
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'cohosts' - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'ticket_types'
    )),
    '{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Workshop",
        "description": "Updated description",
        "hosts": [],
        "kind": "virtual",
        "labels": [],
        "logo_url": "https://example.com/logo.png",
        "name": "Updated Event Name",
        "published": false,
        "slug": "def5678",
        "speakers": [],
        "sponsors": [],
        "test_event": false,
        "manual_tax_rate_ids": [],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "timezone": "America/Los_Angeles",

        "attendee_approval_required": false,
        "capacity": 100,
        "remaining_capacity": 100,
        "seller_display_name": "Update Event Fiscal Sponsor",
        "ends_at": 1896220800,
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "meeting_in_sync": false,
        "meeting_provider": "zoom",
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "meeting_requested": true,
        "registration_questions": [],
        "registration_questions_locked": false,
        "sessions": {},
        "starts_at": 1896213600,
        "waitlist_count": 0,
        "waitlist_enabled": false
    }'::jsonb,
    'Should persist basic update and clear omitted hosts, sponsors, and sessions'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
            values (
                'event_updated',
                %L::uuid,
                'host1-update-event',
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'event',
                %L::uuid
            )
        $$,
        :'user1ID',
        :'community1ID',
        :'group1ID',
        :'event1ID',
        :'event1ID'
    ),
    'Should create the expected audit row'
);

-- Should clear explicitly submitted manual Tax Rate selections on a free event
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventManualTaxID'::uuid,
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Free manual-tax event used for selection clearing checks',
            'kind_id', 'virtual',
            'manual_tax_rate_ids', '[]'::jsonb,
            'name', 'Manual Tax Selection',
            'tax_behavior', 'inclusive',
            'tax_calculation_mode', 'manual',
            'timezone', 'UTC'
        )
    ),
    false,
    'Should clear explicitly submitted manual Tax Rate selections on a free event'
);

-- Should persist the cleared manual Tax Rate selection
select is(
    (
        select e.manual_tax_rate_ids
        from event e
        where e.event_id = :'eventManualTaxID'::uuid
    ),
    '{}'::text[],
    'Should persist the cleared manual Tax Rate selection'
);

-- Should report a paid notification transition for an invitation-only tier
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventFreeToPaidID'::uuid,
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Free event used for paid transition checks',
            'kind_id', 'in-person',
            'name', 'Free To Paid',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'invitation_only',
                    'event_ticket_type_id', :'eventFreeToPaidTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 1500,
                            'event_ticket_price_window_id', :'eventFreeToPaidPriceWindowID'
                        )
                    ),
                    'seats_total', 100,
                    'title', 'Private Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state', 'California',
            'venue_zip_code', '94105'
        ),
        null::jsonb,
        'stripe'
    ),
    true,
    'Should report a paid notification transition for an invitation-only tier'
);

-- Should persist paid capability after a free-to-paid update
select is(
    is_event_paid_capable(:'eventFreeToPaidID'::uuid),
    true,
    'Should persist paid capability after a free-to-paid update'
);

-- Should preserve a code omitted by the deferred legacy form.
select is(
    (select venue_state_code from event where event_id = :'eventFreeToPaidID'::uuid),
    'CA',
    'Should preserve a stored venue state code when unchanged legacy fields omit it'
);

-- Should reject a paid update validated against a stale sponsor
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'group1ID',
        :'eventFreeToPaidID',
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_stale',
                    'seller_display_name', 'Stale Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_stale',
                    'seller_display_name', 'Stale Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Free event used for paid transition checks',
            'kind_id', 'in-person',
            'name', 'Free To Paid',
            'payment_currency_code', 'USD',
            'timezone', 'UTC',
            'venue_address', '456 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a paid update validated against a stale sponsor'
);

-- Should report no paid notification transition for a paid-to-free update
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventPaidToFreeID'::uuid,
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Paid event used for free transition checks',
            'kind_id', 'virtual',
            'name', 'Paid To Free',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventPaidToFreeTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 0,
                            'event_ticket_price_window_id', :'eventPaidToFreePriceWindowID'
                        )
                    ),
                    'seats_total', 100,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC'
        ),
        null::jsonb,
        'stripe'
    ),
    false,
    'Should report no paid notification transition for a paid-to-free update'
);

-- Should persist free capability after a paid-to-free update
select is(
    is_event_paid_capable(:'eventPaidToFreeID'::uuid),
    false,
    'Should persist free capability after a paid-to-free update'
);

-- Should report no paid notification transition for a paid-to-paid update
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventPaidToPaidID'::uuid,
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Paid event used for paid edit checks',
            'kind_id', 'in-person',
            'name', 'Paid To Paid',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventPaidToPaidTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 1800,
                            'event_ticket_price_window_id', :'eventPaidToPaidPriceWindowID'
                        )
                    ),
                    'seats_total', 100,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        ),
        null::jsonb,
        'stripe'
    ),
    false,
    'Should report no paid notification transition for a paid-to-paid update'
);

-- Should persist paid capability after a paid-to-paid update
select is(
    is_event_paid_capable(:'eventPaidToPaidID'::uuid),
    true,
    'Should persist paid capability after a paid-to-paid update'
);

-- Should report a paid notification transition when a free test event is promoted with paid tickets
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventTestFreeToPaidID'::uuid,
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Free test event promoted while adding paid tickets',
            'kind_id', 'in-person',
            'name', 'Test Free To Paid',
            'payment_currency_code', 'USD',
            'test_event', false,
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventTestFreeToPaidTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 1500,
                            'event_ticket_price_window_id', :'eventTestFreeToPaidPriceWindowID'
                        )
                    ),
                    'seats_total', 100,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        ),
        null::jsonb,
        'stripe'
    ),
    true,
    'Should report a paid notification transition when a free test event is promoted with paid tickets'
);

-- Should persist a non-test paid state after promoting a free test event with paid tickets
select is(
    (
        select jsonb_build_object(
            'paid_capable', is_event_paid_capable(e.event_id),
            'test_event', e.test_event
        )
        from event e
        where e.event_id = :'eventTestFreeToPaidID'::uuid
    ),
    '{"paid_capable": true, "test_event": false}'::jsonb,
    'Should persist a non-test paid state after promoting a free test event with paid tickets'
);

-- Should report a paid notification transition when a paid test event is promoted
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventTestPaidToLiveID'::uuid,
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Paid test event promoted without changing tickets',
            'kind_id', 'in-person',
            'name', 'Test Paid To Live',
            'test_event', false,
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        ),
        null::jsonb,
        'stripe'
    ),
    true,
    'Should report a paid notification transition when a paid test event is promoted'
);

-- Should persist a non-test paid state after promoting a paid test event
select is(
    (
        select jsonb_build_object(
            'paid_capable', is_event_paid_capable(e.event_id),
            'test_event', e.test_event
        )
        from event e
        where e.event_id = :'eventTestPaidToLiveID'::uuid
    ),
    '{"paid_capable": true, "test_event": false}'::jsonb,
    'Should persist a non-test paid state after promoting a paid test event'
);

-- Should report no paid notification transition while a paid event remains a test event
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventTestPaidToTestID'::uuid,
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Paid test event that remains a test event',
            'kind_id', 'in-person',
            'name', 'Test Paid To Test',
            'test_event', true,
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        ),
        null::jsonb,
        'stripe'
    ),
    false,
    'Should report no paid notification transition while a paid event remains a test event'
);

-- Should persist the paid test state when the event remains a test event
select is(
    (
        select jsonb_build_object(
            'paid_capable', is_event_paid_capable(e.event_id),
            'test_event', e.test_event
        )
        from event e
        where e.event_id = :'eventTestPaidToTestID'::uuid
    ),
    '{"paid_capable": true, "test_event": true}'::jsonb,
    'Should persist the paid test state when the event remains a test event'
);

-- Should initialize meeting flags for requested event without sessions
select is(
    (
        select jsonb_build_object(
            'meeting_requested', meeting_requested,
            'meeting_in_sync', meeting_in_sync
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "meeting_requested": true,
        "meeting_in_sync": false
    }'::jsonb,
    'Meeting flags are initialized for requested event without sessions'
);

-- Should update all fields (excluding sessions) with full payload
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event1ID',
        jsonb_build_object(
            'banner_url', 'https://example.com/new-banner.jpg',
            'capacity', 200,
            'category_id', :'category1ID',
            'description', 'Fully updated description',
            'description_short', 'Updated short description',
            'ends_at', '2030-02-01T16:00:00',
            'hosts', jsonb_build_array(:'user2ID', :'user3ID'),
            'kind_id', 'hybrid',
            'logo_url', 'https://example.com/new-logo.png',
            'luma_url', 'https://luma.com/new-event',
            'meeting_hosts', jsonb_build_array('althost1@example.com', 'althost2@example.com'),
            'meeting_join_instructions', 'Use the event ticket name when joining.',
            'meeting_join_url', 'https://youtube.com/new-live',
            'meeting_recording_url', 'https://youtube.com/new-recording',
            'meeting_requested', false,
            'meetup_url', 'https://meetup.com/new-event',
            'name', 'Fully Updated Event',
            'photos_urls', jsonb_build_array(
                'https://example.com/new-photo1.jpg',
                'https://example.com/new-photo2.jpg'
            ),
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'description', 'This is an updated session',
                    'ends_at', '2030-02-01T15:30:00',
                    'kind', 'virtual',
                    'meeting_hosts', jsonb_build_array('session-althost@example.com'),
                    'meeting_provider_id', 'zoom',
                    'meeting_requested', true,
                    'name', 'Updated Session',
                    'speakers', jsonb_build_array(
                        jsonb_build_object(
                            'featured', true,
                            'user_id', :'user2ID'
                        )
                    ),
                    'starts_at', '2030-02-01T14:30:00'
                )
            ),
            'speakers', jsonb_build_array(
                jsonb_build_object(
                    'featured', true,
                    'user_id', :'user2ID'
                ),
                jsonb_build_object(
                    'featured', false,
                    'user_id', :'user3ID'
                )
            ),
            'sponsors', jsonb_build_array(
                jsonb_build_object(
                    'group_sponsor_id', :'sponsorNewID',
                    'level', 'Platinum'
                )
            ),
            'starts_at', '2030-02-01T14:00:00',
            'tags', jsonb_build_array('updated', 'event', 'tags'),
            'test_event', true,
            'timezone', 'Asia/Tokyo',
            'venue_address', ' 456 New St ',
            'venue_city', ' Tokyo ',
            'venue_country_code', ' JP ',
            'venue_country_name', ' Japan ',
            'venue_name', ' New Venue ',
            'venue_state_code', ' tk ',
            'venue_state_name', ' Tokyo ',
            'venue_zip_code', ' 100-0001 '
        )
    ),
    'Should update all fields (excluding sessions) with full payload'
);

-- Check event fields except sessions
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'cohosts' - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions' - 'ticket_types'
    )),
    '{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Conference",
        "description": "Fully updated description",
        "kind": "hybrid",
        "labels": [],
        "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
        "meeting_in_sync": false,
        "meeting_requested": false,
        "name": "Fully Updated Event",
        "published": false,
        "slug": "def5678",
        "timezone": "Asia/Tokyo",
        "test_event": true,
        "attendee_approval_required": false,
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 100,
        "remaining_capacity": 100,
        "seller_display_name": "Update Event Fiscal Sponsor",
        "description_short": "Updated short description",
        "starts_at": 1896152400,
        "ends_at": 1896159600,
        "logo_url": "https://example.com/new-logo.png",
        "luma_url": "https://luma.com/new-event",
        "meeting_join_instructions": "Use the event ticket name when joining.",
        "meeting_join_url": "https://youtube.com/new-live",
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "meeting_recording_url": "https://youtube.com/new-recording",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "registration_questions": [],
        "registration_questions_locked": false,
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "tags": ["updated", "event", "tags"],
        "manual_tax_rate_ids": [],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_country_code": "JP",
        "venue_country_name": "Japan",
        "venue_name": "New Venue",
        "venue_state_code": "TK",
        "venue_state_name": "Tokyo",
        "venue_zip_code": "100-0001",
        "waitlist_count": 0,
        "waitlist_enabled": false
    }'::jsonb || jsonb_build_object(
        'hosts', jsonb_build_array(
            jsonb_build_object('name', 'Host Two', 'user_id', :'user2ID', 'username', 'host2-update-event'),
            jsonb_build_object('name', 'Speaker One', 'user_id', :'user3ID', 'username', 'speaker1-update-event')
        ),
        'speakers', jsonb_build_array(
            jsonb_build_object('featured', true, 'name', 'Host Two', 'user_id', :'user2ID', 'username', 'host2-update-event'),
            jsonb_build_object('featured', false, 'name', 'Speaker One', 'user_id', :'user3ID', 'username', 'speaker1-update-event')
        ),
        'sponsors', jsonb_build_array(
            jsonb_build_object(
                'group_sponsor_id', :'sponsorNewID',
                'level', 'Platinum',
                'logo_url', 'https://example.com/newsponsor.png',
                'name', 'NewSponsor Inc',
                'website_url', 'https://newsponsor.com'
            )
        )
    ),
    'Should update all fields (excluding sessions)'
);

-- Should contain expected session rows (ignoring session_id)
select ok(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb->'sessions'->'2030-02-01'
    ) @>
        jsonb_build_array(
            jsonb_build_object(
                'description', 'This is an updated session',
                'ends_at', 1896157800,
                'kind', 'virtual',
                'meeting_hosts', jsonb_build_array('session-althost@example.com'),
                'meeting_provider', 'zoom',
                'meeting_requested', true,
                'name', 'Updated Session',
                'speakers', jsonb_build_array(
                    jsonb_build_object(
                        'featured', true,
                        'name', 'Host Two',
                        'user_id', :'user2ID',
                        'username', 'host2-update-event'
                    )
                ),
                'starts_at', 1896154200
            )
        )
    ),
    'Sessions contain expected rows (ignoring session_id)'
);

-- Should set meeting_in_sync=false when meeting disabled to trigger deletion
select is(
    (
        select jsonb_build_object(
            'event', jsonb_build_object(
                'meeting_requested', meeting_requested,
                'meeting_in_sync', meeting_in_sync
            ),
            'session', (
                select jsonb_build_object(
                    'meeting_requested', meeting_requested,
                    'meeting_in_sync', meeting_in_sync
                )
                from session
                where event_id = :'event1ID'::uuid
            )
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "event": {
            "meeting_requested": false,
            "meeting_in_sync": false
        },
        "session": {
            "meeting_requested": true,
            "meeting_in_sync": false
        }
    }'::jsonb,
    'Should set meeting_in_sync=false when meeting disabled to trigger deletion'
);

-- Should desync a session meeting when only the event hosts change
select lives_ok(
    format(
        $$select update_event(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'user1ID',
        :'group1ID',
        :'eventSessionHostsID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Session hosts event',
            'ends_at', '2030-03-01T12:00:00',
            'hosts', jsonb_build_array(:'user2ID'),
            'kind_id', 'virtual',
            'name', 'Session Hosts Event',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'ends_at', '2030-03-01T11:00:00',
                    'kind', 'virtual',
                    'meeting_provider_id', 'zoom',
                    'meeting_requested', true,
                    'name', 'Hosted Session',
                    'session_id', :'sessionHostsID',
                    'starts_at', '2030-03-01T10:30:00'
                )
            ),
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should desync a session meeting when only the event hosts change'
);

-- Should mark the unchanged session out of sync after the host change
select is(
    (select meeting_in_sync from session where session_id = :'sessionHostsID'::uuid),
    false,
    'Should mark the unchanged session out of sync after the host change'
);

-- Should keep labels when the payload omits labels
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event12ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'cfs_description', 'Initial CFS description',
            'cfs_enabled', true,
            'cfs_ends_at', '2030-01-05T00:00:00',
            'cfs_starts_at', '2029-12-20T00:00:00',
            'description', 'Event seeded for labels update tests',
            'ends_at', '2030-01-15T12:00:00',
            'kind_id', 'virtual',
            'name', 'Event With Labels',
            'starts_at', '2030-01-15T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should keep labels when the payload omits labels'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'event12ID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text), (%L::uuid, %L::text, %L::text)$$,
        :'label1ID', 'track / backend', '#CCFBF1',
        :'label2ID', 'track / frontend', '#FEE2E2'
    ),
    'Should leave labels untouched when the payload omits labels'
);

-- Should keep session links when renaming labels
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event18ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'cfs_description', 'Updated CFS description',
            'cfs_enabled', true,
            'cfs_ends_at', '2030-01-07T00:00:00',
            'cfs_starts_at', '2029-12-22T00:00:00',
            'description', 'Event seeded for labels upsert tests',
            'ends_at', '2030-01-15T12:00:00',
            'kind_id', 'virtual',
            'labels', jsonb_build_array(
                jsonb_build_object(
                    'color', '#DBEAFE',
                    'event_label_id', :'label3ID',
                    'is_new', false,
                    'name', 'track / ai + ml'
                ),
                jsonb_build_object(
                    'color', '#FEE2E2',
                    'event_label_id', :'label5ID',
                    'is_new', true,
                    'name', 'track / web'
                )
            ),
            'name', 'Event With Labels For Upsert',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'virtual',
                    'name', 'Renamed Label Session',
                    'session_id', :'sessionLabelRenameID',
                    'starts_at', '2030-01-15T10:00:00'
                )
            ),
            'starts_at', '2030-01-15T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should keep session links when renaming labels'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'event18ID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text), (%L::uuid, %L::text, %L::text)$$,
        :'label3ID', 'track / ai + ml', '#DBEAFE',
        :'label5ID', 'track / web', '#FEE2E2'
    ),
    'Should rename, add and prune labels by identifier'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid$$,
        :'sessionLabelRenameID'
    ),
    format($$values (%L::uuid)$$, :'label3ID'),
    'Should keep sessions linked to renamed labels'
);
select is(
    get_event_full(
        :'community1ID'::uuid,
        :'group1ID'::uuid,
        :'event18ID'::uuid
    )::jsonb->'labels',
    jsonb_build_array(
        jsonb_build_object(
            'color', '#DBEAFE',
            'event_label_id', :'label3ID',
            'name', 'track / ai + ml'
        ),
        jsonb_build_object(
            'color', '#FEE2E2',
            'event_label_id', :'label5ID',
            'name', 'track / web'
        )
    ),
    'Should return updated labels in the event payload'
);

-- Should reject a stale label identifier
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventLabelStaleID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for stale label tests',
            'ends_at', '2030-01-15T12:00:00',
            'kind_id', 'virtual',
            'labels', jsonb_build_array(
                jsonb_build_object(
                    'color', '#CCFBF1',
                    'event_label_id', :'labelStaleMissingID',
                    'is_new', false,
                    'name', 'track / stale'
                )
            ),
            'name', 'Event With Stale Label',
            'starts_at', '2030-01-15T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'event label not found for event',
    'Should reject a stale label identifier'
);

-- Should reject removing a label still referenced by a session
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventLabelRemovedID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated removed label event',
            'ends_at', '2030-01-15T12:00:00',
            'kind_id', 'virtual',
            'labels', '[]'::jsonb,
            'name', 'Event With Removed Label Updated',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'virtual',
                    'label_ids', jsonb_build_array(:'labelRemovedID'),
                    'name', 'Removed Label Session',
                    'session_id', :'sessionLabelRemovedID',
                    'starts_at', '2030-01-15T10:00:00'
                )
            ),
            'starts_at', '2030-01-15T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'invalid event labels',
    'Should reject removing a label still referenced by a session'
);

-- Should keep organizers when the payload omits them
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventOrganizersKeptID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for kept organizers tests',
            'kind_id', 'in-person',
            'name', 'Event With Kept Organizers',
            'timezone', 'UTC'
        )
    ),
    'Should keep organizers when the payload omits them'
);
select results_eq(
    format(
        $$
            select user_id, "order"
            from event_organizer
            where event_id = %L::uuid
            order by "order"
        $$,
        :'eventOrganizersKeptID'
    ),
    format(
        $$values (%L::uuid, 1), (%L::uuid, 2)$$,
        :'user3ID',
        :'user2ID'
    ),
    'Should leave organizers untouched when the payload omits them'
);

-- Should keep organizers independent of later team changes
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventOrganizersTeamID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for team change organizers tests',
            'kind_id', 'in-person',
            'name', 'Event With Team Organizers',
            'timezone', 'UTC'
        )
    ),
    'Should keep organizers independent of later team changes'
);
select results_eq(
    format(
        $$
            select user_id, "order"
            from event_organizer
            where event_id = %L::uuid
            order by "order"
        $$,
        :'eventOrganizersTeamID'
    ),
    format($$values (%L::uuid, 1)$$, :'user1ID'),
    'Should keep stored organizers instead of the current group team'
);

-- Should reject an invalid organizers payload
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventOrganizersRejectedID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for rejected organizers tests',
            'kind_id', 'in-person',
            'name', 'Event With Rejected Organizers',
            'organizers', jsonb_build_object('user_id', :'user2ID'),
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject an invalid organizers payload'
);

-- Should reject an organizer outside the group team
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventOrganizersRejectedID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for rejected organizers tests',
            'kind_id', 'in-person',
            'name', 'Event With Rejected Organizers',
            'organizers', jsonb_build_array(:'user1ID', :'user2ID'),
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'organizer is not a group team member',
    'Should reject an organizer outside the group team'
);

-- Should replace organizers when submitted
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventOrganizersReplacedID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for replaced organizers tests',
            'kind_id', 'in-person',
            'name', 'Event With Replaced Organizers',
            'organizers', jsonb_build_array(:'teamMemberID', :'user1ID'),
            'timezone', 'UTC'
        )
    ),
    'Should replace organizers when submitted'
);
select results_eq(
    format(
        $$
            select user_id, "order"
            from event_organizer
            where event_id = %L::uuid
            order by "order"
        $$,
        :'eventOrganizersReplacedID'
    ),
    format(
        $$values (%L::uuid, 1), (%L::uuid, 2)$$,
        :'teamMemberID',
        :'user1ID'
    ),
    'Should store submitted organizers in submitted order'
);

-- Should throw error when group_id does not match
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'groupExternalID',
        :'event1ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'This should fail',
            'kind_id', 'in-person',
            'name', 'Won''t Work',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should throw error when the group does not exist
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'missingGroupID',
        :'event1ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'This should fail',
            'kind_id', 'in-person',
            'name', 'Won''t Work',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'event not found or inactive',
    'Should throw error when the group does not exist'
);

-- Should throw error when updating cancelled event
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event4ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'This should fail',
            'kind_id', 'in-person',
            'name', 'Try to Update Canceled',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'event not found or inactive',
    'Should throw error when event is canceled'
);

-- Should throw error for invalid host user_id (FK violation)
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event1ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'hosts', jsonb_build_array(:'missingUserID'),
            'kind_id', 'in-person',
            'name', 'Event with Invalid Host',
            'timezone', 'UTC'
        )
    ),
    '23503',
    null,
    'Should throw error when host user_id does not exist'
);

-- Should throw error for invalid speaker user_id (FK violation)
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event1ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'kind_id', 'in-person',
            'name', 'Event with Invalid Speaker',
            'speakers', jsonb_build_array(
                jsonb_build_object(
                    'featured', false,
                    'user_id', :'missingUserID'
                )
            ),
            'timezone', 'UTC'
        )
    ),
    '23503',
    null,
    'Should throw error when speaker user_id does not exist'
);

-- Should evaluate reminder immediately when published event starts within 24 hours
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event10ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Reminder evaluation check',
            'ends_at', to_char(current_timestamp + interval '14 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'event_reminder_enabled', true,
            'kind_id', 'virtual',
            'name', 'Reminder Event Updated',
            'starts_at', to_char(current_timestamp + interval '12 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    ),
    'Should evaluate reminder immediately when published event starts within 24 hours'
);

-- Should mark reminder as evaluated for the updated start date
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'event10ID'),
    (select starts_at from event where event_id = :'event10ID'),
    'Should mark reminder as evaluated for the updated start date'
);

-- Should not evaluate reminder when starts_at remains unchanged inside 24 hours
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event11ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Reminder regression check',
            'ends_at', to_char(
                (select ends_at from event where event_id = :'event11ID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'event_reminder_enabled', true,
            'kind_id', 'virtual',
            'name', 'Reminder Event Soon Updated',
            'starts_at', to_char(
                (select starts_at from event where event_id = :'event11ID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'timezone', 'UTC'
        )
    ),
    'Should not evaluate reminder when starts_at remains unchanged inside 24 hours'
);

-- Should keep reminder unevaluated when starts_at remains unchanged inside 24 hours
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'event11ID'),
    null::timestamptz,
    'Should keep reminder unevaluated when starts_at remains unchanged inside 24 hours'
);

-- Should not promote waitlist entries after an open-only registration window reaches the event start
select update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventWaitlistWindowID'::uuid,
        jsonb_build_object(
            'name', 'Open Only Waitlist Event Updated',
            'description', 'Event seeded for registration window waitlist update tests',
            'timezone', 'UTC',
            'category_id', :'category1ID',
            'kind_id', 'in-person',
            'capacity', 2,
            'starts_at', to_char(
                (
                    select starts_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'ends_at', to_char(
                (
                    select ends_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'registration_starts_at', to_char(
                (
                    select registration_starts_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'waitlist_enabled', true
        )
    );

-- Should not promote waitlist entries after an open-only registration window reaches the event start
select pass(
    'Should not promote waitlist entries after an open-only registration window reaches the event start'
);

-- Should keep waitlist entries queued after an open-only registration window reaches the event start
select is(
    (
        select jsonb_agg(user_id order by created_at asc, user_id asc)
        from event_waitlist
        where event_id = :'eventWaitlistWindowID'::uuid
    ),
    jsonb_build_array(:'waitlistUserID'),
    'Should keep waitlist entries queued after an open-only registration window reaches the event start'
);

-- Should reject a persisted external URL when the group toggle is off
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'group1ID',
        :'eventExternalClearID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Paid event that still carries leftover external fields',
            'external_payment_url', 'https://pay.example.test/leftover',
            'external_payment_window_hours', 48,
            'kind_id', 'in-person',
            'name', 'External Clear Event',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalClearTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'eventExternalClearPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_zip_code', '94105'
        )
    ),
    'OCG01',
    'external payments are not available for this event',
    'Should reject a persisted external URL when the group toggle is off'
);

-- Should reject a persisted external URL when the group country is delisted
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'groupDelistedID',
        :'eventExternalDelistedID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Paid event whose group country is no longer allowlisted',
            'external_payment_url', 'https://pay.example.test/delisted',
            'external_payment_window_hours', 48,
            'kind_id', 'in-person',
            'name', 'External Delisted Event',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalDelistedTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'eventExternalDelistedPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_zip_code', '94105'
        )
    ),
    'OCG01',
    'external payments are not available for this event',
    'Should reject a persisted external URL when the group country is delisted'
);

-- Should clear a persisted external URL onto Stripe when a recipient is ready
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'group1ID',
        :'eventExternalClearID',
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Paid event that still carries leftover external fields',
            'external_payment_instructions', '',
            'external_payment_url', '',
            'external_payment_window_hours', '',
            'kind_id', 'in-person',
            'name', 'External Clear Event',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalClearTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'eventExternalClearPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_zip_code', '94105'
        )
    ),
    'Should clear a persisted external URL onto Stripe when a recipient is ready'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_instructions', external_payment_instructions,
            'external_payment_url', external_payment_url,
            'external_payment_window_hours', external_payment_window_hours
        )
        from event
        where event_id = :'eventExternalClearID'::uuid
    ),
    '{
        "external_payment_instructions": null,
        "external_payment_url": null,
        "external_payment_window_hours": null
    }'::jsonb,
    'Should clear a persisted external URL onto Stripe when a recipient is ready'
);

-- Should reject clearing an external payment URL while a pending external purchase exists
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'group1ID',
        :'eventExternalPendingClearID',
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_event',
                    'seller_display_name', 'Update Event Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Paid event whose pending external hold keeps the live URL',
            'external_payment_instructions', '',
            'external_payment_url', '',
            'external_payment_window_hours', '',
            'kind_id', 'in-person',
            'name', 'External Pending Clear Event',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalPendingClearTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'eventExternalPendingClearPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_zip_code', '94105'
        )
    ),
    'OCG01',
    'external payment url cannot be cleared while pending external purchases exist',
    'Should reject clearing an external payment URL while a pending external purchase exists'
);

-- Should reject clearing an external URL when Stripe is not ready
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'groupDelistedID',
        :'eventExternalDelistedID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Paid event whose group country is no longer allowlisted',
            'external_payment_url', '',
            'kind_id', 'in-person',
            'name', 'External Delisted Event',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalDelistedTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'eventExternalDelistedPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_zip_code', '94105'
        )
    ),
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject clearing an external URL when Stripe is not ready'
);

-- Should reject updating a paid external event without a payment URL
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'groupExternalID',
        :'eventExternalStripeID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Published Stripe event waiting for an external URL',
            'kind_id', 'in-person',
            'name', 'External Stripe Event',
            'payment_currency_code', 'KRW',
            'starts_at', to_char(
                (select starts_at from event where event_id = :'eventExternalStripeID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalStripeTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 5500,
                            'event_ticket_price_window_id', :'eventExternalStripePriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '1 Test Street',
            'venue_city', 'Seoul',
            'venue_country_code', 'KR',
            'venue_name', 'Test Hall',
            'venue_zip_code', '00000'
        )
    ),
    'OCG01',
    'paid-capable events require a valid external payment url',
    'Should reject updating a paid external event without a payment URL'
);

-- Should reject a paid update on Stripe while the selected external rail lacks its payee name
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, 'stripe')$$,
        :'groupExternalNamelessID',
        :'eventExternalNamelessID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Free event in a nameless external group',
            'kind_id', 'in-person',
            'name', 'Nameless External Group Event',
            'payment_currency_code', 'KRW',
            'starts_at', to_char(
                (select starts_at from event where event_id = :'eventExternalNamelessID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalNamelessTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 5500,
                            'event_ticket_price_window_id', :'eventExternalNamelessPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '1 Test Street',
            'venue_city', 'Seoul',
            'venue_country_code', 'KR',
            'venue_name', 'Test Hall',
            'venue_zip_code', '00000'
        )
    ),
    'OCG01',
    'external payments require the legal name of the organization collecting payments',
    'Should reject a paid update on Stripe while the selected external rail lacks its payee name'
);

-- Should mark a published Stripe event external when this update sets a payment URL
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, null)$$,
        :'groupExternalID',
        :'eventExternalStripeID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Published Stripe event waiting for an external URL',
            'external_payment_url', 'https://pay.example.test/converted',
            'external_payment_window_hours', 120,
            'kind_id', 'in-person',
            'name', 'External Stripe Event',
            'payment_currency_code', 'KRW',
            'starts_at', to_char(
                (select starts_at from event where event_id = :'eventExternalStripeID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'tax_behavior', 'exclusive',
            'tax_calculation_mode', 'automatic',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalStripeTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 5000,
                            'event_ticket_price_window_id', :'eventExternalStripePriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '1 Test Street',
            'venue_city', 'Seoul',
            'venue_country_code', 'KR',
            'venue_name', 'Test Hall',
            'venue_zip_code', '00000'
        )
    ),
    'Should mark a published Stripe event external when this update sets a payment URL'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_url', external_payment_url,
            'external_payment_window_hours', external_payment_window_hours,
            'tax_behavior', tax_behavior,
            'tax_calculation_mode', tax_calculation_mode
        )
        from event
        where event_id = :'eventExternalStripeID'::uuid
    ),
    '{
        "external_payment_url": "https://pay.example.test/converted",
        "external_payment_window_hours": 120,
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "none"
    }'::jsonb,
    'Should persist external URL and normalized tax after converting a Stripe event'
);

-- Should normalize tax and accept an overridden window on an external paid update
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, null)$$,
        :'groupExternalID',
        :'eventExternalPaidID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'External event updated for window and tax normalization',
            'external_payment_url', 'https://pay.example.test/update',
            'external_payment_window_hours', 96,
            'kind_id', 'in-person',
            'name', 'External Paid Event',
            'payment_currency_code', 'KRW',
            'tax_behavior', 'exclusive',
            'tax_calculation_mode', 'automatic',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalPaidTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 5000,
                            'event_ticket_price_window_id', :'eventExternalPaidPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '1 Test Street',
            'venue_city', 'Seoul',
            'venue_country_code', 'KR',
            'venue_name', 'Test Hall',
            'venue_zip_code', '00000'
        )
    ),
    'Should normalize tax and accept an overridden window on an external paid update'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_window_hours', external_payment_window_hours,
            'tax_behavior', tax_behavior,
            'tax_calculation_mode', tax_calculation_mode
        )
        from event
        where event_id = :'eventExternalPaidID'::uuid
    ),
    '{
        "external_payment_window_hours": 96,
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "none"
    }'::jsonb,
    'Should persist normalized tax and the overridden external window'
);

-- Should reject an external payment window above the configured maximum on update
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, null)$$,
        :'groupExternalID',
        :'eventExternalPaidID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'External event updated for window and tax normalization',
            'external_payment_url', 'https://pay.example.test/update',
            'external_payment_window_hours', 337,
            'kind_id', 'in-person',
            'name', 'External Paid Event',
            'payment_currency_code', 'KRW',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalPaidTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 5000,
                            'event_ticket_price_window_id', :'eventExternalPaidPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '1 Test Street',
            'venue_city', 'Seoul',
            'venue_country_code', 'KR',
            'venue_name', 'Test Hall',
            'venue_zip_code', '00000'
        )
    ),
    'OCG01',
    'external payment window exceeds the configured maximum',
    'Should reject an external payment window above the configured maximum on update'
);

-- Should reject moving a paid external event venue outside the group country
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null::jsonb, null)$$,
        :'groupExternalID',
        :'eventExternalPaidID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'External event updated for window and tax normalization',
            'external_payment_url', 'https://pay.example.test/update',
            'kind_id', 'in-person',
            'name', 'External Paid Event',
            'payment_currency_code', 'KRW',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'eventExternalPaidTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 5000,
                            'event_ticket_price_window_id', :'eventExternalPaidPriceWindowID'
                        )
                    ),
                    'seats_total', 50,
                    'title', 'General Admission'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '1 Test Street',
            'venue_city', 'Tokyo',
            'venue_country_code', 'JP',
            'venue_name', 'Test Hall',
            'venue_zip_code', '100-0001'
        )
    ),
    'OCG01',
    'external paid events require a venue in the group country',
    'Should reject moving a paid external event venue outside the group country'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
