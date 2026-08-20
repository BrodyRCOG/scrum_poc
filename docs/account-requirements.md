# Account Requirements — Banking Demo

This document captures detailed requirements for creating and managing bank accounts in the Banking_Demo project. It is intended to live in the repository's docs/ directory so it can be published with GitHub Pages.

## Purpose
Provide functional and non-functional requirements and a high-level architecture diagram for the account lifecycle: creation, update, operations (deposit/withdraw/transfer), and closure.

## Scope
- Customer-facing account creation and management flows
- Backend API and data model requirements
- Admin operations and audit capabilities
- Notifications and integration points (KYC, payments)

## Actors
- Customer (end user)
- Admin / Bank employee
- External KYC provider
- Notification services (email/SMS)
- Fraud detection service

---

## Functional Requirements

### 1. Account Creation
- API: POST /api/v1/accounts
- Inputs:
  - customerId (required)
  - accountType (ENUM: CHECKING, SAVINGS, LOAN) (required)
  - currency (ISO-4217) (required)
  - initialDeposit (decimal, >= 0)
  - productId (optional) — links to specific product tiers
  - accountHolderDetails (name, dob, address)
- Validation:
  - customerId must exist
  - initialDeposit must respect product minimums
  - currency must be supported
  - accountHolderDetails must meet KYC minimums
- Security:
  - API requires authenticated JWT with scopes: accounts.create
  - Rate limit: 10 requests per minute per IP/account to prevent abuse
- Behavior:
  - On success return 201 Created with account resource and location header
  - Generate unique accountNumber (IBAN-like or internal format) and accountId (UUID)
  - Persist initial opening transaction in transactions table (immutable ledger entry)
  - Trigger asynchronous KYC check where required; if KYC fails, mark account as PENDING_REVIEW or SUSPENDED
  - Emit AccountCreated event to event bus
- Edge cases:
  - Duplicate creation attempts must be idempotent (client-supplied idempotency-key header)
  - If DB constraint violation occurs, return 409 with details

### 2. Account Profile Management (Customer)
- API: GET /api/v1/accounts/{accountId}
- API: PUT /api/v1/accounts/{accountId}
  - editable fields: mailingAddress, contactPhone, email (with verification flow), preferredName
  - immutable fields: accountType, accountNumber
- Security: require JWT with accounts.read or accounts.write scoped tokens and ownership check
- Audit: All updates must produce an audit record (who, what, when, previousValues)

### 3. Deposits and Withdrawals
- API: POST /api/v1/accounts/{accountId}/transactions
- transactionType: CREDIT | DEBIT
- Validation:
  - For debit, ensure sufficient available balance (consider holds/pending items)
  - Respect daily and per-transaction limits
- Behavior:
  - Create immutable transaction record with status: PENDING -> SETTLED or FAILED
  - Use ACID DB transactions for balance updates (or event-sourced ledger pattern)
  - Emit TransactionCreated event

### 4. Transfers
- Internal transfers: fromAccountId -> toAccountId
- External transfers (ACH/SWIFT) integrate with payments gateway; follow payments SLA
- Must support scheduled and recurring transfers

### 5. Freeze / Close / Reopen
- Admin APIs to freeze or close accounts
- Closed accounts: mark status CLOSED, disallow new debits, allow balance withdrawal within retention policy
- Reopen requires admin review and audit record

### 6. Transaction History / Statements
- API: GET /api/v1/accounts/{accountId}/transactions?from=&to=&limit=
- Support CSV/PDF statement generation with pagination and filters
- Retain transaction history per regulatory retention (e.g., 7 years) — configurable

### 7. Notifications
- Account creation, suspicious activity, low balance, large transaction — email/SMS/push
- Use an asynchronous Notification Service with retry and DLQ

---

## Non-Functional Requirements
- Security
  - TLS 1.2+ for all traffic
  - Sensitive fields encrypted at rest (PII, account numbers partial masking)
  - Role-based access control (RBAC) with least privilege
  - Audit logging with tamper-evident storage (append-only logs)
- Performance
  - 95th percentile API latency < 200ms for read ops under typical load
  - Throughput: support 1,000 concurrent active sessions per region; scale horizontally
- Availability
  - 99.95% uptime SLA for core account services
  - Multi-AZ deployment for DB and services
- Consistency
  - Strong consistency for balance calculations (no lost updates)
  - Consider use of distributed transactions or event-sourced ledger for scaling
- Compliance
  - Data retention policies, GDPR/CCPA support, PCI DSS considerations for payment data
- Monitoring and Observability
  - Distributed tracing, structured logs, metrics for errors/latency/throughput
- Backups
  - Daily backups for DB with point-in-time recovery for 30 days (configurable)

---

## Data Model (high-level)
- Account
  - id: UUID
  - accountNumber: string (unique)
  - customerId: UUID
  - type: ENUM
  - currency: string
  - status: ENUM (ACTIVE, PENDING, FROZEN, CLOSED)
  - openedAt, closedAt
  - metadata (JSON)

- Transaction
  - id: UUID
  - accountId: UUID
  - amount: decimal
  - currency: string
  - type: ENUM (DEBIT/CREDIT)
  - balanceAfter: decimal
  - createdAt
  - status (PENDING/SETTLED/FAILED)
  - reference (external reference)

- AuditRecord
  - id: UUID
  - entityId: UUID
  - entityType: string
  - action: string
  - performedBy: userId/system
  - before: JSON
  - after: JSON
  - createdAt

---

## High-level Architecture Diagram
Below is a mermaid diagram showing the recommended architecture for the account management system. This can be rendered in the documentation site that supports mermaid.

```mermaid
flowchart LR
  subgraph Web
    A[Customer Browser / Mobile App]
    B[Admin Console]
  end

  subgraph CDN
    CDN[GitHub Pages (docs) / CDN]
  end

  A -->|HTTPS| API[API Gateway / Load Balancer]
  B -->|HTTPS| API
  API --> Auth[Auth Service (OAuth2 / JWT)]
  API -->|REST/gRPC| AccountSvc[Account Service]
  API -->|REST/gRPC| TransactionSvc[Transaction Service]
  AccountSvc --> DB[(Primary SQL DB)]
  TransactionSvc --> Ledger[(Ledger DB / Partitioned SQL)]
  AccountSvc --> EventBus[(Event Bus / Kafka)]
  TransactionSvc --> EventBus
  EventBus --> NotificationSvc[Notification Service]
  EventBus --> AuditSvc[Audit & Logging]
  EventBus --> Analytics[Analytics / Fraud Detection]
  NotificationSvc --> Email[Email Provider]
  NotificationSvc --> SMS[SMS Provider]
  Analytics -->|API| Fraud[Fraud Service]
  API --> Payments[Payments Gateway]
  Payments -->|External networks| ACH[ACH/SWIFT]
  AdminConsole[Admin Console] -.-> AuditSvc
  CDN -->|Docs| A

  classDef svc fill:#f9f,stroke:#333,stroke-width:1px;
  class AccountSvc,TransactionSvc,AuthSvc,NotificationSvc,AuditSvc svc;
```

Notes:
- The API Gateway handles routing, authentication, and rate limiting.
- AccountService owns account CRUD and business rules; TransactionService owns ledger and balance calculations. They communicate through events to ensure eventual consistency for certain read-models, or use synchronous calls for strong consistency when required.
- Ledger DB may be separated from the primary relational DB to optimize for immutable transaction storage and scalability.

---

## Operational Concerns & Next Steps
- Add CI/CD checks, unit/integration tests and contract tests between AccountService and TransactionService.
- Prepare data migration plan for existing users (if any).
- Add a threat model and run security review.
- Add diagrams/images to docs/ (PNG/SVG) if you prefer rendered images; place assets under docs/assets/.

---

## How to publish to GitHub Pages
1. Place this file in docs/ (this file). GitHub Pages can publish from the repository's docs folder on the default branch.
2. In repository Settings > Pages set Source to "Deploy from a branch" and select the default branch and /docs folder.

---

If you want, I can add a PNG/SVG architecture diagram to docs/assets/ and link it from this page, or split the requirements into separate pages (Creation, Management, Architecture).
