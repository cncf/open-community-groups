-- Loads the durable provider refund record for an event purchase.
create or replace function get_event_purchase_refund(
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_job payment_job;
    v_refund event_purchase_refund;
begin
    -- Load the durable refund for the requested purchase
    select epr.*
    into v_refund
    from event_purchase_refund epr
    where epr.event_purchase_id = p_event_purchase_id;

    -- Reject purchases without a durable refund
    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Load the lifecycle state of the refund job
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = v_refund.payment_job_id;

    -- Return the durable provider and local finalization state
    return event_purchase_refund_to_json(v_refund, v_job);
end;
$$ language plpgsql;
