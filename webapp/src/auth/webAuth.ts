import type { Session } from "@supabase/supabase-js";
import { supabase } from "../supabase/client";

export type Phase = "loading" | "signedOut" | "signedIn";

/** Minimal observable auth wrapper (the UI in 4d subscribes to `onChange`). */
export class WebAuth {
  phase: Phase = "loading";
  email: string | null = null;
  private listeners = new Set<() => void>();

  constructor() {
    supabase.auth.getSession().then(({ data }) => this.apply(data.session));
    supabase.auth.onAuthStateChange((_event, session) => this.apply(session));
  }

  onChange(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  get isSignedIn(): boolean { return this.phase === "signedIn"; }

  async signIn(email: string, password: string): Promise<string | null> {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return error?.message ?? null;
  }
  async signUp(email: string, password: string): Promise<string | null> {
    const { error } = await supabase.auth.signUp({ email, password });
    return error?.message ?? null;
  }
  async signInWithGoogle(): Promise<void> {
    await supabase.auth.signInWithOAuth({ provider: "google",
      options: { redirectTo: window.location.origin } });
  }
  async signInWithApple(): Promise<void> {
    await supabase.auth.signInWithOAuth({ provider: "apple",
      options: { redirectTo: window.location.origin } });
  }
  async signOut(): Promise<void> { await supabase.auth.signOut(); }

  private apply(session: Session | null): void {
    this.phase = session ? "signedIn" : "signedOut";
    this.email = session?.user.email ?? null;
    this.listeners.forEach((fn) => fn());
  }
}
