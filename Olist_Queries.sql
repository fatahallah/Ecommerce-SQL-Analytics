/* 1. Check for duplicate order_id */
SELECT order_id, COUNT(*)
FROM olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*) > 1;

/* 2. Check for orphaned records in order_items */
SELECT COUNT(*)
FROM olist_order_items_dataset
WHERE order_id NOT IN (SELECT order_id FROM olist_orders_dataset);

/* 3. Customers <-> Orders relationship checks */
SELECT COUNT(*)
FROM olist_orders_dataset
WHERE customer_id NOT IN (SELECT customer_id FROM olist_customers_dataset);

SELECT COUNT(*)
FROM olist_customers_dataset
WHERE customer_id NOT IN (SELECT customer_id FROM olist_orders_dataset);

/* 4. Products <-> Order Items relationship checks */
SELECT COUNT(*)
FROM olist_order_items_dataset
WHERE product_id NOT IN (SELECT product_id FROM olist_products_dataset);

SELECT COUNT(*)
FROM olist_products_dataset
WHERE product_id NOT IN (SELECT product_id FROM olist_order_items_dataset);

/* 5. Customers table total count check */
SELECT
  (SELECT COUNT(*) FROM olist_customers_dataset) AS TotalCustomers,
  (SELECT COUNT(DISTINCT customer_id) FROM olist_orders_dataset) AS DistinctCustomersInOrders;

/* 6. Missing values in order date columns */
SELECT
  COUNT(*) AS total_orders,
  SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase,
  SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS null_approved,
  SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS null_carrier,
  SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_customer,
  SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS null_estimated
FROM olist_orders_dataset;

/* 7. Missing delivery dates by order_status */
SELECT
  order_status,
  COUNT(*) AS total_orders,
  SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_delivery_date
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;

/* 8. Investigate the 8 "delivered" orders with no delivery date */
SELECT order_id, order_status, order_purchase_timestamp, order_delivered_customer_date
FROM olist_orders_dataset
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

/* 9. Top 10 worst delivery delays */
SELECT
  order_id,
  order_delivered_customer_date,
  order_estimated_delivery_date,
  ROUND(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date), 1) AS DeliveryDelayDays
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
ORDER BY DeliveryDelayDays DESC
LIMIT 10;

/* 10. Volume on 2017-09-19 */
SELECT
  DATE(order_delivered_customer_date) AS DeliveryDate,
  COUNT(*) AS NumberOfOrders
FROM olist_orders_dataset
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
GROUP BY DATE(order_delivered_customer_date)
ORDER BY NumberOfOrders DESC
LIMIT 5;

/* 11. Concentration of severely delayed orders on 2017-09-19 */
SELECT COUNT(*)
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND DATE(order_delivered_customer_date) = '2017-09-19'
  AND julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date) > 100;

/* 12. Overall delivery delay statistics */
SELECT
  ROUND(AVG(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date)), 2) AS AvgDelayDays,
  ROUND(MIN(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date)), 1) AS BestCase_EarlyDays,
  ROUND(MAX(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date)), 1) AS WorstCase_DelayDays
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

/* 13. Median delivery delay */
SELECT
    ROUND(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date), 1) AS MedianDelayDays
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
ORDER BY MedianDelayDays ASC
LIMIT 1
OFFSET (
    SELECT COUNT(*) / 2
    FROM olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
);

/* 14. Payment type breakdown */
SELECT
    payment_type,
    COUNT(*) AS total_transactions,
    ROUND(AVG(payment_value), 2) AS avg_payment_value,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY total_transactions DESC;

/* 15. Top product categories by revenue */
SELECT
  t.product_category_name_english,
  COUNT(oi.order_id) AS NumberOfItemsSold,
  ROUND(SUM(oi.price), 2) AS TotalRevenue
FROM olist_order_items_dataset AS oi
INNER JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
INNER JOIN product_category_name_translation AS t ON p.product_category_name = t.product_category_name
GROUP BY t.product_category_name_english
ORDER BY TotalRevenue DESC
LIMIT 10;

/* 16. Average price per item comparison */
SELECT
  t.product_category_name_english,
  ROUND(SUM(oi.price) / COUNT(oi.order_id), 2) AS AvgPricePerItem
FROM olist_order_items_dataset AS oi
INNER JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
INNER JOIN product_category_name_translation AS t ON p.product_category_name = t.product_category_name
WHERE t.product_category_name_english IN ('health_beauty', 'watches_gifts')
GROUP BY t.product_category_name_english;

/* 17. Items priced above category average */
SELECT
  oi.order_id,
  p.product_category_name,
  oi.price
FROM olist_order_items_dataset AS oi
INNER JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
WHERE oi.price > (
  SELECT AVG(oi2.price)
  FROM olist_order_items_dataset AS oi2
  INNER JOIN olist_products_dataset AS p2 ON oi2.product_id = p2.product_id
  WHERE p2.product_category_name = p.product_category_name
);

/* 18. Top 3 highest priced products per category */
SELECT 
    category, 
    product_id, 
    price, 
    RankInCategory
FROM (
    SELECT
        p.product_category_name AS category,
        oi.product_id,
        oi.price,
        DENSE_RANK() OVER (
            PARTITION BY p.product_category_name 
            ORDER BY oi.price DESC
        ) AS RankInCategory
    FROM olist_order_items_dataset AS oi
    INNER JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
    WHERE p.product_category_name IS NOT NULL
) AS RankedProducts
WHERE RankInCategory <= 3;

SELECT category, product_id, price, RankInCategory
FROM (
  SELECT
    p.product_category_name AS category,
    oi.product_id,
    oi.price,
    RANK() OVER (PARTITION BY p.product_category_name ORDER BY oi.price DESC) AS RankInCategory
  FROM olist_order_items_dataset AS oi
  INNER JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
) AS RankedProducts
WHERE RankInCategory <= 3;

SELECT COUNT(*)
FROM olist_products_dataset
WHERE product_category_name IS NULL;

SELECT category, product_id, price, RankInCategory
FROM (
  SELECT
    p.product_category_name AS category,
    oi.product_id,
    oi.price,
    RANK() OVER (PARTITION BY p.product_category_name ORDER BY oi.price DESC) AS RankInCategory
  FROM olist_order_items_dataset AS oi
  INNER JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
  WHERE p.product_category_name IS NOT NULL
) AS RankedProducts
WHERE RankInCategory <= 3;