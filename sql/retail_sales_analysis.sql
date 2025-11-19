-- Retail Store Sales Analysis - SQL Queries
-- Comprehensive analysis for Tableau dashboard

-- Database: PostgreSQL
-- Created: 2024
-- Author: Retail Analytics Team

-- =============================================
-- 1. DATABASE SETUP & TABLE CREATION
-- =============================================

CREATE DATABASE retail_analytics;

-- Orders Table (Main Fact Table)
CREATE TABLE orders (
    row_id SERIAL PRIMARY KEY,
    order_id VARCHAR(50) NOT NULL,
    order_date DATE NOT NULL,
    ship_date DATE NOT NULL,
    ship_mode VARCHAR(50) NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    customer_name VARCHAR(100) NOT NULL,
    segment VARCHAR(50) NOT NULL,
    country VARCHAR(50) DEFAULT 'United States',
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50) NOT NULL,
    region VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20),
    product_id VARCHAR(50) NOT NULL,
    category VARCHAR(50) NOT NULL,
    sub_category VARCHAR(50) NOT NULL,
    product_name VARCHAR(200) NOT NULL,
    sales DECIMAL(10,2) NOT NULL,
    quantity INTEGER NOT NULL,
    discount DECIMAL(4,2) DEFAULT 0.00,
    profit DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- People Table (Regional Managers)
CREATE TABLE people (
    person VARCHAR(100) NOT NULL,
    region VARCHAR(50) PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Returns Table
CREATE TABLE returns (
    order_id VARCHAR(50) PRIMARY KEY,
    returned VARCHAR(3) CHECK (returned IN ('Yes', 'No')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================
-- 2. INDEXES FOR PERFORMANCE
-- =============================================

CREATE INDEX idx_orders_order_id ON orders(order_id);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_product_id ON orders(product_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_orders_region ON orders(region);
CREATE INDEX idx_orders_category ON orders(category);
CREATE INDEX idx_returns_order_id ON returns(order_id);

-- Composite indexes for common queries
CREATE INDEX idx_date_region ON orders(order_date, region);
CREATE INDEX idx_category_segment ON orders(category, segment);
CREATE INDEX idx_date_category ON orders(order_date, category);

-- =============================================
-- 3. DATA QUALITY CHECKS
-- =============================================

-- Check for NULL values in critical fields
SELECT 
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) as null_orders,
    SUM(CASE WHEN sales IS NULL THEN 1 ELSE 0 END) as null_sales,
    SUM(CASE WHEN profit IS NULL THEN 1 ELSE 0 END) as null_profit,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) as null_customers
FROM orders;

-- Validate profit margin calculations
SELECT 
    COUNT(*) as records_with_invalid_margin
FROM orders
WHERE (profit / sales) <> (profit / sales)  -- Check for NaN
   OR sales <= 0 
   OR ABS(profit) > 100000;  -- Outlier detection

-- Check for data consistency and duplicates
SELECT 
    order_id,
    COUNT(*) as duplicate_count
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- =============================================
-- 4. CORE BUSINESS ANALYSIS QUERIES
-- =============================================

-- 4.1 Executive Overview Metrics
SELECT 
    COUNT(DISTINCT order_id) as total_orders,
    COUNT(DISTINCT customer_id) as unique_customers,
    SUM(sales) as total_sales,
    SUM(profit) as total_profit,
    ROUND(SUM(profit) / SUM(sales) * 100, 2) as profit_margin_pct,
    AVG(sales) as avg_order_value,
    MIN(order_date) as start_date,
    MAX(order_date) as end_date
FROM orders;

-- 4.2 Monthly Sales Trend with Moving Average
WITH monthly_sales AS (
    SELECT 
        DATE_TRUNC('month', order_date) as month,
        SUM(sales) as monthly_sales,
        SUM(profit) as monthly_profit,
        COUNT(DISTINCT order_id) as order_count
    FROM orders
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT 
    month,
    monthly_sales,
    monthly_profit,
    order_count,
    AVG(monthly_sales) OVER (
        ORDER BY month 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) as three_month_avg_sales,
    LAG(monthly_sales, 12) OVER (ORDER BY month) as sales_previous_year,
    ROUND(
        (monthly_sales - LAG(monthly_sales, 12) OVER (ORDER BY month)) / 
        LAG(monthly_sales, 12) OVER (ORDER BY month) * 100, 2
    ) as yoy_growth_pct
FROM monthly_sales
ORDER BY month;

-- 4.3 Top 10 Customers by Profit
SELECT 
    customer_id,
    customer_name,
    segment,
    COUNT(DISTINCT order_id) as total_orders,
    SUM(sales) as total_sales,
    SUM(profit) as total_profit,
    ROUND(SUM(profit) / SUM(sales) * 100, 2) as profit_margin_pct,
    MAX(order_date) as last_order_date
FROM orders
GROUP BY customer_id, customer_name, segment
ORDER BY total_profit DESC
LIMIT 10;

-- 4.4 Loss-Making Products Analysis
SELECT 
    category,
    sub_category,
    product_name,
    COUNT(*) as order_count,
    SUM(sales) as total_sales,
    SUM(profit) as total_profit,
    AVG(discount) as avg_discount,
    ROUND(SUM(profit) / SUM(sales) * 100, 2) as profit_margin_pct
FROM orders
WHERE profit < 0
GROUP BY category, sub_category, product_name
ORDER BY total_profit ASC;

-- 4.5 Regional Performance with Rankings
SELECT 
    o.region,
    p.person as regional_manager,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    SUM(o.sales) as total_sales,
    SUM(o.profit) as total_profit,
    ROUND(SUM(o.profit) / SUM(o.sales) * 100, 2) as profit_margin_pct,
    RANK() OVER (ORDER BY SUM(o.profit) DESC) as profit_rank,
    RANK() OVER (ORDER BY SUM(o.sales) DESC) as sales_rank
FROM orders o
LEFT JOIN people p ON o.region = p.region
GROUP BY o.region, p.person
ORDER BY total_profit DESC;

-- =============================================
-- 5. CUSTOMER SEGMENTATION (RFM ANALYSIS)
-- =============================================

WITH customer_rfm AS (
    SELECT 
        customer_id,
        customer_name,
        segment,
        -- Recency: Days since last order (assuming max date is 2017-12-31)
        DATE_PART('day', DATE '2017-12-31' - MAX(order_date)) as recency_days,
        -- Frequency: Total orders
        COUNT(DISTINCT order_id) as frequency,
        -- Monetary: Total sales value
        SUM(sales) as monetary,
        -- Additional metrics
        AVG(sales) as avg_order_value,
        SUM(profit) as total_profit,
        MAX(order_date) as last_order_date
    FROM orders
    GROUP BY customer_id, customer_name, segment
),
rfm_scores AS (
    SELECT *,
        -- RFM Score Calculation (1-5 scale, 5 being best)
        NTILE(5) OVER (ORDER BY recency_days DESC) as r_score,  -- Lower recency is better
        NTILE(5) OVER (ORDER BY frequency) as f_score,          -- Higher frequency is better
        NTILE(5) OVER (ORDER BY monetary) as m_score           -- Higher monetary is better
    FROM customer_rfm
)
SELECT 
    customer_id,
    customer_name,
    segment,
    recency_days,
    frequency,
    monetary,
    total_profit,
    r_score,
    f_score,
    m_score,
    (r_score * 100 + f_score * 10 + m_score) as rfm_score,
    CASE 
        WHEN (r_score >= 4 AND f_score >= 4 AND m_score >= 4) THEN 'Champions'
        WHEN (r_score >= 3 AND f_score >= 3 AND m_score >= 3) THEN 'Loyal Customers'
        WHEN (r_score >= 3 AND f_score >= 1 AND m_score >= 2) THEN 'Potential Loyalists'
        WHEN (r_score >= 4 AND f_score <= 2 AND m_score <= 2) THEN 'New Customers'
        WHEN (r_score >= 2 AND f_score >= 3 AND m_score >= 3) THEN 'At Risk'
        WHEN (r_score >= 2 AND f_score <= 2 AND m_score >= 2) THEN 'Need Attention'
        ELSE 'Lost Customers'
    END as customer_segment
FROM rfm_scores
ORDER BY rfm_score DESC;

-- =============================================
-- 6. PRODUCT PORTFOLIO ANALYSIS
-- =============================================

-- 6.1 ABC Analysis (Pareto Principle)
WITH product_performance AS (
    SELECT 
        product_id,
        product_name,
        category,
        sub_category,
        SUM(sales) as total_sales,
        SUM(profit) as total_profit,
        COUNT(*) as order_count,
        SUM(quantity) as total_quantity,
        AVG(discount) as avg_discount
    FROM orders
    GROUP BY product_id, product_name, category, sub_category
),
abc_analysis AS (
    SELECT *,
        SUM(total_sales) OVER (ORDER BY total_sales DESC) as running_total,
        SUM(total_sales) OVER () as grand_total,
        ROUND(
            (SUM(total_sales) OVER (ORDER BY total_sales DESC) / 
             SUM(total_sales) OVER ()) * 100, 2
        ) as cumulative_percentage
    FROM product_performance
)
SELECT 
    product_id,
    product_name,
    category,
    sub_category,
    total_sales,
    total_profit,
    order_count,
    cumulative_percentage,
    CASE 
        WHEN cumulative_percentage <= 70 THEN 'A-Class'
        WHEN cumulative_percentage <= 95 THEN 'B-Class' 
        ELSE 'C-Class'
    END as abc_class
FROM abc_analysis
ORDER BY total_sales DESC;

-- 6.2 Discount Effectiveness Analysis
SELECT 
    CASE 
        WHEN discount = 0 THEN 'No Discount'
        WHEN discount <= 0.10 THEN '1-10%'
        WHEN discount <= 0.20 THEN '11-20%'
        WHEN discount <= 0.30 THEN '21-30%'
        ELSE '>30%'
    END as discount_bracket,
    COUNT(*) as order_count,
    AVG(sales) as avg_sales,
    AVG(profit) as avg_profit,
    ROUND(AVG(profit / sales) * 100, 2) as avg_margin_pct,
    SUM(sales) as total_sales,
    SUM(profit) as total_profit,
    COUNT(DISTINCT customer_id) as unique_customers
FROM orders
WHERE sales > 0
GROUP BY discount_bracket
ORDER BY MIN(discount);

-- =============================================
-- 7. RETURNS & SHIPPING ANALYSIS
-- =============================================

-- 7.1 Return Rate Analysis
SELECT 
    o.category,
    o.sub_category,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT r.order_id) as returned_orders,
    ROUND(
        COUNT(DISTINCT r.order_id) * 100.0 / COUNT(DISTINCT o.order_id), 2
    ) as return_rate_pct,
    SUM(o.sales) as total_sales,
    SUM(CASE WHEN r.order_id IS NOT NULL THEN o.sales ELSE 0 END) as returned_sales
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id AND r.returned = 'Yes'
GROUP BY o.category, o.sub_category
ORDER BY return_rate_pct DESC;

-- 7.2 Shipping Performance Analysis
SELECT 
    ship_mode,
    COUNT(*) as order_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders), 2) as pct_of_orders,
    AVG(DATE_PART('day', ship_date - order_date)) as avg_days_to_ship,
    AVG(sales) as avg_order_value,
    AVG(profit) as avg_profit,
    ROUND(AVG(profit / sales) * 100, 2) as avg_margin_pct
FROM orders
GROUP BY ship_mode
ORDER BY order_count DESC;

-- =============================================
-- 8. ADVANCED ANALYTICS QUERIES
-- =============================================

-- 8.1 Cohort Analysis (Customer Retention)
WITH first_orders AS (
    SELECT 
        customer_id,
        DATE_TRUNC('month', MIN(order_date)) as cohort_month
    FROM orders
    GROUP BY customer_id
),
monthly_orders AS (
    SELECT 
        f.customer_id,
        f.cohort_month,
        DATE_TRUNC('month', o.order_date) as order_month,
        DATE_PART('month', AGE(o.order_date, f.cohort_month)) as month_number
    FROM first_orders f
    JOIN orders o ON f.customer_id = o.customer_id
)
SELECT 
    cohort_month,
    COUNT(DISTINCT customer_id) as cohort_size,
    ROUND(COUNT(DISTINCT CASE WHEN month_number = 0 THEN customer_id END) * 100.0 / 
          COUNT(DISTINCT customer_id), 2) as month_0,
    ROUND(COUNT(DISTINCT CASE WHEN month_number = 1 THEN customer_id END) * 100.0 / 
          COUNT(DISTINCT customer_id), 2) as month_1,
    ROUND(COUNT(DISTINCT CASE WHEN month_number = 2 THEN customer_id END) * 100.0 / 
          COUNT(DISTINCT customer_id), 2) as month_2,
    ROUND(COUNT(DISTINCT CASE WHEN month_number = 3 THEN customer_id END) * 100.0 / 
          COUNT(DISTINCT customer_id), 2) as month_3
FROM monthly_orders
GROUP BY cohort_month
ORDER BY cohort_month;

-- 8.2 Product Affinity Analysis (Market Basket)
WITH product_pairs AS (
    SELECT 
        o1.order_id,
        o1.product_name as product1,
        o2.product_name as product2
    FROM orders o1
    JOIN orders o2 ON o1.order_id = o2.order_id 
                   AND o1.product_id < o2.product_id
),
pair_counts AS (
    SELECT 
        product1,
        product2,
        COUNT(*) as pair_count
    FROM product_pairs
    GROUP BY product1, product2
)
SELECT 
    product1,
    product2,
    pair_count,
    RANK() OVER (ORDER BY pair_count DESC) as popularity_rank
FROM pair_counts
WHERE pair_count >= 5  -- Minimum threshold
ORDER BY pair_count DESC
LIMIT 20;

-- =============================================
-- 9. DATA EXPORT QUERIES FOR TABLEAU
-- =============================================

-- 9.1 Main Dataset Export for Tableau
SELECT 
    o.*,
    p.person as regional_manager,
    CASE WHEN r.returned = 'Yes' THEN 1 ELSE 0 END as is_returned,
    ROUND(o.profit / o.sales * 100, 2) as profit_margin_pct,
    DATE_PART('year', o.order_date) as order_year,
    DATE_PART('quarter', o.order_date) as order_quarter,
    DATE_PART('month', o.order_date) as order_month,
    DATE_PART('day', o.ship_date - o.order_date) as days_to_ship
FROM orders o
LEFT JOIN people p ON o.region = p.region
LEFT JOIN returns r ON o.order_id = r.order_id;

-- 9.2 Customer Summary Export
SELECT 
    customer_id,
    customer_name,
    segment,
    COUNT(DISTINCT order_id) as total_orders,
    SUM(sales) as total_sales,
    SUM(profit) as total_profit,
    AVG(sales) as avg_order_value,
    MIN(order_date) as first_order_date,
    MAX(order_date) as last_order_date,
    DATE_PART('day', DATE '2017-12-31' - MAX(order_date)) as days_since_last_order
FROM orders
GROUP BY customer_id, customer_name, segment;

-- 9.3 Product Performance Export
SELECT 
    product_id,
    product_name,
    category,
    sub_category,
    COUNT(*) as order_count,
    SUM(sales) as total_sales,
    SUM(profit) as total_profit,
    SUM(quantity) as total_quantity,
    AVG(discount) as avg_discount,
    ROUND(SUM(profit) / SUM(sales) * 100, 2) as profit_margin_pct
FROM orders
GROUP BY product_id, product_name, category, sub_category;

-- =============================================
-- 10. PERFORMANCE MONITORING QUERIES
-- =============================================

-- 10.1 Query Performance Analysis
SELECT 
    schemaname,
    relname,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del
FROM pg_stat_user_tables
WHERE relname LIKE '%orders%' OR relname LIKE '%returns%';

-- 10.2 Table Statistics
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE tablename IN ('orders', 'returns', 'people')
ORDER BY tablename, attname;

-- =============================================
-- END OF RETAIL SALES ANALYSIS SQL SCRIPT
-- =============================================
