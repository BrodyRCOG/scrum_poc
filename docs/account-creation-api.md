# POST /api/v1/accounts — Demo Notes

## Issue summary
Implement an endpoint that lets an authenticated user open a new bank account. The endpoint accepts customer and account details, validates them (customer existence, deposit minimums, currency, KYC), and on success creates the account, records an opening ledger entry, kicks off an async KYC check, and emits an event for downstream systems.

| Field | Value |
|---|---|
| Type | Functional |
| Priority | P0 |
| Epic | Account Lifecycle |
| Story points | 8 |
| Clarification status | Confirmed |
| Confidence | Firm |
| Source | `docs/account-requirements.md` — Section 1: Account Creation |

## Request contract
**Endpoint:** `POST /api/v1/accounts`
**Auth:** JWT with `accounts.create` scope

| Field | Required | Notes |
|---|---|---|
| `customerId` | Yes | Must exist in the database |
| `accountType` | Yes | `CHECKING`, `SAVINGS`, or `LOAN` |
| `currency` | Yes | ISO-4217 code; must be supported |
| `initialDeposit` | No | Must meet the product's minimum if provided |
| `productId` | No | — |
| `accountHolderDetails` | Yes | Must meet KYC minimums |

**Idempotency:** Duplicate requests using the same `Idempotency-Key` header return the original result instead of creating a second account.

## What happens on success
1. `customerId`, deposit minimum, currency, and KYC minimums are all validated.
2. A unique `accountId` (UUID) and `accountNumber` (IBAN-like) are generated.
3. An immutable opening transaction is written to the ledger.
4. The account is created and an async KYC check is kicked off in the background.
5. An `AccountCreated` event is emitted to the event bus.
6. API responds `201 Created` with the account resource and a `Location` header.

## Status outcomes
- KYC check passes → account stays active.
- KYC check fails or is inconclusive → account is marked `PENDING_REVIEW` or `SUSPENDED`.

## Error handling
- Constraint violations (e.g. duplicate account, bad reference data) → `409 Conflict` with a descriptive error body.
- Rate limiting: 10 requests per minute per IP/account.

## Acceptance criteria checklist
- [ ] Endpoint accepts all required and optional parameters
- [ ] Validates `customerId` exists
- [ ] Validates `initialDeposit` against product minimum
- [ ] Validates currency is supported
- [ ] Validates `accountHolderDetails` against KYC minimums
- [ ] Requires JWT with `accounts.create` scope
- [ ] Enforces rate limit (10 req/min per IP/account)
- [ ] Returns `201 Created` with resource + `Location` header
- [ ] Generates unique `accountId` (UUID) and `accountNumber` (IBAN-like)
- [ ] Records immutable opening transaction
- [ ] Triggers async KYC check; sets `PENDING_REVIEW`/`SUSPENDED` on failure
- [ ] Emits `AccountCreated` event
- [ ] Idempotent on repeated `Idempotency-Key`
- [ ] Returns `409` with details on DB constraint violation

## Demo script
1. **Show the card on the board.** Point out `Epic: Account Lifecycle`, `Priority: P0`, `8 points`, assignee, and linked pull request.
2. **Call the endpoint** with a valid payload — walk through the request body field by field against the table above.
3. **Show the `201` response** — highlight the `Location` header, the generated `accountId`, and the IBAN-like `accountNumber`.
4. **Show the ledger entry** created for the opening transaction — note that it's immutable, not editable after the fact.
5. **Show the account sitting in `PENDING_REVIEW`** while the async KYC check runs, then show it flip once the check resolves.
6. **Show the emitted `AccountCreated` event** on the event bus (or its log entry) so the audience sees the downstream trigger fire.
7. **Repeat the same request with the same `Idempotency-Key`** — show that no second account gets created.
8. **Send an invalid request** (bad currency or missing KYC field) and show the descriptive `409`/validation error.
9. **Close the loop:** merge the PR live if timing allows, and let the board's card flip to Done on its own — same mechanism covered earlier in this walkthrough.