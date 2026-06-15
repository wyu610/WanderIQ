import { authPhase } from "./store";
import { AuthView } from "./AuthView";
import { TripListView } from "./TripListView";

export function App() {
  switch (authPhase.value) {
    case "loading": return <p class="loading">Loading…</p>;
    case "signedOut": return <AuthView />;
    case "signedIn": return <TripListView />;
  }
}
