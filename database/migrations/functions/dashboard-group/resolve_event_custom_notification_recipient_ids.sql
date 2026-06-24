-- Resolves custom email recipient user ids after applying scope-specific eligibility.
create or replace function resolve_event_custom_notification_recipient_ids(
    p_group_id uuid,
    p_event_id uuid,
    p_recipient_scope text,
    p_requested_user_ids uuid[]
)
returns uuid[] as $$
    select coalesce(array_agg(recipients.user_id order by recipients.user_id asc), array[]::uuid[])
    from (
        select distinct ea.user_id
        from event_attendee ea
        join event e using (event_id)
        join "user" u using (user_id)
        left join lateral (
            select event_purchase_id
            from event_purchase
            where event_id = ea.event_id
            and user_id = ea.user_id
            and status = 'pending'
            and hold_expires_at > current_timestamp
            order by created_at desc, event_purchase_id desc
            limit 1
        ) pending_ep on true
        where ea.event_id = p_event_id
        and e.group_id = p_group_id
        and ea.status in ('confirmed', 'registration-questions-pending')
        and u.email_verified = true
        and coalesce(u.optional_notifications_enabled, true) = true
        and pending_ep.event_purchase_id is null
        and (
            (
                p_recipient_scope = 'all-attendees'
                and p_requested_user_ids is null
            )
            or (
                p_recipient_scope = 'selected-attendees'
                and p_requested_user_ids is not null
                and ea.user_id = any(p_requested_user_ids)
            )
        )
    ) recipients;
$$ language sql;
