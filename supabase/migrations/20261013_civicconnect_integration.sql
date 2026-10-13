-- =============================================================================
-- CivicConnect AI — integration & security corrections
-- =============================================================================
-- Review, then run ONCE in Supabase Dashboard → SQL Editor.
--
-- * Non-destructive: no table, column, row or policy-protected data is
--   deleted; RLS stays enabled everywhere. Constraints and policies are
--   replaced only with stricter or wider-but-equivalent versions.
-- * Runs in one transaction: either everything applies or nothing does.
-- * Safe to re-run (CREATE OR REPLACE / IF EXISTS / guarded DO blocks).
--
-- Sections
--   1. Category "drainage" (app has a Water & drainage category)
--   2. Reviews: bind the review's complaint to the reviewed contract  [SECURITY]
--   3. assign_repair_job: contractor must belong to the municipality  [SECURITY]
--   4. Complaint inserts: client cannot set server-owned fields       [SECURITY]
--   5. Complaint image metadata must point at the caller's upload     [SECURITY]
--   6. Defence in depth for profiles.role and contractor verification [SECURITY]
--   7. review_complaint: remarks visible in the citizen's history
--   8. Secure tendering & bidding: open_tender, submit_bid, award_bid
--   9. mark_notifications_read (inbox could not be marked read)
--  10. get_display_names (names on comments / history without exposing
--      profiles)
--  11. Realtime publication for live updates (RLS still applies)
--
-- NOT included (needs the private.* function definitions first — see
-- supabase/inspect_private.sql): server-side re-scoring of existing reports
-- when age/support weights change.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. Category "drainage"
-- Why: the app's approved category list has "Water & drainage"; the CHECK
-- constraints only allow pothole | streetlight | garbage | other, so such
-- reports currently fail. Widening a CHECK keeps every existing row valid.
-- -----------------------------------------------------------------------------
alter table public.complaints
  drop constraint if exists complaints_category_check,
  add constraint complaints_category_check check (category = any (array[
    'pothole', 'streetlight', 'garbage', 'drainage', 'other']));

alter table public.complaints
  drop constraint if exists complaints_suggested_category_check,
  add constraint complaints_suggested_category_check
    check (suggested_category = any (array[
      'pothole', 'streetlight', 'garbage', 'drainage', 'other']));

alter table public.priority_rules
  drop constraint if exists priority_rules_category_check,
  add constraint priority_rules_category_check check (category = any (array[
    'pothole', 'streetlight', 'garbage', 'drainage', 'other']));

-- Same function as before; only the category list gains 'drainage'.
create or replace function public.save_priority_rule(
  p_category text, p_base_score integer, p_age_weight integer,
  p_support_weight integer)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_municipality uuid;
  v_rule_id uuid;
begin
  if auth.uid() is null
     or not private.has_role(array['municipal_admin']) then
    raise exception 'Municipal admin permission required';
  end if;

  select municipality_id into v_municipality
  from public.profiles where id = auth.uid();
  if v_municipality is null then
    raise exception 'Admin municipality is not configured';
  end if;

  if p_category is null or p_category not in (
       'pothole', 'streetlight', 'garbage', 'drainage', 'other') then
    raise exception 'Invalid complaint category';
  end if;

  if p_base_score is null or p_base_score not between 0 and 100
     or p_age_weight is null or p_age_weight not between 0 and 20
     or p_support_weight is null or p_support_weight not between 0 and 20 then
    raise exception 'Invalid priority rule values';
  end if;

  insert into public.priority_rules (
    municipality_id, category, base_score, age_weight, support_weight,
    updated_at)
  values (v_municipality, p_category, p_base_score, p_age_weight,
          p_support_weight, now())
  on conflict (municipality_id, category) do update set
    base_score = excluded.base_score,
    age_weight = excluded.age_weight,
    support_weight = excluded.support_weight,
    updated_at = now()
  returning id into v_rule_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id,
                                 details)
  values (auth.uid(), 'priority_rule_saved', 'priority_rule', v_rule_id,
          jsonb_build_object('category', p_category,
                             'base_score', p_base_score,
                             'age_weight', p_age_weight,
                             'support_weight', p_support_weight,
                             'municipality_id', v_municipality));
  return v_rule_id;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Reviews must rate the contract that repaired THAT complaint
-- Why: reviews_create joined complaint/job/contract but never compared
-- reviews.complaint_id with the contract's complaint, so a citizen could
-- attach a rating for contract A to complaint B. The repair must also have
-- passed inspection.
-- -----------------------------------------------------------------------------
drop policy if exists reviews_create on public.reviews;
create policy reviews_create on public.reviews
  for insert to authenticated
  with check (
    citizen_id = (select auth.uid())
    and exists (
      select 1
      from public.complaints c
      join public.jobs j on j.complaint_id = c.id
      join public.contracts ct on ct.job_id = j.id
      where c.id = reviews.complaint_id
        and ct.id = reviews.contract_id
        and ct.status = 'accepted'
        and c.status = 'resolved'
        and (c.citizen_id = (select auth.uid())
             or exists (select 1 from public.complaint_support s
                        where s.complaint_id = c.id
                          and s.user_id = (select auth.uid())))
    )
  );

-- -----------------------------------------------------------------------------
-- 3. assign_repair_job: contractor must belong to the admin's municipality
-- Why: the function checked the complaint's municipality but accepted any
-- approved contractor, including one registered with another municipality.
-- Everything else is unchanged.
-- -----------------------------------------------------------------------------
create or replace function public.assign_repair_job(
  p_complaint_id uuid, p_contractor_id uuid, p_title text, p_budget numeric,
  p_approved_amount numeric, p_award_reason text,
  p_deadline timestamp with time zone default null)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_admin_municipality uuid;
  v_complaint_municipality uuid;
  v_complaint_status text;
  v_job_id uuid;
  v_contract_id uuid;
  v_owner uuid;
begin
  if auth.uid() is null or not private.has_role(array['municipal_admin']) then
    raise exception 'Permission denied';
  end if;

  select municipality_id into v_admin_municipality
  from public.profiles where id = auth.uid();
  if v_admin_municipality is null then
    raise exception 'Admin municipality is not configured';
  end if;

  select status, municipality_id
    into v_complaint_status, v_complaint_municipality
  from public.complaints where id = p_complaint_id for update;
  if not found then raise exception 'Complaint not found'; end if;
  if v_complaint_municipality is distinct from v_admin_municipality then
    raise exception 'Wrong municipality';
  end if;
  if v_complaint_status <> 'verified' then
    raise exception 'Complaint must be verified first';
  end if;

  select owner_id into v_owner
  from public.contractors
  where id = p_contractor_id
    and verification_status = 'approved'
    and municipality_id = v_admin_municipality;
  if not found then
    raise exception 'Contractor is not approved for this municipality';
  end if;

  if p_title is null or length(trim(p_title)) < 5
     or p_award_reason is null or length(trim(p_award_reason)) < 5 then
    raise exception 'Valid title and award reason required';
  end if;
  if p_budget is null or p_approved_amount is null or p_budget <= 0
     or p_approved_amount <= 0 or p_approved_amount > p_budget then
    raise exception 'Invalid contract budget';
  end if;
  if p_deadline is not null and p_deadline <= now() then
    raise exception 'Deadline must be in the future';
  end if;
  if exists (select 1 from public.jobs where complaint_id = p_complaint_id) then
    raise exception 'A repair job already exists';
  end if;

  insert into public.jobs (complaint_id, created_by, title, budget, deadline,
                           status)
  values (p_complaint_id, auth.uid(), trim(p_title), p_budget, p_deadline,
          'awarded')
  returning id into v_job_id;

  insert into public.contracts (job_id, contractor_id, approved_amount,
                                award_reason, status)
  values (v_job_id, p_contractor_id, p_approved_amount, trim(p_award_reason),
          'awarded')
  returning id into v_contract_id;

  update public.complaints set status = 'assigned', updated_at = now()
  where id = p_complaint_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id,
                                 details)
  values (auth.uid(), 'contract_awarded', 'contract', v_contract_id,
          jsonb_build_object('complaint_id', p_complaint_id,
                             'contractor_id', p_contractor_id,
                             'job_id', v_job_id,
                             'approved_amount', p_approved_amount));

  insert into public.notifications (user_id, title, body)
  values (v_owner, 'New repair assignment',
          'You have been assigned: ' || trim(p_title));

  return v_contract_id;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Complaint inserts cannot set server-owned fields
-- Why: complaints_submit restricts citizen, status, duplicate link and
-- municipality, but not priority, priority_score, suggested_category,
-- classification_method, reference_code or timestamps. This BEFORE INSERT
-- trigger runs first (triggers fire in name order) and resets those fields
-- for API callers, so civic_process_complaint always computes them.
-- -----------------------------------------------------------------------------
create or replace function private.civic_sanitize_complaint_insert()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_user in ('authenticated', 'anon') then
    new.priority := 'medium';
    new.priority_score := 0;
    new.suggested_category := null;
    new.classification_method := 'keyword_rules';
    new.reference_code := 'CMP-' || upper(substr(
      replace(gen_random_uuid()::text, '-', ''), 1, 8));
    new.created_at := now();
    new.updated_at := now();
  end if;
  return new;
end;
$function$;

drop trigger if exists civic_a_sanitize_complaint on public.complaints;
create trigger civic_a_sanitize_complaint
  before insert on public.complaints
  for each row execute function private.civic_sanitize_complaint_insert();

-- -----------------------------------------------------------------------------
-- 5. Complaint image rows must point at the caller's own upload
-- Why: complaint_images_add accepted any storage_path, so a row could reference
-- another complaint's photo or a non-existent object. Now the path must be in
-- this complaint's folder and the object must exist and belong to the caller
-- (mirrors add_repair_evidence).
-- -----------------------------------------------------------------------------
drop policy if exists complaint_images_add on public.complaint_images;
create policy complaint_images_add on public.complaint_images
  for insert to authenticated
  with check (
    uploaded_by = (select auth.uid())
    and kind = 'report'
    and storage_path like 'complaints/' || complaint_id::text || '/%'
    and exists (
      select 1 from public.complaints c
      where c.id = complaint_images.complaint_id
        and c.citizen_id = (select auth.uid())
        and c.status = 'submitted')
    and exists (
      select 1 from storage.objects o
      where o.bucket_id = 'complaint-images'
        and o.name = complaint_images.storage_path
        and o.owner_id = (select auth.uid())::text)
  );

-- -----------------------------------------------------------------------------
-- 6. Defence in depth: privileged columns change only via definer functions
-- Why: profiles_update_own and contractors_edit_own have no column limits.
-- Clients currently lack UPDATE grants, so this is not exploitable today, but
-- a future grant would let users set their own role or approve themselves.
-- These triggers block such changes for API roles; the SECURITY DEFINER
-- workflow functions (e.g. verify_contractor) are unaffected.
-- -----------------------------------------------------------------------------
create or replace function private.civic_protect_profile()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_user in ('authenticated', 'anon')
     and (new.role is distinct from old.role
          or new.municipality_id is distinct from old.municipality_id) then
    raise exception 'Role and municipality are managed by the municipality';
  end if;
  return new;
end;
$function$;

drop trigger if exists civic_protect_profile on public.profiles;
create trigger civic_protect_profile
  before update on public.profiles
  for each row execute function private.civic_protect_profile();

create or replace function private.civic_protect_contractor()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_user in ('authenticated', 'anon')
     and (new.verification_status is distinct from old.verification_status
          or new.owner_id is distinct from old.owner_id
          or new.municipality_id is distinct from old.municipality_id) then
    raise exception 'Verification is managed by the municipality';
  end if;
  return new;
end;
$function$;

drop trigger if exists civic_protect_contractor on public.contractors;
create trigger civic_protect_contractor
  before update on public.contractors
  for each row execute function private.civic_protect_contractor();

-- -----------------------------------------------------------------------------
-- 7. review_complaint: the citizen sees the reason
-- Why: remarks (e.g. the rejection reason) were written only to audit_logs,
-- which citizens cannot read, so a rejected report showed no explanation.
-- The function now also stores the remarks on the history row created by
-- complaint_status_audit in the same transaction. Checks are unchanged.
-- -----------------------------------------------------------------------------
create or replace function public.review_complaint(
  p_complaint_id uuid, p_new_status text, p_remarks text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_old_status text;
  v_municipality_id uuid;
  v_staff_municipality uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.has_role(array['municipal_admin']) then
    raise exception 'Permission denied';
  end if;

  select municipality_id into v_staff_municipality
  from public.profiles where id = auth.uid();
  if v_staff_municipality is null then
    raise exception 'Municipal staff account is not assigned to a municipality';
  end if;

  select status, municipality_id into v_old_status, v_municipality_id
  from public.complaints where id = p_complaint_id for update;
  if not found then raise exception 'Complaint not found'; end if;
  if v_municipality_id is distinct from v_staff_municipality then
    raise exception 'Complaint is outside your municipality';
  end if;

  if not ((v_old_status = 'submitted'
           and p_new_status in ('under_review', 'rejected', 'verified'))
       or (v_old_status = 'under_review'
           and p_new_status in ('verified', 'rejected'))) then
    raise exception 'Invalid complaint status transition';
  end if;

  update public.complaints set status = p_new_status, updated_at = now()
  where id = p_complaint_id;

  if nullif(trim(p_remarks), '') is not null then
    update public.complaint_updates
    set remarks = left(trim(p_remarks), 2000)
    where complaint_id = p_complaint_id
      and new_status = p_new_status
      and created_at >= now()          -- this transaction's history row
      and remarks is null;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id,
                                 details)
  values (auth.uid(), 'municipal_complaint_review', 'complaint',
          p_complaint_id,
          jsonb_build_object('old_status', v_old_status,
                             'new_status', p_new_status,
                             'remarks', p_remarks));
end;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Secure tendering and bidding
-- Why: bids/jobs have no client INSERT grant and no function existed, so the
-- app's "Open tender", "Submit a bid" and "Award" actions could not work.
-- Each function re-checks role, municipality, approval and state.
-- -----------------------------------------------------------------------------
create or replace function public.open_tender(
  p_complaint_id uuid, p_title text, p_budget numeric)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_admin_municipality uuid;
  v_status text;
  v_municipality uuid;
  v_job_id uuid;
begin
  if auth.uid() is null or not private.has_role(array['municipal_admin']) then
    raise exception 'Municipal admin permission required';
  end if;
  select municipality_id into v_admin_municipality
  from public.profiles where id = auth.uid();
  if v_admin_municipality is null then
    raise exception 'Admin municipality is not configured';
  end if;

  select status, municipality_id into v_status, v_municipality
  from public.complaints where id = p_complaint_id for update;
  if not found then raise exception 'Complaint not found'; end if;
  if v_municipality is distinct from v_admin_municipality then
    raise exception 'Complaint is outside your municipality';
  end if;
  if v_status <> 'verified' then
    raise exception 'Complaint must be verified first';
  end if;
  if exists (select 1 from public.jobs where complaint_id = p_complaint_id) then
    raise exception 'A repair job already exists';
  end if;
  if p_title is null or length(trim(p_title)) < 5 then
    raise exception 'A work order title of at least 5 characters is required';
  end if;
  if p_budget is null or p_budget <= 0 then
    raise exception 'Invalid budget';
  end if;

  insert into public.jobs (complaint_id, created_by, title, budget, status)
  values (p_complaint_id, auth.uid(), trim(p_title), p_budget, 'open')
  returning id into v_job_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id,
                                 details)
  values (auth.uid(), 'tender_opened', 'job', v_job_id,
          jsonb_build_object('complaint_id', p_complaint_id,
                             'budget', p_budget));
  return v_job_id;
end;
$function$;

create or replace function public.submit_bid(
  p_job_id uuid, p_amount numeric, p_estimated_days integer,
  p_proposal text default null)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_contractor uuid;
  v_contractor_municipality uuid;
  v_job_status text;
  v_job_municipality uuid;
  v_bid_id uuid;
begin
  if auth.uid() is null or not private.has_role(array['contractor']) then
    raise exception 'Approved contractor account required';
  end if;

  select id, municipality_id into v_contractor, v_contractor_municipality
  from public.contractors
  where owner_id = auth.uid() and verification_status = 'approved';
  if not found then
    raise exception 'Your contractor account is not approved';
  end if;

  select j.status, c.municipality_id into v_job_status, v_job_municipality
  from public.jobs j join public.complaints c on c.id = j.complaint_id
  where j.id = p_job_id;
  if not found then raise exception 'Job not found'; end if;
  if v_job_status <> 'open' then
    raise exception 'This job is no longer accepting bids';
  end if;
  if v_job_municipality is distinct from v_contractor_municipality then
    raise exception 'This job is outside your municipality';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter a realistic amount';
  end if;
  if p_estimated_days is null or p_estimated_days not between 1 and 90 then
    raise exception 'Duration must be 1-90 days';
  end if;
  if exists (select 1 from public.bids
             where job_id = p_job_id and contractor_id = v_contractor) then
    raise exception 'You already bid on this job';
  end if;

  insert into public.bids (job_id, contractor_id, amount, estimated_days,
                           proposal)
  values (p_job_id, v_contractor, p_amount, p_estimated_days,
          left(nullif(trim(p_proposal), ''), 2000))
  returning id into v_bid_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id,
                                 details)
  values (auth.uid(), 'bid_submitted', 'bid', v_bid_id,
          jsonb_build_object('job_id', p_job_id, 'amount', p_amount,
                             'estimated_days', p_estimated_days));
  return v_bid_id;
end;
$function$;

create or replace function public.award_bid(
  p_bid_id uuid,
  p_award_reason text default 'Selected from competitive bids')
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_admin_municipality uuid;
  v_job_id uuid;
  v_contractor uuid;
  v_amount numeric;
  v_job_status text;
  v_complaint uuid;
  v_complaint_status text;
  v_municipality uuid;
  v_owner uuid;
  v_title text;
  v_contract_id uuid;
begin
  if auth.uid() is null or not private.has_role(array['municipal_admin']) then
    raise exception 'Municipal admin permission required';
  end if;
  select municipality_id into v_admin_municipality
  from public.profiles where id = auth.uid();
  if v_admin_municipality is null then
    raise exception 'Admin municipality is not configured';
  end if;

  select b.job_id, b.contractor_id, b.amount
    into v_job_id, v_contractor, v_amount
  from public.bids b where b.id = p_bid_id;
  if not found then raise exception 'Bid not found'; end if;

  select j.status, j.complaint_id, j.title into v_job_status, v_complaint,
                                                 v_title
  from public.jobs j where j.id = v_job_id for update;
  select status, municipality_id into v_complaint_status, v_municipality
  from public.complaints where id = v_complaint for update;

  if v_municipality is distinct from v_admin_municipality then
    raise exception 'Job is outside your municipality';
  end if;
  if v_job_status not in ('open', 'bidding_closed') then
    raise exception 'This tender has already been decided';
  end if;
  if v_complaint_status <> 'verified' then
    raise exception 'Complaint must be verified first';
  end if;

  select owner_id into v_owner from public.contractors
  where id = v_contractor and verification_status = 'approved'
    and municipality_id = v_admin_municipality;
  if not found then
    raise exception 'Contractor is not approved for this municipality';
  end if;
  if v_owner = auth.uid() then
    raise exception 'You cannot award your own bid';
  end if;

  insert into public.contracts (job_id, contractor_id, awarded_bid_id,
                                approved_amount, award_reason, status)
  values (v_job_id, v_contractor, p_bid_id, v_amount,
          coalesce(nullif(trim(p_award_reason), ''),
                   'Selected from competitive bids'),
          'awarded')
  returning id into v_contract_id;

  update public.jobs set status = 'awarded' where id = v_job_id;
  update public.complaints set status = 'assigned', updated_at = now()
  where id = v_complaint;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id,
                                 details)
  values (auth.uid(), 'bid_awarded', 'contract', v_contract_id,
          jsonb_build_object('bid_id', p_bid_id, 'job_id', v_job_id,
                             'amount', v_amount));
  insert into public.notifications (user_id, title, body)
  values (v_owner, 'Bid awarded', 'Your bid was accepted: ' || v_title);
  return v_contract_id;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 9. mark_notifications_read
-- Why: notifications has only a SELECT grant, so notifications_mark_read
-- could never be used. A narrow function is safer than an UPDATE grant: it
-- can only stamp read_at on the caller's own unread rows.
-- -----------------------------------------------------------------------------
create or replace function public.mark_notifications_read()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.notifications set read_at = now()
  where user_id = auth.uid() and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 10. get_display_names
-- Why: profiles are private (own row or staff), so citizens saw "Resident" /
-- "Community member" for everyone on comments and history. This returns only
-- display name and role, and only for people who appear in civic activity
-- (report authors, commenters, status changers) — never email, phone or
-- municipality.
-- -----------------------------------------------------------------------------
create or replace function public.get_display_names(p_ids uuid[])
returns table (id uuid, display_name text, role text)
language sql
stable
security definer
set search_path to ''
as $function$
  select p.id, p.display_name, p.role
  from public.profiles p
  where auth.uid() is not null
    and p.id = any (p_ids[1:500])
    and (exists (select 1 from public.complaints c where c.citizen_id = p.id)
         or exists (select 1 from public.complaint_comments m
                    where m.user_id = p.id)
         or exists (select 1 from public.complaint_updates u
                    where u.changed_by = p.id));
$function$;

-- Function privileges: authenticated users only (functions are executable
-- by PUBLIC by default in PostgreSQL).
revoke all on function public.open_tender(uuid, text, numeric) from public, anon;
revoke all on function public.submit_bid(uuid, numeric, integer, text)
  from public, anon;
revoke all on function public.award_bid(uuid, text) from public, anon;
revoke all on function public.mark_notifications_read() from public, anon;
revoke all on function public.get_display_names(uuid[]) from public, anon;
revoke all on function public.save_priority_rule(text, integer, integer, integer)
  from public, anon;
revoke all on function public.assign_repair_job(uuid, uuid, text, numeric,
  numeric, text, timestamp with time zone) from public, anon;
revoke all on function public.review_complaint(uuid, text, text)
  from public, anon;

grant execute on function public.open_tender(uuid, text, numeric) to authenticated;
grant execute on function public.submit_bid(uuid, numeric, integer, text)
  to authenticated;
grant execute on function public.award_bid(uuid, text) to authenticated;
grant execute on function public.mark_notifications_read() to authenticated;
grant execute on function public.get_display_names(uuid[]) to authenticated;
grant execute on function public.save_priority_rule(text, integer, integer,
  integer) to authenticated;
grant execute on function public.assign_repair_job(uuid, uuid, text, numeric,
  numeric, text, timestamp with time zone) to authenticated;
grant execute on function public.review_complaint(uuid, text, text)
  to authenticated;

revoke all on function private.civic_sanitize_complaint_insert()
  from public, anon, authenticated;
revoke all on function private.civic_protect_profile()
  from public, anon, authenticated;
revoke all on function private.civic_protect_contractor()
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 11. Realtime for live tracker updates
-- Why: the supabase_realtime publication contains no tables, so screens only
-- refresh by polling. Realtime postgres_changes still honours RLS.
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime')
  then
    return;
  end if;
  foreach t in array array['complaints', 'complaint_updates',
      'complaint_comments', 'complaint_support', 'complaint_images',
      'duplicate_candidates', 'jobs', 'contracts', 'bids', 'work_evidence',
      'inspections', 'payments', 'contractors', 'notifications']
  loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I',
                     t);
    end if;
  end loop;
end $$;

commit;

-- After running: reload the PostgREST schema cache (Settings → API → Reload,
-- or `notify pgrst, 'reload schema';`) so the new functions are callable.
