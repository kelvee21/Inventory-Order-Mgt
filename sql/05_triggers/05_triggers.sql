-- ============================================================
-- sql/05_triggers/05_triggers.sql
-- Order-line automation:
--   * snapshot the catalogue price
--   * apply the quantity discount
--   * calculate the line total
--   * deduct stock, write an inventory log and update the order total
--
-- The BEFORE trigger locks the product row before reading its
-- price. The AFTER trigger locks the same row again and performs
-- the authoritative stock check.
-- ============================================================

USE inventory_order_mgt;

DROP TRIGGER IF EXISTS trg_order_items_before_insert;

DELIMITER //
CREATE TRIGGER trg_order_items_before_insert
BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
  DECLARE v_price DECIMAL(10,2);
  DECLARE v_msg VARCHAR(255);
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_price = NULL;

  IF NEW.quantity IS NULL OR NEW.quantity <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Order quantity must be greater than zero';
  END IF;

  SELECT price
    INTO v_price
    FROM products
   WHERE product_id = NEW.product_id
   FOR UPDATE;

  IF v_price IS NULL THEN
    SET v_msg = CONCAT('Unknown product: ', NEW.product_id);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  -- Callers cannot inject a different price or discount.
  SET NEW.unit_price = v_price;
  SET NEW.discount_rate = bulk_discount_rate(NEW.quantity);
  SET NEW.line_total = ROUND(
    NEW.quantity * v_price * (1 - NEW.discount_rate),
    2
  );
END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_order_items_after_insert;

DELIMITER //
CREATE TRIGGER trg_order_items_after_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
  DECLARE v_stock INT;
  DECLARE v_msg VARCHAR(255);
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_stock = NULL;

  SELECT stock_quantity
    INTO v_stock
    FROM products
   WHERE product_id = NEW.product_id
   FOR UPDATE;

  IF v_stock IS NULL THEN
    SET v_msg = CONCAT('Unknown product: ', NEW.product_id);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  IF v_stock < NEW.quantity THEN
    SET v_msg = CONCAT(
      'Not enough stock for product ', NEW.product_id,
      ' (have ', v_stock, ', need ', NEW.quantity, ')'
    );
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  UPDATE products
     SET stock_quantity = stock_quantity - NEW.quantity
   WHERE product_id = NEW.product_id;

  INSERT INTO inventory_logs
    (product_id, order_id, change_quantity, reason)
  VALUES
    (NEW.product_id, NEW.order_id, -NEW.quantity, 'order');

  UPDATE orders
     SET total_amount = total_amount + NEW.line_total
   WHERE order_id = NEW.order_id;
END //
DELIMITER ;

SELECT 'Triggers created.' AS message;
