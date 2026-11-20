-- Tests plpgsql functions with the plpgsql_check static analyzer.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: plpgsql functions should have no plpgsql_check findings
select is_empty(
    $$
        with
        -- Application plpgsql functions, without extension members and fixtures
        plpgsql_function as (
            select
                p.proname as function_name,
                p.oid as function_oid,
                p.prorettype = 'trigger'::regtype as is_trigger
            from pg_proc p
            join pg_language l on l.oid = p.prolang
            where p.pronamespace = 'public'::regnamespace
            and l.lanname = 'plpgsql'
            and p.proname not like 'fx\_%'
            and not exists (
                select 1
                from pg_depend d
                where d.classid = 'pg_proc'::regclass
                and d.objid = p.oid
                and d.deptype = 'e'
            )
        ),
        -- A trigger function is checked once per table it is attached to, with
        -- the transition table names its triggers declare on that table
        check_target as (
            select
                pf.function_name,
                pf.function_oid,
                null::name as new_table,
                null::name as old_table,
                0::oid as table_oid
            from plpgsql_function pf
            where not pf.is_trigger

            union all

            select
                pf.function_name,
                pf.function_oid,
                max(t.tgnewtable) as new_table,
                max(t.tgoldtable) as old_table,
                t.tgrelid as table_oid
            from plpgsql_function pf
            join pg_trigger t on t.tgfoid = pf.function_oid
            where pf.is_trigger
            group by pf.function_oid, pf.function_name, t.tgrelid
        ),
        -- Errors, warnings, extra warnings and performance warnings
        finding as (
            select
                ct.function_name,
                ct.function_oid,
                ct.table_oid,
                c.detail,
                c.level,
                c.lineno,
                c.message,
                c.sqlstate
            from check_target ct
            cross join lateral plpgsql_check_function_tb(
                ct.function_oid,
                ct.table_oid,
                extra_warnings => true,
                fatal_errors => false,
                newtable => ct.new_table,
                oldtable => ct.old_table,
                other_warnings => true,
                performance_warnings => true
            ) c
            -- A quoted reserved word is a valid name; it only limits portability
            where c.message !~ '^name of parameter ".*" is reserved keyword$'
        )
        select
            f.function_name::text,
            f.lineno as body_line,
            f.level,
            f.message,
            f.detail,
            string_agg(f.table_oid::regclass::text, ', ' order by f.table_oid::regclass::text)
                filter (where f.table_oid <> 0) as trigger_tables
        from finding f
        group by f.function_oid, f.function_name, f.lineno, f.level, f.message, f.sqlstate, f.detail
        -- A trigger function shared by several tables reads each table's columns
        -- in a branch for that table, so a missing row field is a finding only
        -- when no attached table has it
        having not (
            f.sqlstate = '42703'
            and f.message ~ '^record "(new|old)" has no field '
            and count(distinct f.table_oid) < (
                select count(*)
                from check_target ct
                where ct.function_oid = f.function_oid
            )
        )
    $$,
    'plpgsql functions should have no plpgsql_check findings'
);

-- Test: trigger functions should be attached to a table so they are checked
select is_empty(
    $$
        select p.proname::text
        from pg_proc p
        join pg_language l on l.oid = p.prolang
        where p.pronamespace = 'public'::regnamespace
        and l.lanname = 'plpgsql'
        and p.proname not like 'fx\_%'
        and p.prorettype = 'trigger'::regtype
        and not exists (
            select 1
            from pg_depend d
            where d.classid = 'pg_proc'::regclass
            and d.objid = p.oid
            and d.deptype = 'e'
        )
        and not exists (
            select 1
            from pg_trigger t
            where t.tgfoid = p.oid
        )
    $$,
    'Trigger functions should be attached to a table so they are checked'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
