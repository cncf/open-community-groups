-- Deletes one bounded batch of expired email verification codes.
create or replace function delete_expired_email_verification_codes(
    p_batch_size integer default 1000
)
returns integer as $$
declare
    v_deleted_count integer;
begin
    -- Reject missing or out-of-range batch sizes
    if p_batch_size is null or p_batch_size <= 0 or p_batch_size > 1000 then
        raise exception 'email verification code cleanup batch size must be between 1 and 1000';
    end if;

    -- Serialize cleanup sweeps across application replicas
    if not pg_try_advisory_xact_lock(
        hashtextextended('ocg:email-verification-code-cleanup', 0)
    ) then
        return 0;
    end if;

    -- Delete one bounded batch of codes outside the shared verification window
    with expired_codes as (
        select email_verification_code_id
        from email_verification_code
        where created_at <= current_timestamp - email_verification_code_ttl()
        order by created_at, email_verification_code_id
        for update skip locked
        limit p_batch_size
    )
    delete from email_verification_code evc
    using expired_codes expired
    where evc.email_verification_code_id = expired.email_verification_code_id;

    -- Return the number of deleted codes
    get diagnostics v_deleted_count = row_count;
    return v_deleted_count;
end;
$$ language plpgsql;
