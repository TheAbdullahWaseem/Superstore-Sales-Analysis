-- ============================================================================
-- SUPERSTORE SALES ANALYSIS — SQL PORTFOLIO PROJECT
-- Phase 7: Advanced SQL Business Analysis
-- Author: Abdullah Waseem
-- Database: PostgreSQL | Tool: DBeaver
-- ============================================================================
-- This script answers 10 advanced business questions using the normalized
-- Superstore schema (customers, products, orders, order_items). Each query
-- demonstrates industry-relevant SQL techniques: window functions, CTEs,
-- correlated subqueries, conditional aggregation, and multi-table JOINs.
-- ============================================================================

select * from customers limit 5;
select * from products;
select * from orders limit 5;
select * from order_items limit 5;

-- ============================================================================
-- QUESTION 1: Customer Lifetime Value Ranking
-- Rank all customers by total profit generated using RANK() and DENSE_RANK()
-- side by side to demonstrate correct tie-handling behavior.
-- ============================================================================

select 
	c.customer_name,
	sum(oi.profit) total_profit,
	rank() over (
		order by sum(oi.profit) desc
	) profit_rank,
	dense_rank() over (
		order by sum(oi.profit) desc
	) profit_dense_rank
from order_items oi 
join orders o
	on o.order_id = oi.order_id
join customers c  
	on c.customer_id = o.customer_id 
group by c.customer_name 
order by total_profit desc 
limit 5;

-- INSIGHT: Emily Phan is the top customer by profit ($34,005.44), nearly
-- double customer #5. Retaining top-tier customers matters more than
-- acquiring new ones for protecting overall profitability.

-- ============================================================================
-- QUESTION 2: Running Total & Moving Average of Monthly Revenue
-- Calculate cumulative revenue over time alongside a 3-month moving average
-- to smooth out volatility and reveal the underlying trend.
-- ============================================================================

with monthly_revenue as (
	select
		o.year,
		o.month,
		o.month_name,
		sum(oi.sales) as revenue
	from order_items oi
	join orders o
		on o.order_id = oi.order_id
	group by o.year, o.month, o.month_name
)
select 
	year,
	month, 
	month_name,
	revenue,
	sum(revenue) over (
		order by year, month
	) as running_total_revenue,
	round(
		avg(revenue) over (
			order by year, month
			rows between 2 preceding and current row
		), 2
	) as moving_avg_3month
from monthly_revenue
order by year, month;

-- Insight: Revenue accumulated to $14.92M by end of 2012, with the 3-month
-- moving average staying fairly flat ($300K-$330K range) in recent months 
-- consistent with your earlier finding of no clear growth trend across 2009-2012

-- ============================================================================
-- QUESTION 3: Top 3 Products by Profit Within Each CategoryS
-- Identify the top 3 most profitable products in every category using a
-- ranked CTE, correctly handling the fact that window functions cannot be
-- filtered directly in a WHERE clause.
-- ============================================================================

with ranked_products as (
	select 
		p.product_category,
		p.product_name,
		sum(oi.profit) as total_profit,
		row_number() over (
			partition by p.product_category
			order by sum(oi.profit) desc 
		) as profit_rank
	from order_items oi 
	join products p 
		on oi.product_id = p.product_id
	group by p.product_category, p.product_name 
)
select 
	product_category,
	product_name,
	total_profit,
	profit_rank
from ranked_products 
where profit_rank <= 3
order by product_category, profit_rank;

-- Insight: Top performers are dominated by high-ticket equipment 
-- (executive chairs, binding machines, copiers/printers) rather than everyday 
-- supplies. The Furniture categorys #1 product ($79,284.78) alone outearns 
-- its #2 and #3 combined, showing profit within categories is concentrated in 
-- a few standout items, not spread evenly.

-- ============================================================================
-- QUESTION 4: Month-over-Month and Year-over-Year Revenue Growth
-- Calculate both MoM and YoY percentage revenue change in a single query,
-- with divide-by-zero protection.
-- ============================================================================

with monthly_revenue as (
	select 
		o.year,
		o.month,
		o.month_name,
		sum(oi.sales) as revenue
	from orders o 
	join order_items oi 
		on o.order_id = oi.order_id
	group by o.year, o.month, o.month_name 
)
select 
	year,
	month,
	month_name,
	revenue,
	lag(revenue) over (
		order by year, month
	) as prev_month_revenue,
	case
		when lag(revenue) over (order by year, month) is null then null
		when lag(revenue) over (order by year, month) = 0 then null 
		else round(
			(revenue - lag(revenue, 12) over (order by year, month))
			/ lag(revenue, 12) over (order by year, month) * 100, 2
		)
	end as yoy_growth_pct
from monthly_revenue
order by year, month;

-- Insight: Monthly revenue is volatile with no consistent growth pattern — 
-- YoY swings range from -30% to +46% within 2012 alone. This confirms your 
-- earlier finding of no clear multi-year growth trend, and suggests revenue 
-- is driven more by individual large orders than steady business expansion.

-- ============================================================================
-- QUESTION 5: High-Value, High-Risk Customers
-- Identify customers whose total sales rank in the top 20% but whose average
-- profit margin falls below the company-wide average — flagging high-revenue
-- customers who are quietly unprofitable.
-- ============================================================================

with customer_metrics as (
	select 
		c.customer_id,
		c.customer_name,
		sum(oi.sales) as total_sales,
		avg(oi.profit_margin) as avg_margin
	from order_items oi 
	join orders o 
		on o.order_id = oi.order_id
	join customers c
		on c.customer_id = o.customer_id
	group by c.customer_id, c.customer_name
),
sales_threshold as (
	select 
		percentile_cont(0.8) within group (
			order by total_sales
		) as p80_sales
	from customer_metrics 
),
company_avg as (
	select avg(profit_margin) as avg_margin
	from order_items
)
select 
	cm.customer_name,
	round(cm.total_sales, 2) as total_sales,
	round(cm.avg_margin, 2) as avg_margin
from customer_metrics cm,
	 sales_threshold st,
	 company_avg ca
where cm.total_sales >= st.p80_sales
	and cm.avg_margin < ca.avg_margin
order by cm.total_sales desc;

-- Insight: All flagged customers show negative average margins despite being 
-- top-20% spenders — several severely so (Jay Fine at -82.77%). This confirms 
-- high revenue does not guarantee profitability at the customer level, and these 
-- accounts need margin review even if their total dollar contribution looks strong.

-- ============================================================================
-- QUESTION 6: Sub-Category Profitability Rank Within Each Region
-- Rank every product sub-category's profit margin within its own region,
-- surfacing each region's best and worst-performing sub-category.
-- ============================================================================

with subcategory_region_margin as (
	select 
		c.region,
		p.product_sub_category,
		avg(oi.profit_margin) as avg_margin,
		rank() over (
			partition by c.region
			order by avg(oi.profit_margin) desc 
		) as best_rank,
		rank() over (
			partition by c.region
			order by avg(oi.profit_margin) asc
		) as worst_rank
	from order_items oi
	join orders o
		on o.order_id = oi.order_id
	join customers c
		on c.customer_id = o.customer_id
	join products p
		on p.product_id = oi.product_id
	group by c.region,
			 p.product_sub_category	
)
select 	
	region, 
	product_sub_category,
	round(avg_margin, 2) as avg_margin,
	case
		when best_rank = 1 then 'Best in Region'
		when worst_rank =1 then 'worst in Region'
	end as performance_flag
from subcategory_region_margin 
where best_rank = 1 or worst_rank = 1
order by region, avg_margin desc;

-- Insight: Labels is the strongest sub-category across every single region 
-- (~26-28% margin), while Appliances is the weakest in 3 of 4 regions 
-- (down to -59.64% in East). This consistency suggests a company-wide pricing 
-- or cost issue with Appliances rather than a regional problem, and Labels could 
-- be a category worth expanding.

-- ============================================================================
-- QUESTION 7: Discount Threshold Where Profitability Breaks Even
-- Group orders into discount bands and identify the exact band where average
-- profit margin flips from positive to negative.
-- ============================================================================

select
	discount_band,
	count(*) as num_orders,
	round(avg(discount), 4) as avg_discount,
	round(avg(profit_margin), 2) as avg_profit_margin
from order_items
group by discount_band 
having avg(profit_margin) < 0
order by avg(profit_margin) asc;

-- Insight: All discount bands show negative average margin, even 'No Discount' 
-- orders (-7.4%). This confirms discounting is not the root cause of losses — 
-- the problem lies elsewhere (e.g., underpricing or high-cost sub-categories 
-- like Appliances), not in how much discount is given

-- ============================================================================
-- QUESTION 8: Customer Order Frequency & Retention Segments
-- Classify customers into One-Time, Occasional, and Frequent segments based
-- on order count, then measure total profit contribution per segment.
-- ============================================================================

with customer_orders as (
	select
		c.customer_id,
		c.customer_name,
		count(distinct o.order_id) as order_count,
		sum(oi.profit) as total_profit
	from order_items oi
	join orders o
		on o.order_id = oi.order_id
	join customers c
		on c.customer_id = o.customer_id
	group by c.customer_id, c.customer_name
),
segmented_customers as (
	select 
		customer_id,
		customer_name,
		order_count,
		total_profit,
		case
			when order_count = 1 then 'One-Time'
			when order_count between 2 and 5 then 'Occasional'
			else 'Frequent'
		end as customer_segment_type
	from customer_orders
)
select 
	customer_segment_type,
	count(*) as num_customers,
	round(sum(total_profit), 2) as total_segment_profit,
	round(avg(total_profit), 2) as avg_profit_per_customer
from segmented_customers 
group by customer_segment_type
order by total_segment_profit desc;

-- Insight: Frequent customers (467 people, 59% of the base) drive $1.24M in 
-- profit — the vast majority of total profit. One-time buyers are a tiny group 
-- (10 customers) contributing almost nothing, confirming retention/repeat 
-- business matters far more than one-off acquisition here.

-- ============================================================================
-- QUESTION 9: Shipping Performance vs. Category Benchmark
-- Identify every order that shipped slower than its product category's
-- average shipping time, and rank how far over benchmark each one is.
-- ============================================================================

select
	oi.row_id,
	p.product_category,
	o.shipping_days,
	cat_avg.avg_shipping_days,
	round(o.shipping_days - cat_avg.avg_shipping_days, 2) as days_over_benchmark,
	rank() over (
		partition by p.product_category
		order by o.shipping_days - cat_avg.avg_shipping_days desc
	) as delay_rank
from order_items oi
join orders o
	on o.order_id = oi.order_id
join products p
	on p.product_id = oi.product_id
join (
	select
		p2.product_category,
		avg(o2.shipping_days) as avg_shipping_days
	from order_items oi2
	join orders o2
		on o2.order_id = oi2.order_id
	join products p2
		on p2.product_id = oi2.product_id
	group by p2.product_category
) cat_avg
	on cat_avg.product_category = p.product_category
where o.shipping_days > cat_avg.avg_shipping_days
order by p.product_category, delay_rank
limit 30;

-- Insight: Furniture average shipping time is just ~2 days, but the worst outlier
-- took 17 days — 15 days over benchmark. A large cluster of orders consistently 
-- ships 7-9 days (5-7 days late), suggesting a systemic fulfillment issue for 
-- certain Furniture items, not just isolated incidents.

-- ============================================================================
-- QUESTION 10: Executive KPI Snapshot with Year-over-Year Comparison
-- A single query producing revenue, profit, margin, and order count for the
-- current year vs. previous year side by side 
-- ============================================================================

select
	round(sum(case when o.year = 2012 then oi.sales else 0 end), 2) as revenue_2012,
	round(sum(case when o.year = 2011 then oi.sales else 0 end), 2) as revenue_2011,
	round(sum(case when o.year = 2012 then oi.profit else 0 end), 2) as profit_2012,
	round(sum(case when o.year = 2011 then oi.profit else 0 end), 2) as profit_2011,
	round(
		sum(case when o.year = 2012 then oi.profit else 0 end)
		/ nullif(sum(case when o.year = 2012 then oi.sales else 0 end), 0) * 100, 2
	) as margin_pct_2012,
	round(
		sum(case when o.year = 2011 then oi.profit else 0 end)
		/ nullif(sum(case when o.year = 2011 then oi.sales else 0 end), 0) * 100, 2
	) as margin_pct_2011,
	count(distinct case when o.year = 2012 then o.order_id end) as orders_2012,
	count(distinct case when o.year = 2011 then o.order_id end) as orders_2011
from order_items oi
join orders o
	on o.order_id = oi.order_id
where o.year in (2011, 2012);

-- Insight: 2012 revenue grew 8.2% over 2011 ($3.72M vs $3.44M) and order volume rose
-- too (1,392 vs 1,317), but profit actually declined ($341.9K vs $381.5K) despite
-- margin staying flat at 11.1%. More orders and revenue did not translate to more
-- profit — worth investigating cost structure or product mix shifts in 2012.


-- ============================================================================
-- END OF ANALYSIS
-- ============================================================================
-- Summary: This script answers 10 advanced business questions against the
-- normalized Superstore schema, demonstrating window functions (RANK,
-- DENSE_RANK, ROW_NUMBER, LAG, PARTITION BY, window frames), CTEs (single
-- and multi-step), correlated and derived-table subqueries, HAVING clauses,
-- conditional aggregation, and percentile calculations.
--
-- Key findings:
-- - Profit is highly concentrated among top customers and top products
-- - Discount level is not the primary driver of unprofitability
-- - Appliances is consistently the weakest sub-category across regions
-- - Frequent customers (59% of base) generate the vast majority of profit
-- - 2012 revenue and order volume grew over 2011, but profit declined,
--   pointing to a cost/margin issue rather than a demand issue
--
-- Author: Abdullah Waseem
-- ============================================================================