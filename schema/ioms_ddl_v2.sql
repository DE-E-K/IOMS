-- Active: 1767084789057@@127.0.0.1@3306@ioms
-- Inventory and Order Management System (IOMS)
-- DDL IMPLEMENTATION
-- Version: 2.0 - Production Ready
-- ============================================

-- DATABASE CREATION
DROP DATABASE IF EXISTS IOMS;
CREATE DATABASE IF NOT EXISTS IOMS 
CHARACTER SET utf8mb4 -- Supports all languages & symbols
COLLATE utf8mb4_unicode_ci; -- Case insensitive, accent sensitive
USE IOMS;

-- CORE TABLES
-- ============================================

-- CUSTOMER TABLE with enhanced fields
CREATE TABLE customer (
  customer_id INT PRIMARY KEY AUTO_INCREMENT,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE CHECK (email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'),
  phone VARCHAR(20),
  shipping_address VARCHAR(255),
  billing_address VARCHAR(255),
  date_of_birth DATE,
  customer_since DATETIME DEFAULT CURRENT_TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE,
  last_purchase_date DATETIME,
  total_lifetime_value DECIMAL(10,2) DEFAULT 0,
  INDEX idx_customer_email (email),
  INDEX idx_customer_active (is_active, last_purchase_date)
);

-- PRODUCT CATEGORIES for better normalization
CREATE TABLE product_category (
  category_id INT PRIMARY KEY AUTO_INCREMENT,
  category_name VARCHAR(50) NOT NULL UNIQUE,
  description TEXT,
  parent_category_id INT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (parent_category_id) REFERENCES product_category(category_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_category_hierarchy (parent_category_id, category_name)
);

-- PRODUCT TABLE with enhanced attributes
CREATE TABLE product (
  product_id INT PRIMARY KEY AUTO_INCREMENT,
  product_name VARCHAR(255) NOT NULL,
  sku VARCHAR(50) UNIQUE NOT NULL,
  category_id INT NOT NULL,
  brand VARCHAR(100),
  description TEXT,
  price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
  cost_price DECIMAL(10,2) CHECK (cost_price >= 0),
  is_active BOOLEAN DEFAULT TRUE,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  rating DECIMAL(3,2) DEFAULT 0,
  review_count INT DEFAULT 0,
  meta_keywords VARCHAR(255),
  FOREIGN KEY (category_id) REFERENCES product_category(category_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_product_category (category_id, is_active),
  INDEX idx_product_sku (sku),
  INDEX idx_product_active_price (is_active, price),
  FULLTEXT INDEX idx_product_search (product_name, description, meta_keywords)
);

-- ORDERS TABLE with comprehensive fields
CREATE TABLE orders (
  order_id INT PRIMARY KEY AUTO_INCREMENT,
  order_number VARCHAR(50) UNIQUE NOT NULL DEFAULT (CONCAT('ORD-', DATE_FORMAT(CURRENT_TIMESTAMP, '%Y%m%d-'), LPAD(FLOOR(RAND() * 10000), 5, '0'))),
  customer_id INT NOT NULL,
  order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  order_status ENUM('Pending','Processing','Shipped','Delivered','Cancelled','Returned','Refunded') DEFAULT 'Pending',
  total_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
  tax_amount DECIMAL(10,2) DEFAULT 0,
  shipping_amount DECIMAL(10,2) DEFAULT 0,
  discount_amount DECIMAL(10,2) DEFAULT 0,
  payment_method ENUM('Credit Card', 'Mobile Money', 'Cash on Delivery', 'Bank Transfer', 'PayPal') DEFAULT 'Cash on Delivery',
  payment_status ENUM('Pending', 'Completed', 'Failed', 'Refunded') DEFAULT 'Pending',
  shipping_method VARCHAR(50),
  shipping_tracking_number VARCHAR(100),
  estimated_delivery_date DATE,
  actual_delivery_date DATE,
  notes TEXT,
  ip_address VARCHAR(45),
  user_agent TEXT,
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_orders_customer_date (customer_id, order_date),
  INDEX idx_orders_status_date (order_status, order_date),
  INDEX idx_orders_number (order_number),
  INDEX idx_orders_payment_status (payment_status, order_status)
);

-- ORDER ITEMS TABLE with tax support
CREATE TABLE order_item (
  order_item_id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  quantity INT NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  unit_tax_amount DECIMAL(10,2) DEFAULT 0,
  unit_discount_amount DECIMAL(10,2) DEFAULT 0,
  total_price DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  UNIQUE KEY uk_order_product (order_id, product_id),
  INDEX idx_order_item_product (product_id),
  INDEX idx_order_item_order (order_id)
);

-- INVENTORY TABLE with batch tracking
CREATE TABLE inventory (
  inventory_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL UNIQUE,
  quantity_on_hand INT NOT NULL CHECK (quantity_on_hand >= 0),
  quantity_reserved INT NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  quantity_available INT GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) VIRTUAL,
  reorder_point INT NOT NULL CHECK (reorder_point >= 0),
  reorder_quantity INT NOT NULL CHECK (reorder_quantity > 0),
  last_restock_date DATETIME,
  last_sale_date DATETIME,
  last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_inventory_low_stock (quantity_on_hand, reorder_point),
  INDEX idx_inventory_product (product_id)
);

-- INVENTORY BATCH for FIFO/LIFO tracking
CREATE TABLE inventory_batch (
  batch_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL,
  batch_number VARCHAR(50) NOT NULL,
  quantity_received INT NOT NULL CHECK (quantity_received > 0),
  quantity_remaining INT NOT NULL CHECK (quantity_remaining >= 0),
  unit_cost DECIMAL(10,2) NOT NULL,
  manufacture_date DATE,
  expiration_date DATE,
  received_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  supplier_id INT,
  notes TEXT,
  FOREIGN KEY (product_id) REFERENCES product(product_id),
  INDEX idx_batch_product (product_id, expiration_date),
  INDEX idx_batch_number (batch_number)
);

-- INVENTORY LOG TABLE with comprehensive tracking
CREATE TABLE inventory_log (
  log_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL,
  quantity_change INT NOT NULL,
  transaction_type ENUM('ORDER', 'RESTOCK', 'ADJUSTMENT', 'RETURN', 'DAMAGE', 'TRANSFER') NOT NULL,
  transaction_subtype VARCHAR(50),
  reference_id INT,
  reference_table VARCHAR(50),
  batch_id INT NULL,
  previous_quantity INT,
  new_quantity INT,
  log_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  performed_by VARCHAR(100),
  notes TEXT,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  FOREIGN KEY (batch_id) REFERENCES inventory_batch(batch_id),
  INDEX idx_inventory_log_product_date (product_id, log_date),
  INDEX idx_inventory_log_reference (reference_table, reference_id),
  INDEX idx_inventory_log_type (transaction_type, log_date)
);

-- LOW STOCK ALERTS with priority levels
CREATE TABLE low_stock_alerts (
  alert_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL,
  alert_level ENUM('INFO', 'WARNING', 'CRITICAL') DEFAULT 'WARNING',
  current_quantity INT NOT NULL,
  reorder_point INT NOT NULL,
  alert_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  message TEXT NOT NULL,
  acknowledged BOOLEAN DEFAULT FALSE,
  acknowledged_by VARCHAR(100),
  acknowledged_at DATETIME,
  resolved BOOLEAN DEFAULT FALSE,
  resolved_at DATETIME,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_alerts_product (product_id, resolved, alert_level),
  INDEX idx_alerts_date (alert_date, acknowledged)
);

-- SUPPLIERS TABLE
CREATE TABLE suppliers (
  supplier_id INT PRIMARY KEY AUTO_INCREMENT,
  supplier_name VARCHAR(100) NOT NULL UNIQUE,
  contact_person VARCHAR(100),
  email VARCHAR(100),
  phone VARCHAR(20) NOT NULL,
  address TEXT,
  payment_terms VARCHAR(50),
  is_active BOOLEAN DEFAULT TRUE,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_supplier_active (is_active, supplier_name)
);

-- PURCHASE ORDERS
CREATE TABLE purchase_orders (
  po_id INT PRIMARY KEY AUTO_INCREMENT,
  po_number VARCHAR(50) UNIQUE NOT NULL DEFAULT (CONCAT('PO-', DATE_FORMAT(CURRENT_TIMESTAMP, '%Y%m%d-'), LPAD(FLOOR(RAND() * 10000), 5, '0'))),
  supplier_id INT NOT NULL,
  order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  expected_delivery_date DATE,
  actual_delivery_date DATE,
  status ENUM('Draft', 'Ordered', 'Received', 'Partial', 'Cancelled') DEFAULT 'Draft',
  total_amount DECIMAL(10,2) DEFAULT 0 CHECK (total_amount >= 0),
  notes TEXT,
  created_by VARCHAR(100),
  FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id),
  INDEX idx_po_supplier (supplier_id, order_date),
  INDEX idx_po_status (status, expected_delivery_date)
);

-- PURCHASE ORDER ITEMS
CREATE TABLE purchase_order_items (
  po_item_id INT PRIMARY KEY AUTO_INCREMENT,
  po_id INT NOT NULL,
  product_id INT NOT NULL,
  quantity_ordered INT NOT NULL CHECK (quantity_ordered > 0),
  quantity_received INT DEFAULT 0 CHECK (quantity_received >= 0),
  unit_cost DECIMAL(10,2) NOT NULL CHECK (unit_cost > 0),
  total_cost DECIMAL(10,2) GENERATED ALWAYS AS (quantity_ordered * unit_cost) STORED,
  FOREIGN KEY (po_id) REFERENCES purchase_orders(po_id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES product(product_id),
  INDEX idx_po_items_product (product_id),
  INDEX idx_po_items_po (po_id)
);

-- RETURNS AND REFUNDS
CREATE TABLE returns (
  return_id INT PRIMARY KEY AUTO_INCREMENT,
  return_number VARCHAR(50) UNIQUE NOT NULL DEFAULT (CONCAT('RET-', DATE_FORMAT(CURRENT_TIMESTAMP, '%Y%m%d-'), LPAD(FLOOR(RAND() * 10000), 5, '0'))),
  order_id INT NOT NULL,
  customer_id INT NOT NULL,
  return_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  return_reason ENUM('Defective', 'Wrong Item', 'Customer Changed Mind', 'Late Delivery', 'Damaged in Transit', 'Not as Described'),
  return_status ENUM('Requested', 'Approved', 'Rejected', 'Received', 'Refunded', 'Replaced') DEFAULT 'Requested',
  refund_amount DECIMAL(10,2),
  refund_method ENUM('Original Payment', 'Store Credit', 'Bank Transfer'),
  refund_date DATETIME,
  notes TEXT,
  inspected_by VARCHAR(100),
  inspection_date DATETIME,
  FOREIGN KEY (order_id) REFERENCES orders(order_id),
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
  INDEX idx_returns_order (order_id),
  INDEX idx_returns_customer (customer_id, return_date),
  INDEX idx_returns_status (return_status, return_date)
);

-- RETURN ITEMS
CREATE TABLE return_items (
  return_item_id INT PRIMARY KEY AUTO_INCREMENT,
  return_id INT NOT NULL,
  product_id INT NOT NULL,
  order_item_id INT NOT NULL,
  quantity_returned INT NOT NULL CHECK (quantity_returned > 0),
  conditions ENUM('New', 'Opened', 'Damaged', 'Defective'),
  restock_eligible BOOLEAN DEFAULT FALSE,
  restocked_quantity INT DEFAULT 0,
  unit_refund_amount DECIMAL(10,2),
  total_refund_amount DECIMAL(10,2) GENERATED ALWAYS AS (quantity_returned * unit_refund_amount) STORED,
  FOREIGN KEY (return_id) REFERENCES returns(return_id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES product(product_id),
  FOREIGN KEY (order_item_id) REFERENCES order_item(order_item_id),
  INDEX idx_return_items_product (product_id),
  INDEX idx_return_items_return (return_id)
);

-- CUSTOMER LOYALTY PROGRAM
CREATE TABLE customer_loyalty (
  loyalty_id INT PRIMARY KEY AUTO_INCREMENT,
  customer_id INT NOT NULL UNIQUE,
  loyalty_points DECIMAL(10,2) DEFAULT 0,
  loyalty_tier ENUM('Bronze', 'Silver', 'Gold', 'Platinum') DEFAULT 'Bronze',
  total_spent DECIMAL(10,2) DEFAULT 0,
  points_earned DECIMAL(10,2) DEFAULT 0,
  points_redeemed DECIMAL(10,2) DEFAULT 0,
  points_expired DECIMAL(10,2) DEFAULT 0,
  tier_effective_date DATE DEFAULT (CURDATE()),
  next_tier_threshold DECIMAL(10,2),
  last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE CASCADE,
  INDEX idx_loyalty_tier (loyalty_tier),
  INDEX idx_loyalty_customer (customer_id)
);

-- LOYALTY TRANSACTIONS
CREATE TABLE loyalty_transactions (
  transaction_id INT PRIMARY KEY AUTO_INCREMENT,
  customer_id INT NOT NULL,
  order_id INT,
  return_id INT,
  points_change DECIMAL(10,2) NOT NULL,
  transaction_type ENUM('Earned', 'Redeemed', 'Expired', 'Adjusted', 'Bonus', 'Tier Upgrade') NOT NULL,
  description VARCHAR(255),
  transaction_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  expiry_date DATE,
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
  FOREIGN KEY (order_id) REFERENCES orders(order_id),
  FOREIGN KEY (return_id) REFERENCES returns(return_id),
  INDEX idx_loyalty_transactions_customer (customer_id, transaction_date),
  INDEX idx_loyalty_transactions_type (transaction_type, transaction_date)
);

-- PROMOTIONS AND DISCOUNTS
CREATE TABLE promotions (
  promotion_id INT PRIMARY KEY AUTO_INCREMENT,
  promotion_code VARCHAR(50) UNIQUE,
  promotion_name VARCHAR(100) NOT NULL,
  promotion_type ENUM('Percentage', 'Fixed Amount', 'Free Shipping', 'Bundle') NOT NULL,
  discount_value DECIMAL(10,2) NOT NULL CHECK (discount_value >= 0),
  minimum_order_amount DECIMAL(10,2) DEFAULT 0,
  maximum_discount_amount DECIMAL(10,2),
  valid_from DATETIME NOT NULL,
  valid_to DATETIME NOT NULL,
  max_uses_total INT,
  max_uses_per_customer INT DEFAULT 1,
  times_used INT DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  applicable_categories JSON, -- Array of category_ids
  excluded_products JSON, -- Array of product_ids
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  created_by VARCHAR(100),
  INDEX idx_promotions_active (is_active, valid_from, valid_to),
  INDEX idx_promotions_code (promotion_code),
  FULLTEXT INDEX idx_promotions_search (promotion_name, promotion_code)
);

-- PROMOTION USAGE
CREATE TABLE promotion_usage (
  usage_id INT PRIMARY KEY AUTO_INCREMENT,
  promotion_id INT NOT NULL,
  customer_id INT NOT NULL,
  order_id INT NOT NULL,
  discount_applied DECIMAL(10,2) NOT NULL,
  used_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (promotion_id) REFERENCES promotions(promotion_id),
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
  FOREIGN KEY (order_id) REFERENCES orders(order_id),
  UNIQUE KEY uk_promotion_order (promotion_id, order_id),
  INDEX idx_promotion_usage_customer (customer_id, used_at),
  INDEX idx_promotion_usage_promotion (promotion_id, used_at)
);

-- PAYMENTS TABLE
CREATE TABLE payments (
  payment_id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  payment_reference VARCHAR(100) UNIQUE,
  payment_method ENUM('Credit Card', 'Mobile Money', 'Cash on Delivery', 'Bank Transfer', 'PayPal', 'Store Credit') NOT NULL,
  payment_provider VARCHAR(50),
  amount DECIMAL(10,2) NOT NULL,
  transaction_fee DECIMAL(10,2) DEFAULT 0,
  currency VARCHAR(3) DEFAULT 'USD',
  payment_status ENUM('Pending', 'Completed', 'Failed', 'Refunded', 'Partially Refunded') DEFAULT 'Pending',
  payment_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  processed_at DATETIME,
  failure_reason TEXT,
  card_last4 VARCHAR(4),
  card_brand VARCHAR(20),
  payment_metadata JSON,
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_payments_order (order_id),
  INDEX idx_payments_status_date (payment_status, payment_date),
  INDEX idx_payments_reference (payment_reference)
);

-- SHIPPING INFORMATION
CREATE TABLE shipping_info (
  shipping_id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL UNIQUE,
  shipping_method VARCHAR(50) NOT NULL,
  shipping_cost DECIMAL(10,2) DEFAULT 0,
  tracking_number VARCHAR(100),
  carrier VARCHAR(50),
  estimated_delivery_date DATE,
  actual_delivery_date DATE,
  shipping_address JSON NOT NULL,
  billing_address JSON,
  shipping_notes TEXT,
  shipped_at DATETIME,
  delivered_at DATETIME,
  delivery_confirmation VARCHAR(100),
  FOREIGN KEY (order_id) REFERENCES orders(order_id),
  INDEX idx_shipping_tracking (tracking_number),
  INDEX idx_shipping_dates (estimated_delivery_date, actual_delivery_date)
);

-- WAREHOUSE LOCATIONS
CREATE TABLE warehouse_locations (
  location_id INT PRIMARY KEY AUTO_INCREMENT,
  location_code VARCHAR(20) UNIQUE NOT NULL,
  location_name VARCHAR(100) NOT NULL,
  address TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  manager VARCHAR(100),
  phone VARCHAR(20),
  email VARCHAR(100),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_warehouse_active (is_active, location_code)
);

-- PRODUCT LOCATIONS
CREATE TABLE product_locations (
  product_location_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL,
  location_id INT NOT NULL,
  quantity_on_hand INT NOT NULL DEFAULT 0,
  last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (product_id) REFERENCES product(product_id),
  FOREIGN KEY (location_id) REFERENCES warehouse_locations(location_id),
  UNIQUE KEY uk_product_location (product_id, location_id),
  INDEX idx_product_location_product (product_id),
  INDEX idx_product_location_location (location_id)
);

-- SYSTEM ERROR LOG
CREATE TABLE system_error_log (
  error_id INT PRIMARY KEY AUTO_INCREMENT,
  error_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  error_code VARCHAR(50),
  mysql_errno INT,
  sql_state VARCHAR(10),
  error_message TEXT,
  stored_procedure VARCHAR(100),
  parameters JSON,
  user_context VARCHAR(100),
  severity ENUM('LOW', 'MEDIUM', 'HIGH', 'CRITICAL') DEFAULT 'MEDIUM',
  stack_trace TEXT,
  resolved BOOLEAN DEFAULT FALSE,
  resolved_at DATETIME,
  resolution_notes TEXT,
  INDEX idx_error_time (error_time),
  INDEX idx_error_severity (severity, resolved),
  INDEX idx_error_procedure (stored_procedure, error_time)
);

-- QUERY PERFORMANCE LOG
CREATE TABLE query_performance_log (
  log_id INT PRIMARY KEY AUTO_INCREMENT,
  query_type VARCHAR(50),
  query_text TEXT,
  execution_time_ms DECIMAL(10,2),
  rows_affected INT,
  rows_examined INT,
  lock_time_ms DECIMAL(10,2),
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  server_hostname VARCHAR(100),
  database_name VARCHAR(50),
  user_host VARCHAR(255),
  connection_id BIGINT,
  INDEX idx_performance_time (timestamp),
  INDEX idx_query_type (query_type, execution_time_ms DESC),
  INDEX idx_slow_queries (execution_time_ms DESC, timestamp)
);

-- BUSINESS RULE VIOLATIONS
CREATE TABLE business_rule_violations (
  violation_id INT PRIMARY KEY AUTO_INCREMENT,
  rule_name VARCHAR(100),
  violation_description TEXT,
  entity_type VARCHAR(50),
  entity_id INT,
  entity_reference VARCHAR(100),
  detected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  severity ENUM('LOW', 'MEDIUM', 'HIGH', 'CRITICAL') DEFAULT 'MEDIUM',
  resolved BOOLEAN DEFAULT FALSE,
  resolved_at DATETIME,
  resolution_notes TEXT,
  INDEX idx_rule_violations (rule_name, detected_at, resolved),
  INDEX idx_violation_entity (entity_type, entity_id, detected_at)
);

-- ACTIVE CONNECTIONS LOG
CREATE TABLE active_connections_log (
  log_id INT PRIMARY KEY AUTO_INCREMENT,
  connection_id BIGINT,
  user_host VARCHAR(255),
  db VARCHAR(64),
  command VARCHAR(16),
  time_ms INT,
  state VARCHAR(64),
  query_text TEXT,
  logged_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_connection_time (logged_at),
  INDEX idx_long_running (time_ms DESC, logged_at)
);

-- DATA ACCESS AUDIT LOG
CREATE TABLE data_access_audit (
  audit_id INT PRIMARY KEY AUTO_INCREMENT,
  user_id VARCHAR(100),
  action ENUM('SELECT', 'INSERT', 'UPDATE', 'DELETE') NOT NULL,
  table_name VARCHAR(100) NOT NULL,
  record_id INT,
  old_values JSON,
  new_values JSON,
  ip_address VARCHAR(45),
  user_agent TEXT,
  access_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_audit_time (access_time),
  INDEX idx_audit_user (user_id, access_time),
  INDEX idx_audit_table (table_name, access_time)
);

-- CUSTOMER SUMMARY DAILY (Materialized view pattern)
CREATE TABLE customer_summary_daily (
  summary_date DATE NOT NULL,
  customer_id INT NOT NULL,
  total_spent DECIMAL(10,2) DEFAULT 0,
  total_orders INT DEFAULT 0,
  avg_order_value DECIMAL(10,2) DEFAULT 0,
  days_since_last_order INT,
  favorite_category VARCHAR(50),
  last_order_date DATETIME,
  last_order_amount DECIMAL(10,2),
  PRIMARY KEY (summary_date, customer_id),
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
  INDEX idx_summary_customer (customer_id, summary_date DESC),
  INDEX idx_summary_date (summary_date)
);

-- PRODUCT SALES SUMMARY DAILY
CREATE TABLE product_sales_summary (
  summary_date DATE NOT NULL,
  product_id INT NOT NULL,
  quantity_sold INT DEFAULT 0,
  total_revenue DECIMAL(10,2) DEFAULT 0,
  avg_selling_price DECIMAL(10,2) DEFAULT 0,
  unique_customers INT DEFAULT 0,
  return_quantity INT DEFAULT 0,
  stock_out_days INT DEFAULT 0,
  PRIMARY KEY (summary_date, product_id),
  FOREIGN KEY (product_id) REFERENCES product(product_id),
  INDEX idx_sales_product (product_id, summary_date DESC),
  INDEX idx_sales_date (summary_date)
);

-- ============================================
-- INDEXES FOR OPTIMIZATION
-- ============================================

-- Additional composite indexes for performance
CREATE INDEX idx_product_inventory_status ON product(is_active, product_id);
CREATE INDEX idx_inventory_availability ON inventory(quantity_on_hand, quantity_reserved);
CREATE INDEX idx_order_items_complete ON order_item(order_id, product_id, quantity);
CREATE INDEX idx_customer_lifetime ON customer(total_lifetime_value DESC, last_purchase_date DESC);
CREATE INDEX idx_promotions_validity ON promotions(is_active, valid_from, valid_to);



-- SAMPLE DATA INSERTION
-- ============================================

-- Insert product categories
INSERT INTO product_category (category_name, description) VALUES
('Electronics', 'Electronic devices and accessories'),
('Apparel', 'Clothing and fashion items'),
('Books', 'Books and educational materials'),
('Home & Garden', 'Home improvement and garden supplies'),
('Sports & Outdoors', 'Sports equipment and outdoor gear'),
('Health & Beauty', 'Health products and beauty items'),
('Toys & Games', 'Toys, games, and entertainment'),
('Automotive', 'Automotive parts and accessories');

-- Insert suppliers
INSERT INTO suppliers (supplier_name, contact_person, email, phone, address) VALUES
('TechGadgets Inc.', 'John Smith', 'john@techgadgets.com', '+1-555-0101', '123 Tech St, Silicon Valley, CA'),
('FashionHub Ltd.', 'Sarah Johnson', 'sarah@fashionhub.com', '+1-555-0102', '456 Fashion Ave, New York, NY'),
('BookWorld Publishers', 'Michael Brown', 'michael@bookworld.com', '+1-555-0103', '789 Library Rd, Boston, MA'),
('HomeEssentials Co.', 'Emma Wilson', 'emma@homeessentials.com', '+1-555-0104', '321 Home St, Chicago, IL'),
('SportsGear Unlimited', 'David Lee', 'david@sportsgear.com', '+1-555-0105', '654 Stadium Blvd, Los Angeles, CA');

-- Insert products with SKUs
INSERT INTO product (product_name, sku, category_id, brand, price, cost_price, description) VALUES
('Smartphone X Pro', 'SKU-ELEC-001', 1, 'TechBrand', 899.99, 550.00, 'Latest smartphone with advanced features'),
('Wireless Bluetooth Headphones', 'SKU-ELEC-002', 1, 'SoundMaster', 149.99, 75.00, 'Noise-cancelling wireless headphones'),
('Gaming Laptop 15"', 'SKU-ELEC-003', 1, 'GameTech', 1299.99, 850.00, 'High-performance gaming laptop'),
('Smart Watch Series 5', 'SKU-ELEC-004', 1, 'WatchTech', 299.99, 180.00, 'Smart watch with health monitoring'),
('USB-C Laptop Charger', 'SKU-ELEC-005', 1, 'PowerUp', 39.99, 15.00, '65W fast charger for laptops'),
('Cotton T-Shirt', 'SKU-APP-001', 2, 'ComfortWear', 24.99, 8.00, '100% cotton crew neck t-shirt'),
('Denim Jeans', 'SKU-APP-002', 2, 'DenimCo', 59.99, 25.00, 'Slim fit denim jeans'),
('Winter Jacket', 'SKU-APP-003', 2, 'OutdoorGear', 129.99, 65.00, 'Waterproof winter jacket'),
('Running Shoes', 'SKU-APP-004', 2, 'RunFast', 89.99, 40.00, 'Lightweight running shoes'),
('Python Programming Book', 'SKU-BOOK-001', 3, 'TechBooks', 39.99, 15.00, 'Complete guide to Python programming'),
('Data Science Handbook', 'SKU-BOOK-002', 3, 'DataPress', 49.99, 20.00, 'Comprehensive data science guide'),
('Machine Learning Basics', 'SKU-BOOK-003', 3, 'AIPress', 44.99, 18.00, 'Introduction to machine learning'),
('Coffee Maker', 'SKU-HOME-001', 4, 'HomeBrew', 79.99, 35.00, '12-cup programmable coffee maker'),
('Air Fryer', 'SKU-HOME-002', 4, 'KitchenTech', 129.99, 60.00, 'Digital air fryer with multiple functions'),
('Yoga Mat', 'SKU-SPORTS-001', 5, 'FitLife', 29.99, 12.00, 'Non-slip yoga mat'),
('Dumbbell Set', 'SKU-SPORTS-002', 5, 'StrongGym', 89.99, 45.00, 'Adjustable dumbbell set 5-25kg'),
('Vitamin C Supplements', 'SKU-HEALTH-001', 6, 'HealthPlus', 19.99, 7.00, '1000mg Vitamin C tablets'),
('Board Game Collection', 'SKU-TOYS-001', 7, 'GameTime', 49.99, 22.00, 'Family board game collection'),
('Car Phone Holder', 'SKU-AUTO-001', 8, 'AutoTech', 24.99, 9.00, 'Adjustable car phone mount');

-- Insert inventory
INSERT INTO inventory (product_id, quantity_on_hand, reorder_point, reorder_quantity, last_restock_date) VALUES
(1, 50, 10, 20, '2024-01-15'),
(2, 120, 20, 50, '2024-01-20'),
(3, 25, 5, 10, '2024-01-10'),
(4, 75, 15, 30, '2024-01-18'),
(5, 200, 30, 100, '2024-01-22'),
(6, 150, 25, 50, '2024-01-12'),
(7, 80, 15, 30, '2024-01-14'),
(8, 45, 10, 20, '2024-01-16'),
(9, 90, 20, 40, '2024-01-19'),
(10, 60, 10, 25, '2024-01-11'),
(11, 40, 8, 20, '2024-01-13'),
(12, 35, 7, 15, '2024-01-17'),
(13, 55, 12, 25, '2024-01-21'),
(14, 30, 6, 15, '2024-01-23'),
(15, 100, 20, 40, '2024-01-24'),
(16, 65, 15, 30, '2024-01-25'),
(17, 85, 18, 35, '2024-01-26'),
(18, 25, 5, 10, '2024-01-27'),
(19, 70, 15, 30, '2024-01-28');

-- Insert customers
INSERT INTO customer (full_name, email, phone, shipping_address, date_of_birth, customer_since) VALUES
('John Smith', 'john.smith@email.com', '0781000001', '123 Main St, Kigali', '1985-05-15', '2023-01-10'),
('Sarah Johnson', 'sarah.j@email.com', '0781000002', '456 Oak Ave, Huye', '1990-08-22', '2023-02-15'),
('Michael Brown', 'michael.b@email.com', '0781000003', '789 Pine Rd, Musanze', '1988-03-30', '2023-01-25'),
('Emily Davis', 'emily.d@email.com', '0781000004', '321 Elm St, Rubavu', '1992-11-05', '2023-03-10'),
('David Wilson', 'david.w@email.com', '0781000005', '654 Maple Dr, Nyamirambo', '1987-07-18', '2023-02-28'),
('Jessica Taylor', 'jessica.t@email.com', '0781000006', '987 Cedar Ln, Kicukiro', '1995-01-25', '2023-03-15'),
('Robert Martinez', 'robert.m@email.com', '0781000007', '147 Birch Blvd, Nyarugenge', '1983-09-12', '2023-01-05'),
('Amanda Anderson', 'amanda.a@email.com', '0781000008', '258 Walnut Way, Bugesera', '1991-06-30', '2023-02-10'),
('Daniel Thomas', 'daniel.t@email.com', '0781000009', '369 Spruce Cir, Gasabo', '1989-04-08', '2023-03-05'),
('Jennifer White', 'jennifer.w@email.com', '0781000010', '741 Oakwood Dr, Muhanga', '1993-12-15', '2023-02-20');

-- Insert warehouse locations
INSERT INTO warehouse_locations (location_code, location_name, address, is_active) VALUES
('WH-001', 'Main Warehouse', '123 Industrial Zone, Kigali', TRUE),
('WH-002', 'West Distribution', '456 Distribution Park, Rubavu', TRUE),
('WH-003', 'North Storage', '789 Storage Facility, Musanze', TRUE),
('WH-004', 'East Center', '321 Logistics Hub, Kayonza', TRUE);

-- Insert sample product locations
INSERT INTO product_locations (product_id, location_id, quantity_on_hand) VALUES
(1, 1, 30),
(1, 2, 20),
(2, 1, 80),
(2, 3, 40),
(3, 1, 25),
(4, 2, 50),
(4, 4, 25),
(5, 1, 150),
(5, 3, 50);

-- Insert initial customer loyalty records
INSERT INTO customer_loyalty (customer_id, loyalty_points, loyalty_tier, total_spent, points_earned) VALUES
(1, 1500, 'Silver', 2500, 1500),
(2, 800, 'Bronze', 1200, 800),
(3, 3000, 'Gold', 5000, 3000),
(4, 500, 'Bronze', 800, 500),
(5, 2200, 'Silver', 3500, 2200),
(6, 100, 'Bronze', 150, 100),
(7, 4500, 'Platinum', 7500, 4500),
(8, 600, 'Bronze', 1000, 600),
(9, 1800, 'Silver', 3000, 1800),
(10, 250, 'Bronze', 400, 250);

-- Insert promotions
INSERT INTO promotions (promotion_code, promotion_name, promotion_type, discount_value, minimum_order_amount, valid_from, valid_to, max_uses_total, is_active) VALUES
('WELCOME10', 'Welcome Discount', 'Percentage', 10.00, 50.00, '2024-01-01', '2024-12-31', 1000, TRUE),
('FREESHIP', 'Free Shipping', 'Free Shipping', 0.00, 100.00, '2024-01-01', '2024-12-31', NULL, TRUE),
('SAVE20', 'Summer Sale', 'Percentage', 20.00, 75.00, '2024-06-01', '2024-08-31', 500, TRUE),
('FLAT15', 'Flat Discount', 'Fixed Amount', 15.00, 50.00, '2024-01-01', '2024-12-31', NULL, TRUE),
('LOYALTY5', 'Loyalty Bonus', 'Percentage', 5.00, 0.00, '2024-01-01', '2024-12-31', NULL, TRUE);

-- Insert sample orders (these will be populated by stored procedures in DML)
-- Note: Actual orders will be created through stored procedures



-- Optimize tables
-- ANALYZE TABLE customer, product, orders, order_item, inventory, inventory_log;

-- Show final status
SELECT 'Database IOMS created successfully!' as status;
SELECT COUNT(*) as total_tables FROM information_schema.tables WHERE table_schema = 'IOMS';
SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = 'IOMS' ORDER BY table_name;