-- KPI QUERIES
-- Selecting database first
use iom;
-- Total Revenue from shipped or delivered orders
SELECT CONCAT('$ ', SUM(total_amount)) AS total_revenue
FROM orders
WHERE order_status IN ('Shipped','Delivered');

-- Top 10 customers by spending
SELECT c.customer_id, c.full_name, c.phone, CONCAT('$ ', SUM(o.total_amount)) AS total_spent
FROM customer c
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id
ORDER BY total_spent DESC
LIMIT 10;

-- Best-selling 5 products by quantity
SELECT p.product_id, p.product_name, SUM(oi.quantity) AS total_sold
FROM order_item oi
JOIN product p ON oi.product_id = p.product_id
GROUP BY oi.product_id
ORDER BY total_sold DESC
LIMIT 5;

-- Monthly sales trend
SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, CONCAT("$ ", SUM(total_amount))AS revenue
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
  RANK() OVER(PARTITION BY p.category ORDER BY SUM(oi.quantity * oi.unit_price_at_purchase) DESC) AS category_rank
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

CREATE VIEW CustomerSalesSummary AS
SELECT 
    c.customer_id,
    c.full_name,
    c.email,
    SUM(oi.quantity * oi.unit_price_at_purchase) AS total_spent,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM customer c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN order_item oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.full_name, c.email;

SELECT * from customersalessummary
ORDER BY total_spent DESC LIMIT 15;

-- DELIMITER $$

-- CREATE PROCEDURE ProcessNewOrder(
--     IN p_customer_id INT,
--     IN p_product_id INT,
--     IN p_quantity INT
-- )
-- BEGIN
--     DECLARE v_stock INT;
--     DECLARE v_price DECIMAL(10,2);
--     DECLARE v_order_id INT;
    
--     -- Start transaction
--     START TRANSACTION;
    
--     -- Check stock and price from Inventory
--     SELECT stock_quantity, unit_price
--     INTO v_stock, v_price
--     FROM inventory
--     WHERE product_id = p_product_id
--     FOR UPDATE;  -- lock row
    
--     -- Validate stock
--     IF v_stock < p_quantity THEN
--         ROLLBACK;
--         SELECT 'Error: Not enough stock available' AS message;
--         LEAVE BEGIN;
--     END IF;

--     -- Create Order
--     INSERT INTO orders (customer_id, order_date, status)
--     VALUES (p_customer_id, NOW(), 'Pending');

--     SET v_order_id = LAST_INSERT_ID();

--     -- Insert Order Item
--     INSERT INTO order_items (order_id, product_id, quantity, unit_price)
--     VALUES (v_order_id, p_product_id, p_quantity, v_price);

--     -- Reduce stock
--     UPDATE inventory
--     SET stock_quantity = stock_quantity - p_quantity
--     WHERE product_id = p_product_id;

--     -- Commit
--     COMMIT;

--     SELECT 'Success: Order processed successfully' AS message,
--            v_order_id AS new_order_id;

-- END$$

-- DELIMITER ;
