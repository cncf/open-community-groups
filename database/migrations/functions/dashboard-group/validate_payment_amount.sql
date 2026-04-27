-- validate_payment_amount rejects amounts outside charge limits.
create or replace function validate_payment_amount(
    p_payment_currency_code text,
    p_amount_minor bigint
)
returns void as $$
declare
    v_currency_code text := nullif(upper(btrim(p_payment_currency_code)), '');
    v_max_amount_minor bigint;
    v_min_amount_minor bigint;
begin
    -- Validate the currency before checking currency-specific limits
    perform validate_payment_currency_code(v_currency_code);

    -- Require callers to provide an amount
    if p_amount_minor is null then
        raise exception 'payment amount is required';
    end if;

    -- Reject malformed negative amounts before checking charge limits
    if p_amount_minor < 0 then
        raise exception 'payment amount must be greater than or equal to 0';
    end if;

    -- Free tickets do not create provider charges
    if p_amount_minor = 0 then
        return;
    end if;

    -- Apply non-zero minimum charge amounts by currency
    v_min_amount_minor := case v_currency_code
        when 'AED' then 200
        when 'ARS' then 50
        when 'AUD' then 50
        when 'BRL' then 50
        when 'CAD' then 50
        when 'CHF' then 50
        when 'COP' then 50
        when 'CZK' then 1500
        when 'DKK' then 250
        when 'EUR' then 50
        when 'GBP' then 30
        when 'HKD' then 400
        when 'HUF' then 17500
        when 'IDR' then 50
        when 'ILS' then 50
        when 'INR' then 50
        when 'JPY' then 50
        when 'KRW' then 50
        when 'MXN' then 1000
        when 'MYR' then 200
        when 'NOK' then 300
        when 'NZD' then 50
        when 'PHP' then 50
        when 'PLN' then 200
        when 'RON' then 200
        when 'RUB' then 50
        when 'SEK' then 300
        when 'SGD' then 50
        when 'THB' then 1000
        when 'USD' then 50
        when 'ZAR' then 50
        else null
    end;

    -- Reject paid amounts below the configured minimum
    if v_min_amount_minor is not null and p_amount_minor < v_min_amount_minor then
        raise exception 'payment amount must be zero or at least Stripe minimum charge amount';
    end if;

    -- Apply maximum charge amounts by currency
    v_max_amount_minor := case v_currency_code
        when 'COP' then 9999999999999
        when 'HUF' then 9999999999999
        when 'IDR' then 999999999999
        when 'INR' then 999999999
        when 'JPY' then 9999999999999
        when 'LBP' then 999999999999
        else 99999999
    end;

    -- Reject paid amounts above the configured maximum
    if p_amount_minor > v_max_amount_minor then
        raise exception 'payment amount exceeds Stripe maximum charge amount';
    end if;
end;
$$ language plpgsql;
