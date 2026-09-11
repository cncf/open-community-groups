-- Tests detecting paid-readiness changes between the stored event and an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(30);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set addedDiscountCodeID '3b020000-0000-0000-0000-000000000018'
\set addedWindowID '3b020000-0000-0000-0000-000000000019'
\set communityID '3b020000-0000-0000-0000-000000000001'
\set datedDiscountCodeID '3b020000-0000-0000-0000-000000000020'
\set datedEarlyWindowID '3b020000-0000-0000-0000-000000000021'
\set datedEventID '3b020000-0000-0000-0000-000000000022'
\set datedLateWindowID '3b020000-0000-0000-0000-000000000023'
\set datedTicketTypeID '3b020000-0000-0000-0000-000000000024'
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
\set undatedDiscountCodeID '3b020000-0000-0000-0000-000000000025'
\set undatedTicketTypeID '3b020000-0000-0000-0000-000000000026'
\set undatedWindowID '3b020000-0000-0000-0000-000000000027'

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

-- Paid in-person event without tax whose tiers and discount codes carry dated windows
select fx_event(:'datedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'tax_behavior', 'inclusive',
    'tax_calculation_mode', 'none',
    'venue_address', '123 Main Street',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_state_code', 'OR',
    'venue_state_name', 'Oregon',
    'venue_zip_code', '97201'
));

-- Paid ticket tiers of every event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'manualTaxTicketTypeID', :'manualTaxEventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'externalTicketTypeID', :'externalEventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'pastTicketTypeID', :'pastEventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'datedTicketTypeID', :'datedEventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_type(:'undatedTicketTypeID', :'datedEventID', jsonb_build_object('order', 2, 'seats_total', 5, 'title', 'VIP'));
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'manualTaxPriceWindowID', :'manualTaxTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'externalPriceWindowID', :'externalTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'pastPriceWindowID', :'pastTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Disjoint bounded price windows of the dated tier and the undated window of the VIP tier
select fx_event_ticket_price_window(:'datedEarlyWindowID', :'datedTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'ends_at', '2030-03-01 10:00:00+00',
    'starts_at', '2030-01-01 10:00:00+00'
));
select fx_event_ticket_price_window(:'datedLateWindowID', :'datedTicketTypeID', jsonb_build_object(
    'amount_minor', 3000,
    'ends_at', '2030-06-01 12:00:00+02',
    'starts_at', '2030-03-01 10:00:01+00'
));
select fx_event_ticket_price_window(:'undatedWindowID', :'undatedTicketTypeID', jsonb_build_object('amount_minor', 2000));

-- Override-on dated discount code of the dated event with live inventory
insert into event_discount_code (
    event_discount_code_id,
    code,
    event_id,
    kind,
    title,
    available,
    available_override_active,
    ends_at,
    percentage,
    starts_at,
    total_available
) values (
    :'datedDiscountCodeID',
    'BETA',
    :'datedEventID',
    'percentage',
    'beta',
    3,
    true,
    '2030-03-01 10:00:00+00',
    10,
    '2030-01-01 10:00:00+00',
    10
);

-- Override-off undated discount code of the dated event
insert into event_discount_code (
    event_discount_code_id,
    code,
    event_id,
    kind,
    title,
    amount_minor
) values (
    :'undatedDiscountCodeID',
    'ALPHA',
    :'datedEventID',
    'fixed_amount',
    'Alpha',
    500
);

-- Test-only helper returning the full editor payload of the dated event as the
-- dashboard submits it: Z timestamp spellings, discount codes in editor order
-- and no live inventory count.
create function dated_editor_payload()
returns jsonb
language sql
return format('{
    "description": "Updated description",
    "discount_codes": [
        {
            "active": true,
            "available_override_active": true,
            "code": "BETA",
            "ends_at": "2030-03-01T10:00:00.000Z",
            "event_discount_code_id": "%1$s",
            "kind": "percentage",
            "percentage": 10,
            "starts_at": "2030-01-01T10:00:00.000Z",
            "title": "beta",
            "total_available": 10
        },
        {
            "active": true,
            "amount_minor": 500,
            "available_override_active": false,
            "code": "ALPHA",
            "event_discount_code_id": "%2$s",
            "kind": "fixed_amount",
            "title": "Alpha"
        }
    ],
    "kind_id": "in-person",
    "payment_currency_code": "USD",
    "tax_behavior": "inclusive",
    "tax_calculation_mode": "none",
    "ticket_types": [
        {
            "active": true,
            "availability": "public",
            "event_ticket_type_id": "%3$s",
            "order": 1,
            "price_windows": [
                {
                    "amount_minor": 2500,
                    "ends_at": "2030-03-01T10:00:00.000Z",
                    "event_ticket_price_window_id": "%4$s",
                    "starts_at": "2030-01-01T10:00:00.000Z"
                },
                {
                    "amount_minor": 3000,
                    "ends_at": "2030-06-01T10:00:00.000Z",
                    "event_ticket_price_window_id": "%5$s",
                    "starts_at": "2030-03-01T10:00:01.000Z"
                }
            ],
            "seats_total": 10,
            "title": "General"
        },
        {
            "active": true,
            "availability": "public",
            "event_ticket_type_id": "%6$s",
            "order": 2,
            "price_windows": [
                {
                    "amount_minor": 2000,
                    "event_ticket_price_window_id": "%7$s"
                }
            ],
            "seats_total": 5,
            "title": "VIP"
        }
    ],
    "venue_address": "123 Main Street",
    "venue_city": "Portland",
    "venue_country_code": "US",
    "venue_name": "Community Hall",
    "venue_state_code": "OR",
    "venue_state_name": "Oregon",
    "venue_zip_code": "97201"
}',
    :'datedDiscountCodeID',
    :'undatedDiscountCodeID',
    :'datedTicketTypeID',
    :'datedEarlyWindowID',
    :'datedLateWindowID',
    :'undatedTicketTypeID',
    :'undatedWindowID'
)::jsonb;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect a cleared discount override in a dated editor payload
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_set(dated_editor_payload(), '{discount_codes,0,available_cleared}', 'true'::jsonb)
    ),
    'Should detect a cleared discount override in a dated editor payload'
);

-- Should detect a discount code added to a dated editor payload
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_insert(
            dated_editor_payload(),
            '{discount_codes,2}',
            format(
                '{"active": true, "available_override_active": false, "code": "GAMMA", "event_discount_code_id": "%s", "kind": "percentage", "percentage": 5, "title": "Gamma"}',
                :'addedDiscountCodeID'
            )::jsonb
        )
    ),
    'Should detect a discount code added to a dated editor payload'
);

-- Should detect a discount code removed from a dated editor payload
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        dated_editor_payload() #- '{discount_codes,1}'
    ),
    'Should detect a discount code removed from a dated editor payload'
);

-- Should detect a changed discount total in a dated editor payload
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_set(dated_editor_payload(), '{discount_codes,0,total_available}', '20'::jsonb)
    ),
    'Should detect a changed discount total in a dated editor payload'
);

-- Should detect a price window added to a dated tier
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_insert(
            dated_editor_payload(),
            '{ticket_types,0,price_windows,2}',
            format(
                '{"amount_minor": 3500, "event_ticket_price_window_id": "%s", "starts_at": "2030-06-01T10:00:01.000Z"}',
                :'addedWindowID'
            )::jsonb
        )
    ),
    'Should detect a price window added to a dated tier'
);

-- Should detect a removed price window end in a dated tier
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        dated_editor_payload() #- '{ticket_types,0,price_windows,1,ends_at}'
    ),
    'Should detect a removed price window end in a dated tier'
);

-- Should detect a shifted discount window in a dated editor payload
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_set(dated_editor_payload(), '{discount_codes,0,ends_at}', '"2030-03-01T11:00:00.000Z"'::jsonb)
    ),
    'Should detect a shifted discount window in a dated editor payload'
);

-- Should detect a shifted price window start in a dated tier
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_set(dated_editor_payload(), '{ticket_types,0,price_windows,0,starts_at}', '"2030-01-01T11:00:00.000Z"'::jsonb)
    ),
    'Should detect a shifted price window start in a dated tier'
);

-- Should detect a start added to an undated price window
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_set(dated_editor_payload(), '{ticket_types,1,price_windows,0,starts_at}', '"2030-01-01T10:00:00.000Z"'::jsonb)
    ),
    'Should detect a start added to an undated price window'
);

-- Should detect a submitted discount count that differs from live inventory
select ok(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_set(dated_editor_payload(), '{discount_codes,0,available}', '9'::jsonb)
    ),
    'Should detect a submitted discount count that differs from live inventory'
);

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

-- Should ignore an explicit unchanged discount count in a dated editor payload
select is(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        jsonb_set(dated_editor_payload(), '{discount_codes,0,available}', '3'::jsonb)
    ),
    false,
    'Should ignore an explicit unchanged discount count in a dated editor payload'
);

-- Should ignore an omitted override flag on an override-off discount code
select is(
    event_ticketing_configuration_changed(
        :'communityID',
        :'groupID',
        :'datedEventID',
        dated_editor_payload() #- '{discount_codes,1,available_override_active}'
    ),
    false,
    'Should ignore an omitted override flag on an override-off discount code'
);

-- Should ignore an unchanged dated editor payload under UTC
set local time zone 'UTC';
select is(
    event_ticketing_configuration_changed(:'communityID', :'groupID', :'datedEventID', dated_editor_payload()),
    false,
    'Should ignore an unchanged dated editor payload under UTC'
);

-- Should ignore an unchanged dated editor payload under Europe/Madrid
set local time zone 'Europe/Madrid';
select is(
    event_ticketing_configuration_changed(:'communityID', :'groupID', :'datedEventID', dated_editor_payload()),
    false,
    'Should ignore an unchanged dated editor payload under Europe/Madrid'
);

-- Should ignore an unchanged dated editor payload under Asia/Kolkata
set local time zone 'Asia/Kolkata';
select is(
    event_ticketing_configuration_changed(:'communityID', :'groupID', :'datedEventID', dated_editor_payload()),
    false,
    'Should ignore an unchanged dated editor payload under Asia/Kolkata'
);

-- Restore the session time zone for the remaining scenarios
set local time zone default;

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
