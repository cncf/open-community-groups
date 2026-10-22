-- Validates the attempt identifiers a refund worker reports with a provider
-- refund result, before any refund row is looked up or locked.
create or replace function validate_event_purchase_refund_result(
    p_expected_idempotency_key text,
    p_provider_refund_id text
)
returns void as $$
begin
    -- Require the idempotency key of the attempt that produced the result
    if nullif(btrim(p_expected_idempotency_key), '') is null then
        raise exception 'expected idempotency key is required';
    end if;

    -- Require the provider refund the attempt produced
    if nullif(btrim(p_provider_refund_id), '') is null then
        raise exception 'provider refund id is required';
    end if;
end;
$$ language plpgsql;
