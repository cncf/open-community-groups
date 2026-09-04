-- Records confirmed attendance for a completed purchase, creating the attendee
-- row or reviving one whose state a checkout may replace (canceled attendance,
-- canceled invitation, pending registration answers or an existing
-- confirmation). Returns false when the user's attendee row is in a state a
-- checkout cannot confirm.
create or replace function confirm_event_purchase_attendee(
    p_event_id uuid,
    p_user_id uuid,
    p_manually_invited boolean
)
returns boolean as $$
begin
    -- Add the attendee, reviving only checkout-compatible states
    insert into event_attendee (event_id, user_id, manually_invited)
    values (p_event_id, p_user_id, p_manually_invited)
    on conflict (event_id, user_id) do update
    set
        attendance_canceled_at = null,
        attendance_canceled_by_user_id = null,
        manually_invited = excluded.manually_invited,
        status = 'confirmed'
    where event_attendee.status in (
        'attendance-canceled',
        'confirmed',
        'invitation-canceled',
        'registration-questions-pending'
    );

    return found;
end;
$$ language plpgsql;
