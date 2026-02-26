-- Adds a new event category to a community.
create or replace function add_event_category(
    p_community_id uuid,
    p_event_category jsonb
)
returns uuid as $$
declare
    v_event_category_id uuid;
begin
    -- Insert the category record
    insert into event_category (
        community_id,
        name
    ) values (
        p_community_id,
        p_event_category->>'name'
    )
    returning event_category_id into v_event_category_id;

    return v_event_category_id;
exception when unique_violation then
    raise exception 'event category already exists';
end;
$$ language plpgsql;
