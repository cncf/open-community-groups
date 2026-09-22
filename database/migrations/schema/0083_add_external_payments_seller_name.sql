-- Adds the legal name of the organization collecting external payments for a group.

alter table "group"
    add column external_payments_seller_display_name text
        check (btrim(external_payments_seller_display_name) <> '');

-- Replace the payload resolvers that now take rail selection and readiness separately.
drop function if exists resolve_event_payload(jsonb, event, boolean);
drop function if exists resolve_event_payment_rail(event, jsonb, boolean);
