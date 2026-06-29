-- upsert_coffee_meet_subscription subscribes a group member to CoffeeMeet.
create or replace function upsert_coffee_meet_subscription(
    p_user_id uuid,
    p_group_id uuid,
    p_frequency text
)
returns void as $$
begin
    if p_frequency not in ('weekly', 'biweekly', 'monthly') then
        raise exception 'invalid CoffeeMeet frequency: %', p_frequency
            using errcode = 'check_violation';
    end if;

    if not exists (
        select 1
        from group_member gm
        join "group" g using (group_id)
        join alliance a using (alliance_id)
        where gm.user_id = p_user_id
          and gm.group_id = p_group_id
          and g.active = true
          and g.deleted = false
          and a.active = true
    ) then
        raise exception 'user is not an active member of this group'
            using errcode = 'insufficient_privilege';
    end if;

    insert into coffee_meet_subscription (
        group_id,
        user_id,
        frequency,
        active,
        next_suggestion_at,
        updated_at
    ) values (
        p_group_id,
        p_user_id,
        p_frequency,
        true,
        current_timestamp,
        current_timestamp
    )
    on conflict (group_id, user_id) do update set
        frequency = excluded.frequency,
        active = true,
        next_suggestion_at = least(
            coffee_meet_subscription.next_suggestion_at,
            current_timestamp
        ),
        updated_at = current_timestamp;
end;
$$ language plpgsql;
