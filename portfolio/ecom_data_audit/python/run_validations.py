#!/usr/bin/env python3
"""
Run SQL control checks and export exception outputs with run metadata.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
from pathlib import Path
from typing import Dict, List

import psycopg

CHECKS: Dict[str, str] = {
    "po_ordered_vs_received": """
        WITH ordered AS (
            SELECT pol.po_id, pol.sku_id, SUM(pol.ordered_qty) AS ordered_qty
            FROM ecom_audit.purchase_order_line pol
            GROUP BY 1,2
        ), received AS (
            SELECT i.po_id, r.sku_id, SUM(r.received_qty) AS received_qty
            FROM ecom_audit.receipt_line r
            JOIN ecom_audit.inbound_shipment i ON i.inbound_id = r.inbound_id
            GROUP BY 1,2
        )
        SELECT o.po_id, o.sku_id, o.ordered_qty, COALESCE(r.received_qty,0) AS received_qty,
               COALESCE(r.received_qty,0) - o.ordered_qty AS qty_variance
        FROM ordered o
        LEFT JOIN received r ON r.po_id = o.po_id AND r.sku_id = o.sku_id
        WHERE ABS(COALESCE(r.received_qty,0) - o.ordered_qty) > 0
        ORDER BY 1,2
    """,
    "sales_quantity_integrity": """
        SELECT sol.sales_order_line_id, so.external_order_id, s.sku_code, sol.ordered_qty, sol.shipped_qty, sol.returned_qty
        FROM ecom_audit.sales_order_line sol
        JOIN ecom_audit.sales_order so ON so.sales_order_id = sol.sales_order_id
        JOIN ecom_audit.sku s ON s.sku_id = sol.sku_id
        WHERE sol.shipped_qty > sol.ordered_qty OR sol.returned_qty > sol.shipped_qty
        ORDER BY sol.sales_order_line_id
    """,
    "negative_or_zero_landed_components": """
        SELECT l.landed_component_id, i.inbound_ref, s.sku_code, l.component_type, l.amount_usd
        FROM ecom_audit.landed_cost_component l
        JOIN ecom_audit.inbound_shipment i ON i.inbound_id = l.inbound_id
        JOIN ecom_audit.sku s ON s.sku_id = l.sku_id
        WHERE l.amount_usd < 0
           OR (l.component_type IN ('FREIGHT','DUTY','BROKER','INSURANCE') AND l.amount_usd = 0)
        ORDER BY l.landed_component_id
    """,
    "negative_running_inventory": """
        WITH running AS (
            SELECT movement_id, sku_id, warehouse_id, movement_ts, qty_delta,
                   SUM(qty_delta) OVER (
                     PARTITION BY sku_id, warehouse_id
                     ORDER BY movement_ts, movement_id
                   ) AS running_qty
            FROM ecom_audit.inventory_movement
        )
        SELECT movement_id, sku_id, warehouse_id, movement_ts, qty_delta, running_qty
        FROM running
        WHERE running_qty < 0
        ORDER BY movement_id
    """,
}


def write_csv(path: Path, rows: List[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run ecommerce data audit checks")
    parser.add_argument("--dsn", default=os.getenv("DATABASE_URL"), help="Postgres DSN or DATABASE_URL")
    parser.add_argument("--out", default="portfolio/ecom_data_audit/reports/out", help="output directory")
    parser.add_argument("--sql-version", default="v1.0.0")
    parser.add_argument("--code-version", default="v1.0.0")
    args = parser.parse_args()

    if not args.dsn:
        raise SystemExit("Missing --dsn and DATABASE_URL")

    out_dir = Path(args.out)
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    summary = {
        "run_id": run_id,
        "run_started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "sql_version": args.sql_version,
        "code_version": args.code_version,
        "checks": {},
    }

    with psycopg.connect(args.dsn) as conn:
        with conn.cursor() as cur:
            for name, sql in CHECKS.items():
                cur.execute(sql)
                columns = [d.name for d in cur.description]
                rows = [dict(zip(columns, row)) for row in cur.fetchall()]
                write_csv(out_dir / f"{run_id}_{name}.csv", rows)
                summary["checks"][name] = {"exception_count": len(rows)}

    summary["run_finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    (out_dir / f"{run_id}_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
