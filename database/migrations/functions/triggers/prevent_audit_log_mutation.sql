-- Prevents updates and deletes on audit_log rows.
create or replace function prevent_audit_log_mutation()
returns trigger as $$
begin
    raise exception 'audit_log is append-only';
end;
$$ language plpgsql;

drop trigger if exists audit_log_mutation_guard on audit_log;

create trigger audit_log_mutation_guard
before update or delete on audit_log
for each row
execute function prevent_audit_log_mutation();
