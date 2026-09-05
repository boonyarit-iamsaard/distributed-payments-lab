# Distributed Payments Lab

This lab explores payment correctness under retries, concurrency, partial failure, and recovery.

## Language

**Payment**:
A payment operation whose lifecycle the lab tracks from creation through subsequent financial outcomes. Creating a payment record does not by itself mean funds have moved or settlement has occurred.

**Ledger**:
The financial record that evolves toward immutable, balanced journal entries and account balances derived from those entries.

**Reconciliation**:
Comparison of internal payment records with external bank/acquirer records to identify missing transactions, duplicates, amount mismatches, and unknown external transactions.

**Webhook delivery**:
Delivery of a payment notification to a merchant endpoint, potentially through multiple attempts for the same event.
