# Database Schema Documentation

This document provides a comprehensive **Data Dictionary** for the Inventory and Order Management System (IOMS).

## Table of Contents
1.  [Core Entities](#1-core-entities)
    *   [customer](#table-customer)
    *   [product](#table-product)
    *   [inventory](#table-inventory)
    *   [orders](#table-orders)
    *   [order_item](#table-order_item)
2.  [Advanced Modules](#2-advanced-modules)
    *   [Loyalty System](#loyalty-system)
    *   [Inventory Audit](#inventory-audit)
    *   [Promotions Engine](#promotions-engine)
    *   [Returns Management](#returns-management)
3.  [Reference Tables](#3-reference-tables)

---

## 1. Core Entities

### Table: `customer`
**Role**: Stores comprehensive customer profile information and lifecycle metrics.

**Relationships**:
*   **One-to-Many** with `orders` (One customer can place multiple orders).
*   **One-to-One** with `customer_loyalty` (Each customer has exactly one loyalty record).
*   **One-to-Many** with `promotion_usage` (A customer can use multiple promotions over time).

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `customer_id` | `INT` | Primary Key. Unique identifier for the customer. |
| `full_name` | `VARCHAR(100)` | Customer's full legal name. |
| `email` | `VARCHAR(100)` | Unique email address. Validated via Regex pattern. |
| `phone` | `VARCHAR(20)` | Contact phone number. |
| `shipping_address`| `VARCHAR(255)`| Default shipping location. |
| `is_active` | `BOOLEAN` | Soft deletion flag (True = Active). |
| `total_lifetime_value` | `DECIMAL(12,2)` | Computed total of all completed orders (Automation). |
| `last_purchase_date`| `DATETIME` | Timestamp of the most recent order. |

### Table: `product`
**Role**: The central catalog of items available for sale.

**Relationships**:
*   **Many-to-One** with `product_category` (Many products belong to one category).
*   **One-to-One** with `inventory` (Each product has one inventory record).
*   **One-to-Many** with `order_item` (A product can appear in many order lines).
*   **One-to-Many** with `inventory_log` (Tracks history for this product).

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `product_id` | `INT` | Primary Key. Unique item identifier. |
| `product_name` | `VARCHAR(255)`| Name of the product (Unique). |
| `category_id` | `INT` | Foreign Key linking to `product_category`. |
| `sku` | `VARCHAR(50)` | Stock Keeping Unit (Unique inventory code). |
| `price` | `DECIMAL(10,2)` | Selling price to the customer. |
| `cost_price` | `DECIMAL(10,2)` | Acquisition cost (used for margin analysis). |
| `rating` | `DECIMAL(3,2)` | Average customer rating (0.00 - 5.00). |
| `review_count` | `INT` | Total number of reviews received. |
| `is_active` | `BOOLEAN` | Status flag for catalog visibility. |

### Table: `inventory`
**Role**: Tracks real-time stock levels, reservations, and reorder triggers.

**Relationships**:
*   **One-to-One** with `product` (Links directly to the product definition).

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `inventory_id` | `INT` | Primary Key. |
| `product_id` | `INT` | Foreign Key (One-to-One with Product). |
| `quantity_on_hand`| `INT` | Total physical stock in the warehouse. |
| `quantity_reserved`| `INT` | Stock locked for pending orders but not yet shipped. |
| `quantity_available`| `INT` | **Virtual Column**. Calculated as (`on_hand` - `reserved`). |
| `reorder_point` | `INT` | Threshold quantity to trigger a low-stock alert. |
| `reorder_quantity`| `INT` | Suggested amount to purchase when restocking. |

### Table: `inventory_batch`
**Role**: Tracks incoming shipments of stock for FIFO/LIFO management (Future proofing) and supplier tracking.

**Relationships**:
*   **Many-to-One** with `product`.
*   **Many-to-One** with `suppliers`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `batch_id` | `INT` | Primary Key. |
| `batch_number` | `VARCHAR(50)` | Supplier provided batch/lot code. |
| `product_id` | `INT` | Foreign Key to `product`. |
| `supplier_id` | `INT` | Foreign Key to `suppliers`. |
| `quantity_received`| `INT` | Original amount in this batch. |
| `quantity_remaining`| `INT` | Current amount left. |
| `expiration_date` | `DATE` | For perishable goods. |
| `received_date` | `DATETIME` | When the batch was received. |

### Table: `orders`
**Role**: The central header record for a customer transaction.

**Relationships**:
*   **Many-to-One** with `customer` (Belongs to one customer).
*   **One-to-Many** with `order_item` (Contains multiple line items).
*   **One-to-One** with `shipping_info` (Has one set of shipping details).
*   **One-to-Many** with `promotion_usage` (Can apply promotions).
*   **One-to-Many** with `returns` (An order can have return requests).
*   **One-to-Many** with `loyalty_transactions` (Points earned/spent).

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `order_id` | `INT` | Primary Key. Internal System ID. |
| `order_number` | `VARCHAR(50)` | Public-facing unique Order Reference (e.g., ORD-2025-X). |
| `customer_id` | `INT` | Foreign Key linking to the purchasing Customer. |
| `order_date` | `DATETIME` | Timestamp when the order was placed. |
| `total_amount` | `DECIMAL(10,2)` | Final payable amount (Subtotal + Tax + Ship - Discount). |
| `order_status` | `ENUM` | Flow: Pending -> Processing -> Shipped -> Delivered. |
| `payment_status` | `ENUM` | Financial state (e.g., Paid, Refunded). |
| `shipping_method` | `VARCHAR(50)` | Selected delivery type (Standard, Express). |

### Table: `shipping_info`
**Role**: Detailed logistics information for an order. Separated to keep the Orders table clean.

**Relationships**:
*   **One-to-One** with `orders`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `shipping_id` | `INT` | Primary Key. |
| `order_id` | `INT` | Foreign Key to Orders. |
| `tracking_number` | `VARCHAR(100)`| Carrier tracking code. |
| `carrier` | `VARCHAR(50)` | Logistics provider (e.g., FedEx, DHL). |
| `shipping_address`| `JSON` | Snapshot of address at time of shipping. |
| `estimated_delivery_date` | `DATETIME` | ETA. |
| `actual_delivery_date`| `DATETIME` | When the order was actually delivered. |

### Table: `order_item`
**Role**: Resolves the Many-to-Many relationship between Orders and Products.

**Relationships**:
*   **Many-to-One** with `orders` (Part of an order).
*   **Many-to-One** with `product` (References a specific product).

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `order_item_id` | `INT` | Primary Key. |
| `order_id` | `INT` | Foreign Key linking to the Order header. |
| `product_id` | `INT` | Foreign Key linking to the Product. |
| `quantity` | `INT` | Number of units purchased. |
| `unit_price` | `DECIMAL(10,2)` | Price per unit **at the time of purchase** (Snapshot). |

---

## 2. Advanced Modules

### Loyalty System

**Table: `customer_loyalty`**

**Relationships**:
*   **One-to-One** with `customer`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `loyalty_id` | `INT` | Primary Key. |
| `customer_id` | `INT` | Foreign Key (One-to-One). |
| `loyalty_tier` | `ENUM` | Current Level (Bronze, Silver, Gold, Platinum). |
| `loyalty_points`| `INT` | Current spendable points balance. |
| `total_spent` | `DECIMAL` | Cumulative spending used for tier calculation. |

**Table: `loyalty_transactions`**

**Relationships**:
*   **Many-to-One** with `customer`.
*   **Many-to-One** with `orders` (Optional link to the order that generated/spent points).

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `transaction_id`| `INT` | Primary Key. |
| `customer_id` | `INT` | Foreign Key to `customer`. |
| `order_id` | `INT` | Foreign Key to `orders` (nullable). |
| `points_change` | `INT` | Positive for earning, Negative for redemption. |
| `transaction_type`| `ENUM` | Earned, Redeemed, Expired, Adjusted. |
| `transaction_date`| `DATETIME` | When the transaction occurred. |

### Inventory Audit & Monitoring

**Table: `inventory_log`**

**Relationships**:
*   **Many-to-One** with `product`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `log_id` | `INT` | Primary Key. |
| `product_id` | `INT` | Foreign Key linking to the modified product. |
| `quantity_change` | `INT` | The delta applied (e.g., -5 for a sale, +100 for restock). |
| `transaction_type`| `ENUM` | Source of change: ORDER, RESTOCK, RETURN, ADJUSTMENT. |
| `reference_id` | `INT` | ID of the source entity (Order ID or Batch ID). |
| `previous_quantity`| `INT` | Snapshot before update (Debugging). |
| `new_quantity` | `INT` | Snapshot after update (Debugging). |
| `timestamp` | `DATETIME` | When the change occurred. |

**Table: `low_stock_alerts`**
**Role**: Active alerts generated by triggers when stock falls below reorder points.

**Relationships**:
*   **Many-to-One** with `product`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `alert_id` | `INT` | Primary Key. |
| `product_id` | `INT` | Foreign Key to `product`. |
| `current_stock` | `INT` | Stock level at the time of alert. |
| `reorder_point` | `INT` | The threshold that was breached. |
| `alert_level` | `ENUM` | INFO, WARNING, CRITICAL. |
| `message` | `VARCHAR` | Auto-generated alert text. |
| `timestamp` | `DATETIME` | When the alert was generated. |
| `resolved` | `BOOLEAN` | Status if the alert has been addressed. |
| `resolved_by` | `VARCHAR(100)` | User who resolved the alert (nullable). |

### Promotions Engine

**Table: `promotions`**

**Relationships**:
*   **One-to-Many** with `promotion_usage`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `promotion_id` | `INT` | Primary Key. |
| `promotion_code`| `VARCHAR(50)` | The code typed by user (e.g., SAVE20). Unique. |
| `promotion_type`| `ENUM` | Logic type: Percentage, Fixed Amount, Free Shipping. |
| `discount_value`| `DECIMAL` | The numeric value (e.g., 20.00 could be $20 or 20%). |
| `valid_from` | `DATETIME` | Start date/time for the promotion. |
| `valid_to` | `DATETIME` | Expiration timestamp. |
| `is_active` | `BOOLEAN` | Whether the promotion is currently active. |

**Table: `promotion_usage`**
**Role**: Links a specific order to the promotion used, preventing abuse and tracking ROI.

**Relationships**:
*   **Many-to-One** with `promotions`.
*   **Many-to-One** with `orders`.
*   **Many-to-One** with `customer`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `usage_id` | `INT` | Primary Key. |
| `promotion_id` | `INT` | Foreign Key to `promotions`. |
| `order_id` | `INT` | The order usage occurred in. |
| `customer_id` | `INT` | The customer who used the promotion. |
| `discount_applied`| `DECIMAL` | The actual dollar amount saved. |
| `usage_date` | `DATETIME` | When the promotion was applied. |

### Returns Management

**Table: `returns`**

**Relationships**:
*   **Many-to-One** with `orders` (Links return to original purchase).
*   **Many-to-One** with `customer`.
*   **One-to-Many** with `return_items`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `return_id` | `INT` | Primary Key. |
| `order_id` | `INT` | Foreign Key to the original Order. |
| `customer_id` | `INT` | Foreign Key to the Customer. |
| `return_date` | `DATETIME` | Date the return was initiated. |
| `return_reason` | `TEXT` | Customer provided reason for return. |
| `return_status` | `ENUM` | Requested, Approved, Rejected, Refunded. |
| `refund_amount` | `DECIMAL` | The amount to be refunded. |

**Table: `return_items`**

**Relationships**:
*   **Many-to-One** with `returns` (Part of a return request).
*   **Many-to-One** with `product`.

| Variable Name | Data Type | Description |
| :--- | :--- | :--- |
| `return_item_id`| `INT` | Primary Key. |
| `return_id` | `INT` | Foreign Key to the Return header. |
| `product_id` | `INT` | Foreign Key to the Product being returned. |
| `quantity_returned`| `INT` | Number of units returned. |
| `restock_eligible`| `BOOLEAN` | If True, items are added back to inventory. |

---

## 3. Reference Tables

| Table | Variable | Type | Relationship | Description |
| :--- | :--- | :--- | :--- | :--- |
| `product_category` | `category_name` | `VARCHAR` | **One-to-Many** with `product` | Unique name of product group. |
| `suppliers` | `supplier_name` | `VARCHAR` | **One-to-Many** with `inventory_batch` | Vendor name for inventory sourcing. |
| `shipping_info` | `tracking_number` | `VARCHAR` | **One-to-One** with `orders` | Carrier tracking code. |
