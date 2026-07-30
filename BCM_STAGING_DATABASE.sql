-- =========================================================
-- BCM NEXUS — STAGING & STAR SCHEMA PIPELINE
-- =========================================================
-- Purpose: Flattens the raw Magento tables (created by the
-- extraction script) into clean staging tables, then builds
-- the final dimension and fact tables (star schema) used for
-- Power BI reporting.
--
-- =========================================================
-- BEFORE RUNNING — READ THIS:
-- This script references TWO databases using placeholder
-- names. Before pasting into phpMyAdmin, use Find & Replace
-- (Ctrl+H in most text editors, including VS Code) to swap
-- these placeholders for your own database names:
--
--   SOURCE_DB   ->  the database holding your raw Magento
--                   extract (created by 01_extraction.sql)
--
--   STAGING_DB  ->  the database where staging + star schema
--                   tables should be created
--
-- Example: if your databases are named "son_bcm" and
-- "staging_bcm", replace every SOURCE_DB with son_bcm and
-- every STAGING_DB with staging_bcm before running.
--
-- Tip: replace STAGING_DB first, then SOURCE_DB — this avoids
-- accidentally matching partial text if your chosen names
-- happen to overlap.
-- =========================================================


-- =========================================================
-- STAGE 1: STAGING TABLES
-- Flattens raw Magento tables into clean, one-row-per-entity
-- tables. Nothing here is optimised for reporting yet — that
-- happens in Stage 2 below.
-- =========================================================

DROP TABLE IF EXISTS
    STAGING_DB.bcm_stg_customers,
    STAGING_DB.bcm_stg_customer_address,
    STAGING_DB.bcm_stg_orders,
    STAGING_DB.bcm_stg_categories,
    STAGING_DB.bcm_stg_order_items,
    STAGING_DB.bcm_stg_products,
    STAGING_DB.bcm_stg_product_category;


-- --- CUSTOMERS ---
-- One row per customer. Resolves group name and classifies
-- the account relationship (Master / Subaccount / Standalone).
-- No personal details (name, email, DOB) are included, by
-- design, for privacy.
CREATE TABLE STAGING_DB.bcm_stg_customers AS
SELECT
    c.entity_id AS magento_customer_id,
    TRIM(cg.customer_group_code) AS customer_group_name,
    c.group_id AS customer_group_id,
    CASE
        WHEN sub.parent_customer_id IS NOT NULL THEN 'Subaccount'
        WHEN EXISTS (
            SELECT 1 FROM SOURCE_DB.bcm_cminds_multiuseraccounts_subaccount s2
            WHERE s2.parent_customer_id = c.entity_id
        ) THEN 'Master'
        ELSE 'Standalone'
    END AS account_type,
    sub.parent_customer_id AS parent_magento_customer_id,
    c.created_at,
    c.updated_at
FROM SOURCE_DB.bcm_customer_entity c
LEFT JOIN SOURCE_DB.bcm_customer_group cg
    ON cg.customer_group_id = c.group_id
LEFT JOIN SOURCE_DB.bcm_cminds_multiuseraccounts_subaccount sub
    ON sub.customer_id = c.entity_id;

/*
-- Sanity checks — see Section 5 of the project documentation
-- for the full list. Uncomment to run individually.

SELECT COUNT(*) FROM STAGING_DB.bcm_stg_customers;
SELECT * FROM STAGING_DB.bcm_stg_customers WHERE customer_group_name IS NULL;
SELECT account_type, COUNT(*) FROM STAGING_DB.bcm_stg_customers GROUP BY account_type;
*/


-- --- CUSTOMER ADDRESSES ---
-- Every address a customer has saved to their profile. Kept
-- separate from orders, since a customer can have multiple
-- addresses and an order's checkout address is not always a
-- saved one (see bcm_stg_orders below).
CREATE TABLE STAGING_DB.bcm_stg_customer_address AS
SELECT
    a.entity_id     AS magento_address_id,
    a.parent_id     AS magento_customer_id,
    a.region,
    a.city,
    a.postcode
FROM SOURCE_DB.bcm_customer_address_entity a;


-- --- ORDERS ---
-- One row per order. Enriched with the placing customer's
-- account type and the shipping address actually used at
-- checkout, plus a basic financial validity flag.
CREATE TABLE STAGING_DB.bcm_stg_orders AS
SELECT
    o.entity_id                    AS magento_order_id,
    o.customer_id                  AS magento_customer_id,
    cust.account_type              AS placed_by_account_type,
    o.status                       AS order_status,
    o.created_at,
    o.updated_at,
    o.total_qty_ordered,
    o.subtotal,
    o.shipping_amount,
    o.shipping_tax_amount,
    o.discount_amount,
    o.coupon_code,
    o.grand_total,
    oa.region                      AS shipping_region,
    oa.city                        AS shipping_city,
    oa.postcode                    AS shipping_postcode,
    CASE
        WHEN o.grand_total IS NULL OR o.grand_total < 0 THEN 'Invalid'
        WHEN o.subtotal IS NULL OR o.subtotal < 0 THEN 'Invalid'
        ELSE 'Valid'
    END                             AS financials_check
FROM SOURCE_DB.bcm_sales_order o
LEFT JOIN STAGING_DB.bcm_stg_customers cust
    ON cust.magento_customer_id = o.customer_id
LEFT JOIN SOURCE_DB.bcm_sales_order_address oa
    ON oa.parent_id = o.entity_id AND oa.address_type = 'shipping';

/*
-- Check for orders with no resolvable shipping address
SELECT o.magento_order_id, o.order_status, o.grand_total, o.total_qty_ordered
FROM STAGING_DB.bcm_stg_orders o
WHERE o.shipping_postcode IS NULL;
*/


-- --- ORDER ITEMS ---
-- One row per order line item. Kept lean/fact-shaped on
-- purpose — descriptive product details (name, supplier, etc.)
-- live in the product dimension instead, not duplicated here.
CREATE TABLE STAGING_DB.bcm_stg_order_items AS
SELECT
    oi.item_id          AS magento_order_item_id,
    oi.order_id          AS magento_order_id,
    oi.product_id         AS magento_product_id,
    oi.qty_ordered,
    oi.base_cost,
    CASE
        WHEN oi.base_cost IS NULL THEN 'No'
        ELSE 'Yes'
    END                    AS has_cost_data
FROM SOURCE_DB.bcm_sales_order_item oi;


-- --- CATEGORIES ---
-- One row per category. Flattens the category NAME (an EAV
-- attribute — attribute_id 42 in this Magento instance) onto
-- the category hierarchy table.
CREATE TABLE STAGING_DB.bcm_stg_categories AS
SELECT
    ce.entity_id      AS magento_category_id,
    ce.parent_id      AS magento_parent_category_id,
    ce.level,
    ce.path,
    MAX(CASE WHEN cv.attribute_id = 42 THEN cv.value END) AS category_name
FROM SOURCE_DB.bcm_catalog_category_entity ce
LEFT JOIN SOURCE_DB.bcm_catalog_category_entity_varchar cv
    ON cv.entity_id = ce.entity_id
GROUP BY ce.entity_id, ce.parent_id, ce.level, ce.path;


-- --- PRODUCT <-> CATEGORY LINK ---
-- Preserves the many-to-many relationship between products
-- and categories (a product can sit in more than one category).
CREATE TABLE STAGING_DB.bcm_stg_product_category AS
SELECT
    cp.product_id  AS magento_product_id,
    cp.category_id AS magento_category_id,
    cp.position
FROM SOURCE_DB.bcm_catalog_category_product cp;


-- --- PRODUCTS ---
-- One row per product. Flattens name, price, cost, weight,
-- shipping cost, and supplier (all EAV attributes) and
-- resolves each simple product's configurable parent, if any.
--
-- Attribute ID reference for this Magento instance:
--   70  = product name (varchar)
--   74  = price (decimal)
--   78  = cost (decimal)
--   79  = weight (decimal)
--   189 = shipping cost (decimal)
--   174 = supplier (int — dropdown/select attribute; value is
--         currently a numeric option_id, not a readable name)
CREATE TABLE STAGING_DB.bcm_stg_products AS
SELECT
    pe.entity_id                                                     AS magento_product_id,
    pe.sku,
    pe.type_id                                                        AS product_type,
    sl.parent_id                                                      AS magento_parent_product_id,
    MAX(CASE WHEN v.attribute_id = 70  THEN v.value END)             AS product_name,
    MAX(CASE WHEN d.attribute_id = 74  THEN d.value END)             AS price,
    MAX(CASE WHEN d.attribute_id = 78  THEN d.value END)             AS cost,
    MAX(CASE WHEN d.attribute_id = 79  THEN d.value END)             AS weight,
    MAX(CASE WHEN d.attribute_id = 189 THEN d.value END)             AS shipping_cost,
    MAX(CASE WHEN i.attribute_id = 174 THEN i.value END)             AS supplier_id
FROM SOURCE_DB.bcm_catalog_product_entity pe
LEFT JOIN SOURCE_DB.bcm_catalog_product_entity_varchar v
    ON v.entity_id = pe.entity_id AND v.store_id = 0
LEFT JOIN SOURCE_DB.bcm_catalog_product_entity_decimal d
    ON d.entity_id = pe.entity_id
LEFT JOIN SOURCE_DB.bcm_catalog_product_entity_int i
    ON i.entity_id = pe.entity_id
LEFT JOIN SOURCE_DB.bcm_catalog_product_super_link sl
    ON sl.product_id = pe.entity_id
GROUP BY pe.entity_id, pe.sku, pe.type_id, sl.parent_id;


-- =========================================================
-- STAGE 2: DIMENSION & FACT TABLES (star schema)
-- Assigns a surrogate key to every dimension, resolves
-- self-referencing hierarchies (master/subaccount, product
-- parent/child, category hierarchy), then rebuilds the fact
-- tables to reference those surrogate keys instead of raw
-- Magento IDs.
-- =========================================================

DROP TABLE IF EXISTS
    STAGING_DB.bcm_dim_customers,
    STAGING_DB.bcm_dim_products,
    STAGING_DB.bcm_dim_categories,
    STAGING_DB.bcm_fact_orders,
    STAGING_DB.bcm_fact_order_items,
    STAGING_DB.bcm_bridge_product_category;


-- --- DIM CUSTOMERS ---
-- Assigns a fresh surrogate key (customer_key) independent of
-- Magento's own ID, then resolves each subaccount's master
-- account via a self-join (parent_customer_key).
CREATE TABLE STAGING_DB.bcm_dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY magento_customer_id) AS customer_key,
    magento_customer_id,
    customer_group_name,
    customer_group_id,
    account_type,
    parent_magento_customer_id,
    created_at,
    updated_at
FROM STAGING_DB.bcm_stg_customers;

ALTER TABLE STAGING_DB.bcm_dim_customers ADD COLUMN parent_customer_key INT;

UPDATE STAGING_DB.bcm_dim_customers child
JOIN STAGING_DB.bcm_dim_customers parent
    ON parent.magento_customer_id = child.parent_magento_customer_id
SET child.parent_customer_key = parent.customer_key;


-- --- DIM PRODUCTS ---
-- Same surrogate key + self-join pattern, applied to the
-- configurable/simple product hierarchy.
CREATE TABLE STAGING_DB.bcm_dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY magento_product_id) AS product_key,
    magento_product_id,
    sku,
    product_type,
    product_name,
    price,
    cost,
    weight,
    shipping_cost,
    supplier_id,
    magento_parent_product_id
FROM STAGING_DB.bcm_stg_products;

ALTER TABLE STAGING_DB.bcm_dim_products ADD COLUMN parent_product_key INT;

UPDATE STAGING_DB.bcm_dim_products child
JOIN STAGING_DB.bcm_dim_products parent
    ON parent.magento_product_id = child.magento_parent_product_id
SET child.parent_product_key = parent.product_key;


-- --- DIM CATEGORIES ---
-- Same surrogate key + self-join pattern, applied to the
-- category hierarchy.
CREATE TABLE STAGING_DB.bcm_dim_categories AS
SELECT
    ROW_NUMBER() OVER (ORDER BY magento_category_id) AS category_key,
    magento_category_id,
    category_name,
    magento_parent_category_id,
    level,
    path
FROM STAGING_DB.bcm_stg_categories;

ALTER TABLE STAGING_DB.bcm_dim_categories ADD COLUMN parent_category_key INT;

UPDATE STAGING_DB.bcm_dim_categories child
JOIN STAGING_DB.bcm_dim_categories parent
    ON parent.magento_category_id = child.magento_parent_category_id
SET child.parent_category_key = parent.category_key;


-- --- FACT ORDERS ---
-- Rebuilds bcm_stg_orders with the raw customer ID replaced
-- by the resolved customer_key, ready to relate to
-- bcm_dim_customers in Power BI.
CREATE TABLE STAGING_DB.bcm_fact_orders AS
SELECT
    o.magento_order_id,
    c.customer_key,
    o.placed_by_account_type,
    o.order_status,
    o.created_at,
    o.updated_at,
    o.total_qty_ordered,
    o.subtotal,
    o.shipping_amount,
    o.shipping_tax_amount,
    o.discount_amount,
    o.coupon_code,
    o.grand_total,
    o.shipping_region,
    o.shipping_city,
    o.shipping_postcode,
    o.financials_check
FROM STAGING_DB.bcm_stg_orders o
LEFT JOIN STAGING_DB.bcm_dim_customers c
    ON c.magento_customer_id = o.magento_customer_id;


-- --- FACT ORDER ITEMS ---
-- Resolves the raw product ID to product_key. A NULL
-- product_key here is expected (not a bug) when a product has
-- since been deleted from the catalogue — history is preserved
-- deliberately by not enforcing a foreign key on this column.
CREATE TABLE STAGING_DB.bcm_fact_order_items AS
SELECT
    oi.magento_order_item_id,
    o.magento_order_id,
    p.product_key,
    oi.qty_ordered,
    oi.base_cost,
    oi.has_cost_data
FROM STAGING_DB.bcm_stg_order_items oi
LEFT JOIN STAGING_DB.bcm_dim_products p
    ON p.magento_product_id = oi.magento_product_id
LEFT JOIN STAGING_DB.bcm_stg_orders o
    ON o.magento_order_id = oi.magento_order_id;


-- --- BRIDGE: PRODUCT <-> CATEGORY ---
-- Resolves the many-to-many product/category link into
-- surrogate keys, ready to sit between bcm_dim_products and
-- bcm_dim_categories in the Power BI model.
CREATE TABLE STAGING_DB.bcm_bridge_product_category AS
SELECT
    p.product_key,
    cat.category_key,
    pc.position
FROM STAGING_DB.bcm_stg_product_category pc
LEFT JOIN STAGING_DB.bcm_dim_products p
    ON p.magento_product_id = pc.magento_product_id
LEFT JOIN STAGING_DB.bcm_dim_categories cat
    ON cat.magento_category_id = pc.magento_category_id;

-- =========================================================
-- END OF PIPELINE
-- Your star schema is now ready: bcm_dim_customers,
-- bcm_dim_products, bcm_dim_categories, bcm_fact_orders,
-- bcm_fact_order_items, bcm_bridge_product_category.
-- Connect Power BI to STAGING_DB and import these six tables.
-- =========================================================