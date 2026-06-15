import { useState } from "preact/hooks";
import { authActions } from "./store";

export function AuthView() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"in" | "up">("in");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: Event) {
    e.preventDefault();
    setBusy(true); setError(null);
    const err = mode === "in"
      ? await authActions.signIn(email, password)
      : await authActions.signUp(email, password);
    setBusy(false);
    if (err) setError(err);
  }

  return (
    <main class="auth">
      <h1>WanderIQ</h1>
      <form onSubmit={submit}>
        <input type="email" placeholder="Email" value={email}
               onInput={(e) => setEmail((e.target as HTMLInputElement).value)} />
        <input type="password" placeholder="Password" value={password}
               onInput={(e) => setPassword((e.target as HTMLInputElement).value)} />
        <button type="submit" disabled={busy || !email || !password}>
          {mode === "in" ? "Sign In" : "Create Account"}
        </button>
      </form>
      <button class="link" onClick={() => setMode(mode === "in" ? "up" : "in")}>
        {mode === "in" ? "Need an account? Sign Up" : "Have an account? Sign In"}
      </button>
      <div class="oauth">
        <button onClick={() => void authActions.apple()}>Sign in with Apple</button>
        <button onClick={() => void authActions.google()}>Continue with Google</button>
      </div>
      {error && <p class="error">{error}</p>}
    </main>
  );
}
