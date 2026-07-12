-- Add registration mode and external URL support to events.

alter table event add column registration_mode text
    check (registration_mode in ('builtin', 'external_url', 'none'))
    default 'builtin' not null;
alter table event add column registration_url text
    check (btrim(registration_url) <> '');
