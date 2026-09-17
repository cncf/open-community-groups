-- Returns a claimed notification to the pending queue without recording a
-- delivery outcome, so an interrupted worker does not spend delivery budget.
create or replace function release_notification(
    p_notification_id uuid,
    p_delivery_claimed_at timestamptz
)
returns void as $$
begin
    -- Make the claim immediately claimable again, refunding the attempt the
    -- claim consumed and keeping the last recorded error intact
    update notification
    set
        delivery_attempts = greatest(delivery_attempts - 1, 0),
        delivery_status = 'pending',
        next_delivery_attempt_at = current_timestamp,
        processed_at = null
    where notification_id = p_notification_id
    and delivery_status = 'processing'
    and delivery_claimed_at = p_delivery_claimed_at;

    -- Confirm that the claimed notification changed state
    if not found then
        raise exception 'notification delivery claim not found or no longer active';
    end if;
end;
$$ language plpgsql;
