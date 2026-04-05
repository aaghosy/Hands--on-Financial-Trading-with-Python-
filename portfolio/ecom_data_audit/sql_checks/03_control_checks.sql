SET search_path TO ecom_audit;

-- 1) PO ordered vs received reconciliation by SKU
WITH ordered AS (
    SELECT pol.po_id, pol.sku_id, SUM(pol.ordered_qty) AS ordered_qty
    FROM purchase_order_line pol
    GROUP BY 1,2
), received AS (
    SELECT i.po_id, r.sku_id, SUM(r.received_qty) AS received_qty
    FROM receipt_line r
    JOIN inbound_shipment i ON i.inbound_id = r.inbound_id
    GROUP BY 1,2
)
SELECT
    o.po_id,
    o.sku_id,
    o.ordered_qty,
    COALESCE(r.received_qty,0) AS received_qty,
    COALESCE(r.received_qty,0) - o.ordered_qty AS qty_variance
FROM ordered o
LEFT JOIN received r
  ON r.po_id = o.po_id AND r.sku_id = o.sku_id
WHERE ABS(COALESCE(r.received_qty,0) - o.ordered_qty) > 0;

-- 2) Invalid sales behavior: shipped > ordered, returned > shipped
SELECT
    sol.sales_order_line_id,
    so.external_order_id,
    s.sku_code,
    sol.ordered_qty,
    sol.shipped_qty,
    sol.returned_qty
FROM sales_order_line sol
JOIN sales_order so ON so.sales_order_id = sol.sales_order_id
JOIN sku s ON s.sku_id = sol.sku_id
WHERE sol.shipped_qty > sol.ordered_qty
   OR sol.returned_qty > sol.shipped_qty;

-- 3) Landed cost sanity checks (negative duties/freight)
SELECT
    l.landed_component_id,
    i.inbound_ref,
    s.sku_code,
    l.component_type,
    l.amount_usd
FROM landed_cost_component l
JOIN inbound_shipment i ON i.inbound_id = l.inbound_id
JOIN sku s ON s.sku_id = l.sku_id
WHERE l.amount_usd < 0
   OR (l.component_type IN ('FREIGHT', 'DUTY', 'BROKER', 'INSURANCE') AND l.amount_usd = 0);

-- 4) Inventory ledger check: no movement should drive stock below zero (per SKU + warehouse)
WITH running AS (
    SELECT
        movement_id,
        sku_id,
        warehouse_id,
        movement_ts,
        qty_delta,
        SUM(qty_delta) OVER (
            PARTITION BY sku_id, warehouse_id
            ORDER BY movement_ts, movement_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_qty
    FROM inventory_movement
)
SELECT
    r.movement_id,
    s.sku_code,
    w.warehouse_code,
    r.movement_ts,
    r.qty_delta,
    r.running_qty
FROM running r
JOIN sku s ON s.sku_id = r.sku_id
JOIN warehouse w ON w.warehouse_id = r.warehouse_id
WHERE r.running_qty < 0;

-- 5) Traceability check: every movement ref should exist in source table where applicable
SELECT m.movement_id, m.ref_type, m.ref_id
FROM inventory_movement m
LEFT JOIN receipt_line r ON m.ref_type = 'RECEIPT_LINE' AND r.receipt_line_id::TEXT = m.ref_id
LEFT JOIN sales_order_line sol ON m.ref_type = 'ORDER_LINE' AND sol.sales_order_line_id::TEXT = m.ref_id
WHERE (m.ref_type = 'RECEIPT_LINE' AND r.receipt_line_id IS NULL)
   OR (m.ref_type = 'ORDER_LINE' AND sol.sales_order_line_id IS NULL);

-- 6) Recompute landed unit cost and compare with expected thresholds
WITH base AS (
    SELECT
        r.inbound_id,
        r.sku_id,
        SUM(r.received_qty - r.damaged_qty) AS net_receipt_qty
    FROM receipt_line r
    GROUP BY 1,2
),
exw AS (
    SELECT
        i.inbound_id,
        pol.sku_id,
        pol.unit_cost_exw
    FROM inbound_shipment i
    JOIN purchase_order_line pol ON pol.po_id = i.po_id
),
landed AS (
    SELECT inbound_id, sku_id, SUM(amount_usd) AS alloc_cost
    FROM landed_cost_component
    GROUP BY 1,2
)
SELECT
    b.inbound_id,
    s.sku_code,
    b.net_receipt_qty,
    e.unit_cost_exw,
    COALESCE(l.alloc_cost,0) AS alloc_cost,
    ROUND(((e.unit_cost_exw * b.net_receipt_qty) + COALESCE(l.alloc_cost,0)) / NULLIF(b.net_receipt_qty,0), 4) AS landed_unit_cost
FROM base b
JOIN exw e ON e.inbound_id = b.inbound_id AND e.sku_id = b.sku_id
JOIN sku s ON s.sku_id = b.sku_id
LEFT JOIN landed l ON l.inbound_id = b.inbound_id AND l.sku_id = b.sku_id
WHERE b.net_receipt_qty <= 0
   OR ROUND(((e.unit_cost_exw * b.net_receipt_qty) + COALESCE(l.alloc_cost,0)) / NULLIF(b.net_receipt_qty,0), 4) <= 0;
