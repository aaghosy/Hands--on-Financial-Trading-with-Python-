SET search_path TO ecom_audit;

-- Source batches
INSERT INTO source_batch (batch_id, source_system, extract_started_at, extract_finished_at, source_file_name, source_file_sha256, row_count, loaded_by)
VALUES
(1001, 'ERP',          '2026-03-01 00:00+00', '2026-03-01 00:10+00', 'po_export_20260301.csv',       'sha256_po_1001', 20, 'pipeline'),
(1002, 'WMS_CSV',      '2026-03-10 00:00+00', '2026-03-10 00:08+00', 'receipts_20260310.csv',        'sha256_rcv_1002', 30, 'pipeline'),
(1003, 'SHOPIFY_API',  '2026-03-15 00:00+00', '2026-03-15 00:05+00', 'shopify_orders_20260315.json', 'sha256_shp_1003', 40, 'pipeline'),
(1004, 'AMAZON_SP_API','2026-03-15 00:00+00', '2026-03-15 00:05+00', 'amazon_orders_20260315.json',  'sha256_amz_1004', 25, 'pipeline'),
(1005, 'LANDCOST',     '2026-03-16 00:00+00', '2026-03-16 00:03+00', 'landed_cost_20260316.csv',     'sha256_lc_1005', 12, 'pipeline');

INSERT INTO channel (channel_id, channel_code, channel_name) VALUES
(1, 'SHOPIFY', 'Shopify DTC'),
(2, 'AMAZON_US', 'Amazon US');

INSERT INTO warehouse (warehouse_id, warehouse_code, warehouse_name, country_code) VALUES
(1, 'US_3PL', 'US Third-Party Logistics', 'US'),
(2, 'CN_FG', 'China Finished Goods Warehouse', 'CN'),
(3, 'AMZ_FBA_US', 'Amazon FBA US', 'US');

INSERT INTO sku (sku_id, sku_code, product_name) VALUES
(101, 'SKU-A', 'Core Product A'),
(102, 'SKU-B', 'Core Product B'),
(103, 'SKU-C', 'Accessory C');

INSERT INTO purchase_order (po_id, po_number, supplier_name, order_date, currency_code, status, batch_id) VALUES
(5001, 'PO-2026-001', 'Shenzhen Alpha Factory', '2026-02-20', 'USD', 'PARTIAL', 1001),
(5002, 'PO-2026-002', 'Shenzhen Alpha Factory', '2026-02-25', 'USD', 'OPEN', 1001);

INSERT INTO purchase_order_line (po_line_id, po_id, sku_id, ordered_qty, unit_cost_exw) VALUES
(6001, 5001, 101, 1000, 8.50),
(6002, 5001, 102,  500, 6.20),
(6003, 5002, 103,  300, 2.80);

INSERT INTO inbound_shipment (inbound_id, po_id, inbound_ref, eta_date, receipt_date, destination_warehouse_id, status, batch_id) VALUES
(7001, 5001, 'INB-PO2026001-A', '2026-03-08', '2026-03-10', 1, 'RECEIVED', 1002),
(7002, 5002, 'INB-PO2026002-A', '2026-03-20', NULL,         1, 'IN_TRANSIT', 1002);

INSERT INTO receipt_line (receipt_line_id, inbound_id, sku_id, received_qty, damaged_qty, received_at, batch_id) VALUES
(8001, 7001, 101, 980, 5, '2026-03-10 10:00+00', 1002),
(8002, 7001, 102, 520, 0, '2026-03-10 10:00+00', 1002);  -- Intentional issue: received > ordered for SKU-B

INSERT INTO landed_cost_component (landed_component_id, inbound_id, sku_id, component_type, amount_usd, allocation_basis, batch_id) VALUES
(9001, 7001, 101, 'FREIGHT',   1500.00, 'UNITS', 1005),
(9002, 7001, 101, 'DUTY',       900.00, 'FOB_VALUE', 1005),
(9003, 7001, 102, 'FREIGHT',    850.00, 'UNITS', 1005),
(9004, 7001, 102, 'BROKER',      90.00, 'UNITS', 1005),
(9005, 7001, 102, 'DUTY',      -120.00, 'FOB_VALUE', 1005); -- Intentional issue: negative duty

INSERT INTO sales_order (sales_order_id, channel_id, external_order_id, order_created_at, order_status, ship_country_code, batch_id) VALUES
(10001, 1, 'SH-1001', '2026-03-12 14:00+00', 'SHIPPED', 'US', 1003),
(10002, 1, 'SH-1002', '2026-03-12 15:00+00', 'SHIPPED', 'US', 1003),
(10003, 2, 'AMZ-9001', '2026-03-12 16:00+00', 'SHIPPED', 'US', 1004);

INSERT INTO sales_order_line (sales_order_line_id, sales_order_id, sku_id, ordered_qty, shipped_qty, returned_qty, unit_price_usd, batch_id) VALUES
(11001, 10001, 101, 2, 2, 0, 24.99, 1003),
(11002, 10002, 102, 1, 1, 0, 19.99, 1003),
(11003, 10003, 101, 30, 30, 0, 21.49, 1004),
(11004, 10003, 103, 10, 12, 0, 9.99, 1004); -- Intentional issue: shipped > ordered

INSERT INTO inventory_movement (movement_id, movement_ts, sku_id, warehouse_id, movement_type, qty_delta, ref_type, ref_id, batch_id) VALUES
(12001, '2026-03-10 10:00+00', 101, 1, 'RECEIPT',      980, 'RECEIPT_LINE', '8001', 1002),
(12002, '2026-03-10 10:00+00', 102, 1, 'RECEIPT',      520, 'RECEIPT_LINE', '8002', 1002),
(12003, '2026-03-12 14:05+00', 101, 1, 'SALE',          -2, 'ORDER_LINE',   '11001', 1003),
(12004, '2026-03-12 15:05+00', 102, 1, 'SALE',          -1, 'ORDER_LINE',   '11002', 1003),
(12005, '2026-03-12 16:10+00', 101, 3, 'SALE',         -30, 'ORDER_LINE',   '11003', 1004), -- sold from FBA warehouse
(12006, '2026-03-12 16:11+00', 103, 3, 'SALE',         -12, 'ORDER_LINE',   '11004', 1004), -- no prior receipt in FBA
(12007, '2026-03-13 09:00+00', 101, 1, 'ADJUSTMENT',    -5, 'WMS_ADJ',      'ADJ-77', 1002);
