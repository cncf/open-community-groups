-- Classifies the refund workflow progress of a purchase, or null when none applies.
create or replace function event_purchase_refund_progress(
    p_purchase event_purchase,
    p_event_canceled boolean,
    p_refund event_purchase_refund,
    p_job payment_job
)
returns text as $$
    select case
        -- Refunds settled on the refund row or the purchase
        when p_refund.status = 'finalized' or p_purchase.status = 'refunded'
            then 'refunded'
        -- Recovery-pending purchases and terminal provider failures need operator recovery
        when p_purchase.status = 'refund-recovery-pending'
            or (p_refund.status = 'provider-failed' and p_refund.terminal_failure)
            then 'recovery-required'
        -- Jobs that used every automatic attempt wait for a manual retry
        when payment_job_is_exhausted(p_job)
            then 'retryable-failure'
        -- Provider work in flight or already confirmed by the provider
        when p_job.status = 'processing'
            or p_refund.status = 'provider-succeeded'
            or p_refund.provider_refund_id is not null
            then 'processing'
        -- Jobs waiting for a worker claim
        when p_job.status in ('failed', 'pending')
            then 'queued'
        -- Refund-pending purchases without refund work and live canceled-event checkouts await checkout
        when p_purchase.status = 'refund-pending'
            or (
                p_event_canceled
                and p_purchase.status = 'pending'
                and (
                    p_purchase.hold_expires_at > current_timestamp
                    or p_purchase.provider_checkout_session_id is not null
                )
            )
            then 'awaiting-checkout'
        -- Purchases outside any refund workflow have no progress
        else null
    end;
$$ language sql stable;
