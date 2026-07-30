-- =========================================================
-- BCM NEXUS — RAW EXTRACTION SCRIPT
-- =========================================================
-- Purpose: Copies the relevant tables from the live Magento
-- database into an isolated working database, applying a
-- consistent "bcm_" table prefix. No data is transformed or
-- cleaned here — this is a faithful, untouched copy used as
-- the starting point for the staging/star-schema pipeline.
--
-- Source database : bcm            (live Magento database)
-- Target database : (this script's current database)
--
-- Run this script from within your target database in
-- phpMyAdmin (i.e. make sure your target database is selected
-- before running, since table names below are not
-- database-qualified).
-- =========================================================


-- ---------------------------------------------------------
-- DROP EXISTING TABLES (if re-running this script)
-- ---------------------------------------------------------
-- Tables are dropped in dependency order: tables with foreign
-- keys pointing to other tables are dropped first ("leaves"),
-- and tables nothing depends on anymore are dropped last
-- ("roots"). This avoids foreign key errors on re-run.
-- ---------------------------------------------------------
DROP TABLE IF EXISTS
    -- Leaves: nothing else depends on these
    bcm_cminds_multiuseraccounts_subaccount,
    bcm_customer_address_entity,
    bcm_sales_order_address,
    bcm_sales_order_item,
    bcm_catalog_product_super_link,
    bcm_catalog_product_entity_varchar,
    bcm_catalog_product_entity_decimal,
    bcm_catalog_product_entity_int,
    bcm_eav_attribute_option_value,
    bcm_catalog_category_product,
    bcm_catalog_category_entity_varchar,
    -- Next layer: depends on eav_attribute, but its own dependent is already gone
    bcm_eav_attribute_option,
    -- Now safe: their dependents above are already dropped
    bcm_sales_order,
    bcm_catalog_product_entity,
    bcm_catalog_category_entity,
    bcm_customer_entity,
    -- Roots: nothing references these anymore
    bcm_eav_attribute,
    bcm_customer_group;


-- =========================================================
-- CUSTOMERS
-- =========================================================

-- Base customer record: one row per customer.
-- group_id links to bcm_customer_group (created below).
CREATE TABLE bcm_customer_entity (
    entity_id INT NOT NULL,
    group_id INT NOT NULL,
    created_at DATETIME,
    updated_at DATETIME,
    PRIMARY KEY (entity_id)
);

INSERT INTO bcm_customer_entity
SELECT entity_id, group_id, created_at, updated_at
FROM bcm.customer_entity;


-- Lookup table: resolves a customer's numeric group_id
-- to a readable group code (e.g. "Retail", "Wholesale").
CREATE TABLE bcm_customer_group (
    customer_group_id INT NOT NULL,
    customer_group_code VARCHAR(32) NOT NULL,
    PRIMARY KEY (customer_group_id)
);

INSERT INTO bcm_customer_group
SELECT customer_group_id, customer_group_code
FROM bcm.customer_group;


-- Saved customer addresses. A customer can have multiple
-- addresses (billing, shipping, etc.) via parent_id.
CREATE TABLE bcm_customer_address_entity (
    entity_id INT NOT NULL,
    parent_id INT NOT NULL,
    region VARCHAR(255),
    city VARCHAR(255),
    postcode VARCHAR(10),
    created_at DATETIME,
    updated_at DATETIME,
    PRIMARY KEY (entity_id),
    FOREIGN KEY (parent_id) REFERENCES bcm_customer_entity(entity_id)
);

-- NOTE: column list is created_at, updated_at (not "created_at DATETIME" —
-- a data type keyword does not belong inside a SELECT list).
INSERT INTO bcm_customer_address_entity
SELECT entity_id, parent_id, region, city, postcode, created_at, updated_at
FROM bcm.customer_address_entity;


-- Master/subaccount relationships. Identifies which customers
-- are subaccounts of a master account (BCM allows one master
-- account to manage multiple subaccounts).
CREATE TABLE bcm_cminds_multiuseraccounts_subaccount (
    entity_id INT NOT NULL,
    customer_id INT NOT NULL,
    parent_customer_id INT NOT NULL,
    PRIMARY KEY (entity_id),
    FOREIGN KEY (customer_id) REFERENCES bcm_customer_entity(entity_id),
    FOREIGN KEY (parent_customer_id) REFERENCES bcm_customer_entity(entity_id)
);

INSERT INTO bcm_cminds_multiuseraccounts_subaccount
SELECT entity_id, customer_id, parent_customer_id
FROM bcm.cminds_multiuseraccounts_subaccount;


-- =========================================================
-- ORDERS
-- =========================================================

-- Core order record. customer_id is nullable to support
-- guest checkout orders (no customer account attached).
CREATE TABLE bcm_sales_order (
    entity_id INT NOT NULL,
    customer_id INT NULL,
    customer_group_id INT,
    status VARCHAR(32),
    total_qty_ordered INT,
    subtotal DECIMAL(12,2),
    shipping_amount DECIMAL(12,2),
    shipping_tax_amount DECIMAL(12,2),
    discount_amount DECIMAL(12,2),
    coupon_code VARCHAR(255),
    grand_total VARCHAR(255),
    shipping_address_id INT NOT NULL,
    created_at DATETIME,
    updated_at DATETIME,
    PRIMARY KEY (entity_id),
    FOREIGN KEY (customer_id) REFERENCES bcm_customer_entity(entity_id)
);

INSERT INTO bcm_sales_order
SELECT entity_id, customer_id, customer_group_id, status, total_qty_ordered, subtotal, shipping_amount, shipping_tax_amount, discount_amount,
coupon_code, grand_total, shipping_address_id, created_at, updated_at
FROM bcm.sales_order;


-- Addresses actually used on an order (may differ from a
-- customer's saved address — e.g. guest or one-time addresses).
-- address_type distinguishes 'shipping' vs 'billing' rows.
CREATE TABLE bcm_sales_order_address (
    entity_id INT NOT NULL,
    parent_id INT NOT NULL,
    customer_address_id INT NOT NULL,
    region VARCHAR(255),
    region_id INT,
    city VARCHAR(255),
    postcode VARCHAR(20),
    country_id VARCHAR(10),
    address_type VARCHAR(50),
    PRIMARY KEY (entity_id),
    FOREIGN KEY (parent_id) REFERENCES bcm_sales_order(entity_id)
);

INSERT INTO bcm_sales_order_address
SELECT entity_id, parent_id, customer_address_id, region, region_id, city, postcode, country_id, address_type
FROM bcm.sales_order_address;


-- Order line items. product_id is a logical (not enforced)
-- foreign key to catalog_product_entity — deliberately not
-- constrained, so historical order lines survive even if the
-- referenced product is later deleted from the catalogue.
CREATE TABLE bcm_sales_order_item (
    item_id INT NOT NULL,
    order_id INT NOT NULL,
    parent_item_id INT,
    quote_item_id INT,
    product_id INT COMMENT 'Logical Foreign Key to catalog_product_entity.entity_id',
    product_type VARCHAR(50),
    sku VARCHAR(255),
    name VARCHAR(255),
    qty_ordered INT,
    base_cost DECIMAL(12,2),
    supplier VARCHAR(255),
    PRIMARY KEY (item_id),
    FOREIGN KEY (order_id) REFERENCES bcm_sales_order(entity_id),
    INDEX idx_bcm_product_id (product_id)
);

INSERT INTO bcm_sales_order_item
SELECT item_id, order_id, parent_item_id, quote_item_id, product_id,
       product_type, sku, name, qty_ordered, base_cost, supplier
FROM bcm.sales_order_item;


-- =========================================================
-- PRODUCTS (Magento EAV structure)
-- =========================================================
-- Product attributes (name, price, cost, etc.) are NOT stored
-- as columns here — Magento stores them separately in
-- attribute "value" tables below (varchar / decimal / int),
-- keyed by attribute_id. These get flattened into readable
-- columns later, in the staging layer.
-- =========================================================

-- Base product record: SKU and product type only.
-- type_id distinguishes 'simple' vs 'configurable' products.
CREATE TABLE bcm_catalog_product_entity (
    entity_id INT NOT NULL,
    type_id VARCHAR(50),
    sku VARCHAR(64),
    has_options INT,
    required_options INT,
    PRIMARY KEY (entity_id)
);

INSERT INTO bcm_catalog_product_entity
SELECT entity_id, type_id, sku, has_options, required_options
FROM bcm.catalog_product_entity;


-- Attribute definitions (what each attribute_id actually means,
-- e.g. attribute_id 70 = "name"). Shared across products and
-- categories.
CREATE TABLE bcm_eav_attribute (
    attribute_id INT NOT NULL,
    entity_type_id INT NOT NULL,
    attribute_code VARCHAR(255),
    frontend_label VARCHAR(255),
    PRIMARY KEY (attribute_id)
);

INSERT INTO bcm_eav_attribute
SELECT attribute_id, entity_type_id, attribute_code, frontend_label
FROM bcm.eav_attribute;


-- Dropdown/select attribute options (e.g. the list of possible
-- suppliers). Referenced by attribute value tables below when
-- an attribute is a dropdown rather than free text.
CREATE TABLE bcm_eav_attribute_option (
    option_id INT NOT NULL,
    attribute_id INT NOT NULL,
    sort_order INT,
    PRIMARY KEY (option_id),
    FOREIGN KEY (attribute_id) REFERENCES bcm_eav_attribute(attribute_id)
);

INSERT INTO bcm_eav_attribute_option
SELECT option_id, attribute_id, sort_order
FROM bcm.eav_attribute_option;


-- Readable label for each dropdown option (e.g. option_id 5
-- might resolve to the text "Supplier A").
CREATE TABLE bcm_eav_attribute_option_value (
    value_id INT NOT NULL,
    option_id INT NOT NULL,
    store_id INT NOT NULL,
    value VARCHAR(255),
    PRIMARY KEY (value_id),
    FOREIGN KEY (option_id) REFERENCES bcm_eav_attribute_option(option_id)
);

INSERT INTO bcm_eav_attribute_option_value
SELECT value_id, option_id, store_id, value
FROM bcm.eav_attribute_option_value;


-- Product attribute values — DECIMAL type (e.g. price, cost,
-- weight, shipping_cost). One row per attribute per product.
CREATE TABLE bcm_catalog_product_entity_decimal (
    value_id INT NOT NULL,
    attribute_id INT NOT NULL,
    entity_id INT NOT NULL,
    value DECIMAL(12,2),
    PRIMARY KEY (value_id),
    FOREIGN KEY (entity_id) REFERENCES bcm_catalog_product_entity(entity_id),
    FOREIGN KEY (attribute_id) REFERENCES bcm_eav_attribute(attribute_id)
);

INSERT INTO bcm_catalog_product_entity_decimal
SELECT value_id, attribute_id, entity_id, value
FROM bcm.catalog_product_entity_decimal;


-- Product attribute values — VARCHAR type (e.g. product name).
-- store_id = 0 represents the default/global value.
CREATE TABLE bcm_catalog_product_entity_varchar (
    value_id INT NOT NULL,
    attribute_id INT NOT NULL,
    store_id INT NOT NULL,
    entity_id INT NOT NULL,
    value VARCHAR(255),
    PRIMARY KEY (value_id),
    FOREIGN KEY (entity_id) REFERENCES bcm_catalog_product_entity(entity_id),
    FOREIGN KEY (attribute_id) REFERENCES bcm_eav_attribute(attribute_id)
);

INSERT INTO bcm_catalog_product_entity_varchar
SELECT value_id, attribute_id, store_id, entity_id, value
FROM bcm.catalog_product_entity_varchar;


-- Product attribute values — INT type (e.g. status, supplier
-- as a dropdown reference into eav_attribute_option).
CREATE TABLE bcm_catalog_product_entity_int (
    value_id INT NOT NULL,
    attribute_id INT NOT NULL,
    entity_id INT NOT NULL,
    value INT,
    PRIMARY KEY (value_id),
    FOREIGN KEY (entity_id) REFERENCES bcm_catalog_product_entity(entity_id),
    FOREIGN KEY (attribute_id) REFERENCES bcm_eav_attribute(attribute_id)
);

INSERT INTO bcm_catalog_product_entity_int
SELECT value_id, attribute_id, entity_id, value
FROM bcm.catalog_product_entity_int;


-- Links a "simple" product (a specific sellable variant, e.g.
-- Medium/Blue) to its "configurable" parent product (the
-- overall product concept, e.g. "Wheelchair Cushion").
CREATE TABLE bcm_catalog_product_super_link (
    link_id INT NOT NULL,
    product_id INT NOT NULL,
    parent_id INT NOT NULL,
    PRIMARY KEY (link_id),
    FOREIGN KEY (product_id) REFERENCES bcm_catalog_product_entity(entity_id),
    FOREIGN KEY (parent_id) REFERENCES bcm_catalog_product_entity(entity_id)
);

INSERT INTO bcm_catalog_product_super_link
SELECT link_id, product_id, parent_id
FROM bcm.catalog_product_super_link;


-- =========================================================
-- CATEGORIES (also EAV — category name is an attribute value,
-- not a native column)
-- =========================================================

-- Category hierarchy: parent_id, level, and path together
-- describe where each category sits in the tree. Category
-- NAME is not stored here — see bcm_catalog_category_entity_varchar.
CREATE TABLE bcm_catalog_category_entity (
    entity_id INT NOT NULL,
    parent_id INT,
    path VARCHAR(255),
    position INT,
    level INT,
    children_count INT,
    PRIMARY KEY (entity_id)
);

INSERT INTO bcm_catalog_category_entity
SELECT entity_id, parent_id, path, position, level, children_count
FROM bcm.catalog_category_entity;


-- Category attribute values — VARCHAR type. This is where the
-- actual category NAME lives (attribute_id 42 in this instance).
CREATE TABLE bcm_catalog_category_entity_varchar (
    value_id INT NOT NULL,
    entity_id INT NOT NULL,
    attribute_id INT NOT NULL,
    value VARCHAR(255),
    PRIMARY KEY (value_id),
    FOREIGN KEY (entity_id) REFERENCES bcm_catalog_category_entity(entity_id),
    FOREIGN KEY (attribute_id) REFERENCES bcm_eav_attribute(attribute_id)
);

INSERT INTO bcm_catalog_category_entity_varchar
SELECT value_id, entity_id, attribute_id, value
FROM bcm.catalog_category_entity_varchar;


-- Many-to-many link between products and categories.
-- A single product can belong to more than one category, and
-- vice versa, so this relationship is preserved as its own
-- table rather than flattened onto either side.
CREATE TABLE bcm_catalog_category_product (
    entity_id INT NOT NULL,
    category_id INT NOT NULL,
    product_id INT NOT NULL,
    position INT,
    PRIMARY KEY (entity_id),
    FOREIGN KEY (category_id) REFERENCES bcm_catalog_category_entity(entity_id),
    FOREIGN KEY (product_id) REFERENCES bcm_catalog_product_entity(entity_id)
);

INSERT INTO bcm_catalog_category_product
SELECT entity_id, category_id, product_id, position
FROM bcm.catalog_category_product;

-- =========================================================
-- END OF EXTRACTION SCRIPT
-- Next step: run the staging/star-schema pipeline script,
-- which flattens these raw tables into reporting-ready
-- dimension and fact tables.
-- =========================================================