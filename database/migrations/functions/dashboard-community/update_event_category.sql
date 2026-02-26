-- Updates an event category in a community.
create or replace function update_event_category(
    p_community_id uuid,
    p_event_category_id uuid,
    p_event_category jsonb
)
returns void as $$
begin
    -- Ensure the target category exists in the selected community
    perform 1
    from event_category ec
    where ec.community_id = p_community_id
      and ec.event_category_id = p_event_category_id;

    if not found then
        raise exception 'event category not found';
    end if;

    -- Update the category record
    update event_category set
        name = p_event_category->>'name'
    where community_id = p_community_id
      and event_category_id = p_event_category_id;
exception when unique_violation then
    raise exception 'event category already exists';
end;
$$ language plpgsql;
