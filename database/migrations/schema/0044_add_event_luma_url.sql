-- Add optional Luma event page links.

alter table event
    add column luma_url text check (btrim(luma_url) <> '');
