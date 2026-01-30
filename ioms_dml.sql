-- Active: 1767084789057@@127.0.0.1@3306@iom
-- KPI QUERIES
-- Selecting database first
use iom;
-- Total Revenue from shipped or delivered orders
SELECT CONCAT('$ ', COALESCE(SUM(total_amount), 0)) AS total_revenue
FROM orders
WHERE order_status IN ('Shipped','Delivered');

-- Top 10 customers by spending
SELECT c.customer_id, c.full_name, c.phone, CONCAT('$ ', COALESCE(SUM(o.total_amount), 0)) AS total_spent
FROM customer c
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id
ORDER BY total_spent DESC
LIMIT 10;

-- Best-selling 5 products by quantity
SELECT p.product_id, p.product_name, COALESCE(SUM(oi.quantity), 0) AS total_sold
FROM order_item oi
JOIN product p ON oi.product_id = p.product_id
GROUP BY oi.product_id
ORDER BY total_sold DESC
LIMIT 5;

-- Monthly sales trend
SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, CONCAT("$ ", COALESCE(SUM(total_amount), 0))AS revenue
FROM orders
WHERE order_status IN ('Shipped','Delivered')
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;

-- WINDOW FUNCTION ANALYTICS
-- Rank products by sales within category
SELECT
  p.category,
  p.product_name,
  SUM(oi.quantity * oi.unit_price_at_purchase) AS revenue,
  RANK() OVER(PARTITION BY p.category ORDER BY COALESCE(SUM(oi.quantity * oi.unit_price_at_purchase), 0) DESC) AS category_rank
FROM order_item oi
JOIN product p ON oi.product_id = p.product_id
GROUP BY p.product_id;

-- Customer order frequency (previous order date and current order)
SELECT 
    c.customer_id,
    c.full_name,
    o.order_id,
    o.order_date AS current_order_date,
    LAG(o.order_date, 1) OVER (
        PARTITION BY c.customer_id 
        ORDER BY o.order_date
    ) AS previous_order_date
FROM customer c
JOIN orders o ON c.customer_id = o.customer_id
ORDER BY c.customer_id, o.order_date;

SELECT * FROM customer;
DROP VIEW IF EXISTS CustomerSalesSummary;
CREATE VIEW CustomerSalesSummary AS
SELECT 
    c.customer_id,
    c.full_name,
    c.email,
    COALESCE(SUM(oi.quantity * oi.unit_price_at_purchase), 0) AS total_spent,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM customer c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN order_item oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.full_name, c.email;

SELECT * from customersalessummary
ORDER BY total_spent DESC LIMIT 15;

DELIMITER $$

DROP PROCEDURE IF EXISTS PlaceOrder$$

CREATE PROCEDURE PlaceOrder(
    IN p_customer_id INT,
    IN p_order_items JSON,
    OUT p_order_id INT
)
proc: BEGIN
    DECLARE v_customer_exists INT;
    DECLARE v_order_id INT;
    DECLARE v_total_order_amount DECIMAL(10,2) DEFAULT 0;
    DECLARE v_item_count INT;
    DECLARE v_err_msg VARCHAR(600);

    -- Use an exit handler for robust cleanup and transaction management
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Ensure OUT parameter reflects failure
        SET p_order_id = NULL;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_items;
        RESIGNAL; -- Propagate the error
    END;

    -- Ensure clean slate for temporary table
    DROP TEMPORARY TABLE IF EXISTS tmp_items;

    -- 1. Validate Customer
    SELECT COUNT(*) INTO v_customer_exists FROM customer WHERE customer_id = p_customer_id;
    IF v_customer_exists = 0 THEN
        SET v_err_msg = CONCAT('Error: Customer ID ', p_customer_id, ' does not exist.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err_msg;
    END IF;

    -- 2. Parse JSON into a temporary aggregated items table
    CREATE TEMPORARY TABLE tmp_items (
        product_id INT PRIMARY KEY,
        quantity INT NOT NULL
    ) ENGINE=MEMORY;

    INSERT INTO tmp_items (product_id, quantity)
    SELECT product_id, SUM(quantity)
    FROM JSON_TABLE(p_order_items, '$[*]'
        COLUMNS (
            product_id INT PATH '$.product_id',
            quantity INT PATH '$.quantity'
        )
    ) AS jt
    WHERE jt.product_id IS NOT NULL AND jt.quantity > 0 -- Add basic validation
    GROUP BY product_id;

    SET v_item_count = (SELECT COUNT(*) FROM tmp_items);
    IF v_item_count = 0 THEN
        DROP TEMPORARY TABLE tmp_items;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No valid order items provided. Items may be missing product_id or have a quantity of zero.';
    END IF;

    -- 3. Start Transaction and lock inventory rows to perform validations safely
    START TRANSACTION;

    -- Lock inventory rows in a consistent order to prevent deadlocks and allow accurate checks
    SELECT i.product_id
    FROM inventory i
    JOIN tmp_items t ON i.product_id = t.product_id
    ORDER BY i.product_id -- CRITICAL: Ensures consistent lock acquisition order
    FOR UPDATE;

    -- 4. Validate all products exist in inventory (bulk check)
    BEGIN
        DECLARE v_missing_product INT;
        SELECT t.product_id INTO v_missing_product
        FROM tmp_items t
        LEFT JOIN inventory i ON i.product_id = t.product_id
        WHERE i.product_id IS NULL
        LIMIT 1;
        
        IF v_missing_product IS NOT NULL THEN
            -- The EXIT HANDLER will automatically ROLLBACK
            SET v_err_msg = CONCAT('Error: Product ID ', v_missing_product, ' not found in inventory.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = SUBSTRING(v_err_msg, 1, 128);
        END IF;
    END;

    -- 5. Validate stock levels in bulk
    BEGIN
        DECLARE v_insufficient_product INT;
        DECLARE v_requested_qty INT;
        DECLARE v_available_qty INT;
        
        SELECT t.product_id, t.quantity, i.quantity_on_hand
        INTO v_insufficient_product, v_requested_qty, v_available_qty
        FROM tmp_items t
        JOIN inventory i ON i.product_id = t.product_id
        WHERE i.quantity_on_hand < t.quantity
        LIMIT 1;
        
        IF v_insufficient_product IS NOT NULL THEN
            -- The EXIT HANDLER will automatically ROLLBACK
            SET v_err_msg = CONCAT(
                'Error: Insufficient stock for Product ID ', v_insufficient_product, 
                '. Requested: ', v_requested_qty,
                ', Available: ', v_available_qty, '.'
            );
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = SUBSTRING(v_err_msg, 1, 128);
        END IF;
    END;

    -- 6. Create order header AFTER successful validations to avoid transient uncommitted headers
    INSERT INTO orders (customer_id, order_date, total_amount, order_status)
    VALUES (p_customer_id, NOW(), 0, 'Pending');
    SET v_order_id = LAST_INSERT_ID();
    -- Note: DO NOT set p_order_id yet. Will set after successful commit.

    -- 7. Insert order items in bulk
    INSERT INTO order_item (order_id, product_id, quantity, unit_price_at_purchase)
    SELECT v_order_id, t.product_id, t.quantity, p.price
    FROM tmp_items t
    JOIN product p ON p.product_id = t.product_id;

    -- 8. Update inventory in bulk (already locked)
    UPDATE inventory i
    JOIN tmp_items t ON i.product_id = t.product_id
    SET i.quantity_on_hand = i.quantity_on_hand - t.quantity;

    -- 9. Log inventory movements in bulk
    INSERT INTO inventory_log (product_id, quantity_change, transaction_type, reference_id)
    SELECT product_id, -quantity, 'ORDER', v_order_id FROM tmp_items;

    -- 10. Compute total and update order
    SELECT SUM(t.quantity * p.price) INTO v_total_order_amount
    FROM tmp_items t
    JOIN product p ON p.product_id = t.product_id;

    UPDATE orders
    SET total_amount = COALESCE(v_total_order_amount, 0)
    WHERE order_id = v_order_id;

    -- 11. Commit and cleanup
    COMMIT;
    DROP TEMPORARY TABLE tmp_items;

    -- Set OUT parameter only after successful commit
    SET p_order_id = v_order_id;

    SELECT 'Success' AS status, v_order_id AS order_id;

END proc$$

DELIMITER ;

-- Test Procedure
-- CALL PlaceOrder(1, '[{"product_id": 5, "quantity": 2}, {"product_id": 2, "quantity": 1}]', @new_order_id);
-- SELECT @new_order_id;
