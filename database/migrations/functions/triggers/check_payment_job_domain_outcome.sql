-- Rejects a domain row without its provider outcome while its payment job is completed.
create or replace function check_payment_job_domain_outcome()
returns trigger as $$
declare
    v_has_outcome boolean;
    v_job_status text;
begin
    -- Load the lifecycle state of the job the row belongs to
    select pj.status
    into v_job_status
    from payment_job pj
    where pj.payment_job_id = new.payment_job_id;

    -- Only completed jobs require their outcome
    if v_job_status is distinct from 'completed' then
        return new;
    end if;

    -- Resolve the typed outcome column of the table
    case tg_table_name
        -- Fee adjustments complete with the provider application-fee refund
        when 'event_purchase_application_fee_adjustment' then
            v_has_outcome := new.provider_application_fee_refund_id is not null;

        -- Credit notes complete with the provider credit-note document
        when 'event_purchase_credit_note' then
            v_has_outcome := new.provider_credit_note_id is not null;

        -- Refunds complete once their local finalization is recorded
        when 'event_purchase_refund' then
            v_has_outcome := new.finalized_at is not null;

        -- Reject tables without a completion contract
        else
            raise exception 'payment job domain table has no completion outcome';
    end case;

    -- Reject clearing or omitting the outcome of completed work
    if not v_has_outcome then
        raise exception 'payment job completed without its provider outcome';
    end if;

    return new;
end;
$$ language plpgsql;
