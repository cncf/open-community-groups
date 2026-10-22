-- Returns the public path of an event page, relative to the site root.
--
-- The group segment uses the pretty slug when the group has one.
create or replace function event_public_path(
    p_community_name text,
    p_group_slug text,
    p_group_slug_pretty text,
    p_event_slug text
)
returns text as $$
    select format(
        '/%s/group/%s/event/%s',
        p_community_name,
        coalesce(p_group_slug_pretty, p_group_slug),
        p_event_slug
    );
$$ language sql immutable;
