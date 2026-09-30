-- Returns, in input order, the recipients who accept a notification kind for
-- the given groups. It is for callers that must decide eligibility before
-- building content; enqueue_notification still makes the final decision.
create or replace function filter_notification_recipient_ids(
    p_kind text,
    p_recipients uuid[],
    p_group_ids uuid[]
)
returns uuid[] as $$
    select coalesce(array_agg(a.user_id order by a.ordinal), '{}'::uuid[])
    from users_accepting_notification(p_kind, p_recipients, p_group_ids) a;
$$ language sql stable;
