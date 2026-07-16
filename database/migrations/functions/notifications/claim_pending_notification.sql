-- claim_pending_notification claims the next notification pending delivery.
create or replace function claim_pending_notification(
    p_delivery_rate_limit integer default 15000,
    p_delivery_rate_limit_window_seconds integer default 60
)
returns table (
    attachment_ids uuid[],
    delivery_claimed_at timestamptz,
    email text,
    kind text,
    notification_id uuid,

    template_data jsonb
) as $$
begin
    -- Check rate limit params are valid
    if p_delivery_rate_limit <= 0 then
        raise exception 'delivery rate limit must be positive';
    end if;
    if p_delivery_rate_limit_window_seconds <= 0 then
        raise exception 'delivery rate limit window must be positive';
    end if;

    -- Serialize delivery reservations across all workers and server instances.
    perform pg_advisory_xact_lock(hashtextextended('ocg:notification-delivery-rate-limit', 0));

    -- Check if the rate limit has been reached
    if (
        select count(*)
        from notification n
        where n.delivery_claimed_at >= current_timestamp - make_interval(
            secs => p_delivery_rate_limit_window_seconds::double precision
        )
    ) >= p_delivery_rate_limit::bigint then
        return;
    end if;

    -- Find the oldest deliverable pending notification
    return query
    with next_notification as (
        select n.notification_id
        from notification n
        join "user" u using (user_id)
        where n.delivery_status = 'pending'
        and (
            n.next_delivery_attempt_at is null
            or n.next_delivery_attempt_at <= current_timestamp
        )
        and (
            (u.registration_status = 'registered' and u.email_verified = true)
            or n.kind = 'email-verification'
            or (n.kind = 'event-invitation' and u.registration_status = 'pre-registered')
        )
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
            error = null,
            next_delivery_attempt_at = null,
            processed_at = null
        from next_notification nn
        where n.notification_id = nn.notification_id
        returning
            n.delivery_claimed_at,
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
        cn.delivery_claimed_at,
        u.email,
        cn.kind,
        cn.notification_id,

        ntd.data as template_data
    from claimed_notification cn
    join "user" u using (user_id)
    left join notification_template_data ntd using (notification_template_data_id);
end;
$$ language plpgsql;
