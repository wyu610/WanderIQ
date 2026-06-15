export function TripDetailView({ onBack }: { tripId: string; onBack: () => void }) {
  return <main class="tripdetail"><button class="link" onClick={onBack}>← Back</button></main>;
}
