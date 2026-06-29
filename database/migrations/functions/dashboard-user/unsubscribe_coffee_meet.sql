-- unsubscribe_coffee_meet disables a user's CoffeeMeet subscription for one group.
create or replace function unsubscribe_coffee_meet(
    p_user_id uuid,
    p_group_id uuid
)
returns void as $$
    update coffee_meet_subscription
    set
        active = false,
        updated_at = current_timestamp
    where user_id = p_user_id
      and group_id = p_group_id;
$$ language sql;
