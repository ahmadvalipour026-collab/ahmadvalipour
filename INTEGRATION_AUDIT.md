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
| transactions | 547 |
| payment_requests | 64 |
| rates | 15 |
| activity_logs | 1,079 |
| announcements | 4 |
| resident_requests | 4 |
| push_subscriptions | 3 |
| sessions | 87 |

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

## Safety status

This audit was performed using read-only repository and database inspection. No production database rows, schemas, or functions were changed. No default branch was changed. The work branch is ready for the implementation commits.
