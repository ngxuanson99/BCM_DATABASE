    DROP TABLE IF EXISTS 
        bcm_stg_customers,
        bcm_stg_customer_address,
        bcm_stg_orders,
        bcm_stg_order_address,
        bcm_stg_categories,
        bcm_stg_order_items,
        bcm_stg_products,
        bcm_stg_product_category;

    -- CREATE CUSTOMER TABLE --
    CREATE TABLE staging_bcm.bcm_stg_customers AS
    SELECT
        c.entity_id AS magento_customer_id,
        TRIM(cg.customer_group_code) AS customer_group_name,
        c.group_id AS customer_group_id,
        CASE
            WHEN sub.parent_customer_id IS NOT NULL THEN 'Subaccount'
            WHEN EXISTS (
                SELECT 1 FROM son_bcm.bcm_cminds_multiuseraccounts_subaccount s2
                WHERE s2.parent_customer_id = c.entity_id
            ) THEN 'Master'
            ELSE 'Standalone'
        END AS account_type,
        sub.parent_customer_id AS parent_magento_customer_id,
        c.created_at,
        c.updated_at
    FROM son_bcm.bcm_customer_entity c
    LEFT JOIN son_bcm.bcm_customer_group cg
        ON cg.customer_group_id = c.group_id
    LEFT JOIN son_bcm.bcm_cminds_multiuseraccounts_subaccount sub
        ON sub.customer_id = c.entity_id;

    /*
    -- Row count sanity check
    SELECT COUNT(*) FROM staging_bcm.bcm_stg_customers;

    -- Any customers with no group name resolved? (orphaned group_id)
    SELECT * FROM staging_bcm.bcm_stg_customers WHERE customer_group_name IS NULL;

    -- Quick look at the master/subaccount split
    SELECT account_type, COUNT(*) FROM staging_bcm.bcm_stg_customers GROUP BY account_type;
    */

    -- CREATE CUSTOMER ADDRESS TABLE --
    CREATE TABLE staging_bcm.bcm_stg_customer_address AS
    SELECT
        a.entity_id     AS magento_address_id,
        a.parent_id     AS magento_customer_id,
        a.region,
        a.city,
        a.postcode
    FROM son_bcm.bcm_customer_address_entity a;



    -- CUSTOMER ORDER TABLE --
    CREATE TABLE staging_bcm.bcm_stg_orders AS
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
    FROM son_bcm.bcm_sales_order o
    LEFT JOIN staging_bcm.bcm_stg_customers cust
        ON cust.magento_customer_id = o.customer_id
    LEFT JOIN son_bcm.bcm_sales_order_address oa
        ON oa.parent_id = o.entity_id AND oa.address_type = 'shipping';


    /* checking null results

    SELECT o.magento_order_id, o.order_status, o.grand_total, o.total_qty_ordered
    FROM staging_bcm.bcm_stg_orders o
    WHERE o.shipping_postcode IS NULL;

    */

    -- CREATE ORDER ITEMS TABLE -- 
    CREATE TABLE staging_bcm.bcm_stg_order_items AS
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
    FROM son_bcm.bcm_sales_order_item oi;


    -- CREATE CATEGORIES TABLE --
    CREATE TABLE staging_bcm.bcm_stg_categories AS
    SELECT
        ce.entity_id      AS magento_category_id,
        ce.parent_id      AS magento_parent_category_id,
        ce.level,
        ce.path,
        MAX(CASE WHEN cv.attribute_id = 42 THEN cv.value END) AS category_name
    FROM son_bcm.bcm_catalog_category_entity ce
    LEFT JOIN son_bcm.bcm_catalog_category_entity_varchar cv
        ON cv.entity_id = ce.entity_id
    GROUP BY ce.entity_id, ce.parent_id, ce.level, ce.path;


    -- Linking categories to product id -- 
    CREATE TABLE staging_bcm.bcm_stg_product_category AS
    SELECT
        cp.product_id  AS magento_product_id,
        cp.category_id AS magento_category_id,
        cp.position
    FROM son_bcm.bcm_catalog_category_product cp;


    -- CREATE PRODUCT TABLES -- 
    CREATE TABLE staging_bcm.bcm_stg_products AS
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
    FROM son_bcm.bcm_catalog_product_entity pe
    LEFT JOIN son_bcm.bcm_catalog_product_entity_varchar v
        ON v.entity_id = pe.entity_id AND v.store_id = 0
    LEFT JOIN son_bcm.bcm_catalog_product_entity_decimal d
        ON d.entity_id = pe.entity_id
    LEFT JOIN son_bcm.bcm_catalog_product_entity_int i
        ON i.entity_id = pe.entity_id
    LEFT JOIN son_bcm.bcm_catalog_product_super_link sl
        ON sl.product_id = pe.entity_id
    GROUP BY pe.entity_id, pe.sku, pe.type_id, sl.parent_id;










DROP TABLE IF EXISTS 
    bcm_dim_customers,
    bcm_dim_products,
    bcm_dim_categories,
    bcm_fact_orders,
    bcm_fact_order_items,
    bcm_bridge_product_category;

-- CREATE DIM CUSTOMER TABLE --
CREATE TABLE staging_bcm.bcm_dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY magento_customer_id) AS customer_key,
    magento_customer_id,
    customer_group_name,
    customer_group_id,
    account_type,
    parent_magento_customer_id,
    created_at,
    updated_at
FROM staging_bcm.bcm_stg_customers;


ALTER TABLE staging_bcm.bcm_dim_customers ADD COLUMN parent_customer_key INT;

UPDATE staging_bcm.bcm_dim_customers child
JOIN staging_bcm.bcm_dim_customers parent
    ON parent.magento_customer_id = child.parent_magento_customer_id
SET child.parent_customer_key = parent.customer_key;


-- customer_dim -- 
CREATE TABLE staging_bcm.bcm_dim_products AS
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
FROM staging_bcm.bcm_stg_products;

ALTER TABLE staging_bcm.bcm_dim_products ADD COLUMN parent_product_key INT;

UPDATE staging_bcm.bcm_dim_products child
JOIN staging_bcm.bcm_dim_products parent
    ON parent.magento_product_id = child.magento_parent_product_id
SET child.parent_product_key = parent.product_key;



-- dim categories -- 
CREATE TABLE staging_bcm.bcm_dim_categories AS
SELECT
    ROW_NUMBER() OVER (ORDER BY magento_category_id) AS category_key,
    magento_category_id,
    category_name,
    magento_parent_category_id,
    level,
    path
FROM staging_bcm.bcm_stg_categories;

ALTER TABLE staging_bcm.bcm_dim_categories ADD COLUMN parent_category_key INT;

UPDATE staging_bcm.bcm_dim_categories child
JOIN staging_bcm.bcm_dim_categories parent
    ON parent.magento_category_id = child.magento_parent_category_id
SET child.parent_category_key = parent.category_key;

-- fact orders -- 
CREATE TABLE staging_bcm.bcm_fact_orders AS
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
FROM staging_bcm.bcm_stg_orders o
LEFT JOIN staging_bcm.bcm_dim_customers c
    ON c.magento_customer_id = o.magento_customer_id;


-- fact_order_items --
CREATE TABLE staging_bcm.bcm_fact_order_items AS
SELECT
    oi.magento_order_item_id,
    o.magento_order_id,
    p.product_key,
    oi.qty_ordered,
    oi.base_cost,
    oi.has_cost_data
FROM staging_bcm.bcm_stg_order_items oi
LEFT JOIN staging_bcm.bcm_dim_products p
    ON p.magento_product_id = oi.magento_product_id
LEFT JOIN staging_bcm.bcm_stg_orders o
    ON o.magento_order_id = oi.magento_order_id;

-- bcm_bridge_product_category --
CREATE TABLE staging_bcm.bcm_bridge_product_category AS
SELECT
    p.product_key,
    cat.category_key,
    pc.position
FROM staging_bcm.bcm_stg_product_category pc
LEFT JOIN staging_bcm.bcm_dim_products p
    ON p.magento_product_id = pc.magento_product_id
LEFT JOIN staging_bcm.bcm_dim_categories cat
    ON cat.magento_category_id = pc.magento_category_id;