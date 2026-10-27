-- Returns whether a provider validation snapshot carries every required key
-- and was taken for the expected and validated payment recipients. JSON null
-- recipients in the snapshot match SQL null recipients.
create or replace function payment_validation_snapshot_matches(
    p_payment_validation jsonb,
    p_expected_payment_recipient jsonb,
    p_validated_payment_recipient jsonb
)
returns boolean as $$
    select coalesce(
        p_payment_validation ? 'expected_payment_recipient'
        and p_payment_validation ? 'validated_payment_recipient'
        and p_payment_validation ? 'require_automatic_tax'
        and p_expected_payment_recipient is not distinct from nullif(
            p_payment_validation->'expected_payment_recipient',
            'null'::jsonb
        )
        and p_validated_payment_recipient is not distinct from nullif(
            p_payment_validation->'validated_payment_recipient',
            'null'::jsonb
        ),
        false
    );
$$ language sql immutable;
