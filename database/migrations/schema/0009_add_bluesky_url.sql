-- Add Bluesky social profile URLs to user, alliance, and group entities.
alter table "user"
    add column bluesky_url text check (btrim(bluesky_url) <> '');

alter table alliance
    add column bluesky_url text check (btrim(bluesky_url) <> '');

alter table "group"
    add column bluesky_url text check (btrim(bluesky_url) <> '');
