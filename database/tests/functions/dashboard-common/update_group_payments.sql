-- Tests updating group payment recipients, fiscal sponsors and external payments.
-- Split from update_group.sql because the payment scenarios and their seed
-- would make the base file unwieldy.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(63);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '1c040000-0000-0000-0000-00000000006c'
\set communityID '1c040000-0000-0000-0000-000000000001'
\set eventAutomaticTaxID '1c040000-0000-0000-0000-00000000001c'
\set eventCategoryID '1c040000-0000-0000-0000-000000000002'
\set eventDelistedID '1c040000-0000-0000-0000-000000000043'
\set eventDelistedReplaceID '1c040000-0000-0000-0000-000000000050'
\set eventDisablePastID '1c040000-0000-0000-0000-000000000044'
\set eventDisableUnpublishedID '1c040000-0000-0000-0000-000000000045'
\set eventEnableAbroadID '1c040000-0000-0000-0000-00000000003c'
\set eventExternalPaidID '1c040000-0000-0000-0000-000000000038'
\set eventFreeID '1c040000-0000-0000-0000-000000000014'
\set eventID '1c040000-0000-0000-0000-000000000003'
\set eventRecipientClearRejectID '1c040000-0000-0000-0000-000000000064'
\set eventSwapRecipientID '1c040000-0000-0000-0000-000000000069'
\set eventUnpublishedID '1c040000-0000-0000-0000-000000000004'
\set eventVenueCountryID '1c040000-0000-0000-0000-00000000003b'
\set group4ID '1c040000-0000-0000-0000-000000000007'
\set group5ID '1c040000-0000-0000-0000-000000000008'
\set group6ID '1c040000-0000-0000-0000-000000000015'
\set groupAutomaticTaxID '1c040000-0000-0000-0000-00000000001d'
\set groupBlockedClearID '1c040000-0000-0000-0000-000000000052'
\set groupBlockedFirstID '1c040000-0000-0000-0000-000000000051'
\set groupBlockedReplaceID '1c040000-0000-0000-0000-000000000053'
\set groupCategoryID '1c040000-0000-0000-0000-000000000009'
\set groupDelistedID '1c040000-0000-0000-0000-000000000036'
\set groupDisableID '1c040000-0000-0000-0000-000000000030'
\set groupEnableAbroadID '1c040000-0000-0000-0000-00000000003e'
\set groupEnableID '1c040000-0000-0000-0000-000000000031'
\set groupExternalDelistedID '1c040000-0000-0000-0000-000000000054'
\set groupExternalPaidID '1c040000-0000-0000-0000-000000000037'
\set groupFinalCountryID '1c040000-0000-0000-0000-000000000032'
\set groupMoveCountryDisableID '1c040000-0000-0000-0000-000000000033'
\set groupMoveCountryID '1c040000-0000-0000-0000-000000000034'
\set groupMoveKeepRecipientID '1c040000-0000-0000-0000-000000000055'
\set groupMoveOffAllowlistID '1c040000-0000-0000-0000-000000000056'
\set groupMoveOntoAllowlistID '1c040000-0000-0000-0000-000000000057'
\set groupNamelessEnableID '1c040000-0000-0000-0000-00000000005a'
\set groupPayeeDisableID '1c040000-0000-0000-0000-000000000062'
\set groupPayeeID '1c040000-0000-0000-0000-00000000005b'
\set groupPayeePreserveID '1c040000-0000-0000-0000-000000000061'
\set groupRecipientClearRejectID '1c040000-0000-0000-0000-000000000063'
\set groupRejectEnableID '1c040000-0000-0000-0000-000000000035'
\set groupSwapRecipientID '1c040000-0000-0000-0000-000000000067'
\set groupVenueCountryID '1c040000-0000-0000-0000-00000000003d'
\set priceWindowAutomaticTaxID '1c040000-0000-0000-0000-00000000001e'
\set priceWindowDelistedID '1c040000-0000-0000-0000-000000000046'
\set priceWindowDelistedReplaceID '1c040000-0000-0000-0000-000000000058'
\set priceWindowDisablePastID '1c040000-0000-0000-0000-000000000047'
\set priceWindowDisableUnpublishedID '1c040000-0000-0000-0000-000000000048'
\set priceWindowEnableAbroadID '1c040000-0000-0000-0000-000000000042'
\set priceWindowExternalPaidID '1c040000-0000-0000-0000-00000000003a'
\set priceWindowFreeID '1c040000-0000-0000-0000-000000000017'
\set priceWindowID '1c040000-0000-0000-0000-000000000016'
\set priceWindowRecipientClearRejectID '1c040000-0000-0000-0000-000000000066'
\set priceWindowSwapRecipientID '1c040000-0000-0000-0000-00000000006b'
\set priceWindowUnpublishedID '1c040000-0000-0000-0000-000000000018'
\set priceWindowVenueCountryID '1c040000-0000-0000-0000-000000000041'
\set ticketTypeAutomaticTaxID '1c040000-0000-0000-0000-00000000001f'
\set ticketTypeDelistedID '1c040000-0000-0000-0000-000000000049'
\set ticketTypeDelistedReplaceID '1c040000-0000-0000-0000-000000000059'
\set ticketTypeDisablePastID '1c040000-0000-0000-0000-00000000004a'
\set ticketTypeDisableUnpublishedID '1c040000-0000-0000-0000-00000000004b'
\set ticketTypeEnableAbroadID '1c040000-0000-0000-0000-000000000040'
\set ticketTypeExternalPaidID '1c040000-0000-0000-0000-000000000039'
\set ticketTypeFreeID '1c040000-0000-0000-0000-000000000019'
\set ticketTypeID '1c040000-0000-0000-0000-00000000000e'
\set ticketTypeRecipientClearRejectID '1c040000-0000-0000-0000-000000000065'
\set ticketTypeSwapRecipientID '1c040000-0000-0000-0000-00000000006a'
\set ticketTypeUnpublishedID '1c040000-0000-0000-0000-00000000000f'
\set ticketTypeVenueCountryID '1c040000-0000-0000-0000-00000000003f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Operator config allowlisting external payments for Japan and Korea
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['JP', 'KR']::text[],
    72,
    336
);

-- User recorded as the actor in the payment audit rows
select fx_user(:'actorUserID', jsonb_build_object('username', 'update-group-payments-audit-actor'));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group for payment recipient audit coverage
select fx_group(:'group4ID'::uuid, :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'Payment recipient audit coverage',
    'name', 'Group With Payment Recipient'
));

-- Group with an unpublished ticketed event for payment recipient guards
select fx_group(:'group5ID'::uuid, :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'Unpublished ticketed event coverage',
    'name', 'Group With Unpublished Ticketed Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_456", "seller_display_name": "Existing Fiscal Sponsor"}'::jsonb
));

-- Group with a published all-zero ticketed event
select fx_group(:'group6ID'::uuid, :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'Free ticketed event coverage',
    'name', 'Group With Free Ticketed Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_free", "seller_display_name": "Free Event Fiscal Sponsor"}'::jsonb
));

-- Group with a published automatic-tax event for validation freshness checks
select fx_group(:'groupAutomaticTaxID'::uuid, :'communityID'::uuid, :'groupCategoryID'::uuid, jsonb_build_object(
    'description', 'Automatic-tax validation freshness coverage',
    'name', 'Group With Automatic Tax Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_automatic", "seller_display_name": "Existing Fiscal Sponsor"}'::jsonb
));

-- Group with a stored recipient blocked from clearing it by a published paid event
select fx_group(:'groupRecipientClearRejectID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'description', 'Payment recipient clear coverage',
    'name', 'Group With Required Recipient',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_clear_reject", "seller_display_name": "Required Fiscal Sponsor"}'::jsonb
));

-- Group with a stored recipient blocked from swapping it by a manual-tax event
select fx_group(:'groupSwapRecipientID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'description', 'Payment recipient swap coverage',
    'name', 'Group With Swap Recipient',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_123", "seller_display_name": "New Fiscal Sponsor"}'::jsonb
));

-- Enabled group whose country is no longer allowlisted despite an upcoming external event
select fx_group(:'groupDelistedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'external_payments_enabled', true,
    'name', 'External Delisted Group'
));

-- Allowlisted group disabling external payments with only past or unpublished external events
select fx_group(:'groupDisableID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Disable Group'
));

-- Allowlisted group blocked from enabling external payments by an event venue abroad
select fx_group(:'groupEnableAbroadID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'JP',
    'name', 'External Enable Abroad Group'
));

-- Allowlisted group used by the successful enable scenario
select fx_group(:'groupEnableID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'External Enable Group'
));

-- Non-allowlisted group enabled by changing country in the same update
select fx_group(:'groupFinalCountryID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'name', 'External Final Country Group'
));

-- Allowlisted enabled group that disables while leaving the allowlist
select fx_group(:'groupMoveCountryDisableID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Move Country Disable Group'
));

-- Allowlisted enabled group rejected when moving country while staying enabled
select fx_group(:'groupMoveCountryID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Move Country Group'
));

-- Allowlisted group rejected when enabling without the external payee legal name
select fx_group(:'groupNamelessEnableID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'External Nameless Enable Group'
));

-- Allowlisted enabled group disabling external payments with a stored payee legal name
select fx_group(:'groupPayeeDisableID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'Disabled Payee Co',
    'name', 'External Payee Disable Group'
));

-- Allowlisted enabled group with a stored external payee legal name
select fx_group(:'groupPayeeID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co',
    'name', 'External Payee Group'
));

-- Allowlisted enabled group keeping its payee legal name on a partial payload
select fx_group(:'groupPayeePreserveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'Preserved Payee Ltd',
    'name', 'External Payee Preserve Group'
));

-- Non-allowlisted group rejected when enabling external payments
select fx_group(:'groupRejectEnableID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'name', 'External Reject Enable Group'
));

-- Allowlisted enabled group blocked from moving country by an upcoming external event
select fx_group(:'groupVenueCountryID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Venue Country Group'
));

-- Allowlisted group whose stored recipient is cleared
select fx_group(:'groupBlockedClearID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'Blocked Clear Sponsor Group',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_blocked_clear", "seller_display_name": "Clear Fiscal Sponsor"}'::jsonb
));

-- Allowlisted group without a recipient that cannot add a first Stripe account
select fx_group(:'groupBlockedFirstID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'Blocked First Sponsor Group'
));

-- Allowlisted group with the toggle off whose stored recipient cannot be replaced
select fx_group(:'groupBlockedReplaceID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'Blocked Replace Sponsor Group',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_blocked_current", "seller_display_name": "Current Blocked Fiscal Sponsor"}'::jsonb
));

-- Enabled group in a delisted country that can still replace its recipient
select fx_group(:'groupExternalDelistedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'BR',
    'external_payments_enabled', true,
    'name', 'External Delisted Replace Group',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_delisted", "seller_display_name": "Delisted Fiscal Sponsor"}'::jsonb
));

-- Allowlisted group whose only paid event is collected outside Stripe
select fx_group(:'groupExternalPaidID'::uuid, :'communityID'::uuid, :'groupCategoryID'::uuid, jsonb_build_object(
    'country_code', 'KR',
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'External paid event recipient coverage',
    'external_payments_enabled', true,
    'name', 'Group With External Paid Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_external", "seller_display_name": "External Event Fiscal Sponsor"}'::jsonb
));

-- Non-allowlisted group moving onto the allowlist while keeping its recipient
select fx_group(:'groupMoveKeepRecipientID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'name', 'Move Keep Recipient Group',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_move_keep", "seller_display_name": "Kept Fiscal Sponsor"}'::jsonb
));

-- Allowlisted group adding a first Stripe account while leaving the allowlist
select fx_group(:'groupMoveOffAllowlistID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'Move Off Allowlist Group'
));

-- Non-allowlisted group adding a first Stripe account while joining the allowlist
select fx_group(:'groupMoveOntoAllowlistID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'name', 'Move Onto Allowlist Group'
));

-- Published manual-tax paid event allowing a first fiscal sponsor
select fx_event(:'eventID'::uuid, :'group4ID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'manual_tax_rate_ids', array['txr_update_group']::text[],
    'payment_currency_code', 'USD',
    'published', true,
    'tax_calculation_mode', 'manual',
    'venue_address', '123 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_state_code', 'OR',
    'venue_state_name', 'Oregon',
    'venue_zip_code', '97201'
));

-- Unpublished manual-tax ticketed event used for payment recipient guards
select fx_event(:'eventUnpublishedID'::uuid, :'group5ID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'event_kind_id', 'virtual',
    'manual_tax_rate_ids', array['txr_draft']::text[],
    'payment_currency_code', 'USD',
    'tax_calculation_mode', 'manual'
));

-- Published all-zero ticketed event used for payment recipient guards
select fx_event(:'eventFreeID'::uuid, :'group6ID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true
));

-- Published automatic-tax event used to reject stale provider validation
select fx_event(:'eventAutomaticTaxID'::uuid, :'groupAutomaticTaxID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'event_kind_id', 'virtual',
    'name', 'Automatic Tax Event',
    'payment_currency_code', 'USD',
    'published', true
));

-- Published paid event that requires the stored recipient
select fx_event(:'eventRecipientClearRejectID'::uuid, :'groupRecipientClearRejectID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'event_kind_id', 'virtual',
    'name', 'Required Recipient Event',
    'payment_currency_code', 'USD',
    'published', true,
    'tax_calculation_mode', 'none'
));

-- Published manual-tax paid event blocking the sponsor swap
select fx_event(:'eventSwapRecipientID'::uuid, :'groupSwapRecipientID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'manual_tax_rate_ids', array['txr_update_group_swap']::text[],
    'name', 'Swap Recipient Event',
    'payment_currency_code', 'USD',
    'published', true,
    'tax_calculation_mode', 'manual',
    'venue_address', '123 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_state_code', 'OR',
    'venue_state_name', 'Oregon',
    'venue_zip_code', '97201'
));

-- Upcoming published external paid event in the delisted group
select fx_event(:'eventDelistedID'::uuid, :'groupDelistedID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/delisted',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Austin',
    'venue_country_code', 'US',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Past published external paid event that must not block disabling the toggle
select fx_event(:'eventDisablePastID'::uuid, :'groupDisableID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'ends_at', current_timestamp - interval '6 days',
    'external_payment_url', 'https://pay.example.test/disable-past',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp - interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Unpublished upcoming external paid event that must not block disabling the toggle
select fx_event(:'eventDisableUnpublishedID'::uuid, :'groupDisableID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/disable-draft',
    'payment_currency_code', 'KRW',
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Published external paid event whose venue is outside its disabled group's country
select fx_event(:'eventEnableAbroadID'::uuid, :'groupEnableAbroadID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/enable-abroad',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Published external paid event anchoring its group to the venue country
select fx_event(:'eventVenueCountryID'::uuid, :'groupVenueCountryID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/venue-country',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Upcoming published external paid event in the delisted replace group
select fx_event(:'eventDelistedReplaceID'::uuid, :'groupExternalDelistedID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/delisted-replace',
    'payment_currency_code', 'BRL',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Sao Paulo',
    'venue_country_code', 'BR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Published external paid event that must not lock the Stripe recipient
select fx_event(:'eventExternalPaidID'::uuid, :'groupExternalPaidID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/group',
    'name', 'External Paid Event',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'manual'
));

-- Ticket type for the published manual-tax event allowing a first fiscal sponsor
select fx_event_ticket_type(:'ticketTypeID'::uuid, :'eventID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'General admission'
));

-- Ticket type for the unpublished manual-tax ticketed event
select fx_event_ticket_type(:'ticketTypeUnpublishedID'::uuid, :'eventUnpublishedID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'General admission'
));

-- Ticket type for the published all-zero ticketed event
select fx_event_ticket_type(:'ticketTypeFreeID'::uuid, :'eventFreeID'::uuid, jsonb_build_object('seats_total', 50));

-- Ticket type for the published automatic-tax event
select fx_event_ticket_type(:'ticketTypeAutomaticTaxID'::uuid, :'eventAutomaticTaxID'::uuid, jsonb_build_object('seats_total', 50));

-- Ticket type for the published paid event that requires the stored recipient
select fx_event_ticket_type(:'ticketTypeRecipientClearRejectID'::uuid, :'eventRecipientClearRejectID'::uuid, jsonb_build_object('seats_total', 50));

-- Ticket type for the published manual-tax paid event blocking the sponsor swap
select fx_event_ticket_type(:'ticketTypeSwapRecipientID'::uuid, :'eventSwapRecipientID'::uuid, jsonb_build_object('seats_total', 50));

-- Ticket type for the upcoming external event in the delisted group
select fx_event_ticket_type(:'ticketTypeDelistedID'::uuid, :'eventDelistedID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the past external event in the disable group
select fx_event_ticket_type(:'ticketTypeDisablePastID'::uuid, :'eventDisablePastID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the unpublished external event in the disable group
select fx_event_ticket_type(:'ticketTypeDisableUnpublishedID'::uuid, :'eventDisableUnpublishedID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the external event held abroad
select fx_event_ticket_type(:'ticketTypeEnableAbroadID'::uuid, :'eventEnableAbroadID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the external event anchoring the venue country
select fx_event_ticket_type(:'ticketTypeVenueCountryID'::uuid, :'eventVenueCountryID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the delisted replace external event
select fx_event_ticket_type(:'ticketTypeDelistedReplaceID'::uuid, :'eventDelistedReplaceID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the published external paid event
select fx_event_ticket_type(:'ticketTypeExternalPaidID'::uuid, :'eventExternalPaidID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket price making the event allowing a first fiscal sponsor paid
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));

-- Ticket price making the unpublished manual-tax event paid
select fx_event_ticket_price_window(:'priceWindowUnpublishedID', :'ticketTypeUnpublishedID', jsonb_build_object('amount_minor', 2500));

-- Zero ticket price keeping the published ticketed event free
select fx_event_ticket_price_window(:'priceWindowFreeID', :'ticketTypeFreeID', jsonb_build_object('amount_minor', 0));

-- Ticket price making the published automatic-tax event paid
select fx_event_ticket_price_window(:'priceWindowAutomaticTaxID', :'ticketTypeAutomaticTaxID', jsonb_build_object('amount_minor', 2500));

-- Ticket price making the event that requires the stored recipient paid
select fx_event_ticket_price_window(:'priceWindowRecipientClearRejectID', :'ticketTypeRecipientClearRejectID', jsonb_build_object('amount_minor', 2500));

-- Ticket price making the event blocking the sponsor swap paid
select fx_event_ticket_price_window(:'priceWindowSwapRecipientID', :'ticketTypeSwapRecipientID', jsonb_build_object('amount_minor', 2500));

-- Ticket price making the upcoming external event in the delisted group paid
select fx_event_ticket_price_window(:'priceWindowDelistedID', :'ticketTypeDelistedID', jsonb_build_object('amount_minor', 5000));

-- Ticket price making the past external event in the disable group paid
select fx_event_ticket_price_window(:'priceWindowDisablePastID', :'ticketTypeDisablePastID', jsonb_build_object('amount_minor', 5000));

-- Ticket price making the unpublished external event in the disable group paid
select fx_event_ticket_price_window(:'priceWindowDisableUnpublishedID', :'ticketTypeDisableUnpublishedID', jsonb_build_object('amount_minor', 5000));

-- Ticket price making the external event held abroad paid
select fx_event_ticket_price_window(:'priceWindowEnableAbroadID', :'ticketTypeEnableAbroadID', jsonb_build_object('amount_minor', 5000));

-- Ticket price making the external event anchoring the venue country paid
select fx_event_ticket_price_window(:'priceWindowVenueCountryID', :'ticketTypeVenueCountryID', jsonb_build_object('amount_minor', 5000));

-- Ticket price making the delisted replace external event paid
select fx_event_ticket_price_window(:'priceWindowDelistedReplaceID', :'ticketTypeDelistedReplaceID', jsonb_build_object('amount_minor', 5000));

-- Ticket price making the published external paid event paid
select fx_event_ticket_price_window(:'priceWindowExternalPaidID', :'ticketTypeExternalPaidID', jsonb_build_object('amount_minor', 5000));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create the payment recipient audit row when the recipient changes
select lives_ok(
    format(
        $$select update_group(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient audit coverage",
            "_payment_validation": {
                "expected_payment_recipient": null,
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_123",
                    "seller_display_name": "New Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": " acct_123 ",
                "seller_display_name": " New Fiscal Sponsor "
            }
        }'::jsonb
    )$$,
        :'actorUserID',
        :'communityID',
        :'group4ID',
        :'groupCategoryID'
    ),
    'Should create the payment recipient audit row when the recipient changes'
);

-- Should create both audit rows when the payment recipient changes
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
        where group_id = %L::uuid
        order by action asc
    $$,
        :'group4ID'
    ),
    format(
        $$
        values
            (
                'group_payment_recipient_updated',
                %L::uuid,
                'update-group-payments-audit-actor'::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            ),
            (
                'group_updated',
                %L::uuid,
                'update-group-payments-audit-actor'::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            )
    $$,
        :'actorUserID',
        :'communityID',
        :'group4ID',
        :'group4ID',
        :'actorUserID',
        :'communityID',
        :'group4ID',
        :'group4ID'
    ),
    'Should create both audit rows when the payment recipient changes'
);

-- Should persist the normalized payment recipient after the update
select is(
    (select get_group_full(:'communityID'::uuid, :'group4ID'::uuid)::jsonb->'payment_recipient'),
    '{
        "provider": "stripe",
        "recipient_id": "acct_123",
        "seller_display_name": "New Fiscal Sponsor"
    }'::jsonb,
    'Should persist the normalized payment recipient after the update'
);

-- Should reject a sponsor swap that invalidates active manual-tax events
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Swap Recipient",
            "category_id": "%s",
            "description": "Payment recipient swap coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_123",
                    "seller_display_name": "New Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_replacement",
                    "seller_display_name": "Replacement Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_replacement",
                "seller_display_name": "Replacement Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupSwapRecipientID',
        :'groupCategoryID'
    ),
    'OCG01',
    'fiscal sponsor cannot be replaced while published manual-tax events are upcoming',
    'Should reject a sponsor swap that invalidates active manual-tax events'
);

-- Should reject a sponsor change validated against stale recipient state
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Unpublished Ticketed Event",
            "category_id": "%s",
            "description": "Unpublished ticketed event coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_stale",
                    "seller_display_name": "Stale Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_new",
                    "seller_display_name": "New Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_new",
                "seller_display_name": "New Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group5ID',
        :'groupCategoryID'
    ),
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a sponsor change validated against stale recipient state'
);

-- Should reject validation that missed a published automatic-tax event
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Automatic Tax Event",
            "category_id": "%s",
            "description": "Automatic-tax validation freshness coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_automatic",
                    "seller_display_name": "Existing Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_new",
                    "seller_display_name": "New Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_new",
                "seller_display_name": "New Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupAutomaticTaxID',
        :'groupCategoryID'
    ),
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject validation that missed a published automatic-tax event'
);

-- Should reject a payment recipient without an attendee-visible seller name
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient validation coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_missing_name"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group4ID',
        :'groupCategoryID'
    ),
    'OCG01',
    'payment recipient account and seller name must be provided together',
    'Should reject a payment recipient without an attendee-visible seller name'
);

-- Should reject a payment recipient account without a provider
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient validation coverage",
            "payment_recipient": {
                "recipient_id": "acct_missing_provider",
                "seller_display_name": "Missing Provider Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group4ID',
        :'groupCategoryID'
    ),
    'OCG01',
    'payment recipient account and seller name must be provided together',
    'Should reject a payment recipient account without a provider'
);

-- Should reject a seller name without a payment recipient account
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient validation coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   ",
                "seller_display_name": "Seller Without Account"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group4ID',
        :'groupCategoryID'
    ),
    'OCG01',
    'payment recipient account and seller name must be provided together',
    'Should reject a seller name without a payment recipient account'
);

-- Should reject clearing payment recipient when published ticketed events exist
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Required Recipient",
            "category_id": "%s",
            "description": "Payment recipient clear coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupRecipientClearRejectID',
        :'groupCategoryID'
    ),
    'OCG01',
    'paid-capable events require a payment recipient',
    'Should reject clearing payment recipient when published paid-capable events exist'
);

-- Should allow clearing payment recipient for a published all-zero event
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Free Ticketed Event",
            "category_id": "%s",
            "description": "Free ticketed event coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group6ID',
        :'groupCategoryID'
    ),
    'Should allow clearing payment recipient for a published all-zero event'
);

-- Should clear the stored recipient for a published all-zero event
select is(
    (select get_group_full(:'communityID'::uuid, :'group6ID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should clear the stored recipient for a published all-zero event'
);

-- Should allow clearing payment recipient when only unpublished ticketed events exist
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Unpublished Ticketed Event",
            "category_id": "%s",
            "description": "Unpublished ticketed event coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group5ID',
        :'groupCategoryID'
    ),
    'Should allow clearing payment recipient when only unpublished ticketed events exist'
);

-- Should clear the stored payment recipient when only unpublished ticketed events exist
select is(
    (select get_group_full(:'communityID'::uuid, :'group5ID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should clear the stored payment recipient when only unpublished ticketed events exist'
);

-- Should clear draft manual-tax selections after the sponsor changes
select is(
    (select manual_tax_rate_ids from event where event_id = :'eventUnpublishedID'::uuid),
    '{}'::text[],
    'Should require draft manual-tax events to reselect rates after a sponsor change'
);

-- Should allow disabling external payments when no upcoming published external events remain
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Disable Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupDisableID',
        :'groupCategoryID'
    ),
    'Should allow disabling external payments when no upcoming published external events remain'
);

-- Should persist the disabled external-payments toggle
select is(
    (
        select external_payments_enabled
        from "group"
        where group_id = :'groupDisableID'::uuid
    ),
    false,
    'Should persist the disabled external-payments toggle'
);

-- Should allow enabling external payments when the final country is allowlisted
select lives_ok(
    format(
        $$select update_group(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Enable Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": true,
            "external_payments_seller_display_name": "External Payee Co"
        }'::jsonb
    )$$,
        :'actorUserID',
        :'communityID',
        :'groupEnableID',
        :'groupCategoryID'
    ),
    'Should allow enabling external payments when the final country is allowlisted'
);

-- Should persist the enabled external-payments toggle for an allowlisted country
select is(
    (
        select external_payments_enabled
        from "group"
        where group_id = :'groupEnableID'::uuid
    ),
    true,
    'Should persist the enabled external-payments toggle for an allowlisted country'
);

-- Should create the external-payments audit row when the toggle changes
select results_eq(
    format(
        $$
        select
            actor_user_id,
            actor_username,
            details
        from audit_log
        where action = 'group_external_payments_updated'
        and group_id = %L::uuid
    $$,
        :'groupEnableID'
    ),
    format(
        $$
        values (
            %L::uuid,
            'update-group-payments-audit-actor'::text,
            '{"external_payments_enabled": true, "external_payments_seller_display_name": "External Payee Co"}'::jsonb
        )
    $$,
        :'actorUserID'
    ),
    'Should create the external-payments audit row when the toggle changes'
);

-- Should reject enabling external payments without the external payee legal name
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Nameless Enable Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": true
        }'::jsonb
    )$$,
        :'communityID',
        :'groupNamelessEnableID',
        :'groupCategoryID'
    ),
    'OCG01',
    'external payments require the legal name of the organization collecting payments',
    'Should reject enabling external payments without the external payee legal name'
);

-- Should reject clearing the external payee legal name while external payments stay enabled
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Payee Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_seller_display_name": "   "
        }'::jsonb
    )$$,
        :'communityID',
        :'groupPayeeID',
        :'groupCategoryID'
    ),
    'OCG01',
    'external payments require the legal name of the organization collecting payments',
    'Should reject clearing the external payee legal name while external payments stay enabled'
);

-- Should rename the external payee legal name while external payments stay enabled
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Payee Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": true,
            "external_payments_seller_display_name": "  Renamed Payee Ltd  "
        }'::jsonb
    )$$,
        :'communityID',
        :'groupPayeeID',
        :'groupCategoryID'
    ),
    'Should rename the external payee legal name while external payments stay enabled'
);

-- Should persist the trimmed external payee legal name
select is(
    (
        select external_payments_seller_display_name
        from "group"
        where group_id = :'groupPayeeID'::uuid
    ),
    'Renamed Payee Ltd',
    'Should persist the trimmed external payee legal name'
);

-- Should create the external-payments audit row when only the payee legal name changes
select ok(
    exists(
        select 1
        from audit_log
        where action = 'group_external_payments_updated'
        and group_id = :'groupPayeeID'::uuid
        and details = '{"external_payments_enabled": true, "external_payments_seller_display_name": "Renamed Payee Ltd"}'::jsonb
    ),
    'Should create the external-payments audit row when only the payee legal name changes'
);

-- Should accept a partial payload that omits the external payee legal name
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Payee Preserve Group Updated",
            "category_id": "%s"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupPayeePreserveID',
        :'groupCategoryID'
    ),
    'Should accept a partial payload that omits the external payee legal name'
);

-- Should preserve the external payee legal name when a partial payload omits it
select is(
    (
        select external_payments_seller_display_name
        from "group"
        where group_id = :'groupPayeePreserveID'::uuid
    ),
    'Preserved Payee Ltd',
    'Should preserve the external payee legal name when a partial payload omits it'
);

-- Should clear the external payee legal name when disabling external payments
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Payee Disable Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": false,
            "external_payments_seller_display_name": ""
        }'::jsonb
    )$$,
        :'communityID',
        :'groupPayeeDisableID',
        :'groupCategoryID'
    ),
    'Should clear the external payee legal name when disabling external payments'
);

-- Should persist the disabled toggle and cleared payee legal name together
select is(
    (
        select jsonb_build_object(
            'external_payments_enabled', external_payments_enabled,
            'external_payments_seller_display_name', external_payments_seller_display_name
        )
        from "group"
        where group_id = :'groupPayeeDisableID'::uuid
    ),
    '{"external_payments_enabled": false, "external_payments_seller_display_name": null}'::jsonb,
    'Should persist the disabled toggle and cleared payee legal name together'
);

-- Should enable external payments when the same update moves onto the allowlist
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Final Country Group",
            "category_id": "%s",
            "country_code": "KR",
            "country_name": "Korea",
            "external_payments_enabled": true,
            "external_payments_seller_display_name": "External Payee Co"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupFinalCountryID',
        :'groupCategoryID'
    ),
    'Should enable external payments when the same update moves onto the allowlist'
);

-- Should persist the allowlisted country and enabled toggle together
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupFinalCountryID'::uuid
    ),
    '{"country_code": "KR", "external_payments_enabled": true}'::jsonb,
    'Should persist the allowlisted country and enabled toggle together'
);

-- Should allow leaving the allowlist when the same update disables external payments
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Move Country Disable Group",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveCountryDisableID',
        :'groupCategoryID'
    ),
    'Should allow leaving the allowlist when the same update disables external payments'
);

-- Should persist the non-allowlisted country and disabled toggle together
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupMoveCountryDisableID'::uuid
    ),
    '{"country_code": "US", "external_payments_enabled": false}'::jsonb,
    'Should persist the non-allowlisted country and disabled toggle together'
);

-- Should reject changing country off the allowlist while external payments stay enabled
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Move Country Group",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveCountryID',
        :'groupCategoryID'
    ),
    'OCG01',
    'external payments are not available for this group country',
    'Should reject changing country off the allowlist while external payments stay enabled'
);

-- Should accept a partial payload that omits country_code while the toggle stays on
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Move Country Group",
            "category_id": "%s"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveCountryID',
        :'groupCategoryID'
    ),
    'Should accept a partial payload that omits country_code while the toggle stays on'
);

-- Should preserve country when a partial payload omits country_code while the toggle stays on
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupMoveCountryID'::uuid
    ),
    '{"country_code": "KR", "external_payments_enabled": true}'::jsonb,
    'Should preserve country when a partial payload omits country_code while the toggle stays on'
);

-- Should reject enabling external payments when the country is not allowlisted
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Reject Enable Group",
            "category_id": "%s",
            "country_code": "US",
            "external_payments_enabled": true,
            "external_payments_seller_display_name": "External Payee Co"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupRejectEnableID',
        :'groupCategoryID'
    ),
    'OCG01',
    'external payments are not available for this group country',
    'Should reject enabling external payments when the country is not allowlisted'
);

-- Should reject enabling external payments while published external events are held abroad
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Enable Abroad Group",
            "category_id": "%s",
            "country_code": "JP",
            "external_payments_enabled": true,
            "external_payments_seller_display_name": "External Payee Co"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupEnableAbroadID',
        :'groupCategoryID'
    ),
    'OCG01',
    'published external paid events require a venue in the group country',
    'Should reject enabling external payments while published external events are held abroad'
);

-- Should reject moving the group country away from upcoming external event venues
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Venue Country Group",
            "category_id": "%s",
            "country_code": "JP",
            "country_name": "Japan"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupVenueCountryID',
        :'groupCategoryID'
    ),
    'OCG01',
    'published external paid events require a venue in the group country',
    'Should reject moving the group country away from upcoming external event venues'
);

-- Should reject disabling external payments while published external paid events are upcoming
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Venue Country Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupVenueCountryID',
        :'groupCategoryID'
    ),
    'OCG01',
    'external payments cannot be disabled while published external paid events are upcoming',
    'Should reject disabling external payments while published external paid events are upcoming'
);

-- Should reject moving the group country away from event venues when the same update disables external payments
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Venue Country Group",
            "category_id": "%s",
            "country_code": "JP",
            "country_name": "Japan",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupVenueCountryID',
        :'groupCategoryID'
    ),
    'OCG01',
    'external payments cannot be disabled while published external paid events are upcoming',
    'Should reject moving the group country away from event venues when the same update disables external payments'
);

-- Should allow unrelated group updates after the country leaves the allowlist
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Delisted Group Updated",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupDelistedID',
        :'groupCategoryID'
    ),
    'Should allow unrelated group updates after the country leaves the allowlist'
);

-- Should keep the toggle enabled after an unrelated save on a delisted country
select is(
    (
        select jsonb_build_object(
            'external_payments_enabled', external_payments_enabled,
            'name', name
        )
        from "group"
        where group_id = :'groupDelistedID'::uuid
    ),
    '{"external_payments_enabled": true, "name": "External Delisted Group Updated"}'::jsonb,
    'Should keep the toggle enabled after an unrelated save on a delisted country'
);

-- Should allow disabling external payments on a delisted country despite upcoming external events
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Delisted Group Updated",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupDelistedID',
        :'groupCategoryID'
    ),
    'Should allow disabling external payments on a delisted country despite upcoming external events'
);

-- Should persist the disabled toggle for the delisted country
select is(
    (
        select external_payments_enabled
        from "group"
        where group_id = :'groupDelistedID'::uuid
    ),
    false,
    'Should persist the disabled toggle for the delisted country'
);

-- Should reject replacing the fiscal sponsor while the group country is allowlisted
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With External Paid Event",
            "category_id": "%s",
            "description": "External paid event recipient coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_external",
                    "seller_display_name": "External Event Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_external_replacement",
                    "seller_display_name": "Replacement External Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_external_replacement",
                "seller_display_name": "Replacement External Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupExternalPaidID',
        :'groupCategoryID'
    ),
    'OCG01',
    'stripe connected account cannot be added or changed for this group country',
    'Should reject replacing the fiscal sponsor while the group country is allowlisted'
);

-- Should clear the fiscal sponsor when only external paid events are published
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With External Paid Event",
            "category_id": "%s",
            "description": "External paid event recipient coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupExternalPaidID',
        :'groupCategoryID'
    ),
    'Should clear the fiscal sponsor when only external paid events are published'
);

-- Should persist a cleared recipient for an external-only group
select is(
    (select get_group_full(:'communityID'::uuid, :'groupExternalPaidID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should persist a cleared recipient for an external-only group'
);

-- Should replace the fiscal sponsor when the enabled group country is delisted
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Delisted Replace Group",
            "category_id": "%s",
            "country_code": "BR",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_delisted",
                    "seller_display_name": "Delisted Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_delisted_replacement",
                    "seller_display_name": "Replacement Delisted Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_delisted_replacement",
                "seller_display_name": "Replacement Delisted Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupExternalDelistedID',
        :'groupCategoryID'
    ),
    'Should replace the fiscal sponsor when the enabled group country is delisted'
);

-- Should persist the replaced fiscal sponsor for a delisted country
select is(
    (select get_group_full(:'communityID'::uuid, :'groupExternalDelistedID'::uuid)::jsonb->'payment_recipient'),
    '{
        "provider": "stripe",
        "recipient_id": "acct_delisted_replacement",
        "seller_display_name": "Replacement Delisted Sponsor"
    }'::jsonb,
    'Should persist the replaced fiscal sponsor for a delisted country'
);

-- Should reject a first fiscal sponsor for an allowlisted country before checking the validation snapshot
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Blocked First Sponsor Group",
            "category_id": "%s",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_blocked_first",
                "seller_display_name": "Blocked First Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupBlockedFirstID',
        :'groupCategoryID'
    ),
    'OCG01',
    'stripe connected account cannot be added or changed for this group country',
    'Should reject a first fiscal sponsor for an allowlisted country before checking the validation snapshot'
);

-- Should reject a first fiscal sponsor for an allowlisted country despite a valid validation snapshot
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Blocked First Sponsor Group",
            "category_id": "%s",
            "_payment_validation": {
                "expected_payment_recipient": null,
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_blocked_first",
                    "seller_display_name": "Blocked First Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_blocked_first",
                "seller_display_name": "Blocked First Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupBlockedFirstID',
        :'groupCategoryID'
    ),
    'OCG01',
    'stripe connected account cannot be added or changed for this group country',
    'Should reject a first fiscal sponsor for an allowlisted country despite a valid validation snapshot'
);

-- Should reject replacing the fiscal sponsor while the allowlisted group keeps external payments off
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Blocked Replace Sponsor Group",
            "category_id": "%s",
            "external_payments_enabled": false,
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_blocked_current",
                    "seller_display_name": "Current Blocked Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_blocked_replacement",
                    "seller_display_name": "Replacement Blocked Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_blocked_replacement",
                "seller_display_name": "Replacement Blocked Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupBlockedReplaceID',
        :'groupCategoryID'
    ),
    'OCG01',
    'stripe connected account cannot be added or changed for this group country',
    'Should reject replacing the fiscal sponsor while the allowlisted group keeps external payments off'
);

-- Should allow renaming the stored fiscal sponsor for an allowlisted country without provider validation
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Blocked Replace Sponsor Group",
            "category_id": "%s",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_blocked_current",
                "seller_display_name": "Renamed Blocked Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupBlockedReplaceID',
        :'groupCategoryID'
    ),
    'Should allow renaming the stored fiscal sponsor for an allowlisted country without provider validation'
);

-- Should persist the renamed fiscal sponsor for an allowlisted country
select is(
    (select get_group_full(:'communityID'::uuid, :'groupBlockedReplaceID'::uuid)::jsonb->'payment_recipient'),
    '{
        "provider": "stripe",
        "recipient_id": "acct_blocked_current",
        "seller_display_name": "Renamed Blocked Fiscal Sponsor"
    }'::jsonb,
    'Should persist the renamed fiscal sponsor for an allowlisted country'
);

-- Should record the payment recipient audit row after renaming the fiscal sponsor
select ok(
    exists(
        select 1
        from audit_log
        where action = 'group_payment_recipient_updated'
        and group_id = :'groupBlockedReplaceID'::uuid
    ),
    'Should record the payment recipient audit row after renaming the fiscal sponsor'
);

-- Should allow clearing the stored fiscal sponsor for an allowlisted country
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Blocked Clear Sponsor Group",
            "category_id": "%s",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "",
                "seller_display_name": ""
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupBlockedClearID',
        :'groupCategoryID'
    ),
    'Should allow clearing the stored fiscal sponsor for an allowlisted country'
);

-- Should persist the cleared fiscal sponsor for an allowlisted country
select is(
    (select get_group_full(:'communityID'::uuid, :'groupBlockedClearID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should persist the cleared fiscal sponsor for an allowlisted country'
);

-- Should reject adding a fiscal sponsor when the same update moves the group onto the allowlist
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Move Onto Allowlist Group",
            "category_id": "%s",
            "country_code": "KR",
            "country_name": "Korea",
            "_payment_validation": {
                "expected_payment_recipient": null,
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_move_onto",
                    "seller_display_name": "Move Onto Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_move_onto",
                "seller_display_name": "Move Onto Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveOntoAllowlistID',
        :'groupCategoryID'
    ),
    'OCG01',
    'stripe connected account cannot be added or changed for this group country',
    'Should reject adding a fiscal sponsor when the same update moves the group onto the allowlist'
);

-- Should allow adding a fiscal sponsor when the same update moves the group off the allowlist
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Move Off Allowlist Group",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States",
            "_payment_validation": {
                "expected_payment_recipient": null,
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_move_off",
                    "seller_display_name": "Move Off Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_move_off",
                "seller_display_name": "Move Off Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveOffAllowlistID',
        :'groupCategoryID'
    ),
    'Should allow adding a fiscal sponsor when the same update moves the group off the allowlist'
);

-- Should persist the new country and fiscal sponsor together after leaving the allowlist
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'payment_recipient', payment_recipient
        )
        from "group"
        where group_id = :'groupMoveOffAllowlistID'::uuid
    ),
    '{
        "country_code": "US",
        "payment_recipient": {
            "provider": "stripe",
            "recipient_id": "acct_move_off",
            "seller_display_name": "Move Off Fiscal Sponsor"
        }
    }'::jsonb,
    'Should persist the new country and fiscal sponsor together after leaving the allowlist'
);

-- Should allow moving the group onto the allowlist while keeping the stored fiscal sponsor
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Move Keep Recipient Group",
            "category_id": "%s",
            "country_code": "KR",
            "country_name": "Korea"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveKeepRecipientID',
        :'groupCategoryID'
    ),
    'Should allow moving the group onto the allowlist while keeping the stored fiscal sponsor'
);

-- Should persist the allowlisted country and the kept fiscal sponsor together
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'payment_recipient', payment_recipient
        )
        from "group"
        where group_id = :'groupMoveKeepRecipientID'::uuid
    ),
    '{
        "country_code": "KR",
        "payment_recipient": {
            "provider": "stripe",
            "recipient_id": "acct_move_keep",
            "seller_display_name": "Kept Fiscal Sponsor"
        }
    }'::jsonb,
    'Should persist the allowlisted country and the kept fiscal sponsor together'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
