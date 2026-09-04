-- Tests building external payment notification template data.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set fullEventID 'f30e0000-0000-0000-0000-000000000001'
\set fullGroupID 'f30e0000-0000-0000-0000-000000000002'
\set fullPurchaseID 'f30e0000-0000-0000-0000-000000000003'
\set sparseEventID 'f30e0000-0000-0000-0000-000000000004'
\set sparseGroupID 'f30e0000-0000-0000-0000-000000000005'
\set sparsePurchaseID 'f30e0000-0000-0000-0000-000000000006'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should build the full external payment payload
select is(
    external_payment_notification_payload(
        jsonb_populate_record(null::event, format('{
            "event_id": "%s",
            "external_payment_instructions": "Wire the balance before the deadline",
            "external_payment_url": "https://pay.example.test/external-payment-notification-payload/full",
            "name": "External Payment Payload Event",
            "timezone": "Europe/Amsterdam"
        }', :'fullEventID')::jsonb),
        jsonb_populate_record(null::"group", '{
            "name": "External Payment Payload Group"
        }'::jsonb),
        jsonb_populate_record(null::event_purchase, format('{
            "amount_minor": 1250,
            "currency_code": "EUR",
            "event_purchase_id": "%s",
            "hold_expires_at": "2026-09-05T10:15:30+00:00",
            "ticket_title": "Community admission"
        }', :'fullPurchaseID')::jsonb),
        '{"primary_color": "#2563eb"}'::jsonb
    ),
    format('{
        "amount_minor": 1250,
        "currency_code": "EUR",
        "dashboard_url": "/dashboard/user?tab=events",
        "deadline": 1788603330,
        "event_id": "%s",
        "event_name": "External Payment Payload Event",
        "event_purchase_id": "%s",
        "external_payment_instructions": "Wire the balance before the deadline",
        "external_payment_url": "https://pay.example.test/external-payment-notification-payload/full",
        "group_name": "External Payment Payload Group",
        "theme": {"primary_color": "#2563eb"},
        "ticket_title": "Community admission",
        "timezone": "Europe/Amsterdam"
    }', :'fullEventID', :'fullPurchaseID')::jsonb,
    'Should build the full external payment payload'
);

-- Should strip null external payment fields
select is(
    external_payment_notification_payload(
        jsonb_populate_record(null::event, format('{
            "event_id": "%s",
            "external_payment_instructions": null,
            "external_payment_url": null,
            "name": "Sparse External Payload Event",
            "timezone": "UTC"
        }', :'sparseEventID')::jsonb),
        jsonb_populate_record(null::"group", '{
            "name": "Sparse External Payload Group"
        }'::jsonb),
        jsonb_populate_record(null::event_purchase, format('{
            "amount_minor": 2500,
            "currency_code": "USD",
            "event_purchase_id": "%s",
            "hold_expires_at": "2026-09-06T11:45:00+00:00",
            "ticket_title": "Sparse admission"
        }', :'sparsePurchaseID')::jsonb),
        null
    ),
    format('{
        "amount_minor": 2500,
        "currency_code": "USD",
        "dashboard_url": "/dashboard/user?tab=events",
        "deadline": 1788695100,
        "event_id": "%s",
        "event_name": "Sparse External Payload Event",
        "event_purchase_id": "%s",
        "group_name": "Sparse External Payload Group",
        "ticket_title": "Sparse admission",
        "timezone": "UTC"
    }', :'sparseEventID', :'sparsePurchaseID')::jsonb,
    'Should strip null external payment fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
