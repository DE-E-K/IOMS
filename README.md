# IOMS - Inventory and Order Management System

## Overview

The **Inventory and Order Management System (IOMS)** is a robust, production-ready database solution designed for e-commerce applications. The core of this project is the Entity-Relationship Diagram (ERD) and the corresponding SQL implementation that provides a scalable schema for managing customers, products, dynamic inventory, and transactional order processing.

Key enhancements in this version include:

- **strict foreign key constraints** for data integrity
- **atomic order processing** to prevent race conditions
- **comprehensive inventory log** for full auditability
- **advanced analytics** with pre-built KPIs and views

## Key Features

- **Transactional Order Processing**: ACID-compliant order placement utilizing `START TRANSACTION` and row-level locking (`FOR UPDATE`) to handle high-concurrency environments safely.
- **Dynamic Inventory Control**: Real-time stock deduction and validation.
- **Audit Logging**: A dedicated `inventory_log` tracks every stock movement (Orders, Restocks, Adjustments) for accountability.
- **Data Integrity**: Enforced via Foreign Keys with `ON DELETE RESTRICT` to prevent accidental loss of historical data.
- **Low Stock Alerts**: Automated triggers to monitor reorder points.
- **Business Intelligence**: Includes the `CustomerSalesSummary` view and analytical queries for revenue trends and product ranking.

## Project Structure

```ascii
DEM03/
├── ioms_ddl.sql         # Database Schema: Tables, Views, FK Constraints
├── ioms_dml.sql         # Database Logic: Stored Procedures (PlaceOrder), KPI Queries
├── verify_changes.sql   # Verification Script: Test cases for new logic
├── IOMS_ERD.pdf         # Visual Entity-Relationship Diagram (PDF)
└── README.md            # Project Documentation
```

## Database Schema (ERD)

The following diagram illustrates the relationships between the core entities.

```dbdiagram
Table customer {
  customer_id int [pk]
  full_name varchar
  email varchar
  phone varchar
  shipping_address varchar
  created_at datetime
}

Table product {
  product_id int [pk]
  product_name varchar
  category enum
  price decimal
  is_active boolean
  created_at datetime
}

Table orders {
  order_id int [pk]
  customer_id int
  order_date datetime
  total_amount decimal
  order_status enum
}

Table order_item {
  order_item_id int [pk]
  order_id int
  product_id int
  quantity int
  unit_price_at_purchase decimal
}

Table inventory {
  inventory_id int [pk]
  product_id int
  quantity_on_hand int
  reorder_point int
  reorder_quantity int
  last_updated datetime
}

Table inventory_log {
  log_id int [pk]
  product_id int
  quantity_change int
  transaction_type enum
  reference_id int
  log_date datetime
}

Table low_stock_alerts {
  alert_id int [pk]
  product_id int
  alert_date datetime
  message varchar
}

Ref: orders.customer_id > customer.customer_id
Ref: order_item.order_id > orders.order_id
Ref: order_item.product_id > product.product_id
Ref: inventory.product_id - product.product_id
Ref: inventory_log.product_id > product.product_id
Ref: low_stock_alerts.product_id > product.product_id
```

## Setup & Usage

### Prerequisites

- **MySQL Server** (8.0+)
- MySQL Workbench or any SQL client

### Installation Steps

1.  **Initialize the Database**:
    Execute the [DDL script](ioms_ddl.sql) to create the schema and populate initial seed data.

    ```bash
    mysql -u root -p < ioms_ddl.sql
    ```

2.  **Load Business Logic**:
    Execute the [DML script](ioms_dml.sql) to install the stored procedures, views, and analytical queries.

    ```bash
    mysql -u root -p < ioms_dml.sql
    ```

3.  **Verify Installation**:
    Run the [verification Quereis](verify_changes.sql) to ensure all constraints and logic are working as expected.
    ```bash
    mysql -u root -p < verify_changes.sql
    ```

### Core Procedure: `PlaceOrder`

The system uses a JSON-based stored procedure to handle multi-item orders atomically.

**Signature:**

```sql
CALL PlaceOrder(
    IN p_customer_id INT,
    IN p_order_items JSON,
    OUT p_order_id INT
);
```

**Example Usage:**

```sql
-- Create an order for Customer ID 1 with two items
CALL PlaceOrder(
    1,
    '[{"product_id": 1, "quantity": 2}, {"product_id": 5, "quantity": 1}]',
    @new_order_id
);
SELECT @new_order_id;

## Technologies

- **Database**: MySQL 8.0
- **Diagramming**: dbdiagram.io, PDF
