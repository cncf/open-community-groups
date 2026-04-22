-- validate_payment_currency_code rejects unsupported payment currencies.
create or replace function validate_payment_currency_code(p_payment_currency_code text)
returns void as $$
declare
    v_currency_code text := nullif(upper(btrim(p_payment_currency_code)), '');
begin
    -- Require a non-empty code before checking the supported Stripe list
    if v_currency_code is null then
        raise exception 'payment_currency_code cannot be empty';
    end if;

    -- Reject currency codes that Stripe checkout cannot price
    if not exists (
        select 1
        from unnest(list_payment_currency_codes()) as supported_currency_code
        where supported_currency_code = v_currency_code
    ) then
        raise exception 'payment_currency_code must be a supported currency code';
    end if;
end;
$$ language plpgsql;
