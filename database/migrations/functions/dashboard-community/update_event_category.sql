-- Updates an event category in a community.
create or replace function update_event_category(
    p_actor_user_id uuid,
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
        raise exception 'event category not found' using errcode = 'OCG01';
    end if;

    -- Update the category record
    update event_category set
        name = p_event_category->>'name'
    where community_id = p_community_id
      and event_category_id = p_event_category_id;

    -- Track the updated category
    perform insert_audit_log(
        'event_category_updated',
        p_actor_user_id,
        'event_category',
        p_event_category_id,
        p_community_id
    );
exception
    when unique_violation then
        raise exception 'event category already exists' using errcode = 'OCG01';
    when check_violation then
        raise exception 'event category name is invalid' using errcode = 'OCG01';
end;
$$ language plpgsql;
