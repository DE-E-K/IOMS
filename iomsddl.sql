-- Inventory and Order Management Database: FULL SQL IMPLEMENTATION
-- DATABASE AND TABLES
DROP DATABASE IF EXISTS IOM;
CREATE DATABASE IF NOT EXISTS IOM;
USE IOM;

-- CUSTOMER TABLE
CREATE TABLE customer (
  customer_id INT PRIMARY KEY AUTO_INCREMENT,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE CHECK (email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'),
  phone VARCHAR(20),
  shipping_address VARCHAR(255),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- PRODUCT TABLE
CREATE TABLE product (
  product_id INT PRIMARY KEY AUTO_INCREMENT,
  product_name VARCHAR(255) NOT NULL UNIQUE,
  category ENUM('Electronics','Apparel','Books') NOT NULL,
  price DECIMAL(10,2) NOT NULL CHECK (price > 0),
  is_active BOOLEAN DEFAULT TRUE,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ORDERS TABLE
CREATE TABLE orders (
  order_id INT PRIMARY KEY AUTO_INCREMENT,
  customer_id INT NOT NULL,
  order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  total_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  order_status ENUM('Pending','Processing','Shipped','Delivered','Cancelled') DEFAULT 'Pending',
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE CASCADE
);

-- ORDER ITEMS TABLE
CREATE TABLE order_item (
  order_item_id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  quantity INT NOT NULL CHECK (quantity > 0),
  unit_price_at_purchase DECIMAL(10,2) NOT NULL CHECK (unit_price_at_purchase > 0),
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON DELETE CASCADE,
  UNIQUE(order_id, product_id)
);

-- INVENTORY TABLE
CREATE TABLE inventory (
  inventory_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL UNIQUE,
  quantity_on_hand INT NOT NULL CHECK (quantity_on_hand >= 0),
  reorder_point INT NOT NULL CHECK (reorder_point >= 0),
  reorder_quantity INT NOT NULL CHECK (reorder_quantity > 0),
  last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON DELETE CASCADE
);

-- LOW STOCK ALERTS
CREATE TABLE low_stock_alerts (
  alert_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL,
  alert_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  message VARCHAR(255) NOT NULL,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON DELETE CASCADE
);


-- INDEXES FOR OPTIMIZATION
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_order_item_product_id ON order_item(product_id);
CREATE INDEX idx_inventory_product_id ON inventory(product_id);

-- TRIGGERS
-- Check stock BEFORE inserting an order item
CREATE TRIGGER trg_check_stock_before_order
BEFORE INSERT ON order_item
FOR EACH ROW
BEGIN
  DECLARE stock INT;
  SELECT quantity_on_hand INTO stock FROM inventory WHERE product_id = NEW.product_id;

  IF stock IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product does not exist in inventory.';
  END IF;

  IF NEW.quantity > stock THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Not enough stock to fulfill this order item.';
  END IF;
END;

-- Reduce stock AFTER inserting an order item
CREATE TRIGGER trg_reduce_stock_after_order
AFTER INSERT ON order_item
FOR EACH ROW
BEGIN
  UPDATE inventory
  SET quantity_on_hand = quantity_on_hand - NEW.quantity
  WHERE product_id = NEW.product_id;
END;

-- Auto-create low stock alert
CREATE TRIGGER trg_low_stock_alert
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
  IF NEW.quantity_on_hand <= NEW.reorder_point THEN
    INSERT INTO low_stock_alerts(product_id, message)
    VALUES(NEW.product_id, 'Stock below reorder point.');
  END IF;
END;

-- Auto-update Order Total
CREATE TRIGGER trg_update_order_total
AFTER INSERT ON order_item
FOR EACH ROW
BEGIN
  UPDATE orders
  SET total_amount = (SELECT SUM(quantity * unit_price_at_purchase)
                      FROM order_item
                      WHERE order_id = NEW.order_id)
  WHERE order_id = NEW.order_id;
END;

-- SAMPLE DATA INSERTS

INSERT INTO customer(full_name,email,phone,shipping_address) VALUES
('John Doe','john@example.com','0781111111','Kigali'),
('Alice Smith','alice@example.com','0782222222','Huye'),
('Michael Brown','mike@example.com','0783333333','Musanze'),
('Grace Uwera','grace@example.com','0784444444','Rubavu'),
('John Smith','johns@example.com','0781000001','Kigali'),
('Alice Simon','alices@example.com','0781000002','Huye'),
('Michael Brown','mikeb@example.com','0781000003','Musanze'),
('Grace Uwera','graceu@example.com','0781000004','Rubavu'),
('Eric Mutabazi','ericm@example.com','0781000005','Nyamirambo'),
('Linda Mbabazi','linda.m@example.com','0781000006','Kicukiro'),
('David Habimana','david.h@example.com','0781000007','Nyarugenge'),
('Sarah Mukamana','sarah.m@example.com','0781000008','Bugesera'),
('Kevin Mugisha','kevin.m@example.com','0781000009','Gasabo'),
('Diane Umwari','diane.u@example.com','0781000010','Muhanga'),
('Peter Nizeyimana','peter.n@example.com','0781000011','Karongi'),
('Claudine Uwera','claudine@example.com','0781000012','Rwamagana'),
('James Hakizimana','james.h@example.com','0781000013','Gicumbi'),
('Olivia Uwase','olivia@example.com','0781000014','Ruhango'),
('Joseph Nkurunziza','joseph.n@example.com','0781000015','Rusizi'),
('Benjamin Tuyishime','ben.t@example.com','0781000016','Kayonza'),
('Angelique Umutesi','angeli@example.com','0781000017','Gakenke'),
('Samuel Rukundo','sam.r@example.com','0781000018','Ngoma'),
('Beatrice Mukanyangezi','bea.m@example.com','0781000019','Nyanza'),
('Aline Murekatete','aline.m@example.com','0781000020','Kirehe'),
('Patrick Hakizimana','patrick.h@example.com','0781000021','Kigali');

INSERT INTO product(product_name, category, price) VALUES
('Smartphone X','Electronics',500),
('Laptop Pro 15','Electronics',1200),
('Wireless Headphones','Electronics',150),
('T-Shirt Classic','Apparel',20),
('Jeans Regular','Apparel',40),
('Python Programming Book','Books',30),
('Smartphone y','Electronics',500),
('Laptop Lenovo','Electronics',1230),
('Bluetooth Speaker','Electronics',80),
('LED Monitor 24"','Electronics',200),
('Gaming Keyboard','Electronics',90),
('USB-C Charger','Electronics',25),
('Smartwatch Fit','Electronics',110),
('Cotton Hoodie','Apparel',35),
('Sport Shoes','Apparel',55),
('Baseball Cap','Apparel',15),
('Winter Jacket','Apparel',75),
('Data Science Handbook','Books',40),
('Machine Learning Guide','Books',45),
('Startup Entrepreneurship','Books',35),
('Financial Accounting Basics','Books',25),
('Advanced SQL Techniques','Books',50),
('Cybersecurity Principles','Books',60);

INSERT INTO inventory (product_id, quantity_on_hand, reorder_point, reorder_quantity) VALUES
(1, 50, 10, 20),
(2, 18, 5, 10),
(3, 60, 10, 20),
(4, 40, 10, 15),
(5, 33, 7, 10),
(6, 25, 8, 15),
(7, 80, 20, 30),
(8, 45, 15, 20),
(9, 70, 20, 30),
(10, 55, 15, 20),
(11, 48, 10, 15),
(12, 36, 10, 15),
(13, 42, 10, 20),
(14, 30, 10, 15),
(15, 100, 30, 40),
(16, 90, 25, 35),
(17, 85, 20, 30),
(18, 50, 12, 20),
(19, 40, 10, 15),
(20, 25, 7, 10),
(21, 20, 5, 10);

-- Create sample orders
INSERT INTO orders(customer_id, order_date, order_status) VALUES
(1, '2025-01-10', 'Delivered'),
(2, '2025-02-15', 'Shipped'),
(1, '2025-03-05', 'Shipped'),
(3, '2025-03-18', 'Pending'),
(1, '2025-01-05','Delivered'),
(2, '2025-01-10','Shipped'),
(3, '2025-01-12','Delivered'),
(4, '2025-01-15','Shipped'),
(5, '2025-02-01','Delivered'),
(6, '2025-02-10','Pending'),
(7, '2025-02-18','Processing'),
(8, '2025-02-20','Delivered'),
(9, '2025-03-01','Shipped'),
(10, '2025-03-05','Delivered'),
(1, '2025-03-12','Processing'),
(12, '2025-03-20','Delivered'),
(13, '2025-03-22','Pending'),
(14, '2025-04-02','Delivered'),
(1, '2025-04-10','Shipped'),
(16, '2025-04-12','Delivered'),
(17, '2025-05-01','Pending'),
(10, '2025-05-05','Delivered'),
(19, '2025-05-10','Shipped'),
(2, '2025-05-11','Delivered'),
(21, '2025-05-12','Delivered');

-- Order items
INSERT INTO order_item(order_id, product_id, quantity, unit_price_at_purchase) VALUES
(1,1,1,500),
(1,9,2,20),
(2,2,1,1200),
(3,3,2,150),
(3,10,1,35),
(4,4,1,80),
(4,15,1,30),
(5,5,1,200),
(5,11,1,55),
(6,6,1,90),
(7,7,2,25),
(7,17,1,45),
(8,8,1,110),
(8,18,1,35),
(9,12,2,15),
(10,13,1,40),
(10,19,1,25),
(11,14,1,75),
(12,20,1,50),
(12,21,1,60),
(13,16,1,40),
(14,3,1,150),
(15,4,1,80),
(16,1,1,500),
(17,6,1,90),
(18,10,2,35),
(19,11,1,55),
(20,5,1,200),
(21,2,1,1200);