/*********************************************************************************************
Memory-Optimized Tables - Querying at the Speed of Light
Demo Scripts
(C) 2015, Enrico van de Laar

Requires SQL Server 2014 Enterprise Edition!

Feedback: mailto:enrico@dotnine.nl

License: 
	This demo script, that is part of the Memory-Optimized Tables - Querying at the Speed of Light 
	session, is free to download and use for personal, educational, and internal 
	corporate purposes, provided that this header is preserved. Redistribution or sale 
	of this script, in whole or in part, is prohibited without the author's express 
	written consent.
*********************************************************************************************/

-- Create Demo database.
-- Change disk/folder locations if needed.
USE [master]
GO

CREATE DATABASE [OLTP_Test] CONTAINMENT = NONE
ON PRIMARY 
	( 
	NAME = N'OLTP_Test', FILENAME = N'D:\Data\OLTP_Test_Data.mdf' , SIZE = 51200KB , FILEGROWTH = 10%
	)
LOG ON 
	( 
	NAME = N'OLTP_Test_log', FILENAME = N'D:\Log\OLTP_Test_Log.ldf' , SIZE = 10240KB , FILEGROWTH = 10%
	);
GO

-- Before we can create Memory-Optimized tables we need to create a Memory-Optimized
-- Filegroup, notice the CONTAINS MEMORY_OPTIMIZED_DATA to indicate this Filegroup
-- will hold Memory-Optimized tables.
ALTER DATABASE OLTP_Test ADD FILEGROUP OLTP_MO CONTAINS MEMORY_OPTIMIZED_DATA;
GO

-- Add a file to the newly created Filegroup.
-- Change drive/folder location if needed.
ALTER DATABASE OLTP_Test ADD FILE (name='OLTP_mo_01', filename='D:\data\OLTP_Test_mo_01.ndf') TO FILEGROUP OLTP_MO;
GO

-- Let's create a Memory-Optimized table.
-- Notice the hint MEMORY_OPTIMIZED=ON
USE [OLTP_Test]
GO

CREATE TABLE dbo.OLTP
	( 
	[AddressID] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
	[AddressLine1] NVARCHAR(60) NOT NULL,
	[AddressLine2] NVARCHAR(60) NULL,
	[City] NVARCHAR(30) NOT NULL,
	[StateProvinceID] INT NOT NULL,
	[PostalCode] NVARCHAR(15) NOT NULL,
	[rowguid] UNIQUEIDENTIFIER,
	[ModifiedDate] DATETIME
	) 
WITH (MEMORY_OPTIMIZED=ON);
GO 

-- Oops! Remember, no Clustered Indexes!
-- We will have to make sure our Primary Key gets a Non-Clustered Index
CREATE TABLE dbo.OLTP
	( 
	[AddressID] INT IDENTITY(1,1) NOT NULL PRIMARY KEY NONCLUSTERED,
	[AddressLine1] NVARCHAR(60) NOT NULL,
	[AddressLine2] NVARCHAR(60) NULL,
	[City] NVARCHAR(30) NOT NULL,
	[StateProvinceID] INT NOT NULL,
	[PostalCode] NVARCHAR(15) NOT NULL,
	[rowguid] UNIQUEIDENTIFIER,
	[ModifiedDate] DATETIME
	) 
WITH (MEMORY_OPTIMIZED=ON);
GO 

-- You can check if a table is a Memory-Optimized table by looking
-- at the properties of the table.
-- Also note the "Durability" property.

-- Let's populate our OLTP database with some data.
-- I created a structure that resemples the Person.Address table of the
-- AdventureWorks database, let's grab some rows from there
INSERT INTO OLTP
	(
	AddressLine1, 
	AddressLine2, 
	City, 
	StateProvinceID, 
	PostalCode, 
	rowguid
	)
SELECT
	AddressLine1, 
	AddressLine2, 
	City, 
	StateProvinceID, 
	PostalCode, 
	rowguid
FROM
	AdventureWorks2014.Person.Address

-- Oh no, another thing that doesn't work.
-- You can't access another database from Memory-Optimized tables
-- Let's drop our OLTP table and create a new one where we can easily insert
-- some data.
DROP TABLE OLTP;
GO

CREATE TABLE OLTP
	(
	ID INT IDENTITY (1,1) PRIMARY KEY NONCLUSTERED,
	RandomData1 VARCHAR(50),
	RandomData2 VARCHAR(50),
	ID2 UNIQUEIDENTIFIER
	)
WITH (MEMORY_OPTIMIZED=ON);
GO 

-- Let's check some In-Memory OLTP DMV's for information about
-- the table we just created
--
-- PRECREATED : Pre-allocated Data/Delta files to avoid overhead
-- UNDER CONSTRUCTION : Data/Delta files that will store new rows
-- ACTIVE : Rows after last checkpoint

-- Fun tip: Check file location of Memory Optimized Filegroup!

SELECT
	container_id,
	file_type_desc,
	state_desc,
	inserted_row_count,
	deleted_row_count,
	lower_bound_tsn,
	upper_bound_tsn,
	file_size_in_bytes,
	file_size_used_in_bytes
FROM
	sys.dm_db_xtp_checkpoint_files
ORDER BY file_type_desc

-- Insert 10 rows
INSERT INTO OLTP
	(
	RandomData1,
	RandomData2,
	ID2
	)
VALUES
  	(
  	CONVERT(VARCHAR(50), NEWID()),
  	CONVERT(VARCHAR(50), NEWID()),
  	NEWID()
  	);
GO 10

-- Check sys.dm_db_xtp_checkpoint_files again
-- Notice file_size_used_in_bytes
SELECT
	container_id,
	file_type_desc,
	state_desc,
	inserted_row_count,
	deleted_row_count,
	lower_bound_tsn,
	upper_bound_tsn,
	file_size_in_bytes,
	file_size_used_in_bytes
FROM
	sys.dm_db_xtp_checkpoint_files
ORDER BY file_type_desc;

-- Force a Checkpoint to occur
CHECKPOINT

-- Check sys.dm_db_xtp_checkpoint_files again
-- Notice change in file_size_used_in_bytes
-- and lower_bound_tsn & upper_bound_tsn.
-- Also notice that two extra files were added (extra data + delta file)
SELECT
	container_id,
	file_type_desc,
	state_desc,
	inserted_row_count,
	deleted_row_count,
	lower_bound_tsn,
	upper_bound_tsn,
	file_size_in_bytes,
	file_size_used_in_bytes
FROM
	sys.dm_db_xtp_checkpoint_files
ORDER BY file_type_desc;

-- We can force a Merge operation to occur
-- The last two parameters are to lower bound and upper bound tsn
EXEC sys.sp_xtp_merge_checkpoint_files 'OLTP_Test',15,32;
GO

-- There is a DMV that tracks Merge operations
-- Let's see what happened
SELECT *
FROM sys.dm_db_xtp_merge_requests;
GO

-- What does the Merge operation mean for our Data/Delta files?
SELECT
	container_id,
	checkpoint_file_id,
	file_type_desc,
	state_desc,
	inserted_row_count,
	deleted_row_count,
	lower_bound_tsn,
	upper_bound_tsn,
	file_size_in_bytes,
	file_size_used_in_bytes
FROM
	sys.dm_db_xtp_checkpoint_files
ORDER BY file_type_desc;

-- Lets create a non-durable Memory-Optimized table
-- and insert a few rows
-- Notice the DURABILITY option
USE OLTP_Test
GO

CREATE TABLE dbo.OLTP_nd
	( 
	ID INT IDENTITY (1,1) PRIMARY KEY NONCLUSTERED,
	RandomData1 VARCHAR(50),
	RandomData2 VARCHAR(50),
	ID2 UNIQUEIDENTIFIER
	) 
WITH (MEMORY_OPTIMIZED=ON, DURABILITY=SCHEMA_ONLY) 
GO

INSERT INTO OLTP_nd
	(
	RandomData1,
	RandomData2,
	ID2
	)
VALUES
  	(
  	CONVERT(VARCHAR(50), NEWID()),
  	CONVERT(VARCHAR(50), NEWID()),
  	NEWID()
  	);
GO 10

-- Restart the SQL Server Service
-- And check the contents of both tables we created
USE OLTP_Test
GO

SELECT * FROM OLTP;
SELECT * FROM OLTP_nd;

-- Create a table with a Hash Index
CREATE TABLE dbo.OLTP_Hash
	( 
	ID INT IDENTITY (1,1) PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 128),
	RandomData1 VARCHAR(50),
	RandomData2 VARCHAR(50),
	ID2 UNIQUEIDENTIFIER
	) 
WITH (MEMORY_OPTIMIZED=ON, DURABILITY=SCHEMA_AND_DATA) 
GO

-- Lets insert some data
INSERT INTO OLTP_Hash
	(
	RandomData1,
	RandomData2,
	ID2
	)
VALUES
  	(
  	CONVERT(VARCHAR(50), NEWID()),
  	CONVERT(VARCHAR(50), NEWID()),
  	NEWID()
  	);
GO 100

-- Query information about the Hash Index
SELECT * FROM sys.dm_db_xtp_hash_index_stats;

-- All done with the demos
-- Clean up everything
USE [master]
GO

DROP DATABASE OLTP_Test;