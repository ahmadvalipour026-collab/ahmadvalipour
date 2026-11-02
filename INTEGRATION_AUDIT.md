# Negin 2 multi-building integration audit

## Repository roles

- Target application (preserve its UI): `ahmadvalipour026-collab/ahmadvalipour`
  - Default branch: `main`
  - Frontend title: `مجتمع نگین ۲ | مدیریت ساختمان`
  - Supabase project: `hpgvgoehkcpjmdbfmnse`
  - The integration work is isolated on `integration/negin2-multibuilding-safe`.
- Multi-building reference implementation: `ahmadvalipour02632819668-wq/modir`
  - Default branch: `main`
  - Supabase project: `fvhzshtgtkqzrgmblczh`
  - Contains the manager/super-admin/resident workflow and finance allocation functions.

## Verified target data inventory (read-only)

Target Negin 2 database currently contains:

| Resource | Rows |
|---|---:|
| buildings | 1 |
| units | 10 |
| accounts | 12 |
| transactions | 551 |
| payment_requests | 64 |
| rates | 15 |
| activity_logs | 1,089 |
| announcements | 4 |
| resident_requests | 4 |
| push_subscriptions | 3 |
| sessions | 88 |

The building row is `مجتمع نگین ۲`. Existing account records include the current building admin/manager and owner/tenant accounts. Unit 3 and unit 7 each have both an owner and a tenant account.

## Verified multi-building reference inventory (read-only)

The reference database already has its own data and must not be cleared or overwritten:

- buildings: 1
- app_accounts: 6
- units: 4
- building_memberships: 5
- building_expenses: 7
- building_expense_allocations: 22
- building_payments: 7
- building_payment_allocations: 12
- building_payment_item_requests: 13

## Important incompatibilities

1. The legacy Negin 2 database uses integer IDs for `public.buildings` and a composite/number-based unit model. The multi-building implementation uses UUID IDs for buildings and units.
2. The legacy account table is `public.accounts`; the new model uses `public.app_accounts` and `public.building_memberships`.
3. Both applications define RPCs with colliding names/signatures, notably `app_login(text,text)` and `app_logout(uuid)`. Blindly applying the reference migrations would replace legacy functions and break the live Negin 2 app.
4. The multi-building repository's checked-in migrations are not a complete fresh-install schema. They assume base tables and helper functions already exist in its Supabase project.
5. Historical Negin 2 financial records cannot be copied naively into the new expense/payment tables: approved payment requests and income transactions overlap, and importing both as income would double-count money.
6. Legacy announcements, activity history, and other records need an explicit preservation/display mapping; they must not be silently discarded.

## Integration strategy

- Keep the legacy Negin 2 database tables and functions intact during the transition.
- Use the Negin 2 UI as the visual baseline; add multi-building role and building-selection behavior without replacing its design system.
- Treat the multi-building repository as the reference for role checks, manager approval/transfer, membership history, tenant exit, and financial allocation.
- Keep the existing multi-building demo data intact.
- Build an idempotent, separately verifiable import for Negin 2 that preserves account identifiers/password hashes where compatible, unit data, historical transactions, payment-request statuses, rates, announcements, requests, and audit history.
- Reconcile transaction income against payment requests before creating financial allocations, to prevent double counting.
- Enforce the product password rule: English username; password of 4–6 numeric digits.
- Run the import first in a non-production copy/staging database, compare per-table counts and financial totals, and only then plan a production cutover.

## Implementation branch progress

Branch: `integration/negin2-multibuilding-safe`

Commits on the branch now include:

- `202611030001_multibuilding_isolated_backend.sql`: isolated `mb` schema with 14 tables, 29 supporting indexes and 53 RPC/helper functions. Every copied RPC is prefixed `mb_`, so legacy `public.app_login`, `public.app_logout` and other Negin 2 RPCs are not replaced.
- The multi-building login bridge can return a separate `legacy_token` for existing Negin 2 accounts, allowing the old UI and its legacy RPCs to continue working while the new UI uses the multi-building token.
- New registration, manager-created account and password-change paths enforce English usernames and 4–6 numeric-digit passwords. Manager password reset now generates a six-digit numeric temporary password.
- Owner and owner-resident debt fields are hidden in the new resident balance response; tenant and manager memberships retain balances.
- `202611030002_import_negin2_as_building.sql`: idempotent import of Negin 2 as an already-approved active building, with 10 units, 12 legacy accounts and memberships. The global super-admin's existing identity and password hash are preserved separately; the Negin 2 admin remains a building manager. Net opening balances are imported across periods: positive debt becomes an itemized opening charge, while overpayment remains a negative account credit.
- `multibuilding.html`: a separate multi-building workspace using the Negin 2 Supabase project and the isolated `mb_*` RPCs. It reuses the same visual design language and enforces the 4–6 digit password rule.
- The existing Negin 2 `index.html` remains the default UI. Its admin account menu now has a `مدیریت چندساختمانی` entry that securely bridges the current legacy session into the new workspace; the old token remains separate from the new token.
- `mb_app_bridge_legacy_session` and `mb_app_logout_all` provide the dual-session handoff and revoke both sessions on logout.
- `supabase/tests/negin2_multibuilding_smoke.sql`: post-import assertions for unit/account/membership counts, one active manager and super-admin, manager pointer, RLS/revoked direct table access, unchanged legacy RPC signatures, preserved password hashes, exact opening-debt parity with the legacy billing engine, legacy-session bridging, combined logout/revocation, six-digit reset passwords, rejected invalid passwords and direct multi-building login.

The global super-admin is imported separately from the original multi-building Supabase project using the same account UUID, username (`admin`) and existing bcrypt password hash. The Negin 2 administrator is imported only as Negin 2's building manager and is not promoted to global super-admin. Negin 2 is inserted with `building_status='active'`, so it is already approved and available in the building list.

## Safety status

All repository work is isolated on the integration branch. The three migration files and smoke test have **not** been applied persistently to either Supabase project. All three migrations and the expanded smoke test were executed together against the live Negin 2 schema inside a single explicit transaction and then rolled back. PostgreSQL accepted the DDL, import, preserved super-admin session, Negin 2 legacy-session bridge, negative-credit regression and itemized net-payment assertions. GitHub Actions inline-JavaScript validation passed on the latest branch commit. A follow-up query confirmed the mb schema was not persisted and legacy counts were unchanged at 1 building, 10 units, 12 accounts, 551 transactions, 64 payment requests and 88 sessions. The default branch remains unchanged. Remaining validation is browser-level login/session testing and an isolated Supabase branch test before production cutover.
