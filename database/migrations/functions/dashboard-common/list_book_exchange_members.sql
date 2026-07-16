-- list_book_exchange_members lists private book exchange member lists visible to admins.
create or replace function list_book_exchange_members(
    p_alliance_id uuid,
    p_group_id uuid default null
)
returns jsonb as $$
    select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', u.user_id,
        'username', u.username,
        'name', u.name,
        'email', u.email,
        'photo_url', u.photo_url,
        'title', u.title,
        'company', u.company,
        'city', u.city,
        'country', u.country,
        'book_exchange_books', u.book_exchange_books,
        'group_id', g.group_id,
        'group_name', g.name,
        'alliance_id', a.alliance_id,
        'alliance_display_name', a.display_name
    ) order by g.name, u.name, u.username), '[]'::jsonb)
    from alliance a
    join "group" g on g.alliance_id = a.alliance_id
    join group_member gm on gm.group_id = g.group_id
    join "user" u on u.user_id = gm.user_id
    where a.alliance_id = p_alliance_id
      and a.active = true
      and a.book_exchange_enabled = true
      and g.active = true
      and g.deleted = false
      and g.book_exchange_enabled = true
      and (p_group_id is null or g.group_id = p_group_id)
      and u.email_verified = true
      and u.registration_status = 'registered'
      and u.book_exchange_enabled = true;
$$ language sql stable;
