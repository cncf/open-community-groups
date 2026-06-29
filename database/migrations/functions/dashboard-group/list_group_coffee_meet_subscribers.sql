-- list_group_coffee_meet_subscribers returns active CoffeeMeet subscribers for a group dashboard.
create or replace function list_group_coffee_meet_subscribers(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'user_id', u.user_id,
        'username', u.username,
        'name', u.name,
        'photo_url', u.photo_url,
        'frequency', cms.frequency,
        'next_suggestion_at', extract(epoch from cms.next_suggestion_at)::bigint,
        'last_suggestion_at', extract(epoch from cms.last_suggestion_at)::bigint,
        'suggestions_total', coalesce(suggestion_counts.total, 0)
    ) order by cms.next_suggestion_at asc, lower(coalesce(u.name, u.username))), '[]'::json)
    from coffee_meet_subscription cms
    join group_member gm
        on gm.group_id = cms.group_id
        and gm.user_id = cms.user_id
    join "user" u on u.user_id = cms.user_id
    left join lateral (
        select count(*)::int as total
        from coffee_meet_suggestion suggestion
        where suggestion.group_id = cms.group_id
          and suggestion.subscriber_user_id = cms.user_id
    ) suggestion_counts on true
    where cms.group_id = p_group_id
      and cms.active = true;
$$ language sql stable;
