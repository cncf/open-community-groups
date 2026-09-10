-- Returns whether the user has another purchase for the event whose refund
-- still awaits operator recovery. Checkout stays blocked until it settles so
-- the recovery cannot be confused with a replacement purchase.
create or replace function event_has_pending_refund_recovery(
    p_event_id uuid,
    p_user_id uuid,
    p_excluded_event_purchase_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and ep.status = 'refund-recovery-pending'
        and (
            p_excluded_event_purchase_id is null
            or ep.event_purchase_id <> p_excluded_event_purchase_id
        )
    );
$$ language sql stable;
