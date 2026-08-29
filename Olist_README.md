# Brazilian E-Commerce (Olist) — SQL Analysis

## Overview
A SQL analysis of the Olist Brazilian e-commerce public dataset, focused on order fulfillment, delivery performance, payments, and product category revenue. The project emphasizes multi-table joins, correlated subqueries, and window functions on real transactional data — a deliberate step up in scope and dataset complexity from an earlier HR-focused SQL project.

## Data Source
The Olist Brazilian E-Commerce Public Dataset (Kaggle), covering ~99,441 orders. Eight of the nine available tables were used:

| Table | Rows | Description |
|---|---|---|
| `olist_orders_dataset` | 99,441 | Core order record: status, purchase/approval/delivery timestamps |
| `olist_customers_dataset` | 99,441 | Customer records |
| `olist_order_items_dataset` | 112,650 | Line items per order (products, price, freight) |
| `olist_order_payments_dataset` | 103,886 | Payment method and value per order |
| `olist_order_reviews_dataset` | 99,224 | Customer reviews |
| `olist_products_dataset` | 32,951 | Product catalog |
| `olist_sellers_dataset` | 3,095 | Seller records |
| `product_category_name_translation` | 71 | Portuguese-to-English category name mapping |

**Excluded by design:** `olist_geolocation_dataset` (~1,000,163 rows of zip-code coordinates) was intentionally left out of this project. Meaningful use of geographic data requires distance calculations (e.g. the Haversine formula) and map-based visualization that fall outside standard SQL analysis — better suited to a dedicated Power BI/geo-visualization project than folded into this one.

## Tools
- **DB Browser for SQLite** — database creation, CSV import, query execution
- **SQL** — data validation, joins, correlated subqueries, window functions, date functions

## Methodology
1. **Data Validation** — checked for duplicate keys and referential integrity between every related table pair (orders/customers, order_items/products), and audited missing values across all order lifecycle date columns.
2. **Delivery Time Analysis** — measured actual vs. estimated delivery using `julianday()`, cross-checked the average against a manually computed median to test for outlier influence, and investigated an anomalous date cluster.
3. **Payment Analysis** — profiled transaction volume and average value by payment method.
4. **Multi-Table Joins** — joined three tables (order items → products → category translation) to analyze revenue by product category.
5. **Correlated Subqueries** — identified items priced above their own category's average, with the subquery re-evaluated per row rather than computed once.
6. **Window Functions** — ranked products by price within each category using `RANK() OVER (PARTITION BY ...)`, wrapped in a derived table.

## Key Insights
- **Dataset design:** `olist_customers_dataset` is a transactional view, not a full user base — every customer row corresponds to exactly one order (99,441 = 99,441, confirmed by query). The same logic explains why every cataloged product has been sold at least once.
- **Delivery performance:** orders are delivered 11.18 days early on average (median: 11.9 days), indicating Olist uses conservative delivery estimates. This holds despite rare extreme outliers (up to 189 days late, and one order 146 days early) — the close average/median agreement confirms these are isolated cases, not a skewed pattern.
- **Data anomaly — status/date mismatch:** 8 orders are marked `delivered` but have no delivery date recorded, a genuine inconsistency between the status and timestamp fields.
- **Data anomaly — delay clustering:** 21 orders delivered on 2017-09-19 alone show delays over 100 days, despite that date not being a generally high-volume delivery day — suggesting a possible batch status update or systemic logging event rather than independent delays. The exact cause could not be confirmed from the dataset alone.
- **Payments:** credit card dominates (~74% of transactions, highest average value at $163.32), followed by boleto (a common Brazilian bank-slip payment method).
- **Revenue by category:** `health_beauty` leads in total revenue, but `watches_gifts` reaches a close second with far fewer items sold — its average price per item ($201.14) is about 54% higher than `health_beauty`'s ($130.16), reflecting a higher-price/lower-volume model.
- **Data validation catch found mid-analysis:** while ranking products by category, 610 of 32,951 products (~1.85%) surfaced with a NULL category — a gap missed in the initial validation pass and caught only once it appeared in later query results. Documented and excluded explicitly rather than left unlabeled.

## Files
- `Olist_SQL_Queries.sql` — full annotated query log, in chronological order, covering every step above.

## Author
Fathallah Saied Abou Eid
