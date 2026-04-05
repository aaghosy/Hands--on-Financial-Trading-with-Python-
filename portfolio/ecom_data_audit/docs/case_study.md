# Case Study: Trustworthy Ecommerce Ops Data Without Dashboards

## Context
A fast-scaling DTC brand sells on Shopify and Amazon, manufactures in China, and fulfills in US 3PL + Amazon FBA. Teams reported "reasonable" metrics, but finance and ops repeatedly disagreed on available inventory and true COGS.

## Goal
Build a control-first data layer that answers one question reliably:
**Can we trust unit counts and landed COGS enough to make purchasing and margin decisions?**

## Approach
1. Normalize source feeds from ERP, WMS, Shopify, and Amazon into PostgreSQL.
2. Keep source-batch metadata for every load (`source_batch`, file hash, timestamps).
3. Track inventory as an event ledger, not overwritten snapshots.
4. Recompute controls directly in SQL using deterministic checks.
5. Export actionable exceptions with ownership, severity, and lineage references.

## What was validated
- Ordered vs received by PO/SKU.
- Received vs on-hand movement trail.
- Sold units vs inventory decrements.
- Landed cost components and recomputed landed unit cost.
- Integrity of references (e.g., every sale movement has a valid order line).

## Key findings from sample run
- PO line over-receipt on SKU-B indicates receiving or PO error.
- Amazon order line shipped quantity exceeds ordered quantity.
- Negative duty line distorts landed COGS downward.
- FBA inventory drops below zero because a transfer/receipt record is missing.

## Business impact if unchecked
- Overstated gross margin from understated landed cost.
- False confidence in stock availability and replenishment timing.
- Disputes between operations and finance during close.
- Increased marketplace penalties from fulfillment errors.

## Deliverables
- PostgreSQL schema for traceable operations model.
- Seed data with realistic failure modes.
- SQL control suite + Python exception runner.
- Exception report design for cross-functional action.
