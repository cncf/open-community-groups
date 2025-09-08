-- publish_event sets published=true and records publication metadata for an event.
create or replace function publish_event(
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
begin
    update event set
        published = true,
        published_at = now(),
        published_by = p_user_id
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    if not found then
        raise exception 'event not found';
    end if;
end;
$$ language plpgsql;

