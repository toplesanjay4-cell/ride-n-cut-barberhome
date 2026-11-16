# Ride N Cut Barberhome

Next.js customer booking site and owner/staff admin dashboard for the Ride N Cut home-service barber business.

## Local setup

1. Copy `.env.example` to `.env.local`.
2. Fill the public Supabase URL and anon/publishable key for a non-production project.
3. Add the server-only `SUPABASE_SERVICE_ROLE_KEY` only to the local server environment when testing owner-managed staff creation. Do not expose or commit it.
4. Install dependencies and run the development server:

```bash
npm install
npm run dev
```

Before deployment, run:

```bash
npm run check:migrations
npm run build
```

## Deployment and database setup

Use the Next.js framework preset in Vercel. Configure the environment variables from `.env.example` separately for Preview and Production; do not copy staging credentials into Production. Apply the ordered SQL migrations and run the read-only security smoke test only against a backed-up, non-production Supabase project first.

See [docs/SETUP-REDESIGN.md](docs/SETUP-REDESIGN.md) for the complete migration order, owner bootstrap, RLS and payment workflow checks, and release blockers. This branch is a staging candidate and must not be merged or deployed to production until those checks pass.
