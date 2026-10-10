-- Ported from the Lovable Cloud backend (migration 20260805122453). Applied to project ploncuhexmwydjxljuhe.
CREATE TABLE IF NOT EXISTS public.shared_recipes (
  slug TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  card JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
GRANT SELECT ON public.shared_recipes TO anon;
GRANT SELECT ON public.shared_recipes TO authenticated;
GRANT ALL ON public.shared_recipes TO service_role;
ALTER TABLE public.shared_recipes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shared recipes are readable by anyone with the link" ON public.shared_recipes;
CREATE POLICY "Shared recipes are readable by anyone with the link"
  ON public.shared_recipes FOR SELECT TO anon, authenticated USING (true);
