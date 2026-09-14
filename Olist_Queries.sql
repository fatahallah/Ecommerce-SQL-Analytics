/* ============================================================
   Project: Brazilian E-Commerce (Olist) - SQL Analysis
   Database: Olist_Ecommerce.db (SQLite)
   Tables: olist_orders_dataset, olist_customers_dataset,
           olist_order_items_dataset, olist_order_payments_dataset,
           olist_order_reviews_dataset, olist_products_dataset,
           olist_sellers_dataset, product_category_name_translation
   Author: Fathallah Saied Abou Eid
   Section: Data Validation
   ============================================================ */


/* ------------------------------------------------------------
   1. Check for duplicate order_id values in olist_orders_dataset
   Goal: Confirm order_id is a valid unique identifier before
         using it as a join key across tables.
   Result: 0 rows returned -> no duplicates found (99,441 orders,
           each with a unique order_id).
------------------------------------------------------------ */
SELECT order_id, COUNT(*)
FROM olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*) > 1;


/* ------------------------------------------------------------
   2. Check for orphaned records in olist_order_items_dataset
   Goal: Confirm every order_id in order_items has a matching
         parent record in the main orders table, using a
         subquery with NOT IN (similar to a failed VLOOKUP).
   Result: 0 -> no orphaned order_items rows; referential
           integrity between the two tables is intact.
------------------------------------------------------------ */
SELECT COUNT(*)
FROM olist_order_items_dataset
WHERE order_id NOT IN (SELECT order_id FROM olist_orders_dataset);

/* ------------------------------------------------------------
   3. Customers <-> Orders relationship checks
   Goal: Verify referential integrity in both directions -
         orders without a matching customer, and customers
         with no orders at all.
   Result: orders_without_customer = 0, customers_without_orders = 0
------------------------------------------------------------ */
SELECT COUNT(*)
FROM olist_orders_dataset
WHERE customer_id NOT IN (SELECT customer_id FROM olist_customers_dataset);

SELECT COUNT(*)
FROM olist_customers_dataset
WHERE customer_id NOT IN (SELECT customer_id FROM olist_orders_dataset);

/* ------------------------------------------------------------
   4. Products <-> Order Items relationship checks
   Goal: Verify every sold item maps to a known product, and
         check whether the product catalog contains items that
         were never sold.
   Result: items_without_product = 0, products_never_sold = 0
------------------------------------------------------------ */
SELECT COUNT(*)
FROM olist_order_items_dataset
WHERE product_id NOT IN (SELECT product_id FROM olist_products_dataset);

SELECT COUNT(*)
FROM olist_products_dataset
WHERE product_id NOT IN (SELECT product_id FROM olist_order_items_dataset);

/* ------------------------------------------------------------
   5. Confirm dataset design: customers table = transactional view
   Goal: customers_without_orders returning 0 is statistically
         unusual for a real store (normally some registered
         customers never complete a purchase). Verify whether
         olist_customers_dataset is fully derived from orders,
         rather than a full user base, by comparing total row
         count against distinct customers appearing in orders.
   Result: 99,441 = 99,441 exact match - confirms the customers
           table only contains customers who placed an order.
           Same logic explains products_never_sold = 0: the
           products table reflects only sold items, not a full
           store catalog. Documented as a dataset design note,
           not a data quality issue.
------------------------------------------------------------ */
SELECT
  (SELECT COUNT(*) FROM olist_customers_dataset) AS TotalCustomers,
  (SELECT COUNT(DISTINCT customer_id) FROM olist_orders_dataset) AS DistinctCustomersInOrders;

/* ============================================================
   Section: Delivery Date Integrity
   ============================================================ */

/* ------------------------------------------------------------
   6. Missing values in order date columns
   Goal: Check for NULLs across the order lifecycle date columns
         to understand data completeness before any delivery
         time analysis.
   Result: 0 missing purchase/estimated dates; 160 missing
           approval dates; 1,783 missing carrier delivery dates;
           2,965 missing customer delivery dates (out of 99,441).
------------------------------------------------------------ */
SELECT
  COUNT(*) AS total_orders,
  SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase,
  SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS null_approved,
  SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS null_carrier,
  SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_customer,
  SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS null_estimated
FROM olist_orders_dataset;

/* ------------------------------------------------------------
   7. Missing delivery dates by order_status
   Goal: Cross-reference missing order_delivered_customer_date
         values against order_status, to check whether missing
         dates are explained by the order's lifecycle stage.
   Result: Missing dates are fully expected for every status
           except "delivered" - shipped/canceled/unavailable/
           invoiced/processing/created/approved orders naturally
           have no delivery date yet (or ever, if canceled).
           However, 8 out of 96,478 "delivered" orders are
           missing a delivery date - a genuine anomaly since a
           delivered order should have a delivery timestamp.
------------------------------------------------------------ */
SELECT
  order_status,
  COUNT(*) AS total_orders,
  SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_delivery_date
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;

/* ------------------------------------------------------------
   8. Investigate the 8 "delivered" orders with no delivery date
   Goal: Isolate the anomalous rows for documentation.
   Result: 8 orders confirmed with order_status = 'delivered'
           but order_delivered_customer_date = NULL. This is a
           genuine data inconsistency between the status field
           and the delivery timestamp field - the exact cause
           (logging gap, delayed status sync, or an export/ETL
           issue) cannot be confirmed from this dataset alone,
           so it is documented as an open anomaly rather than
           a confirmed root cause.
------------------------------------------------------------ */
SELECT order_id, order_status, order_purchase_timestamp, order_delivered_customer_date
FROM olist_orders_dataset
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

/* ============================================================
   Section: Delivery Time Analysis
   ============================================================ */

/* ------------------------------------------------------------
   9. Delivery delay vs. estimated date (top 10 worst delays)
   Goal: Calculate the gap in days between actual and estimated
         delivery using julianday(), to identify the most
         severely delayed orders.
   Result: Top delays range from 159 to 189 days late. Notably,
           6 of the top 10 delayed orders share the same actual
           delivery date (2017-09-19), suggesting a possible
           systemic event rather than independent delays.
------------------------------------------------------------ */
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

/* ------------------------------------------------------------
   10. Check overall order volume on 2017-09-19
   Goal: Test whether 2017-09-19 was simply a high-volume
         delivery day in general (which would explain the
         clustering as coincidence).
   Result: 2017-09-19 does NOT appear among the top 5 highest-
           volume delivery dates (top days had 425-446 orders,
           all in 2018) - ruling out "generally busy day" as
           the explanation.
------------------------------------------------------------ */
SELECT
  DATE(order_delivered_customer_date) AS DeliveryDate,
  COUNT(*) AS NumberOfOrders
FROM olist_orders_dataset
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
GROUP BY DATE(order_delivered_customer_date)
ORDER BY NumberOfOrders DESC
LIMIT 5;

/* ------------------------------------------------------------
   11. Concentration of severely delayed orders on 2017-09-19
   Goal: Rather than testing overall volume, test specifically
         how many severely delayed orders (>100 days late)
         were recorded as delivered on that single date.
   Result: 21 orders delivered on 2017-09-19 alone show a delay
           of more than 100 days - an unusually high
           concentration for one day. This pattern (high count
           of extreme delays clustered on a single date, without
           that date being a generally high-volume day) suggests
           a possible batch status update or systemic delivery
           logging event, rather than 21 independent extreme
           delays. The exact cause cannot be confirmed from this
           dataset alone and is documented as an open finding.
------------------------------------------------------------ */
SELECT COUNT(*)
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND DATE(order_delivered_customer_date) = '2017-09-19'
  AND julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date) > 100;

/* ------------------------------------------------------------
   12. Overall delivery delay statistics (Average, Min, Max)
   Goal: Move beyond worst-case outliers to a store-wide picture
         of delivery performance vs. the estimated date.
   Result: AvgDelayDays = -11.18 (delivered ~11 days early on
           average), BestCase_EarlyDays = -146.0,
           WorstCase_DelayDays = 189.0. The average suggests
           Olist uses conservative (padded) delivery estimates.
------------------------------------------------------------ */
SELECT
  ROUND(AVG(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date)), 2) AS AvgDelayDays,
  ROUND(MIN(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date)), 1) AS BestCase_EarlyDays,
  ROUND(MAX(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date)), 1) AS WorstCase_DelayDays
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

/* ------------------------------------------------------------
   13. Median delivery delay (SQLite has no built-in MEDIAN)
   Goal: Cross-check the average against the median, since
           extreme outliers (+189 / -146 days) could otherwise
           be pulling the average away from the typical order's
           experience. Computed manually using ORDER BY with
           LIMIT 1 OFFSET (COUNT/2), a standard workaround for
           median in SQLite.
   Result: Median = -11.9 days, nearly identical to the average
           (-11.18). This close agreement shows the extreme
           outliers are rare, isolated cases that do NOT skew
           the overall picture - the vast majority of orders
           genuinely cluster around 11 days early, confirming
           Olist's conservative estimation is the dominant
           pattern, not an artifact of a few extreme values.
------------------------------------------------------------ */
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

/* ============================================================
   Section: Payment Analysis
   ============================================================ */

/* ------------------------------------------------------------
   14. Payment type breakdown and average value
   Goal: Understand which payment methods dominate transactions
         and how their average value compares.
   Result: credit_card dominates (76,795 transactions, ~74% of
           all payments) with the highest average value (163.32),
           followed by boleto (a common Brazilian bank-slip
           payment method). A small "not_defined" category (3
           transactions, all valued at 0) is a minor data
           anomaly, negligible in scale but noted for completeness.
------------------------------------------------------------ */
SELECT
    payment_type,
    COUNT(*) AS total_transactions,
    ROUND(AVG(payment_value), 2) AS avg_payment_value,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY total_transactions DESC;

/* ============================================================
   Section: Multi-Table Joins
   ============================================================ */

/* ------------------------------------------------------------
   15. Top product categories by revenue (3-table join)
   Goal: Join order_items -> products -> category translation
         to identify which product categories generate the most
         revenue, using their English category names.
   Result: health_beauty leads with $1,258,681 across 9,670
           items sold. Notably, watches_gifts ranks 2nd in
           revenue ($1,205,006) despite selling far fewer items
           (5,991) than health_beauty - indicating a
           significantly higher average price per item in that
           category.
------------------------------------------------------------ */
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

/* ------------------------------------------------------------
   16. Confirm average price gap: health_beauty vs watches_gifts
   Goal: Quantify the average price per item difference observed
         between the top two revenue categories.
   Result: watches_gifts averages $201.14 per item vs $130.16
           for health_beauty - about 54% higher. This confirms
           watches_gifts reaches similar total revenue through
           a higher-price/lower-volume model, while health_beauty
           relies on higher volume at a lower average price.
------------------------------------------------------------ */
SELECT
  t.product_category_name_english,
  ROUND(SUM(oi.price) / COUNT(oi.order_id), 2) AS AvgPricePerItem
FROM olist_order_items_dataset AS oi
INNER JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
INNER JOIN product_category_name_translation AS t ON p.product_category_name = t.product_category_name
WHERE t.product_category_name_english IN ('health_beauty', 'watches_gifts')
GROUP BY t.product_category_name_english;

/* ============================================================
   Section: Correlated Subqueries
   ============================================================ */

/* ------------------------------------------------------------
   17. Items priced above their own category's average price
   Goal: Use a correlated subquery (re-evaluated per outer row,
         unlike the independent NOT IN subqueries used earlier)
         to flag items priced above the average of their SPECIFIC
         category, not the overall product average.
   Result: 36,178 out of 112,650 items (~32%) are priced above
           their own category's average - consistent with a
           right-skewed price distribution where most categories
           have many lower-priced items and fewer high-priced
           ones pulling the average up.
------------------------------------------------------------ */
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

/* ============================================================
   Section: Window Functions
   ============================================================ */

/* ------------------------------------------------------------
   18. Data validation catch: NULL product categories discovered
       mid-analysis
   Goal: While ranking products by category, a NULL category
         group surfaced in the results - a gap missed during
         the initial validation phase. Quantify it before
         deciding how to handle it.
   Result: 610 out of 32,951 products (~1.85%) have a NULL
           product_category_name. Documented explicitly and
           excluded from the category ranking below, rather than
           silently dropped or left as an unlabeled group.
------------------------------------------------------------ */
SELECT COUNT(*)
FROM olist_products_dataset
WHERE product_category_name IS NULL;

/* ------------------------------------------------------------
   19. Top 3 highest-priced products per category (window function)
   Goal: Rank products by price within each category using
         RANK() OVER (PARTITION BY ...), wrapped in a derived
         table (subquery) since a window function's result
         column cannot be filtered directly in the same-level
         WHERE clause. This replicates the correlated subquery's
         analytical intent (per-category comparison) with a
         single, more efficient pass over the data. Products
         with a NULL category (see above) are excluded.
   Result: Successfully ranked top 3 products by price within
           every product category (e.g. agro_industria_e_comercio
           top product priced at 2,990; alimentos top product at
           274.99). Ties share the same rank (RANK() behavior,
           consistent with its use in the HR project).
------------------------------------------------------------ */
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
