# Exception Report Design (Operations + Finance)

## Objective
A daily, auditable exceptions pack that operations and finance can action in under 30 minutes.

## Report Sections
1. **Run metadata**
   - run_id
   - run timestamp (UTC)
   - source batch range
   - SQL version / code version
2. **Critical blockers (P1)**
   - Negative inventory run-rate
   - Broken lineage (reference missing)
   - Shipped quantity greater than ordered
3. **Financial risk (P2)**
   - Negative/zero landed cost components
   - Landed unit cost outside tolerance vs prior 30-day median
4. **Reconciliation drift (P2/P3)**
   - Ordered vs received variance by PO/SKU
   - Received vs in-stock variance by SKU/warehouse
   - Sold vs inventory decrements mismatch
5. **Action queue**
   - owner_team (Ops / Finance / Marketplace / Data Eng)
   - due_by
   - blocking_impact (stockout risk, margin overstatement, settlement mismatch)

## Required Columns (per exception row)
- exception_type
- severity
- business_date
- channel_code
- warehouse_code
- sku_code
- po_number / external_order_id
- expected_value
- actual_value
- variance
- source_system
- source_batch_id
- lineage_ref (table + primary key)
- first_seen_at
- last_seen_at
- status (OPEN, ACKNOWLEDGED, RESOLVED)
- resolution_note

## Governance Rules
- No silent overwrites: prior exception state kept in history table.
- Every exception must link to source record keys.
- If severity is P1, notify Slack + create ticket automatically.
- Resolved exceptions require evidence field (e.g., corrected PO receipt in ERP).

## Delivery
- CSV extracts for ops teams.
- JSON summary for automation.
- Stored SQL snapshots in git for audit trail.
