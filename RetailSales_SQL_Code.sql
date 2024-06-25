--View each table for familiarizing oneself with the data

SELECT TOP(10) * FROM dbo.customer_data;
SELECT TOP(10) * FROM dbo.item_data;
SELECT TOP(10) * FROM dbo.order_data;
SELECT TOP(10) * FROM dbo.product_type;
SELECT TOP(10) * FROM dbo.sale_data;

-- What are the Most Purchased items?
-- We need to utilizse the sale_data table for order counts, and join back to the item_data table for Product descriptions

SELECT 
i.EAN,
i.product,
SUM(s.quantityOrdered) AS quantityOrdered
FROM item_data i 
JOIN sale_data s 
	ON i.EAN = s.EAN
GROUP BY
i.EAN,
i.product
ORDER BY 
SUM(s.quantityOrdered) DESC;

-- Of these items, how much money did we make? We need to add in the Retail Sales and the Margin from item_data and multiply by our quantityOrdered

SELECT 
i.EAN,
i.product,
SUM(s.quantityOrdered) AS quantityOrdered,
SUM(s.quantityOrdered) * i.retail AS retailSales,
SUM(s.quantityOrdered) * i.margin AS marginDollars
FROM item_data i 
JOIN sale_data s 
	ON i.EAN = s.EAN
GROUP BY
i.EAN,
i.product,
i.retail,
i.margin
ORDER BY 
SUM(s.quantityOrdered) DESC;

-- Great! But which products did we make the most money on? Perhaps we only care about products with greater than 10,000 units sold

SELECT 
i.EAN,
i.product,
sq.quantityOrdered,
sq.retailSales,
sq.marginDollars
FROM item_data i 
JOIN (SELECT 
		i.EAN,
		SUM(s.quantityOrdered) AS quantityOrdered,
		SUM(s.quantityOrdered) * i.retail AS retailSales,
		SUM(s.quantityOrdered) * i.margin AS marginDollars
		FROM item_data i
		JOIN sale_data s 
		ON i.EAN = s.EAN
		GROUP BY
		i.EAN,
		i.retail,
		i.margin) sq
ON sq.EAN = i.EAN
WHERE 1=1
	AND sq.quantityOrdered >= 10000
ORDER BY 
sq.marginDollars DESC;

-- Are our Top Producing UNIT sales products very different from our Top Producing RETAIL sales products? What about actual cash generation?
-- We'll start with ranking each item and comparing those ranks visually

SELECT 
i.EAN,
i.product,
RANK() OVER (ORDER BY sq.quantityOrdered DESC) AS quantityOrderedRank,
RANK() OVER (ORDER BY sq.retailSales DESC) AS retailSalesRank,
RANK() OVER (ORDER BY sq.marginDollars DESC) AS marginDollarsRank

FROM item_data i 
JOIN (SELECT 
		i.EAN,
		SUM(s.quantityOrdered) AS quantityOrdered,
		SUM(s.quantityOrdered) * i.retail AS retailSales,
		SUM(s.quantityOrdered) * i.margin AS marginDollars
		FROM item_data i
		JOIN sale_data s 
		ON i.EAN = s.EAN
		GROUP BY
		i.EAN,
		i.retail,
		i.margin) sq
ON sq.EAN = i.EAN
GROUP BY 
i.EAN,
i.product,
sq.quantityOrdered,
sq.retailSales,
sq.marginDollars
ORDER BY 
sq.marginDollars DESC;

-- Now we see that our Retail Sales and Margin Dollars are very similar, with some variation by product. These do not directly correspond to units sold. We see that our top seller by count is our lowest seller by retail and margin! 
-- No single metric paints an entire picture

--We do similar analysis, but with different attributes. What about overall Retail sales by State? We have an address, but not a State column. We'll extract that in the subquery

SELECT 
sq.orderState,
SUM(sq.quantityOrdered) AS quantityOrdered,
SUM(sq.retailSales) AS retailSales,
SUM(sq.marginDollars) AS marginDollars
FROM item_data i 
JOIN (SELECT 
		i.EAN,
		SUBSTRING(c.purchaseAddress,len(c.purchaseAddress)-7,2) orderState,
		SUM(s.quantityOrdered) AS quantityOrdered,
		SUM(s.quantityOrdered) * i.retail AS retailSales,
		SUM(s.quantityOrdered) * i.margin AS marginDollars
		FROM item_data i
		JOIN sale_data s 
		ON i.EAN = s.EAN
		JOIN dbo.order_data o
		ON o.orderID = s.orderID
		JOIN dbo.customer_data c 
		ON o.custID = c.custID
		GROUP BY
		i.EAN,
		i.retail,
		i.margin,
		c.purchaseAddress) sq
ON sq.EAN = i.EAN
GROUP BY 
sq.orderState
ORDER BY 
SUM(sq.retailSales) DESC;



-- I want to pull together a table to help me visualize Month over Month sales. My goal is to pop this into a visualization program, so using SQL to do the calculation lift will make my dashboard more performant



-- First I'm going to pull together the attributes needed in a CTE, as well as sum everything down to the Month and Year of order, not the Date
WITH attributes AS (

SELECT 
YEAR(o.orderDate)*100+MONTH(o.orderDate) AS orderMonth, /*extract YYYYMM from order date for aggregations*/
i.product AS productName,
SUM(s.quantityOrdered) AS quantityOrdered
FROM 
dbo.order_data o 
JOIN dbo.sale_data s
ON o.orderID = s.orderID
JOIN dbo.item_data i
ON s.EAN = i.EAN
GROUP BY o.orderDate, i.product)

--Create a table with a LM lookback using windows functions LAG()

SELECT 
a.orderMonth,
a.productName,
SUM(a.quantityOrdered) AS currentMonthOrdered,
LAG(SUM(a.quantityOrdered), 1, 0) OVER (PARTITION BY a.productName ORDER BY a.orderMonth) AS priorMonthOrdered
FROM attributes a
GROUP BY a.orderMonth, a.productName;


-- Finally, I want to do some exploratory analysis in Excel. For that I want a single, flat style table that I can perform pivot tables on and use to create graphs and visualizations. I'm going to pull together additional attributes and figures so I have a variety of options
-- I will also add a "pretty" format to the names of my fields so it can be easily worked with in a familiar way

SELECT 
DATENAME(MONTH, DATEADD(MONTH, DATEPART(mm,o.orderDate), -1)) AS [Month],
YEAR(o.orderDate)*100+MONTH(o.orderDate) AS [Order Month], 
SUBSTRING(c.purchaseAddress,LEN(c.purchaseAddress)-7,2) AS [Order State],
i.product AS [Product],
p.Product_Type AS [Product Type],
SUM(s.quantityOrdered) AS [Quantity Ordered],
SUM(s.retail) * SUM(s.quantityOrdered)  AS [Retail],
(SUM(s.retail) - SUM(s.costOfGoods)) * SUM(s.quantityOrdered)  AS [Margin]
FROM 
dbo.order_data o 
JOIN dbo.customer_data c 
ON o.custID = c.custID
JOIN dbo.sale_data s
ON o.orderID = s.orderID
JOIN dbo.item_data i
ON s.EAN = i.EAN
JOIN dbo.product_type p
ON i.product = p.Product
GROUP BY o.orderID, c.custID, o.orderDate, c.purchaseAddress, s.EAN, i.product, p.Product_Type;