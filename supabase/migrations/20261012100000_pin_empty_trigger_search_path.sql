-- Keep the trigger function on an empty search_path.
-- 20261011130500_security_function_search_path.sql set this to public after
-- the hardening migration requested an empty path. This later migration restores
-- the stronger setting; all referenced objects in the function are qualified or built-ins.
alter function public.user_recipes_touch()
  set search_path = '';
