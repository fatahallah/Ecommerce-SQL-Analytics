/* ============================================================
   Project: Geo-Spatial Sales & Delivery Analytics (Power BI)
   Database: Olist_Ecommerce.db (SQLite) - same database as the
             Olist SQL Analytics project, extended with the
             geolocation table for this separate geo-focused project.
   New Table: olist_geolocation_dataset (1,000,163 rows)
   Author: Fathallah Saied Abou Eid
   Section: Data Preparation for Power BI (Reducing Geolocation Size)
   ============================================================ */


/* ------------------------------------------------------------
   1. Confirm geolocation import
   Goal: Verify the full geolocation table imported correctly
         before reducing it for Power BI.
   Result: 1,000,163 rows confirmed - matches source file exactly.
------------------------------------------------------------ */
SELECT COUNT(*) AS Total_Geolocation_Rows
FROM olist_geolocation_dataset;

/* ------------------------------------------------------------
   2. Investigate zip code repetition in geolocation
   Goal: Understand why the table has 1,000,163 rows by checking
         how many times a single zip code prefix repeats.
   Result: Top zip code prefix (24220) repeats 1,146 times -
           confirming each zip code has thousands of near-
           duplicate GPS points (one per address/building),
           which inflates row count without adding analytical
           value at the city/region level needed for this project.
------------------------------------------------------------ */
SELECT geolocation_zip_code_prefix, COUNT(*) AS RepeatCount
FROM olist_geolocation_dataset
GROUP BY geolocation_zip_code_prefix
ORDER BY RepeatCount DESC
LIMIT 5;

/* ------------------------------------------------------------
   3. Reduce geolocation to one averaged row per zip code
   Goal: Collapse the 1,000,163-row table into a lightweight
         summary table (one row per zip code prefix, using the
         average lat/lng) suitable for import into Power BI.
   Result: 19,015 rows - a 98% reduction in size with no loss
           of the geographic precision needed for city/region-
           level mapping and analysis.
------------------------------------------------------------ */
SELECT
  geolocation_zip_code_prefix,
  ROUND(AVG(geolocation_lat), 6) AS avg_lat,
  ROUND(AVG(geolocation_lng), 6) AS avg_lng,
  geolocation_city,
  geolocation_state
FROM olist_geolocation_dataset
GROUP BY geolocation_zip_code_prefix;

/* ------------------------------------------------------------
   4. Persist the reduced summary as a permanent table
   Goal: Save the 19,015-row averaged result as a real table
         (not a temporary query result) so Power BI can connect
         to it directly via ODBC, the same way as any other table.
   Result: New table `geolocation_summary` created and confirmed
           in Database Structure; changes written to disk.
------------------------------------------------------------ */
CREATE TABLE geolocation_summary AS
SELECT
  geolocation_zip_code_prefix,
  ROUND(AVG(geolocation_lat), 6) AS avg_lat,
  ROUND(AVG(geolocation_lng), 6) AS avg_lng,
  geolocation_city,
  geolocation_state
FROM olist_geolocation_dataset
GROUP BY geolocation_zip_code_prefix;

/* ============================================================
   Section: Multi-Table Geo Join (Customer + Seller Coordinates)
   ============================================================ */

/* ------------------------------------------------------------
   5. Join order items to customer and seller coordinates
   Goal: Retrieve both the customer's and seller's approximate
         lat/lng for each order, by joining geolocation_summary
         TWICE under different aliases (cg for customer, sg for
         seller) - the same self-join principle used for the
         manager/employee relationship in the HR project, applied
         here across two different tables (customers and sellers)
         sharing one lookup table.
   Result: Successfully retrieved paired customer/seller
           coordinates for each order - the foundation needed to
           calculate distance per order in the next step.
------------------------------------------------------------ */
SELECT
  oi.order_id,
  c.customer_zip_code_prefix,
  cg.avg_lat AS customer_lat,
  cg.avg_lng AS customer_lng,
  s.seller_zip_code_prefix,
  sg.avg_lat AS seller_lat,
  sg.avg_lng AS seller_lng
FROM olist_order_items_dataset AS oi
INNER JOIN olist_orders_dataset AS o ON oi.order_id = o.order_id
INNER JOIN olist_customers_dataset AS c ON o.customer_id = c.customer_id
INNER JOIN olist_sellers_dataset AS s ON oi.seller_id = s.seller_id
INNER JOIN geolocation_summary AS cg ON c.customer_zip_code_prefix = cg.geolocation_zip_code_prefix
INNER JOIN geolocation_summary AS sg ON s.seller_zip_code_prefix = sg.geolocation_zip_code_prefix;

/* ------------------------------------------------------------
   6. Calculate customer-to-seller distance (Haversine formula)
   Goal: SQLite has no built-in geographic distance function, so
         the Haversine formula is implemented manually using
         trigonometric functions (SIN, COS, ATAN2) to compute
         great-circle distance in kilometers between two lat/lng
         points, accounting for Earth's curvature (Earth radius
         ~6371 km; degrees converted to radians via * 0.0174533).
   Result: Distances range realistically from ~33 km (local
           delivery) to ~646 km (cross-state shipping) - values
           consistent with Brazil's large geography. This
           distance will be joined with delivery time data next
           to test whether distance correlates with delay.
------------------------------------------------------------ */
SELECT
  oi.order_id,
  cg.avg_lat AS customer_lat, cg.avg_lng AS customer_lng,
  sg.avg_lat AS seller_lat, sg.avg_lng AS seller_lng,
  ROUND(
    6371 * 2 * ATAN2(
      SQRT(
        (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
        COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
        (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
      ),
      SQRT(
        1 - (
          (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
          COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
          (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
        )
      )
    ), 1
  ) AS DistanceKM
FROM olist_order_items_dataset AS oi
INNER JOIN olist_orders_dataset AS o ON oi.order_id = o.order_id
INNER JOIN olist_customers_dataset AS c ON o.customer_id = c.customer_id
INNER JOIN olist_sellers_dataset AS s ON oi.seller_id = s.seller_id
INNER JOIN geolocation_summary AS cg ON c.customer_zip_code_prefix = cg.geolocation_zip_code_prefix
INNER JOIN geolocation_summary AS sg ON s.seller_zip_code_prefix = sg.geolocation_zip_code_prefix;

/* ------------------------------------------------------------
   7. Persist distance + delivery delay as a permanent table
   Goal: Combine the Haversine distance calculation with the
         delivery delay metric (from the earlier Olist SQL
         project) into one permanent table, ready to be imported
         into Power BI for mapping and correlation analysis.
   Result: Table `order_distance_delay` created successfully.
           Quick verification: average distance = 596.3 km,
           average delay = -11.3 days - consistent with the
           -11.18 day average delay found in the original Olist
           SQL project, confirming the join did not distort the
           underlying delay data.
------------------------------------------------------------ */
CREATE TABLE order_distance_delay AS
SELECT
  oi.order_id,
  ROUND(
    6371 * 2 * ATAN2(
      SQRT(
        (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
        COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
        (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
      ),
      SQRT(
        1 - (
          (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
          COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
          (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
        )
      )
    ), 1
  ) AS DistanceKM,
  ROUND(julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date), 1) AS DeliveryDelayDays
FROM olist_order_items_dataset AS oi
INNER JOIN olist_orders_dataset AS o ON oi.order_id = o.order_id
INNER JOIN olist_customers_dataset AS c ON o.customer_id = c.customer_id
INNER JOIN olist_sellers_dataset AS s ON oi.seller_id = s.seller_id
INNER JOIN geolocation_summary AS cg ON c.customer_zip_code_prefix = cg.geolocation_zip_code_prefix
INNER JOIN geolocation_summary AS sg ON s.seller_zip_code_prefix = sg.geolocation_zip_code_prefix
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL;

/* ============================================================
   Section: Distance vs. Delivery Delay (Core Hypothesis Test)
   ============================================================ */

/* ------------------------------------------------------------
   8. Test whether distance affects delivery delay
   Goal: Group orders into near/medium/far distance bands and
         compare average delay per group, to answer the
         project's core question.
   Result: All three groups deliver ahead of the estimated date
           (all negative), but the early-delivery margin grows
           with distance: -8.9 days (near, <100km), -11.6 days
           (medium), -12.2 days (far, >500km). This does NOT mean
           longer shipments arrive faster - it indicates Olist
           applies a larger (more conservative) estimation buffer
           for longer distances, anticipating slower fulfillment
           and protecting the promised delivery date, rather than
           distance itself improving delivery performance.
------------------------------------------------------------ */
SELECT
  CASE
    WHEN DistanceKM < 100 THEN '1. Near (<100km)'
    WHEN DistanceKM BETWEEN 100 AND 500 THEN '2. Medium (100-500km)'
    ELSE '3. Far (>500km)'
  END AS DistanceGroup,
  COUNT(*) AS NumberOfOrders,
  ROUND(AVG(DeliveryDelayDays), 1) AS AvgDelayDays
FROM order_distance_delay
GROUP BY DistanceGroup
ORDER BY DistanceGroup;

/* ============================================================
   Section: Enhanced Table - IsDelayed Flag, Freight, Shipping Route
   ============================================================ */

/* ------------------------------------------------------------
   9. Rebuild order_distance_delay with additional analysis columns
   Goal: Extend the table with three improvements identified
         before exporting to Power BI:
         - IsDelayed: a binary flag (order actually late vs. not),
           since an average delay figure alone hides the true
           on-time rate.
         - price and freight_value: enables analyzing shipping
           cost vs. distance, not just delivery time.
         - ShippingRoute (customer_state -> seller_state): a
           text field prepared for a flow map visual in Power BI.
         SQLite does not support adding computed columns via
         ALTER TABLE easily, so the table is dropped and rebuilt.
   Result: Quick validation - only 7.9% of orders are actually
           delayed (IsDelayed = 1), despite the average delay
           figure being negative (early). This is a key finding:
           the vast majority of orders (92.1%) arrive on time or
           early; the earlier average/median figures do not
           capture the true on-time delivery rate. Average
           freight value: $19.94.
------------------------------------------------------------ */
DROP TABLE order_distance_delay;

CREATE TABLE order_distance_delay AS
SELECT
  oi.order_id,
  oi.price,
  oi.freight_value,
  c.customer_state,
  s.seller_state,
  c.customer_state || ' -> ' || s.seller_state AS ShippingRoute,
  ROUND(
    6371 * 2 * ATAN2(
      SQRT(
        (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
        COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
        (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
      ),
      SQRT(
        1 - (
          (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
          COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
          (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
        )
      )
    ), 1
  ) AS DistanceKM,
  ROUND(julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date), 1) AS DeliveryDelayDays,
  CASE
    WHEN julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date) > 0 THEN 1
    ELSE 0
  END AS IsDelayed
FROM olist_order_items_dataset AS oi
INNER JOIN olist_orders_dataset AS o ON oi.order_id = o.order_id
INNER JOIN olist_customers_dataset AS c ON o.customer_id = c.customer_id
INNER JOIN olist_sellers_dataset AS s ON oi.seller_id = s.seller_id
INNER JOIN geolocation_summary AS cg ON c.customer_zip_code_prefix = cg.geolocation_zip_code_prefix
INNER JOIN geolocation_summary AS sg ON s.seller_zip_code_prefix = sg.geolocation_zip_code_prefix
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL;

/* Quick validation */
SELECT
  ROUND(100.0 * SUM(IsDelayed) / COUNT(*), 1) AS DelayedPct,
  ROUND(AVG(freight_value), 2) AS AvgFreight
FROM order_distance_delay;

/* ============================================================
   Section: Map Visualization Preparation
   ============================================================ */

/* ------------------------------------------------------------
   10. Add customer zip code to order_distance_delay
   Goal: Rebuild the table with customer_zip_code_prefix included,
         enabling a direct relationship to geolocation_summary at
         zip-code level (previously only linked at state level),
         needed to color the map by delivery delay per location.
   Result: Table rebuilt successfully with the new column.
------------------------------------------------------------ */
DROP TABLE order_distance_delay;

CREATE TABLE order_distance_delay AS
SELECT
  oi.order_id,
  oi.price,
  oi.freight_value,
  c.customer_zip_code_prefix,
  c.customer_state,
  s.seller_state,
  c.customer_state || ' -> ' || s.seller_state AS ShippingRoute,
  ROUND(
    6371 * 2 * ATAN2(
      SQRT(
        (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
        COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
        (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
      ),
      SQRT(
        1 - (
          (SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2) * SIN((sg.avg_lat - cg.avg_lat) * 0.0174533 / 2)) +
          COS(cg.avg_lat * 0.0174533) * COS(sg.avg_lat * 0.0174533) *
          (SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2) * SIN((sg.avg_lng - cg.avg_lng) * 0.0174533 / 2))
        )
      )
    ), 1
  ) AS DistanceKM,
  ROUND(julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date), 1) AS DeliveryDelayDays,
  CASE
    WHEN julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date) > 0 THEN 1
    ELSE 0
  END AS IsDelayed
FROM olist_order_items_dataset AS oi
INNER JOIN olist_orders_dataset AS o ON oi.order_id = o.order_id
INNER JOIN olist_customers_dataset AS c ON o.customer_id = c.customer_id
INNER JOIN olist_sellers_dataset AS s ON oi.seller_id = s.seller_id
INNER JOIN geolocation_summary AS cg ON c.customer_zip_code_prefix = cg.geolocation_zip_code_prefix
INNER JOIN geolocation_summary AS sg ON s.seller_zip_code_prefix = sg.geolocation_zip_code_prefix
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL;

/* ------------------------------------------------------------
   11. Add a categorical DelayCategory column
   Goal: Power BI's standard Map visual does not support color
         saturation (a continuous gradient), so a continuous
         DeliveryDelayDays value produces a cluttered legend with
         dozens of shades. A simple 3-category column (Delayed /
         On-Time / Early) gives a clean, readable legend instead.
   Result: All 109,653 rows successfully categorized.
------------------------------------------------------------ */
ALTER TABLE order_distance_delay ADD COLUMN DelayCategory TEXT;

UPDATE order_distance_delay
SET DelayCategory = CASE
  WHEN DeliveryDelayDays > 0 THEN 'Delayed'
  WHEN DeliveryDelayDays BETWEEN -5 AND 0 THEN 'On-Time (0-5 days early)'
  ELSE 'Early (5+ days early)'
END;

/* ============================================================
   Section: KPI Summary Table (Power BI Workaround + Fix)
   ============================================================ */

/* ------------------------------------------------------------
   12. Create a single-row KPI summary table
   Goal: Power BI's DAX measures (SUM, COUNTROWS/FILTER) on the
         IsDelayed column repeatedly failed with a "capacity or
         license issue" error via the ODBC connection, despite
         the column displaying correctly in a plain table visual.
         Root cause could not be resolved on the Power BI side,
         so the aggregation was moved to SQL instead: a one-row
         summary table pre-computes the KPIs, avoiding any
         aggregation over the ODBC-sourced column in Power BI.
   Result: Card visuals connected successfully once IsDelayed
           aggregation was removed from Power BI's side entirely.
------------------------------------------------------------ */
CREATE TABLE kpi_summary AS
SELECT
  ROUND(100.0 * SUM(IsDelayed) / COUNT(*), 2) AS DelayedRatePct,
  ROUND(AVG(DistanceKM), 1) AS AvgDistanceKM,
  ROUND(AVG(freight_value), 2) AS AvgFreightValue
FROM order_distance_delay;

/* ------------------------------------------------------------
   13. Fix DelayedRatePct scale for Power BI percentage formatting
   Goal: The initial version stored the rate as a "display-ready"
         percentage (7.9, meaning 7.9%). Power BI's Percentage
         format multiplies by 100, turning 7.9 into a nonsensical
         790%. Rebuilt to store the true decimal fraction (0.079)
         instead, matching what Power BI's Percentage format
         expects.
   Result: Card now correctly displays 7.9% using Power BI's
           native Percentage format, with no manual label
           workaround needed.
------------------------------------------------------------ */
DROP TABLE kpi_summary;

CREATE TABLE kpi_summary AS
SELECT
  ROUND(1.0 * SUM(IsDelayed) / COUNT(*), 4) AS DelayedRatePct,
  ROUND(AVG(DistanceKM), 1) AS AvgDistanceKM,
  ROUND(AVG(freight_value), 2) AS AvgFreightValue
FROM order_distance_delay;
