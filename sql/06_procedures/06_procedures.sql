-- ============================================================
-- sql/06_procedures/06_procedures.sql
-- place_order           - create an order with one or more JSON items
-- restock_low_products  - top up every product below its reorder level
--
-- Both procedures leave transaction control to the caller.
-- Use:
--   START TRANSACTION;
--   CALL ...;
--   COMMIT;
-- and ROLLBACK on error.
-- ============================================================

USE inventory_order_mgt;

DROP PROCEDURE IF EXISTS place_order;

DELIMITER //
CREATE PROCEDURE place_order(
  IN  p_customer_id INT,
  IN  p_items JSON,
  IN  p_order_date DATE,
  OUT p_order_id INT
)
BEGIN
  DECLARE v_count INT DEFAULT 0;
  DECLARE v_bad INT DEFAULT 0;
  DECLARE v_msg VARCHAR(255);

  IF p_customer_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Customer id is required';
  END IF;

  IF p_items IS NULL
     OR JSON_VALID(p_items) = 0
     OR JSON_TYPE(p_items) <> 'ARRAY'
     OR JSON_LENGTH(p_items) = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Items must be a non-empty JSON array';
  END IF;

  -- Every item must carry a product id and a positive quantity.
  SELECT COUNT(*)
    INTO v_bad
    FROM JSON_TABLE(
      p_items,
      '$[*]' COLUMNS (
        product_id INT PATH '$.product_id',
        quantity   INT PATH '$.quantity'
      )
    ) AS jt
   WHERE jt.product_id IS NULL
      OR jt.quantity IS NULL
      OR jt.quantity <= 0;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Each item needs a product_id and a quantity greater than zero';
  END IF;

  -- One line per product: increase the quantity instead of repeating it.
  SELECT COUNT(*)
    INTO v_bad
    FROM (
      SELECT jt.product_id
        FROM JSON_TABLE(
          p_items,
          '$[*]' COLUMNS (
            product_id INT PATH '$.product_id'
          )
        ) AS jt
       GROUP BY jt.product_id
      HAVING COUNT(*) > 1
    ) AS duplicates;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Duplicate product in order items';
  END IF;

  SELECT COUNT(*)
    INTO v_count
    FROM customers
   WHERE customer_id = p_customer_id;

  IF v_count = 0 THEN
    SET v_msg = CONCAT('Unknown customer: ', p_customer_id);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  SELECT COUNT(*)
    INTO v_bad
    FROM JSON_TABLE(
      p_items,
      '$[*]' COLUMNS (
        product_id INT PATH '$.product_id'
      )
    ) AS jt
    LEFT JOIN products AS p
      ON p.product_id = jt.product_id
   WHERE p.product_id IS NULL;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'One or more products do not exist';
  END IF;

  -- Friendly pre-check. The AFTER trigger repeats the check under
  -- a row lock, which is the authoritative concurrency guard.
  SELECT COUNT(*)
    INTO v_bad
    FROM JSON_TABLE(
      p_items,
      '$[*]' COLUMNS (
        product_id INT PATH '$.product_id',
        quantity   INT PATH '$.quantity'
      )
    ) AS jt
    JOIN products AS p
      ON p.product_id = jt.product_id
   WHERE p.stock_quantity < jt.quantity;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Insufficient stock for one or more products';
  END IF;

  INSERT INTO orders (customer_id, order_date)
  VALUES (p_customer_id, COALESCE(p_order_date, CURRENT_DATE));

  SET p_order_id = LAST_INSERT_ID();

  -- Product-id order keeps lock acquisition consistent when
  -- concurrent orders contain the same products.
  INSERT INTO order_items (order_id, product_id, quantity)
  SELECT
    p_order_id,
    jt.product_id,
    jt.quantity
  FROM JSON_TABLE(
    p_items,
    '$[*]' COLUMNS (
      product_id INT PATH '$.product_id',
      quantity   INT PATH '$.quantity'
    )
  ) AS jt
  ORDER BY jt.product_id;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS restock_low_products;

DELIMITER //
CREATE PROCEDURE restock_low_products()
BEGIN
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_product_id INT;
  DECLARE v_stock INT;
  DECLARE v_reorder INT;
  DECLARE v_add_qty INT;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

  WHILE v_done = 0 DO
    SET v_product_id = NULL;

    SELECT
      product_id,
      stock_quantity,
      reorder_level
    INTO
      v_product_id,
      v_stock,
      v_reorder
    FROM products
    WHERE stock_quantity < reorder_level
    ORDER BY product_id
    LIMIT 1
    FOR UPDATE;

    IF v_product_id IS NULL THEN
      SET v_done = 1;
    ELSE
      SET v_add_qty = (v_reorder * 2) - v_stock;

      UPDATE products
         SET stock_quantity = stock_quantity + v_add_qty
       WHERE product_id = v_product_id;

      INSERT INTO inventory_logs
        (product_id, change_quantity, reason)
      VALUES
        (v_product_id, v_add_qty, 'restock');
    END IF;
  END WHILE;
END //
DELIMITER ;

SELECT 'Procedures created.' AS message;
