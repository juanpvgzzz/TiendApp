# TiendApp conventions

- Keep solutions simple, readable, secure, and proportional to 20–30 customers per day. Use strict TypeScript, idiomatic SvelteKit/Svelte 5, and PostgreSQL as the source of truth. Avoid speculative features, unnecessary layers, and dependencies.
- Read existing code before editing. Use camelCase in TypeScript and snake_case in SQL. Comment only non-obvious business, security, or concurrency decisions.
- Use versioned SQL migrations, constraints, RLS, and small transactional RPCs. Authenticate and authorize every operation. Account mutations need row locks and idempotency keys. Audit sensitive changes. Never expose service-role keys in browser code.
- Preserve verified delivery prices. Do not add polling, inventory, credit, online payments, or PWA support. Keep the web UI minimal, responsive, and fast on low-end phones.
- Test meaningful business rules against an isolated environment, never production. Report what actually ran and any remaining failures.
