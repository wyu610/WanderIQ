import { supabase } from "./client";

export interface TripMember {
  id: string;
  role: string;            // "viewer" | "editor"
  status: string;          // "pending" | "accepted"
  invited_email: string | null;
  user_id: string | null;
}

/** Members of a trip (RLS returns only rows the caller may see). */
export async function listMembers(tripId: string): Promise<TripMember[]> {
  const { data, error } = await supabase.from("trip_members")
    .select("id, role, status, invited_email, user_id")
    .eq("trip_id", tripId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []) as TripMember[];
}

/** Owner adds a pending invite (owner-gated by RLS). */
export async function addMember(tripId: string, email: string, role: string): Promise<void> {
  const { error } = await supabase.from("trip_members")
    .insert({ trip_id: tripId, invited_email: email, role, status: "pending" });
  if (error) throw error;
}

/** Link this user to pending invites for their email (5a backend). */
export async function claimInvites(): Promise<void> {
  const { error } = await supabase.rpc("claim_invites");
  if (error) throw error;
}
