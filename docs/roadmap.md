# Distributed Payments Weekend Lab

## Purpose

Build one payment-system repository incrementally over twelve weekends. Each weekend introduces a reliability problem, deliberately reproduces the failure, then adds a mechanism that protects an explicit invariant. Later mechanisms should expose weaknesses in earlier assumptions.

Core principle: **Complexity should be introduced only when a failure mode earns it.**

Progress toward correctness locally, concurrently, asynchronously, across external systems, financially, and during recovery from failure. Keep deployment and build mechanics simple while making internal correctness increasingly serious.

The language is Go. What changes with Go is not the invariants but _where the mechanism lives_. A framework can supply transaction boundaries, retries, and message listeners as annotations. Go supplies `pgx.Tx`, a `for` loop, and `context`. That is the point: every mechanism in this lab becomes code that was written deliberately and can be read.

Secondary goals, in priority order:

1. Payment domain and reliability mechanisms (primary).
2. Idiomatic Go under real constraints, not toy-service Go.
3. AWS certification overlap. The path is Cloud Practitioner (CLF) first, then Developer Associate (DVA). Each weekend names the DVA topics it exercises; CLF overlap is thin by design and is covered in the calendar section.

This document preserves the plan. The weekends describe intended work, not completed features or demonstrated learning. Concrete contracts and unresolved semantics should be worked through in the relevant lesson.

## Teaching approach

The user requested the `teach` skill for hands-on guidance through this project across sessions. Break weekends into small lessons with explanation, prediction, implementation practice, deliberate failure, feedback, and verification. Guide the learner through the work at their level rather than completing the entire course in advance.

Use this plan as the course map. Use the teaching skill's `MISSION.md` for the learner's personal motivation and success criteria, and `learning-records/` for demonstrated insights. Keep planned exercises distinct from observed progress.

Go is the second stack here, not the strongest one. Expect lessons to spend time on Go-specific mechanics (`context` propagation, error wrapping, goroutine lifecycle, panics and `defer`) alongside the distributed-systems content, and treat those mechanics as teachable material rather than assumed background.

## Starting stack

| Concern           | Choice                                                 | Why this, not the alternative                                                                                                                         |
| ----------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Go                | 1.23+                                                  | `context`, generics, `errgroup`, structured logging in the standard library                                                                           |
| HTTP              | `net/http` with `chi`                                  | Standard-library-compatible router; no framework lifecycle to fight                                                                                   |
| PostgreSQL driver | `pgx/v5` native interface, not `database/sql`          | Explicit `BeginTx` with isolation levels, `pgconn.PgError` with SQLSTATE codes, `SKIP LOCKED` support. `database/sql` hides less but also offers less |
| Migrations        | `goose`                                                | Plain SQL files, up and down, embeddable                                                                                                              |
| Query layer       | Hand-written SQL first; `sqlc` optional from Weekend 6 | Writing the SQL by hand is part of learning transactions. `sqlc` earns its place once the schema stabilizes                                           |
| Tests             | `testing` with `testcontainers-go`                     | Real PostgreSQL, real broker. Failure tests must run against real infrastructure                                                                      |
| Broker            | SQS via LocalStack, `aws-sdk-go-v2`                    | Direct DVA overlap. Kafka teaches log semantics the exam does not test                                                                                |
| Local infra       | Docker Compose: postgres, localstack, later toxiproxy  | Introduce each container in the weekend that needs it                                                                                                 |
| Observability     | `log/slog` from day one; OpenTelemetry in Weekend 12   | Structured logs cost nothing to start; tracing waits until there is something distributed to trace                                                    |

Deliberately absent at the start: ORM, dependency-injection framework, Kubernetes, Terraform, multiple databases, multiple binaries.

## Starting architecture

One Git repository, one Go module, one PostgreSQL database, one deployable binary. Docker Compose for local infrastructure. Domain-oriented packages with modular boundaries inside the application.

Layer-per-directory packages (`payment/api`, `payment/application`, `payment/domain`, `payment/infrastructure`) work against Go: sub-packages per layer create import cycles as soon as a port interface and its consumer sit in different directories, and the resulting `payment/domain/payment.go` naming is noise.

Target structure, introduced as the exercises need it: **one package per module, layers as files.**

```text
cmd/
  payments/            main.go — wiring only, no logic
internal/
  payment/             payment.go       domain types, state machine, invariants
                       service.go       use cases (application layer)
                       postgres.go      repository implementation
                       http.go          handlers
                       ports.go         interfaces the service depends on
  account/             same shape (Weekend 2)
  outbox/              (Weekend 3)
  messaging/           SQS publisher and consumer adapters (Weekend 4)
  acquirer/            fake bank client and failure classification (Weekend 5)
  webhook/             (Weekend 7)
  reconciliation/      (Weekend 8)
  ledger/              (Weekend 9)
  saga/                (Weekend 10)
  platform/            db.go, tx.go, clock.go, ids.go — shared, no domain knowledge
migrations/
tests/                 cross-module failure tests (the named scenarios below)
```

Boundary rules:

- `internal/` restricts imports to the tree rooted at its parent. Package visibility hides unexported identifiers, but sibling packages can access any exported symbol, including one declared in `postgres.go`. Cross-module business calls should use the other module's exported service or events; keep repository details unexported where possible and review any exports needed for wiring.
- Dependency direction inside a module: `http.go` to `service.go` to `payment.go`; `postgres.go` implements `ports.go`. These files share a package, so the compiler will not enforce the direction. Package visibility is enforced by the compiler; service-only access and file-level layer direction require discipline and review. Import-boundary linting can restrict dependencies between packages, but cannot enforce these file-level layers.
- Avoid horizontal `pkg/`, `models/`, `handlers/`, and `repositories/` packages.

## Weekend roadmap

Each weekend lists the experiment, the invariant or correctness target, what Go forces the implementer to confront, and the DVA topics touched. The DVA line names topics at Developer Associate depth; where a weekend also gives usable Cloud Practitioner intuition, the calendar section says so rather than repeating it here.

### 1 — Idempotent Payment API

Build `POST /payments` with an `Idempotency-Key` header. Persist a payment first without protection, then add a unique constraint on `(key, scope)` and a stored hash of the request and response.

- Experiment: `errgroup` firing 100 concurrent requests with the same key. Then 100 requests with the same key and _different bodies_; decide what the second caller receives (422 is the usual answer, 409 is defensible; settle it in the lesson).
- Invariant: exactly one payment row per key; every caller with a matching body receives the same logical response.
- Go: `context` threaded from handler to service to `pgx`; catching `pgconn.PgError` with `Code == "23505"` and mapping it to a domain error through `errors.As`; the difference between "insert, catch conflict, re-read" and "select first" under concurrency.
- Test: `TestDuplicatePayment`.
- DVA: idempotency tokens in SDK retries; API Gateway retry behavior.

### 2 — Concurrent Balance Updates

Start with an account holding 1,000 THB. Two concurrent requests each attempt to withdraw 700 THB.

- Experiment, in this order: naive read-modify-write in separate statements, then `SELECT ... FOR UPDATE`, then a `version` column with `UPDATE ... WHERE version = $1`, then a single atomic `UPDATE ... WHERE balance >= $1 RETURNING`, then `BeginTx` with `Serializable` isolation and retry on SQLSTATE `40001`.
- Invariant: the sum of successful withdrawals never exceeds the starting balance, and every successful withdrawal is reflected exactly once.
- Go: `pgx.TxOptions{IsoLevel: pgx.Serializable}` is explicit; nothing decides on the implementer's behalf whether a method is transactional. Write a `platform.WithTx(ctx, func(tx pgx.Tx) error)` helper and understand why it must handle rollback and panic recovery, and why the serialization-failure retry belongs outside the helper's callback rather than inside it.
- Test: `TestConcurrentDebit`.
- DVA: DynamoDB conditional writes and optimistic locking with version attributes; the same mechanism against a different store.

### 3 — Transactional Outbox

Reproduce the dual-write failure: commit a payment, then publish, with an injected crash between the two. Then write `outbox_events` in the same transaction and publish from a separate goroutine.

- Experiments: crash after commit, publish destination unavailable, duplicate publication, publisher restart mid-batch.
- Invariant: a committed payment's event row is written in the same transaction as the payment, always.
- Go: the publisher is a goroutine running `for { select { case <-ctx.Done(): ...; case <-ticker.C: ... } }`. Claim rows with `FOR UPDATE SKIP LOCKED`. Graceful shutdown through `signal.NotifyContext`, draining in-flight publishes before exit.
- Open question for the lesson: crash injection that calls `os.Exit` kills the test binary itself. Resolve how the crash test runs the process under test out-of-process (re-executing the test binary with an environment flag, or running `cmd/payments` as a subprocess) before writing `platform.FaultPoint`.
- Test: `TestOutboxCrashRecovery`.
- DVA: none directly; the publisher's target becomes SQS in Weekend 4.

### 4 — Messaging and Idempotent Consumer

The publisher target becomes SQS on LocalStack. A ledger consumer receives `PaymentCompleted`.

- Experiment: deliver the same message N times; let the visibility timeout expire mid-processing; crash the consumer after the database commit but before `DeleteMessage`.
- Possible persistence: `processed_messages(event_id PK, processed_at)`, inserted **in the same transaction** as the business effect.
- Invariant: N deliveries produce one business effect.
- Go: `aws-sdk-go-v2` long polling with `WaitTimeSeconds`; a consumer loop with bounded concurrency (worker pool or semaphore); deciding whether the deduplication check happens before or inside the transaction, and why only "inside" holds. Note that `DeleteMessage` remains outside the transaction no matter what, which is exactly why the deduplication row is required.
- Test: `TestDuplicateMessage`.
- DVA: SQS visibility timeout, long polling, at-least-once delivery versus FIFO deduplication IDs, `DeleteMessage` semantics.

### 5 — Retry and DLQ

Build a fake acquirer as an `httptest.Server` configurable to return 200, 500, 429, a timeout, or a reset connection.

- Exercise: build an error taxonomy in Go — `ErrRetryable`, `ErrPermanent`, `ErrNeedsOperator` as wrapped error types — and classify each acquirer failure mode. Then add exponential backoff with full jitter, a maximum attempt count, and a dead-letter queue.
- Invariant: a retry is issued only when the operation is provably safe to repeat, which links back to Weekend 1's idempotency key, now sent _to_ the acquirer.
- Go: `http.Client` with a `Timeout` and a `context` deadline, and why both matter; `errors.Is(err, context.DeadlineExceeded)` versus a `net.Error` whose `Timeout()` reports true; writing the backoff loop by hand before reaching for a library.
- Note on ordering: Weekends 3 and 4 already need a rough retryable-versus-permanent split. Keep that split ad hoc until this weekend, then refactor the earlier call sites onto the taxonomy. The refactor is part of the lesson.
- Tests: `TestAcquirerRetry`, `TestPoisonMessageToDLQ`.
- DVA: SQS redrive policy and `maxReceiveCount`, SDK retry modes and adaptive backoff, Lambda asynchronous invocation DLQ.

### 6 — Payment State Machine

Replace a simplistic flag such as `paid bool` with `CREATED → AUTHORIZED → CAPTURED → SETTLED`, plus `FAILED`, `CANCELLED`, and `REFUNDED`.

- Define the transition table once, as data, and validate transitions in the domain type. Persist a validated transition through `UPDATE ... WHERE status = $expected`, so a stale writer affects zero rows and is told so. The expected-state predicate protects against concurrent changes; it does not check whether the old/new state pair is legal.
- Open question for the lesson: must the database also reject writes that bypass domain validation? If so, choose a mechanism that validates the old/new state pair and keeps the legal-transition rules consistent with the domain table.
- Invariant: no row ever holds an illegal state or arrives at a state through an illegal transition.
- Go: an unexported `type status string` with exported constants; a `map[status][]status` transition table; a `Transition(to status) error` method. This is the weekend to evaluate `sqlc`.
- Test: `TestIllegalTransitionRejected`.
- DVA: Step Functions state semantics as a comparison point, not an implementation.

### 7 — Webhook Delivery

Deliver payment notifications to a fake merchant endpoint (`httptest.Server`) that fails randomly.

- Proposed delivery fields: `event_id`, `destination`, `attempt`, `status`, `response_code`, `next_retry_at`, `signature`.
- Signature: `crypto/hmac` with SHA-256 over timestamp and body; merchant-side verification with `hmac.Equal` for constant-time comparison.
- Correctness target: every attempt and its outcome is traceable, replay is possible, and abandonment is explicit and visible.
- Go: a delivery worker polling for `next_retry_at <= now()` with `SKIP LOCKED`. This shape was already built in Weekend 3; notice the repetition rather than extracting it yet.
- Test: `TestWebhookRetry`.
- DVA: SNS HTTP subscriptions and delivery retry policy; EventBridge retry and DLQ.

### 8 — Reconciliation

Compare a fake settlement file (CSV) from the acquirer against internal `SETTLED` payments.

- Detect: missing internal record, missing external record, amount mismatch, unknown external transaction, duplicates.
- Correctness target: every discrepancy lands in a `reconciliation_items` table with a status an operator can act on.
- Go: `encoding/csv` used as a stream rather than loading the whole file; the matching strategy as an explicit decision (acquirer reference, idempotency key, or amount-plus-timestamp heuristics). Parse money from the CSV as an exact decimal string converted to minor units; never through `float64`.
- Test: `TestReconciliationMismatch`.
- DVA: an S3 event triggering a processing pipeline is the natural home for this in the exam's world.

### 9 — Double-Entry Ledger

Evolve the Weekend 4 consumer into immutable journal entries with balances derived from them.

- Invariant: within each journal, the sum of debits equals the sum of credits; entries are never updated or deleted.
- Enforce in the database: a deferred constraint trigger checking the balance per journal at commit, plus `REVOKE UPDATE, DELETE` on the entries table for the application role.
- Open question for the lesson: revoking those grants requires the application role to be distinct from the migration role. Decide the role split (and how `goose` authenticates) before this weekend, or the revoke is theater.
- Go: money representation, see Decision 2. Derive balances by query first; add a materialized balance table with Weekend 2's locking discipline only if the query is measurably too slow.
- Test: `TestUnbalancedJournalRejected`.

### 10 — Saga and Distributed Workflow

Model `Create Order → Authorize Payment → Reserve Inventory → Capture Payment` as in-process orchestration with persisted saga state.

- Experiment: fail inventory reservation after authorization and compensate by cancelling the authorization. Crash the orchestrator mid-saga and resume from persisted state.
- Correctness target: every saga reaches a terminal state, either completed or fully compensated, and is never stranded.
- Go: saga state as a table, with step execution driven by the same polling-worker shape used in Weekends 3 and 7. Having built that shape three times is the cue to extract `platform/worker.go` — the extraction is the deliverable, not an aside.
- Keep the workflow inside the single deployable binary; multiple services are not required for this exercise.
- Tests: `TestSagaCompensation`, `TestSagaResumeAfterCrash`.
- DVA: Step Functions standard workflows with catch and retry semantics; the managed version of what was built by hand.

### 11 — Event Ordering and Versions

Generate `PaymentAuthorized`, `PaymentCaptured`, and `PaymentRefunded`, then deliberately deliver refund, authorization, capture.

- The envelope gains a `version`. Example: `{"eventId":"evt-123","paymentId":"pay-42","version":7,"type":"PaymentCaptured"}`. The consumer applies `UPDATE ... WHERE version < $incoming`.
- Open question for the lesson: what happens on a gap, when v5 arrives and current state is v3? Reject and re-drive, or apply with a warning? The answer depends on whether the events are deltas or snapshots; decide which these are before treating stale-event rejection as a complete ordering solution.
- Correctness target: stale events cannot regress consumer state, and required intermediate effects are not silently lost.
- Test: `TestOutOfOrderEvent`.
- DVA: SQS FIFO message groups, and why they solve a narrower problem than this.

### 12 — Failure Injection and Observability

- Inject: database latency through toxiproxy, broker outage by stopping LocalStack, consumer `kill -9`, duplicate messages, process death after database commit, acquirer timeouts.
- Add: OpenTelemetry traces, Prometheus metrics for retry counts and DLQ depth, correlation IDs carried in `context` and emitted through a `slog` handler.
- Open question for the lesson: choose the trace backend. A local OTLP collector with Jaeger works offline; X-Ray export needs either a real development account or LocalStack Pro. Decide before committing to X-Ray-specific instrumentation.
- Verify: every earlier failure test still passes under injected faults.
- DVA: X-Ray instrumentation concepts, CloudWatch metrics and alarms, structured logging.
- Central question: what does the system do when something fails?

## Why the sequence compounds

Retries make API idempotency essential. Asynchronous messaging makes consumer idempotency essential. External systems make reconciliation necessary. Financial state makes immutable ledger history valuable. Multiple distributed steps make compensation necessary.

The Go-specific version of the same observation: Weekends 3, 7, and 10 each build a polling worker. Weekends 1, 2, 6, and 11 each use a conditional `UPDATE ... WHERE` as the concurrency primitive. Weekends 4 and 9 each put an audit or deduplication row in the same transaction as the effect it guards. A framework would have offered these as three different annotations on day one. Here they are visibly the same three ideas, and the extraction into `platform/` happens in Weekend 10 because the pattern has been seen three times, not because a library offered it up front.

The eventual system connects the payment API and idempotency to PostgreSQL, holding payments, idempotency keys, outbox events, processed messages, ledger entries, and webhook deliveries. An outbox publisher sends through SQS to ledger, webhook, and reconciliation consumers. All of it stays inside one Go process.

## Architectural stages

These stages group capabilities conceptually; the numbered weekends above remain the teaching sequence.

1. Modular monolith foundation: payment API, persistence, idempotency, concurrent-update experiments, transaction boundaries, and payment lifecycle.
2. Asynchronous boundary: transactional outbox, broker, idempotent consumers, retries, and DLQ.
3. External-system boundary: fake acquirer, network timeouts, webhook delivery, retry semantics, and reconciliation.
4. Financial correctness: double-entry ledger, immutable history, settlement concepts, financial invariants, and compensation.
5. Advanced distributed behavior: ordering, versions, failure injection, tracing, recovery metrics, and saga workflows.

## Repository rules

1. Use one database and one deployable binary initially.
2. Evolve this repository instead of replacing it with separate mini-projects.
3. Keep failure scenarios executable as Go tests. Candidate names: `TestDuplicatePayment`, `TestConcurrentDebit`, `TestOutboxCrashRecovery`, `TestDuplicateMessage`, `TestOutOfOrderEvent`, `TestWebhookRetry`, `TestReconciliationMismatch`, `TestIllegalTransitionRejected`, `TestUnbalancedJournalRejected`, `TestSagaCompensation`, `TestSagaResumeAfterCrash`.
4. Preserve broken behavior as controlled tests or experiments, rather than twelve long-lived architecture branches.
5. Prefer domain-oriented packages and explicit module interfaces or events.
6. Introduce infrastructure only when the learning problem requires it.
7. Every new mechanism must protect an explicit invariant; refine the correctness targets above into precise assertions during each lesson.
8. Do not adopt a third-party library for something that has not been written by hand at least once: backoff, worker loops, transaction helpers.
9. Every `context.Context` parameter is the first argument, and is honored all the way down to the driver.
10. Wrap errors with `%w` and classify them with `errors.Is` and `errors.As`. No string matching on error messages.

## Optional growth

Add import-boundary enforcement (`go-arch-lint` or `depguard`) once package boundaries stop moving. This is the analogue of adding Spring Modulith verification to a Java modular monolith, and it retains one repository, one Go module, and one binary.

Introduce a second Go module or separate binaries only for an actual constraint: independent deployment lifecycles, genuinely reusable libraries, or build-level dependency enforcement. Let the domain boundaries stabilize first. Progression: one module with one package per domain → linter-enforced boundaries → separate modules or binaries only if justified.

Introduce toxiproxy, OpenTelemetry, Prometheus, and any further AWS services when an exercise needs them. Avoid Kafka, Redis, Kubernetes, Terraform, EKS, multiple databases, and many services at the outset. The learning targets are transactions, concurrency, failure boundaries, message delivery, financial invariants, and recovery.

## Calendar fit with the AWS certification path

The certification path is Cloud Practitioner (CLF-C02) first, then Developer Associate (DVA-C02), inside the same three-to-four-month window. The lab starts alongside exam preparation. Its twelve weekends are learning units that may span more than twelve calendar weeks; the later units continue after DVA and may extend beyond the exam window.

**The lab helps with DVA and barely helps with CLF, and that is convenient rather than a problem.** CLF is broad and shallow: billing models, the shared responsibility model, service-identification questions, support plans. Almost none of it is reachable by building one payment system well. DVA is the opposite; Weekends 4, 5, 7, and 12 carry heavy, direct overlap. So CLF preparation is reading and practice questions that compete with the lab only for calendar time, not for attention on the same material.

That suggests putting CLF early, while the lab is in its least AWS-dependent stretch:

- **Weekends 1 to 3** touch no AWS at all. They are Go, PostgreSQL, transactions, and the outbox pattern. Run CLF preparation alongside them and sit CLF at the end of this stretch, roughly four to six weeks in. If CLF preparation runs long, these are also the weekends that tolerate a skipped week best, because nothing downstream depends on infrastructure they introduce.
- **Weekends 4 to 7** are the DVA core: SQS semantics, retry and DLQ behavior, SNS delivery policies. Run these after CLF is done, with DVA as the target at the end of the window. Sitting DVA with Weekends 4, 5, and 7 fresh is worth more than sitting it with all twelve weekends half-remembered.
- **Weekends 8 to 12** come after DVA, extending beyond the three-to-four-month exam window when DVA is taken at its end. Weekend 12 is the one exception worth pulling forward if time allows, since X-Ray and CloudWatch appear on the exam; but its value depends on there being something built to instrument, so pulling it earlier than Weekend 7 costs more than it gains.

If preparation for either exam needs more room, Weekends 8 and 9 are the safest to defer. They are domain-heavy and exam-light: reconciliation and double-entry accounting are the most valuable weekends for the fintech career goal and the least valuable for either exam.

**CLF touchpoints in the lab**, such as they are: standing up LocalStack in Weekend 4 gives concrete meaning to SQS, and to the idea of a managed queue as a service you do not operate. Weekend 12 makes CloudWatch and X-Ray real rather than names on a slide. Neither is worth resequencing for. Treat CLF as a separate study track that happens to share a calendar.

## Decisions to make before Weekend 1

These are load-bearing and are **not yet settled**. Everything above assumes the recommended option; changing one changes the weekends that depend on it.

1. **Package layout**: one package per module with layers as files (recommended) versus layer sub-packages. The sub-package route is closer to a Spring layout and to existing instincts, at the cost of import-cycle wrangling and un-Go-like naming. Affects every weekend.
2. **Money type**: `int64` minor units (satang) with currency in a separate column (recommended) versus `shopspring/decimal`. Integers are exact and fast and force rounding to be handled explicitly at the boundaries. Decimal is more general and more forgiving of multi-currency, at the cost of a dependency in the hottest path. Affects Weekends 2, 8, and 9 most.
3. **Broker**: SQS only (recommended) versus SNS-to-SQS fan-out from the start. Fan-out is more realistic and covers more exam ground, but Weekend 4 has enough to teach without it. Introduce SNS in Weekend 7, when a second consumer actually exists.
4. **Query layer**: hand-written SQL through Weekend 5, with `sqlc` optional from Weekend 6 (recommended), versus `sqlc` from day one. Hand-writing early keeps transaction boundaries visible; `sqlc` later removes boilerplate once the boundaries no longer need to be seen.

Record each decision as an ADR under `docs/adr/` when it is settled.
