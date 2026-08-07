-- validate_event_ticketing_payload validates ticketing and discount payloads.
create or replace function validate_event_ticketing_payload(
    p_configured_provider text,
    p_discount_codes jsonb,
    p_payment_currency_code text,
    p_payment_recipient jsonb,
    p_ticket_types jsonb,
    p_validate_payment_configuration boolean default true
)
returns void as $$
declare
    v_amount_minor bigint;
    v_paid_capable boolean;
begin
    -- Validate collection members before deriving payment requirements
    perform validate_event_discount_codes_payload(p_discount_codes);
    perform validate_event_ticket_types_payload(p_ticket_types);

    v_paid_capable := is_event_ticketing_payload_paid_capable(p_ticket_types);

    -- Validate the final payment shape only after mutation-specific guards run
    if p_validate_payment_configuration then
        if not v_paid_capable and p_discount_codes is not null then
            raise exception 'discount_codes require positive ticket pricing';
        end if;

        if not v_paid_capable and p_payment_currency_code is not null then
            raise exception 'payment_currency_code requires positive ticket pricing';
        end if;

        if v_paid_capable then
            perform validate_event_ticketing_payment_readiness(
                p_configured_provider,
                v_paid_capable,
                p_payment_currency_code,
                p_payment_recipient
            );
        end if;
    end if;

    -- Validate charge amount limits for every configured price window
    if v_paid_capable and p_validate_payment_configuration then
        for v_amount_minor in
            select (price_window->>'amount_minor')::bigint
            from jsonb_array_elements(p_ticket_types) as ticket_types(ticket_type)
            cross join jsonb_array_elements(ticket_type->'price_windows') as price_windows(price_window)
        loop
            perform validate_payment_amount(p_payment_currency_code, v_amount_minor);
        end loop;
    end if;
end;
$$ language plpgsql;
