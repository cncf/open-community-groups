-- Checks that the provider validation snapshot carried by an event payload
-- (`_payment_validation`) still describes the group recipient and tax
-- configuration about to be written. The server validates the configuration
-- with the payment provider before calling the database, so any drift between
-- that snapshot and the locked state is rejected. Callers decide when the
-- binding is required (paid-capable tickets on the provider rail).
create or replace function validate_event_payment_validation(
    p_event jsonb,
    p_payment_recipient jsonb,
    p_manual_tax_rate_ids text[],
    p_tax_behavior text,
    p_tax_calculation_mode text
)
returns void as $$
declare
    v_payment_validation jsonb := p_event->'_payment_validation';
begin
    -- Reject snapshots missing, taken for another recipient, or contradicting the tax settings
    if v_payment_validation is null
       or not (v_payment_validation ? 'expected_payment_recipient')
       or not (v_payment_validation ? 'validated_payment_recipient')
       or not (v_payment_validation ? 'require_automatic_tax')
       or p_payment_recipient is distinct from nullif(
           v_payment_validation->'expected_payment_recipient',
           'null'::jsonb
       )
       or p_payment_recipient is distinct from nullif(
           v_payment_validation->'validated_payment_recipient',
           'null'::jsonb
       )
       or (
           coalesce(nullif(p_event->>'tax_calculation_mode', ''), 'automatic') = 'automatic'
           and not (v_payment_validation->>'require_automatic_tax')::boolean
       )
       or (
           p_tax_calculation_mode = 'manual'
           and (
               v_payment_validation->'manual_tax_rate_ids'
                   is distinct from to_jsonb(p_manual_tax_rate_ids)
               or v_payment_validation->>'tax_behavior' is distinct from p_tax_behavior
               or v_payment_validation->>'tax_calculation_mode' <> 'manual'
           )
       ) then
        raise exception 'payment configuration changed during provider validation' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
