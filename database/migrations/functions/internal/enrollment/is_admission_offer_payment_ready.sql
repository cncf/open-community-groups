-- Reports whether a seat priced at p_amount_minor can currently be collected
-- under the organizer offer readiness rule, the boolean form of
-- validate_admission_offer_payment_readiness that checkout also enforces. The
-- result depends only on whether the amount is positive.
create or replace function is_admission_offer_payment_ready(
    p_event event,
    p_group "group",
    p_amount_minor bigint,
    p_configured_provider text
)
returns boolean as $$
begin
    -- Apply the organizer offer readiness rule
    perform validate_admission_offer_payment_readiness(
        p_event,
        p_group,
        p_amount_minor,
        p_configured_provider
    );

    -- Report the seat as collectable once the rule passes
    return true;
exception
    -- Report readiness rejections as an uncollectable seat
    when sqlstate 'OCG01' then
        return false;
end;
$$ language plpgsql;
