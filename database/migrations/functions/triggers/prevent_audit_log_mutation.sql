-- Prevents updates and deletes on audit_log rows.
create or replace function prevent_audit_log_mutation()
returns trigger as $$
begin
    -- Reject every attempted mutation of append-only audit history
    raise exception 'audit_log is append-only';
end;
$$ language plpgsql;
