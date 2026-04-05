-- Ecommerce operations audit schema for Shopify + Amazon + 3PL + purchasing/landed cost.
-- Focus: traceability, reconciliation, controls, and auditability.

CREATE SCHEMA IF NOT EXISTS ecom_audit;
SET search_path TO ecom_audit;

-- Reference dimensions
CREATE TABLE channel (
    channel_id        SMALLSERIAL PRIMARY KEY,
    channel_code      TEXT NOT NULL UNIQUE,   -- SHOPIFY, AMAZON_US, AMAZON_CA
    channel_name      TEXT NOT NULL
);

CREATE TABLE warehouse (
    warehouse_id      SMALLSERIAL PRIMARY KEY,
    warehouse_code    TEXT NOT NULL UNIQUE,   -- US_3PL, CN_BOND, AMZ_FBA_US
    warehouse_name    TEXT NOT NULL,
    country_code      CHAR(2) NOT NULL
);

CREATE TABLE sku (
    sku_id            SERIAL PRIMARY KEY,
    sku_code          TEXT NOT NULL UNIQUE,
    product_name      TEXT NOT NULL,
    uom               TEXT NOT NULL DEFAULT 'EA',
    active_flag       BOOLEAN NOT NULL DEFAULT TRUE
);

-- Raw source loads with hash for immutable source trace
CREATE TABLE source_batch (
    batch_id          BIGSERIAL PRIMARY KEY,
    source_system     TEXT NOT NULL,          -- SHOPIFY_API, AMAZON_SP_API, WMS_CSV, ERP
    extract_started_at TIMESTAMPTZ NOT NULL,
    extract_finished_at TIMESTAMPTZ NOT NULL,
    source_file_name  TEXT,
    source_file_sha256 TEXT,
    row_count         INTEGER,
    loaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    loaded_by         TEXT NOT NULL
);

-- Purchasing
CREATE TABLE purchase_order (
    po_id             BIGSERIAL PRIMARY KEY,
    po_number         TEXT NOT NULL UNIQUE,
    supplier_name     TEXT NOT NULL,
    order_date        DATE NOT NULL,
    currency_code     CHAR(3) NOT NULL,
    status            TEXT NOT NULL,          -- OPEN, PARTIAL, RECEIVED, CLOSED
    batch_id          BIGINT NOT NULL REFERENCES source_batch(batch_id)
);

CREATE TABLE purchase_order_line (
    po_line_id        BIGSERIAL PRIMARY KEY,
    po_id             BIGINT NOT NULL REFERENCES purchase_order(po_id),
    sku_id            INTEGER NOT NULL REFERENCES sku(sku_id),
    ordered_qty       NUMERIC(14,2) NOT NULL CHECK (ordered_qty >= 0),
    unit_cost_exw     NUMERIC(14,4) NOT NULL CHECK (unit_cost_exw >= 0),
    UNIQUE (po_id, sku_id)
);

CREATE TABLE inbound_shipment (
    inbound_id        BIGSERIAL PRIMARY KEY,
    po_id             BIGINT NOT NULL REFERENCES purchase_order(po_id),
    inbound_ref       TEXT NOT NULL UNIQUE,
    eta_date          DATE,
    receipt_date      DATE,
    destination_warehouse_id SMALLINT NOT NULL REFERENCES warehouse(warehouse_id),
    status            TEXT NOT NULL,          -- IN_TRANSIT, RECEIVED, CLOSED
    batch_id          BIGINT NOT NULL REFERENCES source_batch(batch_id)
);

CREATE TABLE receipt_line (
    receipt_line_id   BIGSERIAL PRIMARY KEY,
    inbound_id        BIGINT NOT NULL REFERENCES inbound_shipment(inbound_id),
    sku_id            INTEGER NOT NULL REFERENCES sku(sku_id),
    received_qty      NUMERIC(14,2) NOT NULL CHECK (received_qty >= 0),
    damaged_qty       NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (damaged_qty >= 0),
    received_at       TIMESTAMPTZ NOT NULL,
    batch_id          BIGINT NOT NULL REFERENCES source_batch(batch_id)
);

-- Landed cost components allocated at inbound-shipment + sku granularity
CREATE TABLE landed_cost_component (
    landed_component_id BIGSERIAL PRIMARY KEY,
    inbound_id        BIGINT NOT NULL REFERENCES inbound_shipment(inbound_id),
    sku_id            INTEGER NOT NULL REFERENCES sku(sku_id),
    component_type    TEXT NOT NULL,          -- FREIGHT, DUTY, BROKER, INSURANCE, OTHER
    amount_usd        NUMERIC(14,4) NOT NULL,
    allocation_basis  TEXT NOT NULL,          -- UNITS, WEIGHT_KG, FOB_VALUE
    batch_id          BIGINT NOT NULL REFERENCES source_batch(batch_id)
);

-- Inventory ledger (event-sourced)
CREATE TABLE inventory_movement (
    movement_id       BIGSERIAL PRIMARY KEY,
    movement_ts       TIMESTAMPTZ NOT NULL,
    sku_id            INTEGER NOT NULL REFERENCES sku(sku_id),
    warehouse_id      SMALLINT NOT NULL REFERENCES warehouse(warehouse_id),
    movement_type     TEXT NOT NULL,          -- RECEIPT, SALE, ADJUSTMENT, TRANSFER_IN, TRANSFER_OUT, RETURN
    qty_delta         NUMERIC(14,2) NOT NULL,
    ref_type          TEXT NOT NULL,          -- RECEIPT_LINE, ORDER_LINE, WMS_ADJ, TRANSFER
    ref_id            TEXT NOT NULL,
    batch_id          BIGINT NOT NULL REFERENCES source_batch(batch_id)
);

-- Sales (normalized from Shopify and Amazon)
CREATE TABLE sales_order (
    sales_order_id    BIGSERIAL PRIMARY KEY,
    channel_id        SMALLINT NOT NULL REFERENCES channel(channel_id),
    external_order_id TEXT NOT NULL,
    order_created_at  TIMESTAMPTZ NOT NULL,
    order_status      TEXT NOT NULL,          -- OPEN, PARTIAL, SHIPPED, CANCELLED, REFUNDED
    ship_country_code CHAR(2),
    batch_id          BIGINT NOT NULL REFERENCES source_batch(batch_id),
    UNIQUE (channel_id, external_order_id)
);

CREATE TABLE sales_order_line (
    sales_order_line_id BIGSERIAL PRIMARY KEY,
    sales_order_id    BIGINT NOT NULL REFERENCES sales_order(sales_order_id),
    sku_id            INTEGER NOT NULL REFERENCES sku(sku_id),
    ordered_qty       NUMERIC(14,2) NOT NULL CHECK (ordered_qty >= 0),
    shipped_qty       NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (shipped_qty >= 0),
    returned_qty      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (returned_qty >= 0),
    unit_price_usd    NUMERIC(14,4) NOT NULL,
    batch_id          BIGINT NOT NULL REFERENCES source_batch(batch_id)
);

-- Metric lineage: each computed metric points to originating SQL + batch
CREATE TABLE metric_run (
    metric_run_id     BIGSERIAL PRIMARY KEY,
    metric_name       TEXT NOT NULL,
    run_started_at    TIMESTAMPTZ NOT NULL,
    run_finished_at   TIMESTAMPTZ NOT NULL,
    sql_version       TEXT NOT NULL,
    code_version      TEXT NOT NULL,
    input_batch_min   BIGINT NOT NULL,
    input_batch_max   BIGINT NOT NULL,
    row_count         INTEGER NOT NULL,
    run_status        TEXT NOT NULL           -- SUCCESS, FAILED
);

CREATE INDEX idx_inventory_movement_sku_wh_ts
ON inventory_movement (sku_id, warehouse_id, movement_ts);

CREATE INDEX idx_sales_order_created
ON sales_order (order_created_at);

CREATE INDEX idx_receipt_line_inbound_sku
ON receipt_line (inbound_id, sku_id);
