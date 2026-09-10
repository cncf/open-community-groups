-- Ensures a paid seat reserved by an organizer-issued admission offer can be
-- collected: external events must still be eligible for external payments,
-- other events must satisfy the provider readiness rules for the event
-- currency and group recipient.
create or replace function validate_admission_offer_payment_readiness(
    p_event event,
    p_group "group",
    p_amount_minor bigint,
    p_configured_provider text
)
returns void as $$
begin
    -- External-marked events only need to remain eligible for paid seats
    if p_event.external_payment_url is not null then
        -- Reject paid offers when the external event is no longer eligible
        if p_amount_minor > 0 and not is_event_external_payments_ready(p_event.event_id) then
            raise exception 'external payments are not available for this event' using errcode = 'OCG01';
        end if;

    -- Keep the Stripe provider requirement for non-external events
    else
        perform validate_event_ticketing_payment_readiness(
            p_configured_provider,
            p_amount_minor > 0,
            p_event.payment_currency_code,
            p_group.payment_recipient,
            p_event.event_id
        );
    end if;
end;
$$ language plpgsql;
