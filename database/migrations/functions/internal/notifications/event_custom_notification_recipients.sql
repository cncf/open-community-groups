-- Returns the attendees of a group's event who can receive an organizer event
-- email: confirmed or registration-questions-pending attendance, a verified
-- email, 'event-custom' accepted for the group, and no live pending checkout
-- hold.
create or replace function event_custom_notification_recipients(
    p_group_id uuid,
    p_event_id uuid
)
returns table (user_id uuid) as $$
    select ea.user_id
    from event_attendee ea
    join event e using (event_id)
    join "user" u using (user_id)
    left join lateral (
        select ep.event_purchase_id
        from event_purchase ep
        where ep.event_id = ea.event_id
        and ep.user_id = ea.user_id
        and ep.status = 'pending'
        and ep.hold_expires_at > current_timestamp
        order by ep.created_at desc, ep.event_purchase_id desc
        limit 1
    ) pending_ep on true
    where ea.event_id = p_event_id
    and e.group_id = p_group_id
    and ea.status in ('confirmed', 'registration-questions-pending')
    and u.email_verified = true
    and exists (
        select 1
        from users_accepting_notification('event-custom', array[ea.user_id], array[p_group_id])
    )
    and pending_ep.event_purchase_id is null;
$$ language sql stable;
