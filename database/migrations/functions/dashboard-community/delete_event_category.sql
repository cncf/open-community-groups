-- Deletes an event category from a community when not in use.
create or replace function delete_event_category(
    p_community_id uuid,
    p_event_category_id uuid
)
returns void as $$
declare
    v_events_count bigint;
begin
    -- Ensure the event category exists in the selected community
    perform 1
    from event_category ec
    where ec.community_id = p_community_id
      and ec.event_category_id = p_event_category_id;

    if not found then
        raise exception 'event category not found';
    end if;

    -- Block deletion when events still reference this category
    select count(*)
    into v_events_count
    from event e
    where e.event_category_id = p_event_category_id;

    if v_events_count > 0 then
        raise exception 'cannot delete event category in use by events';
    end if;

    -- Delete the category record
    delete from event_category ec
    where ec.community_id = p_community_id
      and ec.event_category_id = p_event_category_id;
end;
$$ language plpgsql;
