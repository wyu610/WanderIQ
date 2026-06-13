// Minimal Edge Function to verify the deploy pipeline.
// Sub-project 5 adds the invite-email function alongside this.
Deno.serve((_req: Request) => {
  return new Response(
    JSON.stringify({ status: "ok", service: "wanderiq" }),
    { headers: { "Content-Type": "application/json" } },
  );
});
