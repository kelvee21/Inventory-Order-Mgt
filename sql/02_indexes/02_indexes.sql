-- ============================================================
-- sql/02_indexes/02_indexes.sql
-- Additional indexes that are not needed by foreign keys.
--
-- MySQL creates an index automatically for an unindexed FK
-- column. All FK-supporting indexes are declared inline in
-- 01_schema.sql so this file does not create duplicates.
-- ============================================================

USE inventory_order_mgt;

-- Date-range and daily/monthly sales reports.
CREATE INDEX idx_orders_order_date
  ON orders (order_date);

SELECT 'Additional indexes created.' AS message;
