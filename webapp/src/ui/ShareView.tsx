import { useEffect, useState } from "preact/hooks";
import { addMember, listMembers, type TripMember } from "../supabase/sharing";

export function ShareView({ tripId, onClose }: { tripId: string; onClose: () => void }) {
  const [members, setMembers] = useState<TripMember[]>([]);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("editor");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    try { setMembers(await listMembers(tripId)); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  }
  useEffect(() => { void load(); }, [tripId]);

  async function add(e: Event) {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      await addMember(tripId, email.trim(), role);
      setEmail("");
      await load();
    } catch (err) { setError(err instanceof Error ? err.message : String(err)); }
    finally { setBusy(false); }
  }

  return (
    <section class="share">
      <header><h2>Share Trip</h2><button class="link" onClick={onClose}>Done</button></header>
      <ul>
        {members.length === 0
          ? <li class="muted">No one yet</li>
          : members.map((m) => (
              <li key={m.id}>{m.invited_email ?? "member"} <span class="muted">· {m.role} · {m.status}</span></li>
            ))}
      </ul>
      <form onSubmit={add}>
        <input type="email" placeholder="Email" value={email}
               onInput={(e) => setEmail((e.target as HTMLInputElement).value)} />
        <select value={role} onChange={(e) => setRole((e.target as HTMLSelectElement).value)}>
          <option value="editor">Editor</option>
          <option value="viewer">Viewer</option>
        </select>
        <button type="submit" disabled={busy || !email}>Add</button>
      </form>
      {error && <p class="error">{error}</p>}
    </section>
  );
}
