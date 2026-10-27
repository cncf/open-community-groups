-- Ends a user's active attendance at an event, recording who canceled it and
-- clearing check-in. Without a refunded purchase it ends confirmed attendance.
-- When a refunded purchase is given it also ends checkout-answer attendance,
-- unless another completed or refund-requested purchase of the user still
-- occupies the seat. Returns whether attendance was ended.
create or replace function mark_event_attendance_canceled(
    p_event_id uuid,
    p_user_id uuid,
    p_canceled_by_user_id uuid,
    p_refunded_event_purchase_id uuid default null
)
returns boolean as $$
begin
    -- Preserve the attendee row while removing its active attendance
    update event_attendee
    set
        attendance_canceled_at = current_timestamp,
        attendance_canceled_by_user_id = p_canceled_by_user_id,
        checked_in = false,
        checked_in_at = null,
        status = 'attendance-canceled'
    where event_id = p_event_id
    and user_id = p_user_id
    and (
        -- End confirmed attendance released without a refund
        (
            p_refunded_event_purchase_id is null
            and status = 'confirmed'
        )
        -- End attendance owned by the refunded purchase, unless a replacement
        -- purchase still occupies the seat
        or (
            p_refunded_event_purchase_id is not null
            and status in ('confirmed', 'registration-questions-pending')
            and not exists (
                select 1
                from event_purchase replacement
                where replacement.event_id = p_event_id
                and replacement.event_purchase_id <> p_refunded_event_purchase_id
                and replacement.status in ('completed', 'refund-requested')
                and replacement.user_id = p_user_id
            )
        )
    );

    -- Report whether active attendance was ended
    return found;
end;
$$ language plpgsql;
