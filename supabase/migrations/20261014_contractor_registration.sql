-- =============================================================================
-- CivicConnect AI — contractor self-registration: public municipality list
-- =============================================================================
-- Review, then run in Supabase Dashboard → SQL Editor. Not executed by the app.
--
-- Why: contractor sign-up asks the applicant to choose a municipality before
-- an account (and session) exists. Today only `authenticated` can read
-- `municipalities`, so the anonymous sign-up form cannot list them
-- (verified: anon receives 42501 "permission denied for table municipalities").
--
-- What: anonymous visitors may read ONLY the `id` and `name` columns. No
-- other table, column or write permission changes. RLS stays enabled.
--
-- Everything else in the registration flow reuses existing objects:
--   * contractors_apply (INSERT, authenticated): owner = caller, status
--     'pending', valid municipality — creates the application;
--   * UNIQUE (owner_id) on contractors — one application per account;
--   * verify_contractor — municipal approval/rejection, role → contractor.
--
-- Independent of 20261013_civicconnect_integration.sql (either order).
-- =============================================================================

begin;

-- Column-level grant: id and name only (created_at stays private).
grant select (id, name) on public.municipalities to anon;

drop policy if exists municipalities_public_list on public.municipalities;
create policy municipalities_public_list on public.municipalities
  for select to anon
  using (true);

commit;

-- Verify (optional, read-only), signed out / as anon:
--   GET /rest/v1/municipalities?select=id,name   → list of municipalities
--   GET /rest/v1/municipalities?select=created_at → permission denied
