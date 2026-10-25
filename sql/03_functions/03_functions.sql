-- ============================================================
-- sql/03_functions/03_functions.sql
-- Deterministic business rules kept in one place.
-- ============================================================

USE inventory_order_mgt;

DROP FUNCTION IF EXISTS customer_tier;

DELIMITER //
CREATE FUNCTION customer_tier(p_spend DECIMAL(12,2))
RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
  RETURN CASE
    WHEN p_spend >= 500 THEN 'Gold'
    WHEN p_spend >= 200 THEN 'Silver'
    ELSE 'Bronze'
  END;
END //
DELIMITER ;

DROP FUNCTION IF EXISTS bulk_discount_rate;

DELIMITER //
CREATE FUNCTION bulk_discount_rate(p_quantity INT)
RETURNS DECIMAL(4,2)
DETERMINISTIC
NO SQL
BEGIN
  RETURN CASE
    WHEN p_quantity >= 10 THEN 0.10
    WHEN p_quantity >= 5  THEN 0.05
    ELSE 0.00
  END;
END //
DELIMITER ;

SELECT 'Functions created.' AS message;
