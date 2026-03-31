

/**********************************
Query Store Runtime Intervals Demo
**********************************/

-- Clear the Query Store
ALTER DATABASE DatabaseA SET QUERY_STORE CLEAR;
GO

-- Run a query
SELECT *
FROM Sales.SalesOrderDetail

-- Grab the plan_id from the QS plan DMV
SELECT * from sys.query_store_plan

-- Look at the runtime stats
-- Focus on count_exec and stdev_duration
SELECT * FROM sys.query_store_runtime_stats WHERE plan_id = 1

-- Run the same query again
SELECT *
FROM Sales.SalesOrderDetail

-- Look at the runtime stats again
SELECT * FROM sys.query_store_runtime_stats WHERE plan_id = 1

-- Look at the intervals involved
SELECT * FROM sys.query_store_runtime_stats_interval

/**********************************
Query Store DMVs
**********************************/

-- Let's look at some runtime statistics
SELECT * FROM sys.query_store_runtime_stats

-- Query top 10 queries based on avg. duration
-- Here we join most of the DMVs together
SELECT TOP 10
  qt.query_sql_text,
  CAST(qp.query_plan AS XML) AS 'Execution Plan',
  rs.avg_duration/1000 AS 'Avg. Duration in ms'
FROM sys.query_store_plan qp
INNER JOIN sys.query_store_query q
  ON qp.query_id = q.query_id
INNER JOIN sys.query_store_query_text qt
  ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_runtime_stats rs
  ON qp.plan_id = rs.plan_id
ORDER BY rs.avg_duration DESC


-- Let's see if we can identify queries that used parallelism
-- Execute a parallel query first
SELECT *
FROM Sales.SalesOrderDetail
ORDER BY CarrierTrackingNumber DESC

SELECT
  qt.query_sql_text,
  CAST(query_plan AS XML) AS 'Execution Plan',
  rs.count_executions,
  rs.avg_dop,
  rs.last_dop
FROM sys.query_store_plan qp
INNER JOIN sys.query_store_query q
  ON qp.query_id = q.query_id
INNER JOIN sys.query_store_query_text qt
  ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_runtime_stats rs
  ON qp.plan_id = rs.plan_id
WHERE rs.last_dop > 1


-- Create demo stored procedure
CREATE OR ALTER PROCEDURE sp_SalesbyProduct
	@ProductID INT
AS
SELECT 
  SalesOrderID, 
  OrderQty,
  UnitPrice
FROM Sales.SalesOrderDetail
WHERE ProductID = @ProductID
GO

-- Enable actual plan
-- Query 1, should result in two Index Seek operations
DBCC FREEPROCCACHE
GO

EXEC sp_SalesbyProduct @ProductID = 710
GO

-- Query 2, should result in one Index Seek and one Index Scan operation
DBCC FREEPROCCACHE
GO

EXEC sp_SalesbyProduct @ProductID = 870
GO

-- Things can get pretty complicated fast!
-- Take a look at how we can identify queries with multiple plans
WITH CTE_QS_Multiple_Plans (query_id, plan_count)
	AS
		(
		SELECT
		  qsp.query_id,
		  COUNT(qsp.plan_id)
		FROM sys.query_store_plan qsp WITH (NOLOCK)
		GROUP BY query_id HAVING COUNT(plan_id) > 1
		)

SELECT
  cte.query_id AS 'Query ID',
  qsp.plan_id AS 'Plan ID',
  CONVERT(datetime, SWITCHOFFSET(CONVERT(datetimeoffset, qsp.last_execution_time), DATENAME(TzOffset, SYSDATETIMEOFFSET()))) AS 'Last Execution Time',
  qsqt.query_sql_text AS 'Query Text',
  qsp.engine_version AS 'Engine Version',
  qsp.[compatibility_level] AS 'Compatibility Level',
  CAST(qsp.query_plan AS XML) AS 'Execution Plan'
FROM CTE_QS_Multiple_Plans cte
INNER JOIN sys.query_store_plan qsp
  ON cte.query_id = qsp.query_id
INNER JOIN sys.query_store_query qsq WITH (NOLOCK)
  ON qsp.query_id = qsq.query_id
INNER JOIN sys.query_store_query_text qsqt WITH (NOLOCK)
  ON qsq.query_text_id = qsqt.query_text_id
ORDER BY cte.query_id ASC

/**********************************
sp_WhatsupQueryStore
**********************************/

-- By default nothing is returned
EXEC sp_WhatsupQueryStore
  @dbname = 'DatabaseA'

-- Use the @return_all parameter to return everything
EXEC sp_WhatsupQueryStore
  @dbname = 'DatabaseA',
  @return_all = 1

-- You can decide on what info you want to return
EXEC sp_WhatsupQueryStore
  @dbname = 'DatabaseA',
  @return_top_executed = 1,
  @return_multiple_plans = 1

-- You can also specify the timewindow to limit results
-- For instance, return all query information in the last 4 hours
-- and limit the results to the top 10 
EXEC sp_WhatsupQueryStore
  @dbname = 'DatabaseA',
  @return_top_executed = 1,
  @timewindow = 4,
  @topqueries = 10

/**********************************
Query Store Replay
**********************************/

-- Database A is in 2012 compatibility mode
-- Database B in 2016

-- Run the T-SQL script before running the different Powershell commands

-- Example 1: .\QueryStoreReplay.ps1 -sourceserver localhost -SourceDatabase DatabaseA -TargetServer localhost -TargetDatabase DatabaseB -TimeWindow 1
-- Example 2: .\QueryStoreReplay.ps1 -sourceserver localhost -SourceDatabase DatabaseA -TargetServer localhost -TargetDatabase DatabaseB -TimeWindow 1 -PlanConsistency $true -ComparePerf $True -IncludeStatements $true

-- Switch to our source database
USE [DatabaseA]
GO

-- Clear Query Store
ALTER DATABASE DatabaseA SET QUERY_STORE CLEAR;
GO

-- Execute some queries
SELECT Name, ProductNumber, ListPrice AS Price
FROM Production.Product 
ORDER BY Name ASC;
GO

SELECT DISTINCT p.LastName, p.FirstName 
FROM Person.Person AS p 
JOIN HumanResources.Employee AS e
    ON e.BusinessEntityID = p.BusinessEntityID WHERE 5000.00 IN
    (SELECT Bonus
     FROM Sales.SalesPerson AS sp
     WHERE e.BusinessEntityID = sp.BusinessEntityID);
GO

SELECT p.Name AS ProductName, 
NonDiscountSales = (OrderQty * UnitPrice),
Discounts = ((OrderQty * UnitPrice) * UnitPriceDiscount)
FROM Production.Product AS p 
INNER JOIN Sales.SalesOrderDetail AS sod
ON p.ProductID = sod.ProductID 
ORDER BY ProductName DESC;
GO

-- Switch to target database
USE [DatabaseB]
GO

-- Clear Query Store
ALTER DATABASE DatabaseB SET QUERY_STORE CLEAR;
GO