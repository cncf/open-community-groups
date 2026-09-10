-- Tests selecting the payment rail of a resolved event payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Resolved event carrying external fields and provider tax settings
create temporary table test_resolved (payload event not null);
insert into test_resolved values (jsonb_populate_record(null::event, '{
    "external_payment_instructions": "Wire the purchase ID.",
    "external_payment_url": "https://pay.example.test/event",
    "external_payment_window_hours": 72,
    "manual_tax_rate_ids": ["txr_state"],
    "tax_behavior": "exclusive",
    "tax_calculation_mode": "manual"
}'::jsonb));

-- Paid and free ticket configurations
create temporary table test_ticket_types (paid jsonb not null, free jsonb not null);
insert into test_ticket_types values (
    '[{"price_windows": [{"amount_minor": 2500}]}]'::jsonb,
    '[{"price_windows": [{"amount_minor": 0}]}]'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should clear external fields for free events in an eligible group
select is(
    (
        select jsonb_build_object(
            'external_mode', r.external_mode,
            'external_payment_url', (r.resolved).external_payment_url,
            'external_payment_window_hours', (r.resolved).external_payment_window_hours,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode
        )
        from test_resolved t
        cross join test_ticket_types tt
        cross join resolve_event_payment_rail(t.payload, tt.free, true) r
    ),
    '{"external_mode": false, "external_payment_url": null, "external_payment_window_hours": null, "tax_calculation_mode": "manual"}'::jsonb,
    'Should clear external fields for free events in an eligible group'
);

-- Should clear external fields when the payload has no ticket types
select is(
    (
        select r.external_mode
        from resolve_event_payment_rail(
            jsonb_populate_record(null::event, '{"tax_calculation_mode": "automatic"}'::jsonb),
            null::jsonb,
            true
        ) r
    ),
    false,
    'Should clear external fields when the payload has no ticket types'
);

-- Should keep provider tax settings for paid events in an ineligible group without a URL
select is(
    (
        select jsonb_build_object(
            'external_mode', r.external_mode,
            'external_payment_instructions', (r.resolved).external_payment_instructions,
            'manual_tax_rate_ids', to_jsonb((r.resolved).manual_tax_rate_ids),
            'tax_behavior', (r.resolved).tax_behavior,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode
        )
        from test_resolved t
        cross join test_ticket_types tt
        cross join resolve_event_payment_rail(
            jsonb_populate_record(t.payload, '{"external_payment_url": null}'::jsonb),
            tt.paid,
            false
        ) r
    ),
    '{"external_mode": false, "external_payment_instructions": null, "manual_tax_rate_ids": ["txr_state"], "tax_behavior": "exclusive", "tax_calculation_mode": "manual"}'::jsonb,
    'Should keep provider tax settings for paid events in an ineligible group without a URL'
);

-- Should move paid events in an eligible group onto organizer-managed tax
select is(
    (
        select jsonb_build_object(
            'external_mode', r.external_mode,
            'external_payment_instructions', (r.resolved).external_payment_instructions,
            'external_payment_url', (r.resolved).external_payment_url,
            'external_payment_window_hours', (r.resolved).external_payment_window_hours,
            'manual_tax_rate_ids', to_jsonb((r.resolved).manual_tax_rate_ids),
            'tax_behavior', (r.resolved).tax_behavior,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode
        )
        from test_resolved t
        cross join test_ticket_types tt
        cross join resolve_event_payment_rail(t.payload, tt.paid, true) r
    ),
    '{"external_mode": true, "external_payment_instructions": "Wire the purchase ID.", "external_payment_url": "https://pay.example.test/event", "external_payment_window_hours": 72, "manual_tax_rate_ids": [], "tax_behavior": "inclusive", "tax_calculation_mode": "none"}'::jsonb,
    'Should move paid events in an eligible group onto organizer-managed tax'
);

-- Should preserve the other resolved columns
select is(
    (
        select (r.resolved).name
        from test_ticket_types tt
        cross join resolve_event_payment_rail(
            jsonb_populate_record(null::event, '{"name": "Kept Name"}'::jsonb),
            tt.paid,
            true
        ) r
    ),
    'Kept Name',
    'Should preserve the other resolved columns'
);

-- Should reject an external URL for free events in an ineligible group
select throws_ok(
    $$select * from test_resolved t
      cross join test_ticket_types tt
      cross join resolve_event_payment_rail(t.payload, tt.free, false) r$$,
    'OCG01',
    'external payments are not available for this event',
    'Should reject an external URL for free events in an ineligible group'
);

-- Should reject an external URL for paid events in an ineligible group
select throws_ok(
    $$select * from test_resolved t
      cross join test_ticket_types tt
      cross join resolve_event_payment_rail(t.payload, tt.paid, false) r$$,
    'OCG01',
    'external payments are not available for this event',
    'Should reject an external URL for paid events in an ineligible group'
);

-- Should return exactly one row
select is(
    (
        select count(*)
        from test_ticket_types tt
        cross join resolve_event_payment_rail(null::event, tt.paid, true) r
    ),
    1::bigint,
    'Should return exactly one row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
