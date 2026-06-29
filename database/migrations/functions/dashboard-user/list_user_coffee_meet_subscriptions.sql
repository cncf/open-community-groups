-- list_user_coffee_meet_subscriptions returns CoffeeMeet status for all groups a user belongs to.
create or replace function list_user_coffee_meet_subscriptions(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'group_id', g.group_id,
        'group_name', g.name,
        'group_slug', g.slug,
        'alliance_name', a.name,
        'alliance_display_name', a.display_name,
        'frequency', cms.frequency,
        'active', coalesce(cms.active, false),
        'next_suggestion_at', extract(epoch from cms.next_suggestion_at)::bigint,
        'last_suggestion_at', extract(epoch from cms.last_suggestion_at)::bigint,
        'last_suggested_name', suggested.name,
        'last_suggested_username', suggested.username
    ) order by lower(a.display_name), lower(g.name)), '[]'::json)
    from group_member gm
    join "group" g using (group_id)
    join alliance a using (alliance_id)
    left join coffee_meet_subscription cms
        on cms.group_id = gm.group_id
        and cms.user_id = gm.user_id
    left join lateral (
        select
            u.name,
            u.username
        from coffee_meet_suggestion suggestion
        join "user" u on u.user_id = suggestion.suggested_user_id
        where suggestion.group_id = gm.group_id
          and suggestion.subscriber_user_id = gm.user_id
        order by suggestion.created_at desc
        limit 1
    ) suggested on true
    where gm.user_id = p_user_id
      and a.active = true
      and g.active = true
      and g.deleted = false;
$$ language sql stable;
