-- CivicConnect AI — READ-ONLY follow-up inspection (private schema + grants).
-- Run in Supabase Dashboard → SQL Editor and save the single JSON value as
-- supabase/private_inspection.json. It creates, alters and deletes nothing.
--
-- Needed to finish the security audit:
--   * private.create_profile — does sign-up metadata influence role or
--     municipality? (role-escalation check)
--   * private.process_new_complaint — how category, priority and score are
--     computed (server-side re-scoring when weights change)
--   * private.civic_detect_duplicates — the real duplicate scoring
--   * private.track_complaint_status — what history rows contain
--   * private.has_role
--   * column-level grants and PUBLIC function grants (not covered before)

select jsonb_pretty(jsonb_build_object(
  'private_functions', (
    select jsonb_agg(jsonb_build_object(
      'name', p.proname,
      'arguments', pg_get_function_arguments(p.oid),
      'security_definer', p.prosecdef,
      'search_path', p.proconfig,
      'definition', pg_get_functiondef(p.oid)) order by p.proname)
    from pg_proc p
    where p.pronamespace = 'private'::regnamespace and p.prokind = 'f'),

  'column_grants', (
    select jsonb_agg(jsonb_build_object(
      'table', table_name, 'column', column_name, 'grantee', grantee,
      'privilege', privilege_type) order by table_name, column_name)
    from information_schema.column_privileges
    where table_schema = 'public'
      and grantee in ('anon', 'authenticated', 'PUBLIC')),

  'function_grants_all', (
    select jsonb_agg(jsonb_build_object(
      'schema', routine_schema, 'function', routine_name,
      'grantee', grantee) order by routine_schema, routine_name, grantee)
    from information_schema.routine_privileges
    where routine_schema in ('public', 'private')
      and grantee in ('anon', 'authenticated', 'PUBLIC')),

  'private_schema_usage', (
    select jsonb_agg(jsonb_build_object('role', r.rolname,
      'usage', has_schema_privilege(r.rolname, 'private', 'USAGE')))
    from pg_roles r where r.rolname in ('anon', 'authenticated')),

  'auth_settings_hint', 'Check Authentication → Providers → Email: '
    || '"Confirm email" and URL Configuration redirect URLs.'
)) as civicconnect_private;
