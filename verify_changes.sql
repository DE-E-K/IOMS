-- VERIFICATION SCRIPT
-- Run this script to verify the integrity and logic of the new IOMS implementation.

USE IOM;

-- 1. SETUP TEST DATA
-- Create a test user if not exists (although sample data has them)
INSERT IGNORE INTO customer(full_name, email, shipping_address) 
VALUES ('Test User', 'test@test.com', '123 Test Lane');

SET @test_customer_id = (SELECT customer_id FROM customer WHERE email = 'test@test.com');

-- Ensure dummy products exist with known stock
-- Product 1001: High stock
INSERT INTO product(product_id, product_name, category, price) 
VALUES (1001, 'High Stock Item', 'Electronics', 100) 
ON DUPLICATE KEY UPDATE product_name=product_name;

INSERT INTO inventory(product_id, quantity_on_hand, reorder_point, reorder_quantity) 
VALUES (1001, 100, 10, 50) 
ON DUPLICATE KEY UPDATE quantity_on_hand=100;

-- Product 1002: Low stock (1 item left)
INSERT INTO product(product_id, product_name, category, price) 
VALUES (1002, 'Low Stock Item', 'Electronics', 100) 
ON DUPLICATE KEY UPDATE product_name=product_name;

INSERT INTO inventory(product_id, quantity_on_hand, reorder_point, reorder_quantity) 
VALUES (1002, 1, 10, 50) 
ON DUPLICATE KEY UPDATE quantity_on_hand=1;

-- 2. TEST CASE: SUCCESSFUL MULTI-ITEM ORDER
-- Order 1x High Stock Item and 1x Low Stock Item
CALL PlaceOrder(@test_customer_id, '[{"product_id": 1001, "quantity": 1}, {"product_id": 1002, "quantity": 1}]', @order_id_1);

SELECT 'Order 1 Result:' as info, @order_id_1 as order_id;

-- VERIFY RESULTS
SELECT 'Inventory Check (Should be 99 and 0)' as info;
SELECT * FROM inventory WHERE product_id IN (1001, 1002);

SELECT 'Inventory Log Check (Should have 2 entries for this order)' as info;
SELECT * FROM inventory_log WHERE reference_id = @order_id_1;

SELECT 'Order Total Check (Should be 200)' as info;
SELECT * FROM orders WHERE order_id = @order_id_1;


-- 3. TEST CASE: INSUFFICIENT STOCK
-- Try to order Low Stock Item again (Stock is now 0)
SET @order_id_2 = NULL;
CALL PlaceOrder(@test_customer_id, '[{"product_id": 1002, "quantity": 1}]', @order_id_2);

SELECT 'Order 2 Result (Should fail/be null):' as info, @order_id_2 as order_id;


-- 4. TEST CASE: INVALID CUSTOMER
CALL PlaceOrder(999999, '[{"product_id": 1001, "quantity": 1}]', @order_id_3);


-- 5. TEST CASE: FK CONSTRAINT (SAFE DELETE)
-- Try to delete the customer who just placed an order. Should FAIL.
DELETE FROM customer WHERE customer_id = @test_customer_id;
SELECT 'Customer Delete Check (Should expect error above)' as info;
