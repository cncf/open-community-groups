-- Validates payment readiness for paid-capable ticket configuration.
create or replace function validate_event_ticketing_payment_readiness(
    p_configured_provider text,
    p_paid_capable boolean,
    p_payment_currency_code text,
    p_payment_recipient jsonb
)
returns void as $$
begin
    -- Skip provider requirements when every configured ticket price is zero
    if p_paid_capable is not true then
        return;
    end if;

    -- Validate the currency required by every positive ticket price
    if p_payment_currency_code is null then
        raise exception 'paid-capable events require payment_currency_code';
    end if;

    perform validate_payment_currency_code(p_payment_currency_code);

    -- Validate the server and group payment configuration
    if p_configured_provider is null then
        raise exception 'payments are not configured on this server';
    end if;

    if p_payment_recipient is null then
        raise exception 'paid-capable events require a payment recipient';
    end if;

    if coalesce(p_payment_recipient->>'provider', '') <> p_configured_provider then
        raise exception 'paid-capable events require a payment recipient for the server payments provider';
    end if;

    if nullif(btrim(p_payment_recipient->>'recipient_id'), '') is null then
        raise exception 'paid-capable events require a valid payment recipient';
    end if;
end;
$$ language plpgsql;
