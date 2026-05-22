-- Add optional admin-managed pretty slugs for groups.

-- Add the nullable pretty slug column
alter table "group"
add column slug_pretty text;

-- Enforce the local pretty slug shape
alter table "group"
add constraint group_slug_pretty_chk check (
    slug_pretty is null
    or (
        char_length(slug_pretty) <= 50
        and slug_pretty ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$'
        and slug_pretty not like '%--%'
    )
);

-- Enforce pretty slug uniqueness within each community
create unique index group_slug_pretty_community_id_key
on "group" (slug_pretty, community_id)
where slug_pretty is not null;

-- Validate pretty slug routing conflicts with generated slugs
create or replace function validate_group_slug_pretty()
returns trigger as $$
begin
    if exists (
        select 1
        from "group" g
        where g.community_id = new.community_id
        and g.group_id <> new.group_id
        and g.slug_pretty = new.slug
    ) then
        raise exception 'Pretty slug is already used by another group in this community';
    end if;

    if new.slug_pretty is null then
        return new;
    end if;

    if char_length(new.slug_pretty) > 50 then
        raise exception 'Pretty slug must be 50 characters or fewer';
    end if;

    if new.slug_pretty !~ '^[a-z0-9-]+$' then
        raise exception 'Pretty slug must use lowercase ASCII letters, numbers, and hyphens only';
    end if;

    if new.slug_pretty !~ '^[a-z0-9]'
       or new.slug_pretty !~ '[a-z0-9]$' then
        raise exception 'Pretty slug must start and end with a lowercase ASCII letter or number';
    end if;

    if new.slug_pretty like '%--%' then
        raise exception 'Pretty slug cannot contain consecutive hyphens';
    end if;

    if new.slug_pretty = new.slug then
        raise exception 'Pretty slug must be different from the generated slug';
    end if;

    if exists (
        select 1
        from "group" g
        where g.community_id = new.community_id
        and g.group_id <> new.group_id
        and (
            g.slug = new.slug_pretty
            or g.slug_pretty = new.slug_pretty
        )
    ) then
        raise exception 'Pretty slug is already used by another group in this community';
    end if;

    return new;
end;
$$ language plpgsql;

-- Run pretty slug validation on group inserts or updates
create trigger group_slug_pretty_validate
before insert or update of slug, slug_pretty, community_id on "group"
for each row execute function validate_group_slug_pretty();
