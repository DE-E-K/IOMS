-- ============================================
-- PROJECT VERIFICATION SCRIPT
-- ============================================
-- Usage: Execute this script after setting up the database.

USE IOMS;

SELECT '1. Checking Tables Existence' AS 'Step';
SHOW TABLES;

SELECT '2. Checking Sample Data' AS 'Step';
SELECT COUNT(*) AS customer_count FROM customer;
SELECT COUNT(*) AS product_count FROM product;
SELECT COUNT(*) AS inventory_count FROM inventory;

-- 3. TEST ORDER PLACEMENT (Success Scenario)
SELECT '3. Testing PlaceOrder Procedure (Success)' AS 'Step';
SET @order_id = 0;
SET @order_number = '';
SET @status = '';
SET @msg = '';

-- Order: Customer 1 orders 1x Smartphone X (Prod 1) and 2x T-Shirt (Prod 5)
CALL PlaceOrder(
    1,                               -- Customer ID
    '[{"product_id": 1, "quantity": 1}, {"product_id": 5, "quantity": 2}]', -- Items
    'Credit Card',                   -- Payment Method
    'STANDARD',                      -- Shipping Method
    '{"street": "123 Test St", "city": "Kigali"}', -- Address
    'WELCOME10',                     -- Promo Code
    @order_id, @order_number, @status, @msg -- OUT Params
);

SELECT @status AS Status, @msg AS Message, @order_number AS OrderNum;

-- Verify Inventory Deduction
SELECT '4. Verifying Inventory Deduction' AS 'Step';
SELECT p.product_name, i.quantity_on_hand, i.quantity_reserved 
FROM inventory i JOIN product p ON i.product_id = p.product_id
WHERE i.product_id IN (1, 5);

-- Verify Log
SELECT '5. Verifying Inventory Log' AS 'Step';
SELECT * FROM inventory_log WHERE reference_id = @order_id ORDER BY log_id DESC LIMIT 5;

-- 4. TEST ORDER PLACEMENT (Failure Scenario - Low Stock)
SELECT '6. Testing PlaceOrder Procedure (Failure - Excessive Quantity)' AS 'Step';
-- Try to order 1000 Smartphones (Stock is ~50)
CALL PlaceOrder(
    1,
    '[{"product_id": 1, "quantity": 1000}]', 
    'Credit Card', 'STANDARD', '{}', NULL,
    @fail_id, @fail_num, @fail_status, @fail_msg
);

SELECT @fail_status AS Status, @fail_msg AS Message;

-- 5. VERIFY VIEWS
SELECT '7. Verifying CustomerSalesSummary View' AS 'Step';
SELECT * FROM CustomerSalesSummary WHERE customer_id = 1;

-- 6. VERIFY KPI QUERIES
SELECT '8. Testing Best Selling Products Query' AS 'Step';
SELECT 
    p.product_name, 
    SUM(oi.quantity) AS total_sold
FROM order_item oi
JOIN product p ON oi.product_id = p.product_id
JOIN orders o ON oi.order_id = o.order_id
GROUP BY p.product_id, p.product_name
ORDER BY total_sold DESC 
LIMIT 5;

SELECT 'VERIFICATION COMPLETE' AS 'Status';
