-- Returns whether the domain row of a payment job is in a state a worker can act on.
create or replace function payment_job_is_ready(p_job payment_job)
returns boolean as $$
    select case p_job.kind
        -- Fee refunds need the provider application fee the purchase was charged with
        when 'event-purchase-application-fee-adjustment' then exists (
            select 1
            from event_purchase ep
            where ep.event_purchase_id = p_job.event_purchase_id
            and ep.provider_application_fee_id is not null
        )
        -- Credit notes follow a customer refund the provider has confirmed
        when 'event-purchase-credit-note' then exists (
            select 1
            from event_purchase_credit_note epcn
            join event_purchase_refund epr
                on epr.event_purchase_refund_id = epcn.event_purchase_refund_id
            where epcn.payment_job_id = p_job.payment_job_id
            and epr.provider_refunded_at is not null
        )
        -- Refunds pinned to a terminal provider failure wait for operator recovery
        when 'event-purchase-refund' then exists (
            select 1
            from event_purchase_refund epr
            where epr.payment_job_id = p_job.payment_job_id
            and not (epr.status = 'provider-failed' and epr.terminal_failure)
        )
        else false
    end;
$$ language sql stable;
