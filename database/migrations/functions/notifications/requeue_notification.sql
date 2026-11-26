-- Requeues a claimed notification after a retryable delivery failure.
create or replace function requeue_notification(
    p_notification_id uuid,
    p_error text,
    p_base_retry_after_seconds bigint,
    p_max_retry_after_seconds bigint,
    p_max_delivery_attempts integer,
    p_delivery_claimed_at timestamptz
)
returns void as $$
declare
    v_created_at timestamptz;
    v_delivery_attempts integer;
    v_error text := p_error;
    v_kind text;
    v_notification_template_data_id uuid;
    v_should_fail boolean;
    v_user_id uuid;
begin
    -- Validate retry metadata before changing delivery state
    if p_error is null or btrim(p_error) = '' then
        raise exception 'delivery error is required';
    end if;
    if p_base_retry_after_seconds is null or p_base_retry_after_seconds <= 0 then
        raise exception 'base retry delay must be positive';
    end if;
    if p_max_retry_after_seconds is null or p_max_retry_after_seconds <= 0 then
        raise exception 'maximum retry delay must be positive';
    end if;
    if p_max_retry_after_seconds < p_base_retry_after_seconds then
        raise exception 'maximum retry delay cannot be less than base retry delay';
    end if;
    if p_max_delivery_attempts is null or p_max_delivery_attempts <= 0 then
        raise exception 'maximum delivery attempts must be positive';
    end if;

    -- Lock the claimed notification and capture its metadata
    select created_at, delivery_attempts, kind, notification_template_data_id, user_id
    into v_created_at, v_delivery_attempts, v_kind, v_notification_template_data_id, v_user_id
    from notification
    where notification_id = p_notification_id
    and delivery_status = 'processing'
    and delivery_claimed_at = p_delivery_claimed_at
    for update;

    -- Reject stale or missing delivery claims
    if not found then
        raise exception 'notification delivery claim not found or no longer active';
    end if;

    -- Fail immediately when the attempt budget is exhausted or a reset token is no longer active
    v_should_fail := v_delivery_attempts >= p_max_delivery_attempts;
    if not v_should_fail
       and v_kind = 'password-reset'
       and not is_password_reset_notification_active(v_user_id, v_created_at) then
        v_should_fail := true;
        v_error := 'password reset token no longer active';
    end if;

    -- Requeue retryable failures or finalize exhausted/superseded notifications
    update notification
    set
        delivery_status = case
            -- Mark exhausted or superseded claims as failed
            when v_should_fail then 'failed'
            -- Return retryable claims to pending with backoff
            else 'pending'
        end,
        error = v_error,
        next_delivery_attempt_at = case
            -- Clear retry schedule when finalizing as failed
            when v_should_fail then null
            -- Schedule the next attempt using capped exponential backoff
            else current_timestamp + make_interval(
                secs => least(
                    p_max_retry_after_seconds,
                    (
                        p_base_retry_after_seconds::numeric
                        * power(2::numeric, least(greatest(v_delivery_attempts - 1, 0), 30))
                    )::bigint
                )::double precision
            )
        end,
        notification_template_data_id = case
            -- Detach sensitive password-reset payloads on terminal failure
            when v_should_fail and v_kind = 'password-reset' then null
            -- Keep template data links while retries remain or for ordinary notifications
            else notification_template_data_id
        end,
        processed_at = case
            -- Stamp completion time on terminal failure
            when v_should_fail then current_timestamp
            -- Clear completion time while pending retry
            else null
        end
    where notification_id = p_notification_id;

    -- Delete unreferenced password-reset template data on terminal failure
    if v_should_fail and v_kind = 'password-reset' and v_notification_template_data_id is not null then
        perform delete_unreferenced_notification_template_data(
            array[v_notification_template_data_id]
        );
    end if;
end;
$$ language plpgsql;
