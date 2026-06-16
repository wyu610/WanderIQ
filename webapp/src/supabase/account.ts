import { supabase } from "./client";

/** Permanently delete the signed-in user's account via the delete_my_account
 *  RPC. FK cascades remove all their trips, days, items, and memberships. */
export async function deleteAccount(): Promise<void> {
  const { error } = await supabase.rpc("delete_my_account");
  if (error) throw error;
}
