-- Resolves custom email recipient user ids. Eligibility comes from
-- event_custom_notification_recipients; this function applies the recipient
-- scope.
create or replace function resolve_event_custom_notification_recipient_ids(
    p_group_id uuid,
    p_event_id uuid,
    p_recipient_scope text,
    p_requested_user_ids uuid[]
)
returns uuid[] as $$
    select coalesce(array_agg(r.user_id order by r.user_id asc), array[]::uuid[])
    from event_custom_notification_recipients(p_group_id, p_event_id) r
    where (
        p_recipient_scope = 'all-attendees'
        and p_requested_user_ids is null
    )
    or (
        p_recipient_scope = 'selected-attendees'
        and p_requested_user_ids is not null
        and r.user_id = any(p_requested_user_ids)
    );
$$ language sql stable;
