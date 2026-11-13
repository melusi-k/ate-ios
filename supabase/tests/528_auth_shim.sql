-- Disposable postgres service ONLY. Not a Supabase project migration.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role supabase_admin nologin bypassrls;
create role supabase_auth_admin nologin;
create schema auth;
create table auth.users(id uuid primary key);
alter table auth.users owner to supabase_auth_admin;
grant usage on schema public,auth to anon,authenticated,service_role,supabase_auth_admin;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant execute on function auth.uid() to public;
-- PUBLIC is schema usage, not data write authority. Real grants differ and must
-- be audited in staging; this shim does not model GoTrue, PostgREST or hooks.
