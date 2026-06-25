create table if not exists group_store_item (
    group_store_item_id uuid primary key default gen_random_uuid(),
    group_id uuid not null references "group" (group_id) on delete cascade,
    created_by uuid not null references "user" (user_id),
    name text not null,
    description text,
    image_url text,
    price_minor bigint not null,
    currency_code text not null default 'USD',
    inventory_count integer,
    checkout_url text not null,
    featured boolean default false not null,
    active boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_store_item_name_check check (btrim(name) <> ''),
    constraint group_store_item_description_check check (description is null or btrim(description) <> ''),
    constraint group_store_item_image_url_check check (image_url is null or btrim(image_url) <> ''),
    constraint group_store_item_price_minor_check check (price_minor >= 0),
    constraint group_store_item_currency_code_check check (currency_code ~ '^[A-Z]{3}$'),
    constraint group_store_item_inventory_count_check check (inventory_count is null or inventory_count >= 0),
    constraint group_store_item_checkout_url_check check (btrim(checkout_url) <> '')
);

create index if not exists group_store_item_group_id_idx
on group_store_item (group_id, active, featured desc, created_at desc);
