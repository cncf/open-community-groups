-- validate_event_ticketing_payload validates ticketing and discount payloads.
create or replace function validate_event_ticketing_payload(
    p_discount_codes jsonb,
    p_payment_currency_code text,
    p_ticket_types jsonb,
    p_waitlist_enabled boolean
)
returns void as $$
begin
    -- Validate shared relationships between ticketing and event settings
    if p_ticket_types is not null and p_waitlist_enabled = true then
        raise exception 'waitlist cannot be enabled for ticketed events';
    end if;

    if p_ticket_types is not null and p_payment_currency_code is null then
        raise exception 'ticketed events require payment_currency_code';
    end if;

    if p_ticket_types is null and p_discount_codes is not null then
        raise exception 'discount_codes require ticket_types';
    end if;

    if p_ticket_types is null and p_payment_currency_code is not null then
        raise exception 'payment_currency_code requires ticket_types';
    end if;

    if p_ticket_types is not null and p_payment_currency_code is not null then
        perform validate_payment_currency_code(p_payment_currency_code);
    end if;

    perform validate_event_discount_codes_payload(p_discount_codes);
    perform validate_event_ticket_types_payload(p_ticket_types);
end;
$$ language plpgsql;
