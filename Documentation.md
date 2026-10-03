# Northwind Sales Dashboard Documentation

This note is for someone who already understands relational databases and reports, and wants to know what this project does and why it is shaped this way.

## Goal

Northwind Traders is a sample trading company. The job is an end-to-end sales report: prepare the data in PostgreSQL, model it as a star schema in Power BI, calculate the business numbers in DAX, and show them on three pages.

The grain of the analysis is one order line: one product on one order. Revenue is not the list price. It is what was actually charged after the line discount.

## What is prepared in SQL, and why

Power BI could join the raw tables itself. The assignment asks for that work in SQL, so the report imports clean tables instead of rebuilding the business rules in Power Query.

Three views do that.

**`v_Product_Enriched`** is the product dimension. `products` is left-joined to `categories` and `suppliers` on `category_id` and `supplier_id`. The view keeps product id, product name, category name, the supplier company name renamed to `supplier`, and unit price. A left join is used so a product is not dropped if a category or supplier is missing. Supplier stays a column on the product, not its own dimension, because the report never filters or charts suppliers on their own. Folding category and supplier into the product table keeps the model a star. A separate category table hanging off products would be a snowflake.

**`v_Order_Sales`** is the fact table. `orders` is inner-joined to `order_details` on `order_id`, so every row is a line that belongs to a real order. The view keeps the foreign keys the model needs later (`product_id`, `customer_id`, `employee_id`, `ship_via`) and the dates, quantity, discount, and unit price. It does not pull product names, customer names, or employee names. Those come from the dimensions. Putting them here would duplicate descriptive data onto every line and fight the star schema.

The line amount is calculated in SQL, not in DAX:

`unit_price * quantity * (1 - discount)`

stored as `total_line_amount`. The unit price and discount on the line are the values sold, not the current list price on `products`. Computing the amount once, in the database, means every visual uses the same definition.

**`v_Customer_Geo`** is the customer dimension for the map. It keeps `customer_id`, company name, city, and country, and only for customers who appear on at least one order (`INNER JOIN orders`, then `DISTINCT`). Northwind has 91 customers and 89 of them have ordered. The two with no orders are not useful on a sales map, and they would be an unmatched side of the relationship. `customer_id` is included even though the brief only names city and country, because the dimension has to join back to the fact table. In this database that id is text (`ALFKI`), not an integer.

`employees` and `shippers` are not views. They are already small, clean dimensions, so they are imported as tables. `ship_via` on the order is the shipper key; it is renamed to `Shipper ID` in Power Query so the relationship is obvious.

## What Power BI imports, and what it does not

The model loads only:

- `v_Product_Enriched` as `Products`
- `v_Order_Sales` as `Sales`
- `v_Customer_Geo` as `Customers`
- `employees` as `Employees`
- `shippers` as `Shippers`

The raw `orders`, `order_details`, `products`, `categories`, `customers`, and `suppliers` tables are not imported. Their useful content is already in the views. Importing them again would duplicate facts and invite extra relationships.

Power Query does not redo the joins. It drops columns the report will not use (employee photos, notes, and the nested related-table columns the PostgreSQL connector adds), renames technical names (`shipped_date` becomes `Shipping Date`), and sets types: dates as dates, money as currency, keys as whole numbers except `Customer ID`, which stays text. Choosing columns is safer than deleting a list of unwanted ones, because a newly added connector column would not slip through.

`Full Name` on `Employees` is a small calculated column, `First Name` plus `Last Name`. Last names in this database happen to be unique, but the charts and the employee slicer are clearer with the full name. The relationship still uses `Employee ID`, not the name.

## The model

`Sales` is the fact. Around it:

| Dimension | Connects to |
|---|---|
| `Calendar[Date]` | `Sales[Order Date]` |
| `Products[Product ID]` | `Sales[Product ID]` |
| `Customers[Customer ID]` | `Sales[Customer ID]` |
| `Employees[Employee ID]` | `Sales[Employee ID]` |
| `Shippers[Shipper ID]` | `Sales[Shipper ID]` |

Each relationship is many-to-one, with the "one" side on the dimension and the filter direction single, from the dimension into `Sales`. A country, a product, or a year filters the fact. The fact does not filter back into the dimensions. Bidirectional filters are not used; nothing in this report needs them, and they make filter context harder to reason about.

`Calendar` is not a table in PostgreSQL. It is a DAX table of one row per day from the first `Order Date` to the last, plus year, month number, month name, and `YYYY-MM`. It is marked as the model's date table on the `Date` column, and `Month` is sorted by `Month Number` so charts run January to December instead of alphabetically. Time intelligence (`DATESYTD`, `SAMEPERIODLASTYEAR`) needs that table. The calendar is tied to `Order Date` only. `Shipping Date` and `Required Date` stay attributes of the line; a second active relationship to the same calendar is not allowed, and order date is the date the sales questions use.

`_Measures` is an otherwise empty table that only holds measures. It is not related to `Sales`. Measures do not need a relationship; they read whatever filter context the visual has.

![Power BI star schema](00-data-model.png)

## The measures

All of them live in `_Measures` and use `VAR` so the intent is named instead of nested inside one expression.

- **Total Revenue** is `SUM` of `Sales[Total Line Amount]`. Every other money measure is defined from this, so "sales" means one thing.
- **Total Orders** is `DISTINCTCOUNT` of `Order ID`. A count of rows would count lines, not orders. An order with three products is one order.
- **Average Order Value** is `DIVIDE` of revenue by orders. `DIVIDE` returns blank when there are no orders, which is the right result: there is no average, rather than zero or an infinity error.
- **Total Quantity Sold** is the sum of quantity.
- **Revenue YTD** is revenue under `DATESYTD` on `Calendar[Date]`: from 1 January of the selected year through the last visible date.
- **Revenue Previous Year** is revenue under `SAMEPERIODLASTYEAR`: the same dates shifted back one year.
- **YoY Growth %** is `(current - previous) / previous`, again with `DIVIDE`. If the previous period is empty, the result is blank.
- **% Discounted** is the share of revenue that comes from lines where `Discount > 0`, not the average discount rate.
- **Top Product Sales** is the revenue of the top three products by revenue, using `TOPN` over `ALLSELECTED ( Products )`, so the "top three" respects the current slicers instead of always being the global top three.
- **Drill-through Title** is a presentation helper. It uses `SELECTEDVALUE` to build a title such as `Order Details — Côte de Blaye, 1997` from the product and year carried into the page.

YTD, the discounted share, and top-three sales are not placed on a visual. The assignment asks for the measures. The pages ask for a specific set of charts. Leaving a measure off a page does not remove it from the model.

One reading of the 1997 overview is easy to misread. YoY growth on that page is about 197%, and the previous-year line only starts in July. Northwind's first year, 1996, has no orders before July, so "the same period last year" for January–June 1997 is empty, and the 1996 baseline is only half a year. The measure is doing what it was asked to do. The data, not the formula, makes that year look extreme.

## The three pages

**Executive Overview** answers "how is the business doing?". Four cards show Total Revenue, YoY Growth %, Total Orders, and Average Order Value. A line chart plots Total Revenue and Revenue Previous Year by calendar month. A map uses customer country with revenue as the bubble size, so the point is where customers are, not where the goods were shipped. A donut shows revenue by shipper. A year slicer is on the page so the comparison is for one year. For 1997 the cards read about $617K revenue, 408 orders, and about $1.51K per order, and the donut's three shippers add back to that same $617K.

![Executive Overview](01-executive-overview.png)

**Detailed Analysis** answers "which products and people". A bar chart shows the top 10 products by revenue, using a Top N filter on the visual so the other products are not drawn and then hidden. A decomposition tree splits revenue from category to product to customer; the user opens the next level, which is what that visual is for. A column chart shows revenue by employee full name. Slicers for year, category, and employee sit on the page and filter all of those visuals, because the relationships are single-direction into `Sales` and the measures respect that filter context.

![Detailed Analysis](02-detailed-analysis.png)

Z-pattern reading starts at the top left and finishes at the bottom right, so the first glance belongs on the result. On both pages the slicers still sit at the top right of the first row: the year on the overview, and the year, employee, and category on the detailed page. That is a deliberate choice. Those filters are the context the charts depend on, so they stay in that corner even though the reading pattern would not put a control there.



**Drill-through** answers "show me the lines behind this product". The page's drill-through field is `Products[Product]`. From the top-10 chart, a right-click on a product opens this page with that product applied. "Keep all filters" is on, so the year slicer comes along too. Its dynamic title shows the selected product and year. The table lists order date, customer, product, quantity, and revenue; Order ID is omitted because it does not help the reader answer who bought the product, when, how many, or for how much. The headers differ slightly from the brief on purpose: Order Date instead of Date, because the line also has a shipping date and a required date; Product instead of Products, because each row is one product; Total Revenue instead of Amount, because that is the name used on the other pages. Order Date uses the compact, unambiguous `dd-MMM-yyyy` format, Total Revenue is currency with two decimal places, and Quantity is not summarized. Opening the page directly, with no drill-through filter, shows every line. That is expected. The filter arrives with the drill. For Côte de Blaye in 1997 the lines total about $49K, which matches that product's bar on the detailed page.

![Drill-through Order Details](03-drill-through.png)

## Mobile layouts

Mobile layouts are included even though the brief only requires the desktop report. They reuse the same visuals and measures rather than creating a second report. The overview stacks the cards, slicer, trend, map, and shipper share vertically. Detailed Analysis uses compact dropdown slicers and gives each chart enough height to remain readable; the decomposition tree stays interactive because its three levels cannot fit side by side on a phone. The drill-through table shows every row vertically and uses horizontal scrolling for its five columns. These layout changes do not alter the desktop pages.

## What was left out on purpose

There is no separate supplier chart. The project goal mentions suppliers, but the task list only asks for the supplier name on the product dimension.

There is no second date relationship, no bidirectional filter, and no import of the operational tables that the views already replaced.

Employee photos, notes, and the connector's nested tables are removed in Power Query because they are not part of any question the report asks.
