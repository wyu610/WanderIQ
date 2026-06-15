import { createClient } from "@supabase/supabase-js";

/** Single app-wide Supabase client (auth + data share it). */
export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
);
