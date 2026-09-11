-- Tests projecting discount code payloads onto their comparable configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alphaDiscountCodeID '3b060000-0000-0000-0000-000000000002'
\set betaDiscountCodeID '3b060000-0000-0000-0000-000000000001'
\set newDiscountCodeID '3b060000-0000-0000-0000-000000000003'

-- Stored codes as list_event_discount_codes returns them: title order, an
-- override-on dated code with live inventory and an override-off undated code
\set storedCodes '[{"active": true, "amount_minor": 500, "available_override_active": false, "code": "ALPHA", "event_discount_code_id": "3b060000-0000-0000-0000-000000000002", "kind": "fixed_amount", "title": "Alpha"}, {"active": true, "available": 3, "available_override_active": true, "code": "BETA", "ends_at": "2030-03-01T10:00:00+00:00", "event_discount_code_id": "3b060000-0000-0000-0000-000000000001", "kind": "percentage", "percentage": 10, "starts_at": "2030-01-01T10:00:00+00:00", "title": "beta", "total_available": 10}]'

-- Editor echo of the stored codes: reversed order, Z spellings, no available key
\set editorCodes '[{"active": true, "available_override_active": true, "code": "BETA", "ends_at": "2030-03-01T10:00:00.000Z", "event_discount_code_id": "3b060000-0000-0000-0000-000000000001", "kind": "percentage", "percentage": 10, "starts_at": "2030-01-01T10:00:00.000Z", "title": "beta", "total_available": 10}, {"active": true, "amount_minor": 500, "available_override_active": false, "code": "ALPHA", "event_discount_code_id": "3b060000-0000-0000-0000-000000000002", "kind": "fixed_amount", "title": "Alpha"}]'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should compare an editor echo with reversed order and Z spellings as equal
select is(
    event_discount_codes_configuration(:'editorCodes'::jsonb, :'storedCodes'::jsonb),
    event_discount_codes_configuration(:'storedCodes'::jsonb, :'storedCodes'::jsonb),
    'Should compare an editor echo with reversed order and Z spellings as equal'
);

-- Should compare an explicit unchanged count as equal
select is(
    event_discount_codes_configuration(
        (
            select jsonb_agg(
                case
                    when code->>'code' = 'BETA' then code || '{"available": 3}'::jsonb
                    else code
                end
            )
            from jsonb_array_elements(:'editorCodes'::jsonb) as codes(code)
        ),
        :'storedCodes'::jsonb
    ),
    event_discount_codes_configuration(:'storedCodes'::jsonb, :'storedCodes'::jsonb),
    'Should compare an explicit unchanged count as equal'
);

-- Should default an omitted active flag to true
select is(
    event_discount_codes_configuration(
        format('[{"code": "NEW", "event_discount_code_id": "%s", "kind": "fixed_amount", "amount_minor": 100, "title": "New"}]', :'newDiscountCodeID')::jsonb,
        :'storedCodes'::jsonb
    ),
    format('[{"active": true, "amount_minor": 100, "available_override_active": false, "code": "NEW", "event_discount_code_id": "%s", "kind": "fixed_amount", "title": "New"}]', :'newDiscountCodeID')::jsonb,
    'Should default an omitted active flag to true'
);

-- Should detect a cleared override on an override-on code
select isnt(
    event_discount_codes_configuration(
        (
            select jsonb_agg(
                case
                    when code->>'code' = 'BETA' then code || '{"available_cleared": true}'::jsonb
                    else code
                end
            )
            from jsonb_array_elements(:'editorCodes'::jsonb) as codes(code)
        ),
        :'storedCodes'::jsonb
    ),
    event_discount_codes_configuration(:'storedCodes'::jsonb, :'storedCodes'::jsonb),
    'Should detect a cleared override on an override-on code'
);

-- Should detect a submitted count that differs from the stored inventory
select isnt(
    event_discount_codes_configuration(
        (
            select jsonb_agg(
                case
                    when code->>'code' = 'BETA' then code || '{"available": 9}'::jsonb
                    else code
                end
            )
            from jsonb_array_elements(:'editorCodes'::jsonb) as codes(code)
        ),
        :'storedCodes'::jsonb
    ),
    event_discount_codes_configuration(:'storedCodes'::jsonb, :'storedCodes'::jsonb),
    'Should detect a submitted count that differs from the stored inventory'
);

-- Should drop the count and the clear command when the override is cleared
select is(
    event_discount_codes_configuration(
        format('[{"active": true, "available": 9, "available_cleared": true, "code": "BETA", "event_discount_code_id": "%s", "kind": "percentage", "percentage": 10, "title": "beta"}]', :'betaDiscountCodeID')::jsonb,
        :'storedCodes'::jsonb
    ),
    format('[{"active": true, "available_override_active": false, "code": "BETA", "event_discount_code_id": "%s", "kind": "percentage", "percentage": 10, "title": "beta"}]', :'betaDiscountCodeID')::jsonb,
    'Should drop the count and the clear command when the override is cleared'
);

-- Should drop a submitted count when the override is explicitly off
select is(
    event_discount_codes_configuration(
        format('[{"active": true, "available": 9, "available_override_active": false, "code": "ALPHA", "amount_minor": 500, "event_discount_code_id": "%s", "kind": "fixed_amount", "title": "Alpha"}]', :'alphaDiscountCodeID')::jsonb,
        :'storedCodes'::jsonb
    ),
    format('[{"active": true, "amount_minor": 500, "available_override_active": false, "code": "ALPHA", "event_discount_code_id": "%s", "kind": "fixed_amount", "title": "Alpha"}]', :'alphaDiscountCodeID')::jsonb,
    'Should drop a submitted count when the override is explicitly off'
);

-- Should keep the stored inventory when an override-on code omits its count
select is(
    event_discount_codes_configuration(
        format('[{"active": true, "available_override_active": true, "code": "BETA", "event_discount_code_id": "%s", "kind": "percentage", "percentage": 10, "title": "beta"}]', :'betaDiscountCodeID')::jsonb,
        :'storedCodes'::jsonb
    ),
    format('[{"active": true, "available": 3, "available_override_active": true, "code": "BETA", "event_discount_code_id": "%s", "kind": "percentage", "percentage": 10, "title": "beta"}]', :'betaDiscountCodeID')::jsonb,
    'Should keep the stored inventory when an override-on code omits its count'
);

-- Should preserve duplicate identifiers instead of collapsing them
select is(
    jsonb_array_length(
        event_discount_codes_configuration(
            format('[{"code": "NEW", "event_discount_code_id": "%s", "kind": "fixed_amount", "amount_minor": 100, "title": "New"}, {"code": "NEW", "event_discount_code_id": "%s", "kind": "fixed_amount", "amount_minor": 100, "title": "New"}]', :'newDiscountCodeID', :'newDiscountCodeID')::jsonb,
            :'storedCodes'::jsonb
        )
    ),
    2,
    'Should preserve duplicate identifiers instead of collapsing them'
);

-- Should project the stored codes onto themselves as the identity
select is(
    event_discount_codes_configuration(:'storedCodes'::jsonb, :'storedCodes'::jsonb),
    format('[
        {
            "active": true,
            "available": 3,
            "available_override_active": true,
            "code": "BETA",
            "ends_at": 1898589600,
            "event_discount_code_id": "%s",
            "kind": "percentage",
            "percentage": 10,
            "starts_at": 1893492000,
            "title": "beta",
            "total_available": 10
        },
        {
            "active": true,
            "amount_minor": 500,
            "available_override_active": false,
            "code": "ALPHA",
            "event_discount_code_id": "%s",
            "kind": "fixed_amount",
            "title": "Alpha"
        }
    ]', :'betaDiscountCodeID', :'alphaDiscountCodeID')::jsonb,
    'Should project the stored codes onto themselves as the identity'
);

-- Should project a JSON null payload to an empty array
select is(
    event_discount_codes_configuration('null'::jsonb, :'storedCodes'::jsonb),
    '[]'::jsonb,
    'Should project a JSON null payload to an empty array'
);

-- Should project a SQL null payload to an empty array
select is(
    event_discount_codes_configuration(null, null),
    '[]'::jsonb,
    'Should project a SQL null payload to an empty array'
);

-- Should project an empty payload to an empty array
select is(
    event_discount_codes_configuration('[]'::jsonb, :'storedCodes'::jsonb),
    '[]'::jsonb,
    'Should project an empty payload to an empty array'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
