-- CivicConnect AI — READ-ONLY schema inspection.
-- Run in Supabase Dashboard → SQL Editor. It only SELECTs from catalog
-- views; it creates, alters and deletes nothing. Copy the single JSON value
-- it returns (or "Download CSV") and share it for the integration review.

select jsonb_pretty(jsonb_build_object(

  'tables', (
    select jsonb_agg(jsonb_build_object(
      'table', c.relname,
      'rls_enabled', c.relrowsecurity,
      'rls_forced', c.relforcerowsecurity,
      'columns', (
        select jsonb_agg(jsonb_build_object(
          'name', col.column_name,
          'type', col.udt_name,
          'nullable', col.is_nullable,
          'default', col.column_default) order by col.ordinal_position)
        from information_schema.columns col
        where col.table_schema = 'public' and col.table_name = c.relname)
    ) order by c.relname)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')),

  'views', (
    select jsonb_agg(jsonb_build_object('view', viewname,
      'definition', definition) order by viewname)
    from pg_views where schemaname = 'public'),

  'constraints', (
    select jsonb_agg(jsonb_build_object(
      'table', conrelid::regclass::text,
      'name', conname,
      'type', contype,
      'definition', pg_get_constraintdef(oid)) order by conrelid::regclass::text, conname)
    from pg_constraint
    where connamespace = 'public'::regnamespace),

  'enums', (
    select jsonb_agg(jsonb_build_object('type', t.typname,
      'values', (select jsonb_agg(e.enumlabel order by e.enumsortorder)
                 from pg_enum e where e.enumtypid = t.oid)) order by t.typname)
    from pg_type t
    where t.typnamespace = 'public'::regnamespace and t.typtype = 'e'),

  'policies', (
    select jsonb_agg(jsonb_build_object(
      'schema', schemaname, 'table', tablename, 'policy', policyname,
      'permissive', permissive, 'roles', roles, 'command', cmd,
      'using', qual, 'with_check', with_check) order by schemaname, tablename, policyname)
    from pg_policies where schemaname in ('public', 'storage')),

  'functions', (
    select jsonb_agg(jsonb_build_object(
      'name', p.proname,
      'arguments', pg_get_function_arguments(p.oid),
      'returns', pg_get_function_result(p.oid),
      'security_definer', p.prosecdef,
      'search_path', p.proconfig,
      'volatility', p.provolatile,
      'definition', pg_get_functiondef(p.oid)) order by p.proname)
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),

  'function_grants', (
    select jsonb_agg(jsonb_build_object(
      'function', routine_name, 'grantee', grantee,
      'privilege', privilege_type) order by routine_name, grantee)
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and grantee in ('anon', 'authenticated', 'public')),

  'triggers', (
    select jsonb_agg(jsonb_build_object(
      'table', event_object_schema || '.' || event_object_table,
      'trigger', trigger_name, 'timing', action_timing,
      'event', event_manipulation, 'action', action_statement)
      order by event_object_table, trigger_name)
    from information_schema.triggers
    where event_object_schema in ('public', 'auth', 'storage')),

  'table_grants', (
    select jsonb_agg(jsonb_build_object(
      'table', table_name, 'grantee', grantee,
      'privilege', privilege_type) order by table_name, grantee, privilege_type)
    from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon', 'authenticated')),

  'storage_buckets', (
    select jsonb_agg(jsonb_build_object(
      'id', id, 'public', public, 'file_size_limit', file_size_limit,
      'allowed_mime_types', allowed_mime_types) order by id)
    from storage.buckets),

  'realtime_tables', (
    select jsonb_agg(schemaname || '.' || tablename)
    from pg_publication_tables where pubname = 'supabase_realtime'),

  'extensions', (
    select jsonb_agg(extname order by extname) from pg_extension)

)) as civicconnect_schema;
