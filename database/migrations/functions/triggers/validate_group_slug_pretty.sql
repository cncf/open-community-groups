-- Validates the optional pretty slug of a group and keeps it unique within the community.
create or replace function validate_group_slug_pretty()
returns trigger as $$
begin
    -- Reject generated slugs that collide with another group's pretty slug
    if exists (
        select 1
        from "group" g
        where g.community_id = new.community_id
        and g.group_id <> new.group_id
        and g.slug_pretty = new.slug
    ) then
        raise exception 'Pretty slug is already used by another group in this community' using errcode = 'OCG01';
    end if;

    -- Allow groups without a pretty slug
    if new.slug_pretty is null then
        return new;
    end if;

    -- Reject pretty slugs over the length limit
    if char_length(new.slug_pretty) > 50 then
        raise exception 'Pretty slug must be 50 characters or fewer' using errcode = 'OCG01';
    end if;

    -- Reject characters outside the lowercase slug alphabet
    if new.slug_pretty !~ '^[a-z0-9-]+$' then
        raise exception 'Pretty slug must use lowercase ASCII letters, numbers, and hyphens only' using errcode = 'OCG01';
    end if;

    -- Reject leading or trailing hyphens
    if new.slug_pretty !~ '^[a-z0-9]'
       or new.slug_pretty !~ '[a-z0-9]$' then
        raise exception 'Pretty slug must start and end with a lowercase ASCII letter or number' using errcode = 'OCG01';
    end if;

    -- Reject consecutive hyphens
    if new.slug_pretty like '%--%' then
        raise exception 'Pretty slug cannot contain consecutive hyphens' using errcode = 'OCG01';
    end if;

    -- Reject pretty slugs equal to the generated slug
    if new.slug_pretty = new.slug then
        raise exception 'Pretty slug must be different from the generated slug' using errcode = 'OCG01';
    end if;

    -- Reject pretty slugs that collide with another group's slug or pretty slug
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
        raise exception 'Pretty slug is already used by another group in this community' using errcode = 'OCG01';
    end if;

    -- Return the validated group row
    return new;
end;
$$ language plpgsql;
