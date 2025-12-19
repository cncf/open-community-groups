-- get_pending_notification returns the next notification pending delivery.
create or replace function get_pending_notification()
returns table (
    attachment_ids uuid[],
    email text,
    kind text,
    notification_id uuid,

    template_data jsonb
) as $$
    select
        (
            select array_agg(na.attachment_id order by na.attachment_id)
            from notification_attachment na
            where na.notification_id = n.notification_id
        ) as attachment_ids,
        u.email,
        n.kind,
        n.notification_id,

        ntd.data as template_data
    from notification n
    join "user" u using (user_id)
    left join notification_template_data ntd using (notification_template_data_id)
    where n.processed = false
    and (u.email_verified = true or n.kind = 'email-verification')
    order by n.created_at asc
    limit 1
    for update of n skip locked;
$$ language sql;
