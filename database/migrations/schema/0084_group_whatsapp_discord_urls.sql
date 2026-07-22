alter table "group"
add column if not exists whatsapp_url text,
add column if not exists discord_url text;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'group_whatsapp_url_check'
    ) then
        alter table "group"
        add constraint group_whatsapp_url_check
        check (btrim(whatsapp_url) <> '');
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'group_discord_url_check'
    ) then
        alter table "group"
        add constraint group_discord_url_check
        check (btrim(discord_url) <> '');
    end if;
end $$;
