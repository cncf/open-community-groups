-- Add GitHub social profile URL to user profiles.
alter table "user"
    add column github_url text check (btrim(github_url) <> '');
