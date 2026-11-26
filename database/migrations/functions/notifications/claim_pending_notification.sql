-- Claims the next deliverable notification within the configured rate limit.
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
declare
    v_created_at timestamptz;
    v_kind text;
    v_notification_id uuid;
    v_notification_template_data_id uuid;
    v_user_id uuid;
begin
    -- Require a positive rate limit
    if p_delivery_rate_limit <= 0 then
        raise exception 'delivery rate limit must be positive';
    end if;

    -- Require a positive rate limit window
    if p_delivery_rate_limit_window_seconds <= 0 then
        raise exception 'delivery rate limit window must be positive';
    end if;

    -- Serialize delivery reservations across all workers and server instances
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

    -- Scan pending notifications in FIFO order, failing and scrubbing dead password-reset rows
    loop
        -- Lock the oldest deliverable pending notification
        select
            n.created_at,
            n.kind,
            n.notification_id,
            n.notification_template_data_id,
            n.user_id
        into
            v_created_at,
            v_kind,
            v_notification_id,
            v_notification_template_data_id,
            v_user_id
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
            or (
                n.kind in (
                    'event-admission-offer-canceled',
                    'event-admission-offer-created'
                )
                and u.registration_status = 'pre-registered'
            )
        )
        order by n.created_at asc
        limit 1
        for update of n skip locked;

        -- Stop when no deliverable pending notification exists
        if not found then
            return;
        end if;

        -- Fail and scrub password-reset notifications whose token has expired or been replaced
        if v_kind = 'password-reset'
           and not is_password_reset_notification_active(v_user_id, v_created_at) then
            update notification n
            set
                delivery_status = 'failed',
                error = 'password reset token no longer active',
                next_delivery_attempt_at = null,
                notification_template_data_id = null,
                processed_at = current_timestamp
            where n.notification_id = v_notification_id;

            -- Delete unreferenced template data so dead tokens do not persist at rest
            if v_notification_template_data_id is not null then
                perform delete_unreferenced_notification_template_data(
                    array[v_notification_template_data_id]
                );
            end if;

            continue;
        end if;

        -- Persist the claim before any external delivery work and return its payload
        return query
        with claimed_notification as (
            update notification n
            set
                delivery_attempts = n.delivery_attempts + 1,
                delivery_claimed_at = current_timestamp,
                delivery_status = 'processing',
                error = null,
                next_delivery_attempt_at = null,
                processed_at = null
            where n.notification_id = v_notification_id
            returning
                n.delivery_claimed_at,
                n.kind,
                n.notification_id,
                n.notification_template_data_id,
                n.user_id
        )
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

        return;
    end loop;
end;
$$ language plpgsql;
