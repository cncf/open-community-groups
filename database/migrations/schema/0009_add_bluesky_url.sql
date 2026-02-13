-- Add Bluesky social profile URLs to user, community, and group entities.
alter table "user"
    add column bluesky_url text check (btrim(bluesky_url) <> '');

alter table community
    add column bluesky_url text check (btrim(bluesky_url) <> '');

alter table "group"
    add column bluesky_url text check (btrim(bluesky_url) <> '');
