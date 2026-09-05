# Distributed Payments Weekend Lab

## Purpose

Build one payment-system repository incrementally over twelve weekends. Each weekend introduces a reliability problem, deliberately reproduces the failure, then adds a mechanism that protects an explicit invariant. Later mechanisms should expose weaknesses in earlier assumptions.

Core principle: **Complexity should be introduced only when a failure mode earns it.**

Progress toward correctness locally, concurrently, asynchronously, across external systems, financially, and during recovery from failure. Keep deployment and build mechanics simple while making internal correctness increasingly serious.

This document preserves the user's starting plan. The weekends describe intended work, not completed features or demonstrated learning. Concrete contracts and unresolved semantics should be worked through in the relevant lesson.

## Teaching approach

The user requested the `teach` skill for hands-on guidance through this project across sessions. Break weekends into small lessons with explanation, prediction, implementation practice, deliberate failure, feedback, and verification. Guide the learner through the work at their level rather than completing the entire course in advance.

Use this plan as the course map. Use the teaching skill's `MISSION.md` for the learner's personal motivation and success criteria, and `learning-records/` for demonstrated insights. Establish experience level and personal motivation before tailoring lessons; those details have not yet been supplied. Keep planned exercises distinct from observed progress.

## Starting architecture

- One Git repository, Spring Boot application, Maven module, PostgreSQL database, and deployable application.
- Docker Compose for local infrastructure.
- Domain-oriented packages with modular boundaries inside the application.
- Java 21+, Spring Boot, PostgreSQL, JUnit, and Testcontainers as the suggested starting stack; choose concrete versions at implementation time.

A modular monolith defines architectural boundaries inside one deployable application. Maven multi-modules primarily define build-time boundaries. Architectural clarity matters more than build complexity here.

Target package structure, introduced as the exercises need it:

```text
src/main/java/com/example/payments/
├── payment/
│   ├── api/
│   ├── application/
│   ├── domain/
│   └── infrastructure/
├── ledger/
│   ├── application/
│   ├── domain/
│   └── infrastructure/
├── outbox/
├── webhook/
├── reconciliation/
└── shared/
```

Inside a module, dependencies flow from API to application to domain. Infrastructure implements ports owned by application/domain layers. Across modules, use explicit APIs or events, such as payment emitting `PaymentCompleted` for ledger consumption. Avoid accessing another module's internal classes or organizing the whole application into horizontal controller/service/repository/entity packages.

## Weekend roadmap

### 1 — Idempotent Payment API

Build `POST /payments`, initially persisting a payment, then add an `Idempotency-Key` header and PostgreSQL uniqueness protection. Deliberately retry requests and exercise concurrent duplicates.

- Experiment: 100 concurrent requests with the same key, such as `abc-123`.
- Invariant: exactly one payment record; all callers receive the same logical result for the same operation.
- Learn: HTTP retries, idempotency, race conditions, database uniqueness, and concurrency correctness.

### 2 — Concurrent Balance Updates

Start with an account holding 1,000 THB. Concurrent requests A and B each attempt to withdraw 700 THB.

- Experiment: naive read-modify-write, then optimistic locking, pessimistic locking, atomic SQL updates, and transaction isolation.
- Correctness target: concurrent withdrawals respect the available funds and preserve the effect of each successful withdrawal.
- Learn: lost updates, locking, transaction boundaries, and database isolation.

### 3 — Transactional Outbox

First build the dual-write failure: commit a payment and separately publish `PaymentCompleted`, with an injected crash between the operations. Then write the payment and an `outbox_event` in the same database transaction, and publish pending events separately.

- Experiments: crash after commit, destination unavailable, duplicate publication, and publisher restart. Exercise broker-specific cases once the broker is introduced in Weekend 4.
- Invariant: a committed payment's required event is durably recorded in the same transaction.
- Learn: the dual-write problem, atomicity boundaries, and eventual consistency.

### 4 — Messaging and Idempotent Consumer

Introduce a broker between payment events and the ledger consumer. Repeatedly deliver the same event.

- Possible persistence: `processed_messages` with unique `event_id` and `processed_at`.
- Invariant: delivering an event N times produces its business effect once.
- Learn: at-least-once delivery, duplicate events, consumer idempotency, and the limits of claims about exactly-once behavior.

### 5 — Retry and DLQ

Build a fake bank/acquirer API returning successful responses, HTTP 500, timeouts, and connection resets. Add exponential backoff, jitter, retry limits, and a dead-letter queue (DLQ).

- Exercise: classify failures as retryable, permanent, suitable for a DLQ, or requiring manual intervention.
- Invariant: a retry is safe only when the operation is safe to repeat.
- Learn: transient versus permanent failures, poison messages, backoff, jitter, and DLQs.

### 6 — Payment State Machine

Replace simplistic flags such as `paid = true` with an explicit lifecycle. Proposed main path: `CREATED → AUTHORIZED → CAPTURED → SETTLED`; additional states: `FAILED`, `CANCELLED`, and `REFUNDED`.

- Define legal transitions. Proposed examples: `CREATED → AUTHORIZED`, `AUTHORIZED → CAPTURED`, and `CAPTURED → REFUNDED` are legal; `CAPTURED → CREATED` is illegal.
- Invariant: transitions preserve the agreed payment lifecycle and reject impossible states.
- Learn: domain invariants, lifecycle modeling, and state machines.

### 7 — Webhook Delivery

Deliver payment notifications to a fake merchant endpoint that randomly fails. Implement signatures, retries, delivery history, duplicates, replay, and eventual abandonment.

- Proposed delivery fields: `event_id`, `destination`, `attempt`, `status`, `response_code`, and `next_retry_at`.
- Correctness target: delivery attempts and their outcomes remain traceable through retries, replay, and abandonment.
- Learn: external integration reliability, delivery guarantees, replay, and observability.

### 8 — Reconciliation

Compare internal payments against a fake external settlement file/API. Example internal amounts: payments #123 = 500, #124 = 800, #125 = 300; external transactions A = 500, B = 700, C = 400. Define matching identifiers during the exercise.

- Detect missing transactions, duplicates, amount mismatches, and unknown external transactions.
- Correctness target: discrepancies are detectable and available for investigation and repair.
- Learn: distributed systems need inconsistency detection and recovery in addition to prevention.

### 9 — Double-Entry Ledger

Evolve the earlier ledger consumer into immutable journal entries and derived balances. Illustrative transfer: customer account −500, merchant account +500; define actual debit/credit conventions in the lesson.

- Invariant: total debits equal total credits.
- Learn: double-entry accounting, immutable financial history, auditability, and derived balances.

### 10 — Saga / Distributed Workflow

Model `Create Order → Authorize Payment → Reserve Inventory → Capture Payment`. Deliberately fail inventory reservation after authorization, then compensate by cancelling the authorization. Explore cancellation/refund compensation as appropriate to the completed step.

- Correctness target: partial failures lead to explicit recovery or compensation outcomes.
- Learn: sagas, compensation, partial failure, and workflow design.
- Keep the workflow in the modular monolith initially; multiple microservices are not required for this exercise.

### 11 — Event Ordering and Versions

Generate `PaymentAuthorized`, `PaymentCaptured`, and `PaymentRefunded`, then deliberately deliver refund, authorization, capture. Add entity versions or sequence numbers and stale-event protection.

- Example envelope: `{"eventId":"evt-123","paymentId":"pay-42","version":7,"type":"PaymentCaptured"}`.
- Proposed rule to examine: ignore/reject `incoming version <= current version` as stale. Determine how gaps and required intermediate effects are handled before treating this as a complete ordering solution.
- Correctness target: stale deliveries cannot regress consumer state, while required effects remain accounted for.
- Learn: ordering, stale events, causal consistency, and optimistic concurrency.

### 12 — Failure Injection and Observability

Inject database latency, broker outages, consumer crashes, duplicate messages, network timeouts, process death after database commit, and external API timeouts.

- Add logs, metrics, traces, correlation IDs, event IDs, payment IDs, retry counters, and DLQ metrics.
- Verify recovery behavior and the earlier invariants under injected failures.
- Learn: fault tolerance, operational observability, recovery behavior, and failure analysis.
- Central question: what does the system do when something fails?

## Why the sequence compounds

Retries make API idempotency essential. Asynchronous messaging makes consumer idempotency essential. External systems make reconciliation necessary. Financial state makes immutable ledger history valuable. Multiple distributed steps make compensation necessary.

The eventual system connects payment API and idempotency to PostgreSQL, with payments, idempotency keys, outbox events, processed messages, ledger entries, and webhook deliveries as needed. An outbox publisher sends through a broker to ledger, webhook, and settlement/reconciliation consumers. Many components can remain inside one Spring Boot process.

## Architectural stages

These stages group capabilities conceptually; the numbered weekends above remain the proposed teaching sequence.

1. Modular monolith foundation: payment API, persistence, idempotency, concurrent-update experiments, transaction boundaries, and payment lifecycle.
2. Asynchronous boundary: transactional outbox, broker, idempotent consumers, retries, and DLQ.
3. External-system boundary: fake bank/acquirer, network timeouts, webhook delivery, retry semantics, and reconciliation.
4. Financial correctness: double-entry ledger, immutable history, settlement concepts, financial invariants, and compensation.
5. Advanced distributed behavior: ordering, versions, failure injection, tracing, recovery metrics, and saga workflows.

## Repository rules

1. Use one database and one deployable application initially.
2. Evolve this repository instead of replacing it with separate mini-projects.
3. Keep failure scenarios executable as tests. Candidate names: `DuplicatePaymentTest`, `ConcurrentDebitTest`, `OutboxCrashRecoveryTest`, `DuplicateMessageTest`, `OutOfOrderEventTest`, `WebhookRetryTest`, and `ReconciliationMismatchTest`.
4. Preserve broken behavior as controlled tests or experiments, rather than twelve long-lived architecture branches.
5. Prefer domain-oriented packages and explicit module interfaces/events.
6. Introduce infrastructure only when the learning problem requires it.
7. Every new mechanism must protect an explicit invariant; refine the correctness targets above into precise assertions during each lesson.

## Optional growth

Add Spring Modulith verification once package boundaries are meaningful enough to enforce. This can retain one repository, Maven module, Spring Boot application, and deployable JAR.

Introduce Maven multi-modules only for an actual constraint: stronger compile-time isolation, independently reusable libraries, large build times, different module lifecycles, team ownership, or build-level dependency enforcement. Let domain boundaries stabilize first.

Progression: single Maven module → package-based modular monolith → optional Spring Modulith verification → Maven multi-modules only if justified.

Introduce Kafka or RabbitMQ, LocalStack, AWS services, OpenTelemetry, and Prometheus/Grafana when an exercise needs them. Avoid adding Kafka, Redis, Kubernetes, Terraform, EKS, multiple databases, and many services at the outset. The learning targets are transactions, concurrency, failure boundaries, message delivery, financial invariants, and recovery.
