-- Security advisor fix: pin the trigger function search_path.
alter function public.user_recipes_touch()
  set search_path = public;
