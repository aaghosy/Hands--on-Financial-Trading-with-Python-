# Ecommerce Data Audit Portfolio Project (Shopify + Amazon)

This project demonstrates practical data controls for a DTC ecommerce brand that manufactures in China and fulfills in the US/China.

## What this project proves
- Reconcile purchased, received, in-stock, and sold units.
- Compute landed COGS at SKU level with traceable source components.
- Detect plausible but wrong data before decisions are made.
- Verify outputs directly against source loads.
- Trace every key metric to source batch, SQL logic, and run metadata.

## Folder Structure
```text
portfolio/ecom_data_audit/
  README.md
  schema/
    01_postgres_schema.sql
  data/
    02_seed_sample_data.sql
  sql_checks/
    03_control_checks.sql
  python/
    run_validations.py
    requirements.txt
  reports/
    exception_report_design.md
  docs/
    case_study.md
    application_answer.md
```

## Step-by-step build

### 1) Create schema
Run:
```bash
psql "$DATABASE_URL" -f portfolio/ecom_data_audit/schema/01_postgres_schema.sql
```

### 2) Load sample data (with intentional issues)
Run:
```bash
psql "$DATABASE_URL" -f portfolio/ecom_data_audit/data/02_seed_sample_data.sql
```

Intentional issues include:
- Received quantity > ordered quantity.
- Negative duty landed-cost component.
- Shipped quantity > ordered quantity.
- Negative running stock in FBA due to missing inbound/transfer record.

### 3) Run SQL controls
Run:
```bash
psql "$DATABASE_URL" -f portfolio/ecom_data_audit/sql_checks/03_control_checks.sql
```

### 4) Run Python exception export
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r portfolio/ecom_data_audit/python/requirements.txt
python portfolio/ecom_data_audit/python/run_validations.py --dsn "$DATABASE_URL"
```

Outputs:
- `reports/out/<run_id>_*.csv` per control check.
- `reports/out/<run_id>_summary.json` with run-level counts.

## Core controls implemented
1. **PO vs receipt reconciliation** (unit integrity).
2. **Sales order quantity integrity** (`shipped <= ordered`, `returned <= shipped`).
3. **Landed cost sanity checks** (no negative/zero critical costs).
4. **Running inventory non-negative check** by SKU + warehouse.
5. **Reference lineage check** (movement refs must exist).
6. **Landed unit cost recomputation** from EXW + allocated components.

## Why this matters for business impact
- Prevents margin distortion from bad landed cost components.
- Prevents false in-stock positions that cause overselling.
- Prevents finance close surprises caused by inventory/sales mismatch.
- Creates auditable history for month-end and channel settlement disputes.
