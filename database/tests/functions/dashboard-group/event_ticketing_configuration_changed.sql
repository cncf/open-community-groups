-- Tests event_ticketing_configuration_changed.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Temporary holder for the canonical persisted event payload
create temporary table test_event_before (payload jsonb not null);

-- Canonical persisted event payload used by every comparison
insert into test_event_before values ('{
  "discount_codes": [],
  "kind": "in-person",
  "payment_currency_code": "USD",
  "tax_behavior": "inclusive",
  "tax_calculation_mode": "automatic",
  "timezone": "UTC",
  "ticket_types": [
    {
      "active": true,
      "availability": "public",
      "current_price": {"amount_minor": 2500},
      "event_ticket_type_id": "00000000-0000-0000-0000-000000000001",
      "order": 1,
      "price_windows": [
        {
          "amount_minor": 2500,
          "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000002"
        }
      ],
      "remaining_seats": 10,
      "seats_total": 10,
      "sold_out": false,
      "title": "General"
    }
  ],
  "venue_address": "123 Main Street",
  "venue_city": "Portland",
  "venue_country_code": "US",
  "venue_name": "Community Hall",
  "venue_state_code": "OR",
  "venue_state_name": "Oregon",
  "venue_zip_code": "97201"
}'::jsonb);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect changed discount codes
select ok(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{"discount_codes":[{"active":true,"code":"SAVE10","kind":"percentage","percentage":10,"title":"Save 10"}],"kind_id":"in-person","tax_behavior":"inclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed discount codes'
);

-- Should detect changed event kind
select ok(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{"kind_id":"virtual","tax_behavior":"inclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed event kind'
);

-- Should detect changed payment currency
select ok(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{"kind_id":"in-person","payment_currency_code":"EUR","tax_behavior":"inclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed payment currency'
);

-- Should detect changed tax behavior
select ok(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{"kind_id":"in-person","tax_behavior":"exclusive","tax_calculation_mode":"automatic"}'::jsonb
    ),
    'Should detect changed tax behavior'
);

-- Should detect changed tax calculation mode
select ok(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{"kind_id":"in-person","tax_behavior":"inclusive","tax_calculation_mode":"manual"}'::jsonb
    ),
    'Should detect changed tax calculation mode'
);

-- Should detect changed manual Tax Rate selections
select ok(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{"kind_id":"in-person","manual_tax_rate_ids":["txr_state"],"tax_behavior":"inclusive","tax_calculation_mode":"manual"}'::jsonb
    ),
    'Should detect changed manual Tax Rate selections'
);

-- Should preserve manual Tax Rate selections omitted from a partial payload
select is(
    event_ticketing_configuration_changed(
        (
            select payload || '{
                "manual_tax_rate_ids": ["txr_state"],
                "tax_calculation_mode": "manual"
            }'::jsonb
            from test_event_before
        ),
        (
            select
                (payload - 'kind' - 'manual_tax_rate_ids')
                || '{"kind_id":"in-person","tax_calculation_mode":"manual"}'::jsonb
            from test_event_before
        )
    ),
    false,
    'Should preserve manual Tax Rate selections omitted from a partial payload'
);

-- Should detect changed venue data
select ok(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{"kind_id":"in-person","tax_behavior":"inclusive","tax_calculation_mode":"automatic","venue_city":"Seattle"}'::jsonb
    ),
    'Should detect changed venue data'
);

-- Should ignore read-model-only ticket fields in an unchanged editor payload
select is(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        '{
          "kind_id": "in-person",
          "tax_behavior": "inclusive",
          "tax_calculation_mode": "automatic",
          "ticket_types": [
            {
              "active": true,
              "availability": "public",
              "event_ticket_type_id": "00000000-0000-0000-0000-000000000001",
              "order": 1,
              "price_windows": [
                {
                  "amount_minor": 2500,
                  "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000002"
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
        }'::jsonb
    ),
    false,
    'Should ignore read-model-only ticket fields in an unchanged editor payload'
);

-- Should ignore ticketing changes when the resulting event is free
select is(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
        (
            select
                (payload - 'kind')
                || jsonb_build_object(
                    'kind_id', payload->>'kind',
                    'ticket_types', '[]'::jsonb,
                    'venue_city', 'Seattle'
                )
            from test_event_before
        )
    ),
    false,
    'Should ignore ticketing changes when the resulting event is free'
);

-- Should ignore unrelated and canonically equivalent venue edits
select is(
    event_ticketing_configuration_changed(
        (select payload from test_event_before),
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

-- Should require readiness when a published paid event becomes active again
select ok(
    event_ticketing_configuration_changed(
        (
            select payload || jsonb_build_object(
                'ends_at', floor(extract(epoch from current_timestamp - interval '1 day')),
                'published', true
            )
            from test_event_before
        ),
        (
            select
                (payload - 'kind' - 'published' - 'starts_at' - 'ends_at')
                || jsonb_build_object(
                    'ends_at', to_char(
                        current_timestamp + interval '1 day',
                        'YYYY-MM-DD"T"HH24:MI:SS'
                    ),
                    'kind_id', payload->>'kind'
                )
            from test_event_before
        )
    ),
    'Should require readiness when a published paid event becomes active again'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
