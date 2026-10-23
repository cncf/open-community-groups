-- validate_event_ticketing_payload validates ticketing and discount payloads
-- against the resolved event row they will be persisted with.
create or replace function validate_event_ticketing_payload(
    p_configured_provider text,
    p_discount_codes jsonb,
    p_ticket_types jsonb,
    p_event event,
    p_payment_recipient jsonb,
    p_external_mode boolean,
    p_group_country_code text,
    p_validate_payment_configuration boolean
)
returns void as $$
declare
    v_amount_minor bigint;
    v_paid_capable boolean;
begin
    -- Validate collection members before deriving payment requirements
    perform validate_event_discount_codes_payload(p_discount_codes);
    perform validate_event_ticket_types_payload(p_ticket_types);

    -- Derive whether any configured price requires payment collection
    v_paid_capable := is_event_ticketing_payload_paid_capable(p_ticket_types);

    -- Validate the final payment shape only after mutation-specific guards run
    if p_validate_payment_configuration then
        -- Reject discount codes on events that cannot collect payment
        if not v_paid_capable and p_discount_codes is not null then
            raise exception 'discount_codes require positive ticket pricing' using errcode = 'OCG01';
        end if;

        -- Reject a currency on events that cannot collect payment
        if not v_paid_capable and p_event.payment_currency_code is not null then
            raise exception 'payment_currency_code requires positive ticket pricing' using errcode = 'OCG01';
        end if;

        -- Require a ready payment path and chargeable prices for paid-capable tickets
        if v_paid_capable then
            -- Validate the payment path before the currency-specific amount limits
            perform validate_event_ticketing_payment_readiness(
                p_configured_provider,
                v_paid_capable,
                p_event.payment_currency_code,
                p_payment_recipient,
                p_event,
                p_external_mode,
                p_group_country_code
            );

            -- Check each configured price against the currency's charge limits
            for v_amount_minor in
                select (price_window->>'amount_minor')::bigint
                from jsonb_array_elements(p_ticket_types) as ticket_types(ticket_type)
                cross join jsonb_array_elements(ticket_type->'price_windows') as price_windows(price_window)
            loop
                perform validate_payment_amount(p_event.payment_currency_code, v_amount_minor);
            end loop;
        end if;
    end if;
end;
$$ language plpgsql;
