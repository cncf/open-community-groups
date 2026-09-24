-- Returns whether an event has unanswered co-host invitations.
create or replace function event_has_pending_cohosts(p_event_id uuid)
returns boolean as $$
    select exists (
        select 1
        from event_cohost ec
        where ec.event_id = p_event_id
        and ec.event_cohost_status_id = 'pending'
    );
$$ language sql stable;
