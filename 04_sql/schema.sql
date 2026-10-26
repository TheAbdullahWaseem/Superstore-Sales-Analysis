-- ============================================================================
-- SUPERSTORE SALES ANALYSIS — DATABASE SCHEMA
-- Phase 7: SQL Analysis Setup
-- Author: Abdullah Waseem
-- Database: PostgreSQL (superstore_sql)
-- ============================================================================
-- This script loads the already-cleaned Superstore CSV (cleaned in the
-- Python phase) into PostgreSQL and restructures it into a normalized,
-- query-ready relational schema in three stages:
--   1. Staging table — flat, unnormalized mirror of the cleaned CSV
--   2. Normalized tables — customers, products, orders, order_items
--   3. Population — deduplicating and linking staging data into the
--      normalized structure
-- ============================================================================


-- ============================================================================
-- STAGE 1: STAGING TABLE
-- Flat landing table matching the cleaned CSV's structure exactly. Dates and
-- zip codes kept as TEXT to avoid format ambiguity (DD/MM/YYYY) and
-- leading-zero loss during import.
-- ============================================================================
CREATE TABLE superstore_staging (
    row_id INTEGER,
    order_id INTEGER,
    order_date TEXT,
    order_priority TEXT,
    order_quantity INTEGER,
    sales NUMERIC(12,2),
    discount NUMERIC(5,4),
    ship_mode TEXT,
    profit NUMERIC(12,2),
    unit_price NUMERIC(12,2),
    shipping_cost NUMERIC(12,2),
    customer_name TEXT,
    city TEXT,
    zip_code TEXT,
    state TEXT,
    region TEXT,
    customer_segment TEXT,
    product_category TEXT,
    product_sub_category TEXT,
    product_name TEXT,
    product_container TEXT,
    product_base_margin NUMERIC(6,4),
    ship_date TEXT,
    shipping_days INTEGER,
    profit_margin NUMERIC(12,8),
    year INTEGER,
    month INTEGER,
    month_name TEXT,
    quarter TEXT,
    day_of_week TEXT,
    is_profitable BOOLEAN,
    discount_band TEXT,
    sales_band TEXT
);

select count(*) from superstore_staging;


-- Check a few sample rows look right
SELECT * FROM superstore_staging LIMIT 5;

-- Confirm date columns still look like text in DD/MM/YYYY format (not garbled)
SELECT order_date, ship_date FROM superstore_staging LIMIT 5;

-- Find any dates where day appears to exceed 12 (proves DD/MM was used, not MM/DD)
SELECT order_date 
FROM superstore_staging 
WHERE order_date IS NOT NULL
ORDER BY order_date 
LIMIT 10;

-- Cross-check: count how many rows have order_date in ISO format vs anything unexpected
SELECT COUNT(*) FILTER (WHERE order_date ~ '^\d{4}-\d{2}-\d{2}$') AS iso_format_count,
       COUNT(*) AS total_rows
FROM superstore_staging;

-- Confirm numeric columns loaded correctly (not nulls, not zeros everywhere)
SELECT MIN(sales), MAX(sales), MIN(profit), MAX(profit), AVG(profit_margin) 
FROM superstore_staging;

-- Confirm no unexpected NULLs crept in anywhere important
SELECT COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_id,
       COUNT(*) FILTER (WHERE customer_name IS NULL) AS null_customer,
       COUNT(*) FILTER (WHERE order_date IS NULL) AS null_order_date
FROM superstore_staging;


-- ============================================================================
-- STAGE 2: NORMALIZED TABLE DEFINITIONS
-- Four related tables: customers, products, orders, order_items — enforcing
-- referential integrity via foreign keys.
-- ============================================================================

-- ============
-- Final Schema
-- ============

--customers

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    customer_name TEXT NOT NULL,
    city TEXT,
    state TEXT,
    region TEXT,
    customer_segment TEXT,
    zip_code TEXT
);

--products

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name TEXT NOT NULL,
    product_category TEXT,
    product_sub_category TEXT,
    product_container TEXT,
    product_base_margin NUMERIC(6,4)
);

--orders

CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    order_date DATE,
    ship_date DATE,
    shipping_days INTEGER,
    order_priority TEXT,
    ship_mode TEXT,
    year INTEGER,
    month INTEGER,
    month_name TEXT,
    quarter TEXT,
    day_of_week TEXT
);

--order_items

CREATE TABLE order_items (
    row_id INTEGER PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    order_quantity INTEGER,
    sales NUMERIC(12,2),
    discount NUMERIC(5,4),
    unit_price NUMERIC(12,2),
    shipping_cost NUMERIC(12,2),
    profit NUMERIC(12,2),
    profit_margin NUMERIC(12,8),
    is_profitable BOOLEAN,
    discount_band TEXT,
    sales_band TEXT
);


-- ============================================================================
-- STAGE 3: POPULATE NORMALIZED TABLES FROM STAGING
-- Deduplicates customers/products, converts text dates to proper DATE type,
-- and links orders/line items via foreign key lookups.
-- ============================================================================

-- ===========================
-- Order of population matters
-- ===========================

-- customers and products first (no dependencies), then orders (depends on
-- customers), then order_items (depends on both orders and products).

-- ==========================
-- Step 1: Populate customers
-- ==========================

INSERT INTO customers 
	(customer_name, city, state, region, customer_segment, zip_code)
SELECT DISTINCT ON (customer_name)
    customer_name, city, state, region, customer_segment, zip_code
FROM superstore_staging
ORDER BY customer_name;

-- =========================
-- Step 2: Populate products
-- =========================

INSERT INTO products 
	(product_name, product_category, product_sub_category, product_container, product_base_margin)
SELECT DISTINCT ON (product_name)
    product_name, product_category, product_sub_category, product_container, product_base_margin
FROM superstore_staging
ORDER BY product_name;

-- =======================
-- Step 3: Populate orders
-- =======================

INSERT INTO orders 
	(order_id, customer_id, order_date, ship_date, shipping_days, order_priority, ship_mode, year, 
	month, month_name, quarter, day_of_week)
SELECT DISTINCT ON (s.order_id)
    s.order_id,
    c.customer_id,
    TO_DATE(s.order_date, 'YYYY-MM-DD'),
    TO_DATE(s.ship_date, 'YYYY-MM-DD'),
    s.shipping_days,
    s.order_priority,
    s.ship_mode,
    s.year,
    s.month,
    s.month_name,
    s.quarter,
    s.day_of_week
FROM superstore_staging s
JOIN customers c ON s.customer_name = c.customer_name
ORDER BY s.order_id;

-- ============================
-- Step 4: Populate order_items
-- ============================

INSERT INTO order_items 
	(row_id, order_id, product_id, order_quantity, sales,
	discount, unit_price, shipping_cost, profit, 
	profit_margin, is_profitable, discount_band, sales_band)
SELECT 
    s.row_id,
    s.order_id,
    p.product_id,
    s.order_quantity,
    s.sales,
    s.discount,
    s.unit_price,
    s.shipping_cost,
    s.profit,
    s.profit_margin,
    s.is_profitable,
    s.discount_band,
    s.sales_band
FROM superstore_staging s
JOIN products p ON s.product_name = p.product_name;

-- ============
-- Verification
-- ============

select count(*) from customers;
select count(*) from products;
select count(*) from orders;
select count(*) from order_items;


SELECT COUNT(*) FILTER (WHERE customer_id IS NULL) AS orders_missing_customer
FROM orders;

SELECT COUNT(*) FILTER (WHERE product_id IS NULL) AS items_missing_product
FROM order_items;

-- ============================================================================
-- END OF SCHEMA
-- Verified row counts: customers = 795 | products = 1,263 | orders = 5,496 |
-- order_items = 8,399 | zero orphaned foreign keys
-- ============================================================================