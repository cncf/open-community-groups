-- Adds an indexed search document for user profile lookup.

alter table "user" add column if not exists tsdoc tsvector not null
    generated always as (
        setweight(to_tsvector('simple', coalesce(name, '')), 'A') ||
        setweight(to_tsvector('simple', username), 'A') ||
        setweight(to_tsvector('simple', email), 'B') ||
        setweight(to_tsvector('simple', coalesce(company, '')), 'C') ||
        setweight(to_tsvector('simple', coalesce(title, '')), 'C')
    ) stored;

create index if not exists user_tsdoc_idx on "user" using gin (tsdoc);
