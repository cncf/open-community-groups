-- claim_pending_notification claims the next notification pending delivery.
create or replace function claim_pending_notification()
returns table (
    attachment_ids uuid[],
    email text,
    kind text,
    notification_id uuid,

    template_data jsonb
) as $$
    -- Find the oldest deliverable pending notification
    with next_notification as (
        select n.notification_id
        from notification n
        join "user" u using (user_id)
        where n.delivery_status = 'pending'
        and (u.email_verified = true or n.kind = 'email-verification')
        order by n.created_at asc
        limit 1
        for update of n skip locked
    ),
    -- Persist the claim before any external delivery work
    claimed_notification as (
        update notification n
        set
            delivery_attempts = n.delivery_attempts + 1,
            delivery_claimed_at = current_timestamp,
            delivery_status = 'processing',
            error = null
        from next_notification nn
        where n.notification_id = nn.notification_id
        returning
            n.kind,
            n.notification_id,
            n.notification_template_data_id,
            n.user_id
    )
    -- Return the claimed notification payload to the worker
    select
        (
            select array_agg(na.attachment_id order by na.attachment_id)
            from notification_attachment na
            where na.notification_id = cn.notification_id
        ) as attachment_ids,
        u.email,
        cn.kind,
        cn.notification_id,

        ntd.data as template_data
    from claimed_notification cn
    join "user" u using (user_id)
    left join notification_template_data ntd using (notification_template_data_id);
$$ language sql;
