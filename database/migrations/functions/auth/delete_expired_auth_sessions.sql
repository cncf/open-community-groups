-- Deletes one bounded batch of expired authentication sessions.
create or replace function delete_expired_auth_sessions(
    p_batch_size integer default 1000
)
returns integer as $$
declare
    v_deleted_count integer;
begin
    -- Reject missing or out-of-range batch sizes
    if p_batch_size is null or p_batch_size <= 0 or p_batch_size > 1000 then
        raise exception 'auth session cleanup batch size must be between 1 and 1000';
    end if;

    -- Serialize cleanup sweeps across application replicas
    if not pg_try_advisory_xact_lock(hashtextextended('ocg:auth-session-cleanup', 0)) then
        return 0;
    end if;

    -- Delete one bounded batch of expired sessions past the 1-minute grace window
    with expired_sessions as (
        select auth_session_id
        from auth_session
        where expires_at <= current_timestamp - interval '1 minute'
        order by expires_at, auth_session_id
        for update skip locked
        limit p_batch_size
    )
    delete from auth_session s
    using expired_sessions expired
    where s.auth_session_id = expired.auth_session_id;

    -- Return the number of deleted sessions
    get diagnostics v_deleted_count = row_count;
    return v_deleted_count;
end;
$$ language plpgsql;
