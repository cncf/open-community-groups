-- Rejects completing a payment job whose domain row lacks its provider outcome.
create or replace function check_payment_job_completion_outcome()
returns trigger as $$
declare
    v_has_outcome boolean;
begin
    -- Resolve the typed outcome the completed job must have written
    case new.kind
        -- Fee adjustments complete with the provider application-fee refund
        when 'event-purchase-application-fee-adjustment' then
            select epafa.provider_application_fee_refund_id is not null
            into v_has_outcome
            from event_purchase_application_fee_adjustment epafa
            where epafa.payment_job_id = new.payment_job_id;

        -- Credit notes complete with the provider credit-note document
        when 'event-purchase-credit-note' then
            select epcn.provider_credit_note_id is not null
            into v_has_outcome
            from event_purchase_credit_note epcn
            where epcn.payment_job_id = new.payment_job_id;

        -- Refunds complete once their local finalization is recorded
        when 'event-purchase-refund' then
            select epr.finalized_at is not null
            into v_has_outcome
            from event_purchase_refund epr
            where epr.payment_job_id = new.payment_job_id;

        -- Reject kinds without a completion contract
        else
            raise exception 'payment job kind has no completion outcome';
    end case;

    -- Reject completion without a domain row or without its outcome
    if not coalesce(v_has_outcome, false) then
        raise exception 'payment job completed without its provider outcome';
    end if;

    return new;
end;
$$ language plpgsql;
