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

## [Database Schema (ERD)](https://dbdiagram.io/d/697c8161bd82f5fce21ffbfb)

The following diagram illustrates the relationships between the core entities.

<img width="900" height="700" alt="DB Schema" src="https://github.com/user-attachments/assets/ad9ebe5f-c7c1-48ff-8b74-7b5ae0dc18b8" />


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
