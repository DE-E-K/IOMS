-- SAMPLE DATA POPULATION (Enhanced)
-- Populates core tables with realistic data for testing

-- 1. CATEGORIES
INSERT INTO product_category (category_name, description) VALUES 
('Electronics', 'Gadgets, computers, and accessories'),
('Apparel', 'Clothing, shoes, and wearables'),
('Books', 'Technical and non-fiction books'),
('Home & Garden', 'Furniture, decor, and tools');

-- 2. PRODUCTS
INSERT INTO product (product_name, category_id, sku, price, cost_price) VALUES
-- Electronics
('Smartphone X', 1, 'ELEC-PH-001', 500.00, 350.00),
('Laptop Pro 15', 1, 'ELEC-LP-001', 1200.00, 900.00),
('Wireless Headphones', 1, 'ELEC-AU-001', 150.00, 80.00),
('Monitor 27"', 1, 'ELEC-MN-001', 300.00, 200.00),
-- Apparel
('T-Shirt Classic', 2, 'APP-TS-001', 20.00, 5.00),
('Jeans Regular', 2, 'APP-JN-001', 40.00, 15.00),
('Running Shoes', 2, 'APP-SH-001', 85.00, 40.00),
-- Books
('Python Programming', 3, 'BK-CS-001', 45.00, 20.00),
('Data Science Guide', 3, 'BK-CS-002', 55.00, 25.00);

-- 3. INVENTORY (Initial Stock)
INSERT INTO inventory (product_id, quantity_on_hand, reorder_point, reorder_quantity) VALUES
(1, 50, 10, 20),
(2, 20, 5, 10),
(3, 100, 20, 50),
(4, 30, 8, 15),
(5, 200, 30, 100),
(6, 80, 20, 40),
(7, 60, 15, 30),
(8, 40, 10, 20),
(9, 35, 10, 20);

-- 4. SUPPLIERS
INSERT INTO suppliers (supplier_name, contact_email) VALUES 
('Tech Global Inc', 'sales@techglobal.com'),
('Fashion Wholesalers', 'orders@fashionwhole.com'),
('Book Publishers Ltd', 'distrib@books.com');

-- 5. PROMOTIONS
INSERT INTO promotions (promotion_code, promotion_name, promotion_type, discount_value, minimum_order_amount, valid_from, valid_to) VALUES
('WELCOME10', 'Welcome Discount', 'Percentage', 10.00, 0.00, NOW(), DATE_ADD(NOW(), INTERVAL 1 YEAR)),
('FREESHIP', 'Free Shipping over $100', 'Free Shipping', 0.00, 100.00, NOW(), DATE_ADD(NOW(), INTERVAL 1 YEAR)),
('SAVE50', 'Save $50 on Big Orders', 'Fixed Amount', 50.00, 500.00, NOW(), DATE_ADD(NOW(), INTERVAL 6 MONTH));

-- 6. CUSTOMERS
INSERT INTO customer (full_name, email, phone, shipping_address) VALUES
('John Doe', 'john@example.com', '123-456-7890', 'Kigali, Rwanda'),
('Jane Smith', 'jane@example.com', '098-765-4321', 'Musanze, Rwanda'),
('Alice Brown', 'alice@example.com', '555-555-5555', 'Huye, Rwanda');

-- Initialize Loyalty for customers
INSERT INTO customer_loyalty (customer_id) SELECT customer_id FROM customer;
