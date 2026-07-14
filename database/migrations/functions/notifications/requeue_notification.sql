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

    -- Requeue retryable failures until the durable claim budget is exhausted
    update notification
    set
        delivery_status = case
            when delivery_attempts >= p_max_delivery_attempts then 'failed'
            else 'pending'
        end,
        error = p_error,
        next_delivery_attempt_at = case
            when delivery_attempts >= p_max_delivery_attempts then null
            else current_timestamp + make_interval(
                secs => least(
                    p_max_retry_after_seconds,
                    (
                        p_base_retry_after_seconds::numeric
                        * power(2::numeric, least(greatest(delivery_attempts - 1, 0), 30))
                    )::bigint
                )::double precision
            )
        end,
        processed_at = case
            when delivery_attempts >= p_max_delivery_attempts then current_timestamp
            else null
        end
    where notification_id = p_notification_id
    and delivery_status = 'processing'
    and delivery_claimed_at = p_delivery_claimed_at;

    if not found then
        raise exception 'notification delivery claim not found or no longer active';
    end if;
end;
$$ language plpgsql;
