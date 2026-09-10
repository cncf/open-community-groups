-- Tests detecting paid-readiness changes between the stored event and an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3b020000-0000-0000-0000-000000000001'
\set eventCategoryID '3b020000-0000-0000-0000-000000000002'
\set eventID '3b020000-0000-0000-0000-000000000003'
\set externalEventID '3b020000-0000-0000-0000-000000000004'
\set externalPriceWindowID '3b020000-0000-0000-0000-000000000005'
\set externalTicketTypeID '3b020000-0000-0000-0000-000000000006'
\set groupCategoryID '3b020000-0000-0000-0000-000000000007'
\set groupID '3b020000-0000-0000-0000-000000000008'
\set manualTaxEventID '3b020000-0000-0000-0000-000000000009'
\set manualTaxPriceWindowID '3b020000-0000-0000-0000-000000000010'
\set manualTaxTicketTypeID '3b020000-0000-0000-0000-000000000011'
\set missingEventID '3b020000-0000-0000-0000-000000000012'
\set pastEventID '3b020000-0000-0000-0000-000000000013'
\set pastPriceWindowID '3b020000-0000-0000-0000-000000000014'
\set pastTicketTypeID '3b020000-0000-0000-0000-000000000015'
\set priceWindowID '3b020000-0000-0000-0000-000000000016'
\set ticketTypeID '3b020000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Paid in-person event with automatic tax and a full venue
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'tax_behavior', 'inclusive',
    'tax_calculation_mode', 'automatic',
    'venue_address', '123 Main Street',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_state_code', 'OR',
    'venue_state_name', 'Oregon',
    'venue_zip_code', '97201'
));

-- Paid event collecting tax through a selected manual rate
select fx_event(:'manualTaxEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'manual_tax_rate_ids', jsonb_build_array('txr_state'),
    'payment_currency_code', 'USD',
    'tax_behavior', 'inclusive',
    'tax_calculation_mode', 'manual'
));

-- Paid event collecting payments externally
select fx_event(:'externalEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_instructions', 'Wire the purchase ID.',
    'external_payment_url', 'https://pay.example.test/event',
    'external_payment_window_hours', 72,
    'payment_currency_code', 'USD',
    'tax_behavior', 'inclusive',
    'tax_calculation_mode', 'none'
));

-- Published paid event that already ended
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 day',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp - interval '2 days'
));

-- Paid ticket tiers of every event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'manualTaxTicketTypeID', :'manualTaxEventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'externalTicketTypeID', :'externalEventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'pastTicketTypeID', :'pastEventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'manualTaxPriceWindowID', :'manualTaxTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'externalPriceWindowID', :'externalTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'pastPriceWindowID', :'pastTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect changed discount codes
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"discount_codes":[{"active":true,"code":"SAVE10","kind":"percentage","percentage":10,"title":"Save 10"}],"kind_id":"in-person","tax_behavior":"inclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed discount codes'
);

-- Should detect changed event kind
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"kind_id":"virtual","tax_behavior":"inclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed event kind'
);

-- Should detect changed external payment URL
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"external_payment_url":"https://pay.example.test/event","kind_id":"in-person","tax_behavior":"inclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed external payment URL'
);

-- Should detect changed manual Tax Rate selections
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"kind_id":"in-person","manual_tax_rate_ids":["txr_state"],"tax_behavior":"inclusive","tax_calculation_mode":"manual"}'::jsonb
    ),
    'Should detect changed manual Tax Rate selections'
);

-- Should detect changed payment currency
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"kind_id":"in-person","payment_currency_code":"EUR","tax_behavior":"inclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed payment currency'
);

-- Should detect changed tax behavior
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"kind_id":"in-person","tax_behavior":"exclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed tax behavior'
);

-- Should detect changed tax calculation mode
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"kind_id":"in-person","tax_behavior":"inclusive","tax_calculation_mode":"manual"}'::jsonb
    ),
    'Should detect changed tax calculation mode'
);

-- Should detect changed venue data
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"kind_id":"in-person","tax_behavior":"inclusive","tax_calculation_mode":"automatic","venue_city":"Seattle"}'::jsonb
    ),
    'Should detect changed venue data'
);

-- Should ignore read-model-only ticket fields in an unchanged editor payload
select is(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        format('{
          "kind_id": "in-person",
          "payment_currency_code": "USD",
          "tax_behavior": "inclusive",
          "tax_calculation_mode": "automatic",
          "ticket_types": [
            {
              "active": true,
              "availability": "public",
              "event_ticket_type_id": "%s",
              "order": 1,
              "price_windows": [
                {
                  "amount_minor": 2500,
                  "event_ticket_price_window_id": "%s"
                }
              ],
              "seats_total": 10,
              "title": "General"
            }
          ],
          "venue_address": "123 Main Street",
          "venue_city": "Portland",
          "venue_country_code": "US",
          "venue_name": "Community Hall",
          "venue_state": "Oregon",
          "venue_zip_code": "97201"
        }', :'ticketTypeID', :'priceWindowID')::jsonb
    ),
    false,
    'Should ignore read-model-only ticket fields in an unchanged editor payload'
);

-- Should ignore ticketing changes when the resulting event is free
select is(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{"kind_id":"in-person","ticket_types":[],"venue_city":"Seattle"}'::jsonb
    ),
    false,
    'Should ignore ticketing changes when the resulting event is free'
);

-- Should ignore unrelated and canonically equivalent venue edits
select is(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'eventID',
        '{
          "description": "Updated description",
          "kind_id": "in-person",
          "tax_behavior": "inclusive",
          "tax_calculation_mode": "automatic",
          "venue_address": " 123 Main Street ",
          "venue_city": "Portland",
          "venue_country_code": "US",
          "venue_name": "Community Hall",
          "venue_state_code": "OR",
          "venue_state_name": "Oregon",
          "venue_zip_code": "97201"
        }'::jsonb
    ),
    false,
    'Should ignore unrelated and canonically equivalent venue edits'
);

-- Should preserve external payment fields omitted from a partial payload
select is(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'externalEventID',
        '{"kind_id":"in-person","payment_currency_code":"USD","tax_behavior":"inclusive","tax_calculation_mode":"none"}'::jsonb
    ),
    false,
    'Should preserve external payment fields omitted from a partial payload'
);

-- Should preserve manual Tax Rate selections omitted from a partial payload
select is(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'manualTaxEventID',
        '{"kind_id":"in-person","payment_currency_code":"USD","tax_behavior":"inclusive","tax_calculation_mode":"manual"}'::jsonb
    ),
    false,
    'Should preserve manual Tax Rate selections omitted from a partial payload'
);

-- Should reject an event outside the group and community scope
select throws_ok(
    format(
        $$select event_ticketing_configuration_changed(%L, %L, %L, '{}'::jsonb)$$,
        :'communityID',
        :'groupID',
        :'missingEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject an event outside the group and community scope'
);

-- Should require readiness when a published paid event becomes active again
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'pastEventID',
        jsonb_build_object(
            'ends_at', to_char(current_timestamp + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind_id', 'in-person',
            'payment_currency_code', 'USD',
            'timezone', 'UTC'
        )
    ),
    'Should require readiness when a published paid event becomes active again'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
