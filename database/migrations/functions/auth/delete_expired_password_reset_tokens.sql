-- Deletes one bounded batch of expired password reset tokens.
create or replace function delete_expired_password_reset_tokens(
    p_batch_size integer default 1000
)
returns integer as $$
declare
    v_deleted_count integer;
    v_deleted_user_ids uuid[];
begin
    -- Reject missing or out-of-range batch sizes
    if p_batch_size is null or p_batch_size <= 0 or p_batch_size > 1000 then
        raise exception 'password reset token cleanup batch size must be between 1 and 1000';
    end if;

    -- Serialize cleanup sweeps across application replicas
    if not pg_try_advisory_xact_lock(
        hashtextextended('ocg:password-reset-token-cleanup', 0)
    ) then
        return 0;
    end if;

    -- Delete one bounded batch of tokens outside the shared reset window
    with expired_tokens as (
        select token_hash
        from password_reset_token
        where created_at <= current_timestamp - password_reset_token_ttl()
        order by created_at, token_hash
        for update skip locked
        limit p_batch_size
    ),
    deleted as (
        delete from password_reset_token prt
        using expired_tokens expired
        where prt.token_hash = expired.token_hash
        returning prt.user_id
    )
    select count(*)::integer, array_agg(distinct user_id)
    into v_deleted_count, v_deleted_user_ids
    from deleted;

    -- Scrub stored password-reset notification payloads for deleted expired tokens
    perform purge_password_reset_notification_data(v_deleted_user_ids);

    -- Return the number of deleted tokens
    return coalesce(v_deleted_count, 0);
end;
$$ language plpgsql;
