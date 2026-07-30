-- DROP ALL TABLES IF EXISTS--
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


-- CREATE customer_entity--
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


-- CREATE customer_group--
CREATE TABLE bcm_customer_group (
    customer_group_id INT NOT NULL,
    customer_group_code VARCHAR(32) NOT NULL,
    PRIMARY KEY (customer_group_id)
);

INSERT INTO bcm_customer_group
SELECT customer_group_id, customer_group_code
FROM bcm.customer_group;


-- CREATE customer_address_entity--
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

INSERT INTO bcm_customer_address_entity
SELECT entity_id, parent_id, region, city, postcode, created_at DATETIME, updated_at DATETIME
FROM bcm.customer_address_entity;

-- CREATE cminds_multiuseraccounts_subaccount table--
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


-- CREATE sales_order table--
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
SELECT entity_id, customer_id, customer_group_id, status, total_qty_ordered, subtotal, shipping_amount,shipping_tax_amount,  discount_amount, 
coupon_code, grand_total, shipping_address_id, created_at, updated_at
FROM bcm.sales_order;

-- CREATE sales_order_address table --
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


-- CREATE sales_order_item table --
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


-- CREATE catalog_product_entity table--
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


-- CREATE eav_attribute table--
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


-- CREATE eav_attribute_option table--
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

-- CREATE eav_attribute_option_value table--
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

-- CREATE catalog_product_entity_decimal table--
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

-- CREATE catalog_product_entity_varchar table--
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

-- CREATE catalog_product_entity_int table--
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

-- CREATE catalog_product_super_link table--
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

-- CREATE catalog_category_entity table--
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


DROP TABLE IF EXISTS bcm_catalog_category_entity_varchar;

-- CREATE catalog_category_entity_varchar table--
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



-- CREATE catalog_category_product table--
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
