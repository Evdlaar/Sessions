/*********************************************************************************************
Introducing the SQL Server 2016 Query Store
Demo Scripts
(C) 2016, Enrico van de Laar

Feedback: mailto:enrico@dotnine.net

License: 
	This demo script, that is part of the Introducing the SQL Server 2016 Query Store 
	session, is free to download and use for personal, educational, and internal 
	corporate purposes, provided that this header is preserved. Redistribution or sale 
	of this script, in whole or in part, is prohibited without the author's express 
	written consent.
*********************************************************************************************/

USE [AdventureWorks]
GO

/*
Demo: Enabling and configuring the Query Store
*/

-- Enable the Query Store through T-SQL
ALTER DATABASE AdventureWorks SET QUERY_STORE = ON;

-- Change Query Store configuration example
-- All options can be found on the ALTER DATABASE MSDB page
-- https://msdn.microsoft.com/en-us/library/bb522682.aspx

ALTER DATABASE AdventureWorks
SET QUERY_STORE
  (
  MAX_STORAGE_SIZE_MB = 250, -- Maximum size of the Query Store
  SIZE_BASED_CLEANUP_MODE = AUTO, -- Cleanup mode
  CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30) -- Cleanup policy, 30 days
  );

-- Purge the Query Store
ALTER DATABASE AdventureWorks SET QUERY_STORE CLEAR;

/*
Demo: Query Store DMVs
*/

-- Query the Query Store configuration
SELECT * FROM sys.database_query_store_options;

-- Show all the runtime statistics we can query on
SELECT * FROM sys.query_store_runtime_stats;

-- Query top 10 queries based on avg. duration
SELECT TOP 10
  qt.query_sql_text,
  CAST(query_plan AS XML) AS 'Execution Plan',
  rs.avg_duration
FROM sys.query_store_plan qp
INNER JOIN sys.query_store_query q
  ON qp.query_id = q.query_id
INNER JOIN sys.query_store_query_text qt
  ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_runtime_stats rs
  ON qp.plan_id = rs.plan_id
ORDER BY rs.avg_duration DESC;

-- Parallel Query, execute first
SELECT *
FROM Sales.SalesOrderDetail
ORDER BY CarrierTrackingNumber DESC

-- Query the Query Store for parallel queries
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
WHERE rs.last_dop > 1;


/*
Demo: Forcing Execution Plans
*/

-- Drop all plan guides before testing
EXEC sp_control_plan_guide N'DROP ALL';

-- Get two Execution Plans for the same query
-- Query 1, should result in two Index Seek operations
DBCC FREEPROCCACHE
GO

EXEC sp_executesql
@stmt = N'SELECT
  p.name,
  tha.TransactionDate,
  tha.TransactionType,
  tha.Quantity,
  tha.ActualCost
FROM Production.TransactionHistoryArchive tha
JOIN Production.Product p
ON tha.ProductID = p.ProductID
WHERE p.ProductID = @productID', 
@params = N'@productID INT',
@productID = 461

-- Query 2, should result in one Index Seek and one Index Scan operation
DBCC FREEPROCCACHE
GO

EXEC sp_executesql
@stmt = N'SELECT
  p.name,
  tha.TransactionDate,
  tha.TransactionType,
  tha.Quantity,
  tha.ActualCost
FROM Production.TransactionHistoryArchive tha
JOIN Production.Product p
ON tha.ProductID = p.ProductID
WHERE p.ProductID = @productID', 
@params = N'@productID INT',
@productID = 712 

-- Let's build a plan guide the old fashioned way
-- in which we want to use the first Execution Plan
-- without the Index Scan operation

-- Execute the query with ID 461 to get the plan we want
EXEC sp_executesql
@stmt = N'SELECT p.name,tha.TransactionDate,tha.TransactionType,tha.Quantity,tha.ActualCost FROM Production.TransactionHistoryArchive tha JOIN Production.Product p ON tha.ProductID = p.ProductID WHERE p.ProductID = @productID', 
@params = N'@productID INT',
@productID = 461 

-- Grab the query we just executed from the Plan Cache
SELECT
  qt.[text],
  qp.query_plan
FROM 
sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) qt

-- Build the plan guide using the XML plan
EXEC sp_create_plan_guide
@name = N'ForcePlan',
@stmt = N'SELECT p.name,tha.TransactionDate,tha.TransactionType,tha.Quantity,tha.ActualCost FROM Production.TransactionHistoryArchive tha JOIN Production.Product p ON tha.ProductID = p.ProductID WHERE p.ProductID = @productID', 
@type = N'SQL',
@module_or_batch = NULL,
@params = N'@productID INT',
@hints = N'<ShowPlanXML xmlns="http://schemas.microsoft.com/sqlserver/2004/07/showplan" Version="1.5" Build="13.0.1100.288"><BatchSequence><Batch><Statements><StmtSimple StatementText="(@productID INT)SELECT p.name,tha.TransactionDate,tha.TransactionType,tha.Quantity,tha.ActualCost FROM Production.TransactionHistoryArchive tha JOIN Production.Product p ON tha.ProductID = p.ProductID WHERE p.ProductID = @productID" StatementId="1" StatementCompId="2" StatementType="SELECT" RetrievedFromCache="true" PlanGuideDB="AdventureWorks" PlanGuideName="ForcePlan" StatementSubTreeCost="0.0116881" StatementEstRows="2.50562" SecurityPolicyApplied="false" StatementOptmLevel="FULL" QueryHash="0x2567346B1381B053" QueryPlanHash="0x2567346B1381B053" CardinalityEstimationModelVersion="130"><StatementSetOptions QUOTED_IDENTIFIER="true" ARITHABORT="true" CONCAT_NULL_YIELDS_NULL="true" ANSI_NULLS="true" ANSI_PADDING="true" ANSI_WARNINGS="true" NUMERIC_ROUNDABORT="false" /><QueryPlan CachedPlanSize="32" CompileTime="79" CompileCPU="35" CompileMemory="1640" UsePlan="1"><MemoryGrantInfo SerialRequiredMemory="0" SerialDesiredMemory="0" /><OptimizerHardwareDependentProperties EstimatedAvailableMemoryGrant="102910" EstimatedPagesCached="25727" EstimatedAvailableDegreeOfParallelism="2" /><RelOp NodeId="0" PhysicalOp="Nested Loops" LogicalOp="Inner Join" EstimateRows="2.50562" EstimateIO="0" EstimateCPU="1.04735e-005" AvgRowSize="83" EstimatedTotalSubtreeCost="0.0116881" Parallel="0" EstimateRebinds="0" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionDate" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionType" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="Quantity" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="ActualCost" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[Product]" Alias="[p]" Column="Name" /></OutputList><NestedLoops Optimized="0"><RelOp NodeId="1" PhysicalOp="Clustered Index Seek" LogicalOp="Clustered Index Seek" EstimateRows="1" EstimateIO="0.003125" EstimateCPU="0.0001581" AvgRowSize="61" EstimatedTotalSubtreeCost="0.0032831" TableCardinality="504" Parallel="0" EstimateRebinds="0" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[Product]" Alias="[p]" Column="Name" /></OutputList><IndexScan Ordered="1" ScanDirection="FORWARD" ForcedIndex="0" ForceSeek="0" ForceScan="0" NoExpandHint="0" Storage="RowStore"><DefinedValues><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[Product]" Alias="[p]" Column="Name" /></DefinedValue></DefinedValues><Object Database="[AdventureWorks]" Schema="[Production]" Table="[Product]" Index="[PK_Product_ProductID]" Alias="[p]" IndexKind="Clustered" Storage="RowStore" /><SeekPredicates><SeekPredicateNew><SeekKeys><Prefix ScanType="EQ"><RangeColumns><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[Product]" Alias="[p]" Column="ProductID" /></RangeColumns><RangeExpressions><ScalarOperator ScalarString="[@productID]"><Identifier><ColumnReference Column="@productID" /></Identifier></ScalarOperator></RangeExpressions></Prefix></SeekKeys></SeekPredicateNew></SeekPredicates></IndexScan></RelOp><RelOp NodeId="2" PhysicalOp="Nested Loops" LogicalOp="Inner Join" EstimateRows="2.50562" EstimateIO="0" EstimateCPU="1.04735e-005" AvgRowSize="29" EstimatedTotalSubtreeCost="0.00839452" Parallel="0" EstimateRebinds="0" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionDate" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionType" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="Quantity" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="ActualCost" /></OutputList><NestedLoops Optimized="0"><OuterReferences><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionID" /></OuterReferences><RelOp NodeId="3" PhysicalOp="Index Seek" LogicalOp="Index Seek" EstimateRows="2.50562" EstimateIO="0.003125" EstimateCPU="0.000159756" AvgRowSize="11" EstimatedTotalSubtreeCost="0.00328476" TableCardinality="89253" Parallel="0" EstimateRebinds="0" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionID" /></OutputList><IndexScan Ordered="1" ScanDirection="FORWARD" ForcedIndex="0" ForceSeek="0" ForceScan="0" NoExpandHint="0" Storage="RowStore"><DefinedValues><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionID" /></DefinedValue></DefinedValues><Object Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Index="[IX_TransactionHistoryArchive_ProductID]" Alias="[tha]" IndexKind="NonClustered" Storage="RowStore" /><SeekPredicates><SeekPredicateNew><SeekKeys><Prefix ScanType="EQ"><RangeColumns><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="ProductID" /></RangeColumns><RangeExpressions><ScalarOperator ScalarString="[@productID]"><Identifier><ColumnReference Column="@productID" /></Identifier></ScalarOperator></RangeExpressions></Prefix></SeekKeys></SeekPredicateNew></SeekPredicates></IndexScan></RelOp><RelOp NodeId="5" PhysicalOp="Clustered Index Seek" LogicalOp="Clustered Index Seek" EstimateRows="1" EstimateIO="0.003125" EstimateCPU="0.0001581" AvgRowSize="29" EstimatedTotalSubtreeCost="0.00509929" TableCardinality="89253" Parallel="0" EstimateRebinds="1.50562" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionDate" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionType" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="Quantity" /><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="ActualCost" /></OutputList><IndexScan Lookup="1" Ordered="1" ScanDirection="FORWARD" ForcedIndex="0" ForceSeek="0" ForceScan="0" NoExpandHint="0" Storage="RowStore"><DefinedValues><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionDate" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionType" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="Quantity" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="ActualCost" /></DefinedValue></DefinedValues><Object Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Index="[PK_TransactionHistoryArchive_TransactionID]" Alias="[tha]" TableReferenceId="-1" IndexKind="Clustered" Storage="RowStore" /><SeekPredicates><SeekPredicateNew><SeekKeys><Prefix ScanType="EQ"><RangeColumns><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionID" /></RangeColumns><RangeExpressions><ScalarOperator ScalarString="[AdventureWorks].[Production].[TransactionHistoryArchive].[TransactionID] as [tha].[TransactionID]"><Identifier><ColumnReference Database="[AdventureWorks]" Schema="[Production]" Table="[TransactionHistoryArchive]" Alias="[tha]" Column="TransactionID" /></Identifier></ScalarOperator></RangeExpressions></Prefix></SeekKeys></SeekPredicateNew></SeekPredicates></IndexScan></RelOp></NestedLoops></RelOp></NestedLoops></RelOp><ParameterList><ColumnReference Column="@productID" ParameterCompiledValue="(461)" /></ParameterList></QueryPlan></StmtSimple></Statements></Batch></BatchSequence></ShowPlanXML>'

-- Execute the second query again
-- Normally this would result in the Index Scan operation
DBCC FREEPROCCACHE
GO

EXEC sp_executesql
@stmt = N'SELECT p.name,tha.TransactionDate,tha.TransactionType,tha.Quantity,tha.ActualCost FROM Production.TransactionHistoryArchive tha JOIN Production.Product p ON tha.ProductID = p.ProductID WHERE p.ProductID = @productID', 
@params = N'@productID INT',
@productID = 712

-- Drop all plan guides again
EXEC sp_control_plan_guide N'DROP ALL';


/*
Demo: Query Store Performance
*/

-- Query Query Store related Wait Types
SELECT * 
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'QDS%'

-- Query Store Extended Events
SELECT
  [name],
  [description]
FROM sys.dm_xe_objects
WHERE NAME LIKE 'query_store%'

/*
Cleanup
*/

ALTER DATABASE AdventureWorks SET QUERY_STORE = OFF;