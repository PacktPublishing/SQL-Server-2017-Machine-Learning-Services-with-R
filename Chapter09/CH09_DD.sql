/*

Chapter 09 

*/

-- Script for Delayed Durability
USE MASTER
GO

DROP DATABASE DelayedDurability;
GO
-- Create New Database
CREATE DATABASE [DelayedDurability];
GO

BACKUP DATABASE [DelayedDurability] TO DISK = N'nul'
GO 

/*

Processed 336 pages for database 'DelayedDurability', file 'DelayedDurability' on file 1.
Processed 2 pages for database 'DelayedDurability', file 'DelayedDurability_log' on file 1.
BACKUP DATABASE successfully processed 338 pages in 0.020 seconds (131.982 MB/sec).



*/

ALTER DATABASE [DelayedDurability] SET DELAYED_DURABILITY = ALLOWED WITH NO_WAIT;
GO



-- Creating Dummy table
USE [DelayedDurability];
GO

DROP TABLE IF EXISTS TestDDTable;
GO

CREATE TABLE TestDDTable
(ID INT IDENTITY(1,1) PRIMARY KEY 
,R_num INT
,Class CHAR(10)  
,InsertTime DATETIME DEFAULT(GETDATE())
);
GO

SET NOCOUNT ON;
GO

--clean state
EXECUTE sys.sp_flush_log;
GO

DECLARE @count INT = 0
DECLARE @start1 DATETIME = GETDATE()
WHILE (@count <= 250000)
	BEGIN
		BEGIN TRAN
			INSERT INTO TestDDTable(R_num, class) VALUES(@count, 'WITHOUT_DD')
			SET @count += 1
		COMMIT WITH (DELAYED_DURABILITY = OFF)
	END

DECLARE @count INT = 0
DECLARE @start2 DATETIME = GETDATE()
WHILE (@count <= 2500000)
	BEGIN
		BEGIN TRAN
			INSERT INTO TestDDTable(R_num, class) VALUES(@count, 'WITH_DD')
			SET @count += 1
		COMMIT WITH (DELAYED_DURABILITY = ON)
	END

SELECT 
 DATEDIFF(SECOND, @start1, GETDATE()) AS With_DD_OFF
,DATEDIFF(SECOND, @start2, GETDATE()) AS With_DD_ON



SELECT * FROM TestDDTable


-- run this in another session:
-- capture the VLF statistics
SELECT TOP 0 
	GETDATE() AS start_time
,* 
INTO #VLF_DelayDurab
FROM sys.dm_io_virtual_file_stats(DB_ID('DelayedDurability'), 2);

INSERT INTO #VLF_DelayDurab
SELECT 
	 GETDATE() AS start_time
	,* 
 FROM sys.dm_io_virtual_file_stats(DB_ID('DelayedDurability'),2);
GO 10000

SELECT *  FROM #Data_DelayDurability

-- run this in another session:
-- capture the Wait statistics

SELECT  TOP 0
 GETDATE() AS start_time
,*
INTO #WaitStats_DelayDurab
FROM sys.dm_os_wait_stats
WHERE 
	wait_type IN ('WRITELOG')

INSERT INTO #WaitStats_DelayDurab
SELECT 
 GETDATE() AS start_time
,*
INTO #WaitStats_DelayDurab
FROM sys.dm_os_wait_stats
WHERE 
	wait_type IN ('WRITELOG');
GO 10000



-- creating extended event

IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name='DelayDurab_Log_flush')  
DROP EVENT session DelayDurab_Log_flush ON SERVER; 

-- Get DelayedDurability database ID
--  SELECT db_id()

CREATE EVENT SESSION DelayDurab_Log_flush ON SERVER
ADD EVENT sqlserver.log_flush_start
	(WHERE  (database_id=40)),
ADD EVENT sqlserver.databases_log_flush 
	(WHERE (database_id =40)),
ADD EVENT sqlserver.transaction_log
	(WHERE (database_id =40))
-- maybe add batchrequests/second

ADD TARGET package0.event_file
(
     SET filename     ='C:\CH09\MonitorDelayDurability.xel'
	    ,metadatafile ='C:\CH09\MonitorDelayDurability.xem'
)
WITH (MAX_MEMORY=4096KB
		,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS
		,MEMORY_PARTITION_MODE=NONE
		,STARTUP_STATE=ON);
GO

 
ALTER EVENT SESSION DelayDurab_Log_flush ON SERVER
STATE = START;
GO

/* RUN SOME QUERIES */

DECLARE @count INT = 0
DECLARE @start1 DATETIME = GETDATE()
WHILE (@count <= 2500)
	BEGIN
		BEGIN TRAN
			INSERT INTO TestDDTable(R_num, class) VALUES(@count, 'WITHOUT_DD')
			SET @count += 1
		COMMIT WITH (DELAYED_DURABILITY = OFF)
	END



ALTER EVENT SESSION DelayDurab_Log_flush ON SERVER
STATE = STOP;
GO


----- Read Data

WITH XML_raw_XE
AS
(
SELECT 
	CAST(event_data AS XML) AS event_data
FROM sys.fn_xe_file_target_read_file('C:\CH09\MonitorDelayDurability*.xel', 'C:\CH09\MonitorDelayDurability*.xem', null, null)
) 

SELECT 
    event_data.value('(event/@name)[1]', 'varchar(50)') AS event_name,
    DATEADD(hh, 
            DATEDIFF(hh, GETUTCDATE(), CURRENT_TIMESTAMP), 
            event_data.value('(event/@timestamp)[1]', 'datetime2')) AS [timestamp],
    COALESCE(event_data.value('(event/data[@name="database_id"]/value)[1]', 'int'), 
             event_data.value('(event/action[@name="database_id"]/value)[1]', 'int')) AS database_id,
    event_data.value('(event/data[@name="count"]/value)[1]', 'bigint') AS [count],
    event_data.value('(event/data[@name="start_log_block_id"]/value)[1]', 'bigint') AS [start_log_block_id],
    event_data.value('(event/data[@name="is_read_ahead"]/value)[1]', 'nvarchar(4000)') AS [is_read_ahead],
    event_data.value('(event/data[@name="private_consumer_id"]/value)[1]', 'bigint') AS [private_consumer_id],
    event_data.value('(event/data[@name="mode"]/text)[1]', 'nvarchar(4000)') AS [mode],
    event_data.value('(event/data[@name="file_handle"]/value)[1]', 'nvarchar(4000)') AS [file_handle],
    event_data.value('(event/data[@name="offset"]/value)[1]', 'bigint') AS [offset],
    event_data.value('(event/data[@name="file_id"]/value)[1]', 'int') AS [file_id],
    event_data.value('(event/data[@name="filegroup_id"]/value)[1]', 'int') AS [filegroup_id],
    event_data.value('(event/data[@name="size"]/value)[1]', 'bigint') AS [size],
    event_data.value('(event/data[@name="path"]/value)[1]', 'nvarchar(4000)') AS [path],
    event_data.value('(event/data[@name="duration"]/value)[1]', 'bigint') AS [duration],
    event_data.value('(event/data[@name="io_data"]/value)[1]', 'nvarchar(4000)') AS [io_data],
    event_data.value('(event/data[@name="resource_type"]/text)[1]', 'nvarchar(4000)') AS [resource_type],
    event_data.value('(event/data[@name="owner_type"]/text)[1]', 'nvarchar(4000)') AS [owner_type],
    event_data.value('(event/data[@name="transaction_id"]/value)[1]', 'bigint') AS [transaction_id],
    event_data.value('(event/data[@name="lockspace_workspace_id"]/value)[1]', 'nvarchar(4000)') AS [lockspace_workspace_id],
    event_data.value('(event/data[@name="lockspace_sub_id"]/value)[1]', 'int') AS [lockspace_sub_id],
    event_data.value('(event/data[@name="lockspace_nest_id"]/value)[1]', 'int') AS [lockspace_nest_id],
    event_data.value('(event/data[@name="resource_0"]/value)[1]', 'int') AS [resource_0],
    event_data.value('(event/data[@name="resource_1"]/value)[1]', 'int') AS [resource_1],
    event_data.value('(event/data[@name="resource_2"]/value)[1]', 'int') AS [resource_2],
    event_data.value('(event/data[@name="object_id"]/value)[1]', 'int') AS [object_id],
    event_data.value('(event/data[@name="associated_object_id"]/value)[1]', 'bigint') AS [associated_object_id],
    event_data.value('(event/data[@name="resource_description"]/value)[1]', 'nvarchar(4000)') AS [resource_description],
    event_data.value('(event/data[@name="database_name"]/value)[1]', 'nvarchar(4000)') AS [database_name],
    event_data.value('(event/data[@name="log_block_id"]/value)[1]', 'bigint') AS [log_block_id],
    event_data.value('(event/data[@name="log_block_size"]/value)[1]', 'int') AS [log_block_size],
    event_data.value('(event/data[@name="from_disk"]/value)[1]', 'nvarchar(4000)') AS [from_disk],
    event_data.value('(event/data[@name="incomplete"]/value)[1]', 'nvarchar(4000)') AS [incomplete],
    event_data.value('(event/data[@name="cache_buffer_pointer"]/value)[1]', 'nvarchar(4000)') AS [cache_buffer_pointer],
    event_data.value('(event/data[@name="consumer_id"]/value)[1]', 'bigint') AS [consumer_id],
    event_data.value('(event/data[@name="old_weight"]/value)[1]', 'int') AS [old_weight],
    event_data.value('(event/data[@name="new_weight"]/value)[1]', 'int') AS [new_weight],
    event_data.value('(event/data[@name="new_position"]/value)[1]', 'int') AS [new_position],
    event_data.value('(event/data[@name="last_log_block_id"]/value)[1]', 'bigint') AS [last_log_block_id],
    event_data.value('(event/data[@name="weight"]/value)[1]', 'int') AS [weight],
    event_data.value('(event/data[@name="address"]/value)[1]', 'nvarchar(4000)') AS [address],
    event_data.value('(event/data[@name="type"]/text)[1]', 'nvarchar(4000)') AS [type],
    event_data.value('(event/data[@name="current_count"]/value)[1]', 'int') AS [current_count],
    event_data.value('(event/data[@name="change_type"]/value)[1]', 'int') AS [change_type],
    event_data.value('(event/data[@name="activity_id"]/value)[1]', 'int') AS [activity_id],
    event_data.value('(event/data[@name="write_size"]/value)[1]', 'int') AS [write_size],
    event_data.value('(event/data[@name="rows"]/value)[1]', 'int') AS [rows],
    event_data.value('(event/data[@name="pending_writes"]/value)[1]', 'int') AS [pending_writes],
    event_data.value('(event/data[@name="pending_bytes"]/value)[1]', 'int') AS [pending_bytes],
    event_data.value('(event/data[@name="reason"]/text)[1]', 'nvarchar(4000)') AS [reason],
    event_data.value('(event/data[@name="waiters"]/value)[1]', 'int') AS [waiters],
    event_data.value('(event/data[@name="error"]/value)[1]', 'int') AS [error],
    event_data.value('(event/data[@name="slot_id"]/value)[1]', 'int') AS [slot_id],
    event_data.value('(event/data[@name="used_size"]/value)[1]', 'int') AS [used_size],
    event_data.value('(event/data[@name="reservation_size"]/value)[1]', 'bigint') AS [reservation_size],
    event_data.value('(event/data[@name="log_op_id"]/value)[1]', 'int') AS [log_op_id],
    event_data.value('(event/data[@name="log_op_name"]/value)[1]', 'nvarchar(4000)') AS [log_op_name],
    event_data.value('(event/data[@name="interest"]/value)[1]', 'nvarchar(4000)') AS [interest],
    event_data.value('(event/data[@name="cache_type"]/value)[1]', 'int') AS [cache_type],
    event_data.value('(event/data[@name="keys"]/value)[1]', 'nvarchar(4000)') AS [keys],
    event_data.value('(event/data[@name="stop_mark"]/value)[1]', 'nvarchar(4000)') AS [stop_mark],
    event_data.value('(event/data[@name="operation"]/text)[1]', 'nvarchar(4000)') AS [operation],
    event_data.value('(event/data[@name="success"]/value)[1]', 'nvarchar(4000)') AS [success],
    event_data.value('(event/data[@name="index_id"]/value)[1]', 'int') AS [index_id],
    event_data.value('(event/data[@name="log_record_size"]/value)[1]', 'int') AS [log_record_size],
    event_data.value('(event/data[@name="context"]/text)[1]', 'nvarchar(4000)') AS [context],
    event_data.value('(event/data[@name="replication_command"]/value)[1]', 'int') AS [replication_command],
    event_data.value('(event/data[@name="transaction_start_time"]/value)[1]', 'nvarchar(4000)') AS [transaction_start_time]

INTO DD_XML
FROM XML_raw_XE


--- CLEAN UP
IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name='DelayDurab_Log_flush')  
DROP EVENT session DelayDurab_Log_flush ON SERVER; 
	

USE [master];
GO

DROP DATABASE [DelayedDurability];
GO

----------------------------------------

CREATE DATABASE ServerInfo;
GO

USE [ServerInfo]
GO

DROP TABLE IF EXISTS server_info;
GO

CREATE TABLE [dbo].[server_info](
	[XE01] TINYINT NULL,
	[XE02] TINYINT NULL,
	[XE03] TINYINT NULL,
	[XE04] TINYINT NULL,
	[XE05] TINYINT NULL,
	[XE06] TINYINT NULL,
	[XE07] TINYINT NULL,
	[XE08] TINYINT NULL,
	[XE09] TINYINT NULL,
	[XE10] TINYINT NULL,
	[XE11] TINYINT NULL,
	[XE12] TINYINT NULL,
	[XE13] TINYINT NULL,
	[XE14] TINYINT NULL,
	[XE15] TINYINT NULL,
	[XE16] TINYINT NULL,
	[XE17] TINYINT NULL,
	[XE18] TINYINT NULL,
	[XE19] TINYINT NULL,
	[XE20] TINYINT NULL,
	[XE21] TINYINT NULL,
	[XE22] TINYINT NULL,
	[XE23] TINYINT NULL,
	[XE24] TINYINT NULL,
	[XE25] TINYINT NULL,
	[XE26] TINYINT NULL,
	[XE27] TINYINT NULL,
	[XE28] TINYINT NULL,
	[XE29] TINYINT NULL,
	[XE30] TINYINT NULL,
	[XE31] TINYINT NULL,
	[XE32] TINYINT NULL
);
GO

INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 8, 9, 12, 2, 4, 9, 6, 20, 20, 12, 8, 9, 20, 5, 12, 12, 4, 12, 8, 15, 4, 15, 20, 20, 12, 4, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 15, 8, 2, 6, 20, 2, 10, 3, 15, 15, 20, 12, 2, 6, 4, 15, 20, 3, 10, 15, 4, 15, 2, 6, 15, 20, 9, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 12, 6, 12, 20, 6, 2, 12, 6, 5, 20, 12, 6, 6, 20, 5, 20, 12, 8, 12, 12, 10, 8, 3, 15, 16, 15, 8, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 4, 8, 9, 16, 8, 8, 15, 12, 5, 16, 15, 6, 9, 16, 10, 20, 12, 8, 12, 12, 10, 8, 6, 5, 20, 9, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 15, 4, 4, 12, 20, 4, 6, 9, 12, 10, 20, 9, 6, 9, 20, 5, 16, 6, 10, 15, 4, 15, 4, 6, 20, 16, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 15, 16, 6, 12, 16, 4, 2, 12, 9, 15, 20, 15, 6, 6, 16, 5, 20, 9, 10, 12, 4, 15, 6, 3, 10, 20, 15, 8, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 4, 4, 3, 4, 4, 10, 12, 12, 5, 20, 3, 2, 12, 20, 25, 4, 9, 4, 15, 4, 20, 4, 3, 5, 20, 3, 4, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 8, 8, 3, 16, 6, 6, 15, 12, 5, 16, 9, 4, 12, 16, 20, 8, 15, 4, 12, 12, 15, 2, 3, 15, 16, 9, 6, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 12, 12, 4, 3, 16, 8, 4, 9, 12, 5, 16, 12, 4, 15, 20, 25, 16, 12, 4, 15, 8, 20, 4, 12, 20, 16, 9, 10, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 4, 8, 9, 16, 2, 10, 12, 15, 5, 20, 9, 8, 12, 16, 5, 4, 15, 4, 12, 4, 25, 6, 12, 5, 20, 12, 4, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 6, 3, 16, 4, 8, 15, 9, 5, 12, 9, 6, 12, 20, 20, 4, 12, 2, 12, 8, 15, 10, 15, 20, 12, 9, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 20, 4, 9, 20, 10, 4, 12, 6, 20, 16, 12, 8, 9, 20, 10, 20, 9, 8, 15, 8, 5, 6, 3, 5, 16, 15, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 10, 15, 12, 6, 12, 16, 2, 6, 12, 12, 5, 20, 9, 6, 9, 16, 5, 16, 15, 8, 15, 4, 10, 8, 3, 5, 20, 6, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 15, 16, 8, 6, 16, 8, 10, 12, 12, 5, 20, 3, 10, 15, 20, 5, 8, 15, 8, 15, 4, 10, 8, 15, 25, 20, 15, 6, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 8, 8, 12, 16, 2, 4, 12, 12, 20, 20, 12, 8, 12, 16, 15, 16, 12, 8, 6, 12, 15, 8, 9, 5, 16, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 6, 12, 6, 12, 16, 4, 2, 6, 6, 5, 20, 6, 2, 12, 16, 5, 20, 15, 6, 9, 4, 5, 6, 6, 10, 8, 3, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 12, 16, 8, 3, 16, 6, 8, 12, 6, 5, 16, 9, 10, 9, 16, 10, 8, 3, 2, 6, 16, 20, 8, 9, 5, 8, 12, 4, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 8, 6, 6, 4, 6, 8, 15, 15, 10, 20, 9, 6, 12, 16, 10, 16, 6, 6, 12, 8, 10, 8, 9, 5, 16, 9, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 15, 16, 6, 12, 16, 6, 4, 15, 6, 5, 16, 12, 6, 9, 16, 10, 20, 9, 8, 9, 12, 5, 8, 3, 15, 12, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 6, 15, 20, 6, 15, 16, 2, 10, 15, 15, 20, 20, 3, 6, 9, 16, 5, 4, 9, 10, 15, 12, 25, 6, 9, 15, 16, 15, 8, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 9, 20, 2, 15, 8, 8, 2, 12, 12, 25, 12, 15, 8, 9, 20, 25, 4, 3, 10, 3, 20, 10, 8, 15, 25, 4, 15, 8, 6, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 4, 15, 12, 8, 6, 20, 2, 8, 6, 9, 25, 16, 3, 8, 9, 20, 25, 16, 9, 4, 15, 4, 25, 6, 9, 25, 20, 3, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 4, 8, 9, 20, 4, 6, 9, 9, 5, 20, 12, 8, 9, 12, 5, 16, 12, 10, 15, 4, 15, 6, 9, 15, 20, 12, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 12, 10, 6, 16, 8, 10, 15, 12, 20, 16, 3, 10, 15, 12, 5, 4, 15, 2, 6, 12, 25, 10, 15, 5, 8, 15, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 20, 10, 15, 20, 2, 4, 15, 12, 5, 20, 15, 10, 15, 12, 5, 20, 12, 10, 15, 8, 5, 8, 12, 20, 20, 12, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 4, 10, 6, 12, 4, 4, 15, 15, 15, 8, 9, 6, 12, 20, 20, 16, 15, 2, 9, 16, 15, 8, 12, 15, 16, 12, 10, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 8, 6, 12, 16, 4, 6, 9, 12, 5, 20, 6, 4, 9, 20, 20, 20, 15, 6, 12, 4, 25, 6, 6, 15, 20, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 12, 4, 8, 12, 16, 2, 4, 9, 12, 5, 16, 12, 8, 9, 16, 5, 16, 12, 8, 12, 4, 15, 8, 6, 5, 16, 3, 8, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 9, 16, 4, 15, 16, 8, 8, 9, 15, 20, 4, 15, 6, 12, 12, 20, 16, 9, 10, 12, 16, 20, 8, 9, 10, 4, 9, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 12, 4, 2, 3, 20, 8, 8, 15, 15, 5, 20, 12, 10, 15, 16, 5, 16, 12, 8, 12, 4, 20, 2, 15, 20, 8, 3, 6, 2, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 16, 6, 9, 12, 4, 2, 12, 3, 10, 20, 15, 10, 9, 12, 10, 20, 9, 6, 15, 16, 15, 6, 12, 20, 12, 15, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 10, 12, 16, 4, 6, 12, 12, 20, 20, 12, 10, 15, 8, 10, 12, 15, 6, 15, 12, 20, 8, 12, 20, 16, 15, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 12, 8, 6, 12, 16, 2, 8, 12, 12, 15, 8, 9, 4, 12, 16, 15, 8, 3, 4, 9, 12, 5, 8, 6, 15, 16, 15, 4, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 16, 8, 9, 20, 4, 10, 15, 15, 5, 20, 12, 10, 15, 20, 5, 20, 15, 8, 15, 4, 10, 8, 9, 5, 20, 12, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 15, 20, 4, 9, 12, 2, 2, 12, 3, 15, 20, 15, 6, 9, 16, 10, 20, 3, 8, 15, 12, 5, 2, 9, 15, 8, 15, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 12, 12, 8, 9, 16, 2, 8, 9, 9, 20, 16, 3, 8, 12, 16, 20, 16, 9, 8, 12, 8, 20, 4, 9, 15, 16, 3, 8, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 16, 6, 6, 16, 4, 4, 15, 9, 25, 20, 12, 6, 6, 12, 10, 20, 9, 4, 12, 8, 5, 6, 9, 10, 16, 15, 6, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 12, 4, 9, 12, 4, 2, 9, 6, 15, 16, 12, 8, 12, 8, 10, 20, 9, 4, 9, 12, 10, 4, 6, 15, 12, 12, 6, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 4, 2, 3, 8, 4, 8, 15, 15, 5, 4, 6, 10, 12, 20, 5, 12, 15, 6, 9, 8, 15, 6, 15, 20, 12, 9, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 8, 8, 15, 12, 6, 8, 12, 12, 5, 20, 15, 10, 12, 16, 10, 16, 12, 10, 15, 12, 25, 10, 12, 25, 20, 12, 2, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 15, 8, 6, 15, 12, 4, 6, 9, 9, 5, 16, 9, 6, 6, 16, 15, 16, 12, 10, 15, 8, 15, 6, 3, 20, 12, 9, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 9, 8, 8, 12, 16, 8, 6, 12, 9, 5, 16, 12, 6, 9, 16, 20, 16, 9, 8, 12, 16, 10, 8, 6, 20, 16, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 10, 3, 16, 2, 8, 15, 12, 10, 20, 6, 8, 15, 16, 5, 4, 15, 2, 15, 4, 25, 10, 12, 15, 16, 9, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 12, 8, 9, 16, 8, 2, 12, 15, 15, 20, 15, 8, 12, 20, 25, 20, 15, 2, 15, 12, 20, 8, 12, 5, 16, 12, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 10, 3, 12, 8, 10, 12, 12, 5, 20, 6, 10, 15, 20, 20, 4, 15, 2, 12, 20, 20, 8, 15, 10, 12, 6, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 6, 3, 16, 2, 8, 12, 12, 15, 20, 12, 4, 15, 8, 10, 8, 12, 2, 15, 8, 10, 2, 15, 5, 12, 9, 2, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 16, 8, 6, 16, 4, 4, 15, 6, 10, 20, 12, 8, 6, 20, 5, 12, 12, 2, 12, 16, 10, 8, 9, 5, 20, 9, 10, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 4, 8, 3, 16, 2, 6, 9, 15, 5, 20, 12, 8, 12, 16, 20, 12, 12, 2, 15, 12, 25, 6, 12, 5, 12, 9, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 12, 4, 10, 12, 16, 4, 10, 15, 12, 5, 20, 3, 10, 12, 16, 5, 4, 12, 8, 15, 8, 25, 10, 12, 5, 20, 3, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 10, 15, 4, 10, 3, 20, 2, 8, 15, 12, 10, 20, 9, 8, 9, 8, 10, 8, 12, 6, 15, 8, 25, 10, 12, 5, 20, 6, 8, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 12, 16, 8, 6, 16, 6, 8, 12, 6, 20, 16, 6, 8, 12, 12, 20, 16, 6, 4, 15, 16, 25, 4, 12, 10, 16, 6, 10, 4, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 15, 12, 10, 9, 16, 4, 4, 15, 12, 5, 20, 9, 6, 12, 16, 20, 16, 15, 8, 12, 4, 15, 8, 12, 5, 20, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 12, 20, 4, 12, 16, 8, 8, 12, 6, 20, 16, 9, 6, 6, 16, 5, 8, 9, 8, 9, 16, 20, 4, 9, 20, 12, 15, 8, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 3, 4, 8, 15, 4, 4, 2, 12, 15, 5, 20, 15, 2, 12, 16, 10, 12, 12, 10, 15, 4, 15, 10, 9, 15, 20, 15, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 12, 4, 6, 9, 16, 2, 8, 12, 6, 5, 20, 9, 6, 9, 16, 10, 12, 12, 6, 12, 12, 20, 6, 6, 15, 12, 12, 4, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 10, 9, 16, 2, 2, 15, 15, 15, 20, 15, 8, 12, 16, 10, 16, 15, 4, 12, 4, 20, 8, 12, 10, 16, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 12, 8, 12, 12, 2, 2, 15, 12, 20, 12, 12, 10, 12, 8, 15, 16, 15, 10, 15, 12, 10, 10, 15, 20, 16, 9, 10, 4, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 15, 16, 6, 15, 20, 8, 8, 3, 6, 5, 20, 12, 8, 3, 20, 25, 16, 6, 10, 15, 16, 20, 2, 6, 25, 20, 15, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 16, 8, 9, 20, 8, 4, 9, 15, 15, 16, 15, 8, 9, 4, 15, 16, 12, 2, 15, 8, 10, 8, 12, 25, 16, 12, 2, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 15, 4, 8, 9, 20, 6, 8, 15, 9, 20, 20, 6, 4, 12, 20, 20, 12, 15, 8, 15, 12, 15, 8, 12, 5, 12, 6, 4, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 12, 12, 8, 6, 16, 8, 6, 15, 12, 5, 16, 9, 6, 12, 20, 25, 12, 15, 8, 12, 16, 15, 8, 9, 10, 16, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 15, 4, 8, 12, 20, 2, 6, 12, 15, 10, 20, 12, 8, 9, 16, 15, 12, 12, 8, 12, 4, 25, 6, 6, 20, 20, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 9, 4, 10, 9, 16, 6, 8, 15, 15, 5, 20, 3, 6, 15, 20, 15, 4, 15, 2, 15, 4, 20, 8, 15, 5, 12, 3, 8, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 15, 16, 6, 12, 20, 6, 4, 9, 6, 5, 20, 15, 8, 9, 16, 10, 20, 9, 8, 15, 16, 15, 6, 12, 10, 16, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 12, 6, 12, 16, 6, 6, 12, 9, 15, 20, 9, 10, 12, 12, 5, 20, 9, 10, 15, 16, 20, 6, 12, 20, 20, 12, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 15, 4, 6, 12, 16, 2, 8, 15, 9, 20, 20, 15, 8, 6, 16, 20, 12, 15, 8, 12, 12, 25, 10, 9, 5, 20, 15, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 15, 16, 6, 9, 20, 4, 2, 15, 15, 10, 20, 12, 6, 12, 16, 5, 20, 9, 4, 12, 8, 5, 8, 15, 20, 20, 12, 6, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 15, 16, 10, 15, 16, 4, 4, 15, 9, 5, 16, 15, 10, 9, 16, 10, 16, 15, 10, 12, 8, 5, 10, 3, 15, 20, 9, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 8, 6, 9, 16, 6, 4, 12, 12, 10, 16, 12, 8, 9, 16, 10, 16, 9, 6, 15, 16, 10, 6, 6, 10, 16, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 9, 4, 8, 6, 12, 4, 10, 12, 12, 5, 12, 3, 4, 12, 16, 10, 4, 12, 2, 12, 16, 25, 8, 12, 10, 8, 3, 6, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 8, 6, 3, 16, 2, 4, 12, 12, 10, 20, 12, 4, 12, 16, 15, 20, 12, 2, 12, 16, 10, 6, 12, 10, 20, 12, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 15, 4, 10, 15, 20, 4, 8, 9, 9, 5, 20, 9, 6, 9, 20, 5, 4, 9, 6, 15, 4, 15, 2, 15, 5, 20, 9, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 8, 3, 16, 4, 8, 15, 15, 10, 20, 15, 6, 15, 20, 5, 20, 15, 2, 15, 4, 15, 6, 15, 5, 20, 9, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 15, 4, 8, 3, 20, 2, 10, 12, 15, 5, 20, 6, 6, 15, 16, 5, 4, 15, 8, 15, 4, 20, 8, 9, 5, 20, 12, 10, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 16, 6, 6, 20, 2, 10, 15, 3, 10, 20, 6, 10, 9, 20, 5, 12, 12, 8, 9, 4, 15, 4, 12, 20, 20, 12, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 3, 16, 10, 12, 12, 8, 6, 15, 12, 20, 20, 15, 10, 15, 12, 20, 16, 15, 4, 12, 20, 10, 8, 3, 5, 12, 15, 10, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 9, 16, 10, 6, 16, 6, 4, 6, 12, 20, 16, 6, 10, 6, 12, 20, 12, 3, 4, 6, 12, 20, 2, 12, 10, 8, 12, 10, 4, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 6, 16, 6, 3, 12, 10, 2, 9, 12, 15, 8, 12, 4, 15, 16, 15, 16, 15, 6, 12, 20, 5, 4, 12, 20, 16, 12, 4, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 4, 8, 6, 16, 6, 8, 12, 12, 5, 16, 9, 8, 12, 12, 5, 4, 12, 2, 9, 4, 5, 8, 12, 15, 20, 6, 8, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 12, 6, 12, 16, 8, 4, 9, 9, 5, 20, 12, 6, 9, 16, 20, 16, 12, 6, 12, 12, 15, 6, 6, 15, 12, 12, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 8, 10, 3, 20, 2, 10, 15, 12, 5, 20, 12, 10, 15, 20, 15, 4, 15, 2, 15, 4, 25, 10, 15, 5, 20, 15, 8, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 12, 16, 4, 15, 12, 6, 8, 9, 3, 10, 16, 3, 4, 3, 16, 10, 12, 9, 8, 12, 20, 10, 4, 12, 15, 8, 15, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 10, 15, 8, 8, 15, 16, 4, 4, 15, 12, 15, 20, 12, 8, 12, 12, 5, 16, 12, 6, 15, 4, 15, 8, 15, 15, 16, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 15, 4, 6, 12, 16, 4, 8, 15, 9, 5, 20, 12, 4, 9, 16, 5, 4, 12, 8, 9, 12, 20, 8, 6, 20, 20, 15, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 12, 8, 6, 16, 8, 2, 15, 12, 10, 20, 12, 10, 12, 12, 10, 20, 15, 8, 15, 16, 20, 4, 12, 10, 12, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 8, 3, 16, 6, 4, 15, 12, 10, 20, 15, 10, 12, 12, 15, 16, 9, 2, 15, 8, 20, 8, 15, 20, 16, 12, 8, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 6, 6, 20, 4, 15, 8, 6, 2, 9, 3, 15, 4, 12, 10, 9, 16, 25, 16, 12, 8, 12, 16, 5, 6, 9, 20, 12, 9, 6, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 12, 10, 6, 20, 4, 6, 15, 15, 10, 20, 9, 8, 15, 20, 5, 12, 15, 2, 15, 4, 25, 10, 15, 5, 16, 9, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 16, 6, 3, 12, 8, 4, 12, 9, 20, 16, 15, 6, 9, 16, 20, 16, 9, 2, 15, 16, 10, 6, 9, 5, 16, 12, 8, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 6, 16, 6, 6, 16, 10, 8, 15, 15, 15, 20, 12, 10, 9, 16, 25, 12, 12, 6, 12, 20, 25, 6, 15, 20, 8, 15, 10, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 12, 12, 8, 9, 20, 8, 6, 15, 15, 5, 20, 12, 10, 12, 12, 10, 20, 15, 10, 12, 16, 25, 10, 12, 20, 16, 9, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 8, 8, 3, 20, 2, 6, 9, 12, 5, 20, 15, 8, 15, 20, 5, 20, 15, 2, 12, 4, 10, 6, 15, 5, 16, 6, 8, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 15, 4, 8, 12, 20, 10, 2, 15, 15, 5, 16, 15, 8, 15, 4, 20, 4, 15, 4, 15, 4, 20, 10, 15, 20, 20, 15, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 9, 4, 8, 3, 16, 4, 6, 12, 9, 5, 16, 9, 6, 9, 16, 20, 12, 15, 2, 15, 16, 20, 8, 12, 10, 16, 6, 6, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 4, 10, 6, 20, 2, 8, 15, 15, 5, 20, 3, 10, 15, 20, 5, 4, 12, 2, 15, 4, 25, 10, 15, 5, 20, 3, 8, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 16, 8, 3, 20, 2, 10, 15, 15, 20, 20, 12, 10, 12, 20, 5, 20, 15, 4, 12, 4, 10, 8, 12, 5, 20, 15, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 12, 16, 4, 12, 12, 6, 4, 12, 12, 5, 20, 12, 4, 6, 12, 5, 12, 9, 8, 12, 4, 5, 4, 6, 25, 12, 15, 4, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 8, 6, 6, 16, 8, 6, 6, 12, 15, 12, 12, 6, 12, 12, 10, 4, 9, 2, 6, 16, 10, 4, 15, 10, 16, 6, 6, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 15, 16, 8, 6, 16, 2, 2, 12, 12, 5, 20, 12, 8, 12, 12, 10, 4, 12, 2, 9, 4, 10, 8, 15, 15, 16, 15, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 8, 9, 16, 6, 6, 15, 12, 25, 20, 9, 8, 12, 12, 15, 12, 15, 2, 9, 12, 20, 10, 15, 5, 16, 12, 10, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 12, 4, 6, 12, 16, 4, 4, 9, 9, 10, 16, 12, 6, 6, 16, 20, 16, 9, 8, 12, 8, 5, 4, 6, 10, 16, 12, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 12, 4, 8, 3, 20, 8, 10, 15, 12, 5, 16, 3, 8, 12, 20, 25, 8, 12, 2, 15, 20, 25, 10, 12, 5, 8, 3, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 15, 16, 10, 3, 20, 2, 2, 15, 3, 20, 20, 12, 4, 12, 4, 5, 16, 15, 2, 9, 4, 20, 10, 15, 25, 16, 12, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 6, 12, 16, 4, 12, 20, 8, 4, 15, 9, 5, 20, 9, 6, 3, 20, 15, 16, 12, 10, 15, 12, 10, 6, 3, 15, 12, 9, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 4, 6, 12, 12, 8, 4, 12, 12, 15, 20, 6, 10, 9, 20, 25, 20, 15, 8, 12, 20, 10, 8, 9, 5, 16, 6, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 16, 4, 6, 16, 10, 2, 15, 3, 5, 20, 12, 4, 15, 20, 10, 20, 12, 6, 15, 16, 5, 4, 12, 5, 8, 6, 8, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 6, 4, 6, 9, 12, 8, 8, 12, 12, 20, 8, 9, 6, 12, 16, 10, 20, 15, 2, 15, 16, 10, 4, 9, 15, 16, 12, 10, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 9, 8, 6, 12, 16, 4, 6, 12, 9, 5, 16, 12, 6, 9, 16, 5, 20, 12, 6, 12, 16, 10, 4, 12, 15, 8, 12, 8, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 12, 8, 4, 6, 16, 8, 8, 12, 12, 15, 8, 12, 4, 9, 4, 15, 20, 9, 4, 12, 16, 20, 10, 6, 5, 12, 6, 4, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 12, 6, 12, 16, 6, 6, 15, 12, 5, 16, 9, 10, 15, 20, 15, 12, 12, 6, 15, 12, 15, 6, 12, 5, 16, 9, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 4, 8, 9, 8, 8, 8, 15, 9, 5, 20, 12, 6, 9, 12, 25, 12, 12, 6, 6, 12, 20, 10, 9, 10, 12, 12, 8, 8, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 9, 4, 4, 12, 16, 8, 8, 9, 6, 5, 20, 12, 10, 9, 8, 10, 12, 6, 8, 15, 16, 25, 4, 6, 10, 16, 3, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 20, 8, 15, 20, 2, 4, 15, 12, 5, 4, 15, 10, 15, 20, 5, 20, 15, 2, 15, 16, 5, 10, 15, 5, 20, 15, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 9, 16, 8, 12, 12, 4, 4, 15, 3, 5, 16, 12, 4, 15, 8, 25, 12, 15, 4, 12, 20, 20, 10, 9, 20, 4, 12, 10, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 4, 10, 3, 16, 4, 8, 15, 15, 20, 16, 6, 6, 15, 12, 10, 12, 15, 2, 12, 4, 25, 10, 15, 10, 20, 9, 8, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 6, 4, 6, 3, 16, 6, 10, 15, 12, 5, 16, 6, 6, 12, 20, 15, 8, 9, 6, 15, 12, 20, 8, 9, 15, 12, 6, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 15, 12, 8, 15, 20, 2, 8, 12, 12, 5, 20, 15, 10, 12, 20, 5, 20, 6, 10, 15, 4, 10, 8, 3, 5, 20, 12, 8, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 9, 8, 8, 12, 16, 6, 6, 9, 9, 10, 16, 9, 6, 9, 16, 15, 8, 6, 8, 9, 8, 10, 8, 12, 10, 16, 6, 6, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 16, 8, 6, 20, 6, 4, 9, 3, 20, 20, 6, 2, 12, 20, 5, 8, 12, 8, 15, 16, 10, 8, 12, 15, 20, 15, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 8, 8, 3, 20, 2, 8, 3, 12, 10, 20, 6, 8, 12, 20, 5, 16, 9, 8, 15, 8, 20, 6, 6, 5, 20, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 15, 16, 6, 15, 12, 6, 4, 12, 15, 10, 20, 15, 8, 12, 12, 20, 20, 12, 10, 9, 4, 5, 8, 6, 10, 20, 15, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 8, 8, 9, 16, 8, 4, 15, 12, 20, 16, 12, 6, 12, 8, 5, 12, 12, 4, 12, 16, 10, 8, 9, 10, 16, 12, 6, 8, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 6, 8, 8, 9, 16, 8, 4, 6, 3, 15, 16, 9, 8, 6, 4, 20, 12, 3, 8, 15, 4, 5, 8, 3, 15, 16, 6, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 12, 12, 6, 3, 8, 10, 2, 9, 9, 10, 12, 15, 8, 9, 12, 25, 16, 12, 4, 15, 20, 5, 2, 12, 20, 16, 15, 6, 6, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 10, 15, 4, 10, 12, 20, 2, 10, 15, 9, 25, 20, 3, 10, 15, 12, 5, 4, 15, 4, 15, 16, 25, 10, 15, 25, 20, 12, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 9, 4, 8, 3, 12, 6, 4, 12, 15, 10, 16, 9, 6, 12, 12, 15, 12, 12, 2, 6, 12, 20, 6, 12, 5, 16, 9, 6, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 8, 6, 3, 20, 8, 10, 9, 12, 5, 8, 12, 10, 9, 20, 25, 12, 15, 10, 12, 16, 20, 8, 6, 20, 4, 9, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 4, 6, 16, 4, 6, 20, 10, 4, 6, 6, 10, 8, 15, 10, 12, 16, 20, 4, 6, 4, 12, 20, 5, 10, 6, 10, 4, 15, 8, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 4, 6, 12, 16, 2, 4, 9, 6, 5, 20, 6, 6, 9, 12, 25, 8, 9, 6, 15, 12, 10, 6, 6, 5, 20, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 4, 8, 3, 12, 4, 8, 12, 12, 5, 16, 3, 6, 12, 12, 15, 8, 9, 2, 12, 16, 20, 8, 12, 5, 12, 12, 8, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 8, 8, 6, 20, 6, 10, 6, 6, 25, 20, 9, 8, 6, 16, 25, 20, 15, 4, 15, 16, 15, 8, 6, 15, 16, 15, 8, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 4, 8, 3, 16, 4, 6, 12, 12, 5, 16, 6, 8, 9, 12, 5, 16, 12, 2, 12, 12, 15, 6, 12, 15, 12, 9, 8, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 16, 8, 3, 20, 8, 8, 9, 12, 5, 20, 12, 10, 15, 20, 5, 16, 12, 2, 15, 8, 10, 6, 15, 15, 20, 12, 8, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 15, 12, 4, 12, 4, 2, 6, 12, 9, 5, 20, 12, 8, 12, 16, 10, 16, 9, 8, 15, 8, 20, 6, 6, 5, 16, 6, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 12, 8, 8, 12, 20, 4, 10, 9, 12, 25, 16, 9, 6, 12, 20, 5, 16, 9, 8, 15, 4, 25, 6, 9, 5, 20, 6, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 8, 8, 3, 16, 2, 6, 12, 12, 10, 16, 12, 8, 12, 16, 5, 16, 15, 4, 12, 12, 15, 8, 12, 10, 16, 9, 10, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 9, 16, 4, 6, 16, 6, 6, 12, 9, 15, 12, 12, 4, 9, 16, 20, 16, 9, 8, 12, 16, 15, 6, 9, 10, 12, 9, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 4, 8, 3, 20, 4, 10, 12, 15, 15, 20, 6, 6, 12, 16, 15, 16, 9, 2, 15, 8, 20, 8, 12, 5, 16, 3, 2, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 12, 8, 12, 16, 4, 4, 12, 9, 10, 16, 12, 8, 12, 12, 10, 16, 15, 2, 15, 8, 15, 8, 12, 5, 20, 12, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 10, 15, 4, 10, 6, 20, 2, 10, 15, 15, 5, 20, 6, 10, 15, 4, 5, 16, 15, 4, 6, 4, 5, 10, 9, 10, 20, 12, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 8, 6, 9, 16, 4, 6, 12, 12, 10, 16, 9, 6, 9, 12, 10, 16, 9, 4, 12, 12, 15, 6, 12, 10, 16, 9, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 4, 3, 16, 4, 9, 8, 6, 4, 3, 9, 10, 4, 12, 4, 12, 12, 20, 4, 12, 6, 12, 20, 5, 2, 12, 25, 4, 12, 6, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 4, 8, 12, 16, 2, 8, 15, 12, 10, 20, 12, 8, 9, 16, 15, 16, 12, 8, 12, 8, 15, 8, 9, 10, 16, 6, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 9, 12, 8, 9, 16, 8, 6, 12, 12, 20, 12, 12, 4, 12, 8, 15, 16, 12, 4, 15, 16, 10, 4, 12, 10, 12, 12, 4, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 8, 8, 9, 12, 8, 10, 12, 12, 15, 20, 3, 10, 9, 8, 10, 4, 15, 6, 12, 8, 20, 8, 12, 10, 16, 9, 4, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 9, 4, 6, 6, 16, 6, 2, 12, 9, 10, 16, 12, 6, 9, 20, 20, 16, 15, 6, 15, 16, 10, 8, 6, 5, 16, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 10, 3, 20, 2, 10, 15, 15, 5, 20, 3, 10, 15, 16, 5, 4, 15, 2, 15, 4, 25, 10, 15, 5, 20, 3, 6, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 12, 8, 10, 3, 16, 6, 4, 15, 12, 10, 20, 15, 10, 15, 16, 10, 20, 15, 2, 15, 12, 10, 10, 15, 10, 12, 12, 10, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 4, 10, 9, 20, 2, 6, 12, 15, 5, 20, 9, 8, 12, 8, 5, 16, 15, 8, 12, 4, 15, 10, 15, 5, 20, 12, 10, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 6, 4, 4, 3, 16, 8, 8, 3, 9, 10, 4, 6, 8, 12, 8, 20, 20, 12, 6, 9, 16, 25, 2, 9, 10, 12, 12, 10, 6, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 8, 8, 3, 16, 8, 8, 6, 15, 5, 16, 9, 8, 12, 20, 25, 16, 12, 2, 15, 16, 15, 10, 9, 5, 12, 9, 10, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 12, 8, 3, 16, 8, 6, 12, 15, 25, 20, 12, 8, 15, 16, 5, 4, 9, 2, 12, 12, 20, 8, 12, 5, 20, 15, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 12, 20, 8, 15, 16, 8, 2, 12, 6, 5, 16, 15, 6, 3, 20, 5, 20, 12, 8, 12, 20, 5, 10, 6, 20, 12, 12, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 8, 6, 6, 20, 4, 6, 6, 6, 15, 16, 3, 4, 6, 12, 20, 4, 6, 4, 12, 20, 10, 8, 3, 5, 8, 9, 4, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 6, 6, 20, 6, 10, 15, 15, 15, 20, 6, 6, 12, 16, 5, 20, 12, 6, 12, 12, 20, 4, 9, 20, 16, 15, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 12, 16, 8, 12, 16, 8, 4, 12, 6, 5, 16, 12, 6, 9, 16, 20, 16, 12, 8, 12, 12, 15, 8, 6, 5, 16, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 4, 2, 9, 16, 8, 2, 15, 12, 5, 20, 15, 8, 12, 12, 15, 16, 9, 8, 12, 4, 10, 6, 6, 5, 20, 6, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 4, 8, 12, 16, 4, 6, 12, 12, 10, 16, 6, 6, 12, 16, 10, 8, 12, 8, 12, 8, 20, 8, 9, 5, 16, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 6, 6, 12, 4, 12, 12, 8, 6, 12, 12, 25, 8, 12, 6, 15, 20, 20, 8, 9, 10, 12, 16, 20, 8, 15, 20, 8, 12, 4, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 6, 16, 2, 12, 8, 8, 4, 12, 9, 10, 4, 15, 4, 6, 12, 20, 16, 3, 8, 6, 16, 10, 8, 6, 15, 4, 9, 8, 6, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 15, 20, 4, 12, 4, 4, 2, 15, 3, 5, 20, 15, 10, 9, 4, 15, 20, 9, 8, 9, 8, 5, 6, 6, 20, 20, 12, 2, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 16, 2, 6, 20, 4, 2, 12, 9, 5, 16, 15, 2, 9, 16, 5, 20, 12, 8, 15, 16, 5, 2, 9, 5, 16, 15, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 4, 10, 3, 8, 6, 10, 15, 15, 5, 16, 3, 8, 15, 12, 20, 4, 15, 2, 12, 16, 20, 10, 15, 5, 16, 6, 8, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 8, 6, 9, 16, 8, 6, 12, 9, 5, 20, 9, 2, 9, 16, 10, 8, 15, 6, 12, 12, 25, 8, 9, 15, 16, 6, 10, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 4, 6, 12, 4, 8, 10, 15, 12, 15, 12, 12, 10, 6, 4, 20, 12, 15, 10, 15, 12, 25, 6, 12, 15, 12, 9, 6, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 12, 8, 9, 16, 4, 4, 9, 9, 10, 20, 12, 6, 12, 12, 5, 16, 12, 6, 12, 4, 15, 4, 12, 15, 16, 12, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 12, 4, 8, 12, 16, 6, 8, 15, 12, 10, 16, 6, 10, 9, 16, 20, 4, 12, 8, 12, 8, 25, 8, 12, 10, 20, 6, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 15, 12, 8, 12, 20, 2, 8, 15, 12, 5, 20, 12, 6, 9, 8, 5, 8, 12, 10, 12, 12, 25, 8, 9, 10, 20, 6, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 16, 4, 3, 20, 8, 2, 9, 12, 5, 16, 15, 2, 12, 20, 25, 20, 12, 2, 15, 16, 10, 2, 6, 5, 16, 15, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 12, 4, 6, 9, 16, 2, 10, 12, 9, 10, 12, 3, 6, 9, 8, 10, 12, 15, 8, 9, 4, 20, 6, 9, 15, 20, 12, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 16, 10, 9, 16, 10, 8, 15, 12, 5, 20, 12, 2, 15, 20, 15, 12, 15, 6, 15, 20, 15, 10, 9, 5, 4, 15, 8, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 9, 4, 4, 3, 16, 8, 8, 15, 6, 15, 20, 12, 4, 6, 20, 25, 4, 12, 8, 15, 16, 15, 4, 6, 15, 16, 15, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 12, 8, 9, 12, 4, 6, 9, 12, 20, 16, 9, 8, 12, 8, 10, 12, 9, 4, 12, 16, 15, 8, 9, 10, 12, 12, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 6, 12, 2, 9, 4, 10, 2, 12, 9, 10, 4, 15, 2, 9, 12, 10, 8, 12, 8, 3, 12, 20, 6, 3, 20, 4, 9, 8, 10, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 12, 12, 6, 9, 16, 2, 4, 9, 6, 5, 20, 15, 6, 6, 20, 15, 20, 9, 10, 15, 4, 10, 4, 6, 10, 12, 9, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 4, 15, 20, 8, 15, 12, 8, 2, 12, 9, 15, 8, 15, 2, 12, 8, 15, 8, 3, 8, 12, 16, 5, 8, 12, 15, 12, 12, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 9, 20, 4, 12, 12, 2, 2, 9, 6, 5, 16, 15, 6, 6, 12, 5, 20, 6, 8, 15, 16, 5, 4, 6, 20, 12, 15, 8, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 4, 8, 6, 20, 4, 8, 12, 12, 5, 20, 6, 6, 12, 20, 5, 4, 12, 2, 15, 4, 20, 6, 12, 5, 16, 3, 8, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 9, 8, 8, 12, 12, 4, 4, 12, 9, 5, 16, 6, 6, 9, 16, 10, 16, 9, 6, 12, 8, 15, 6, 6, 5, 16, 12, 8, 6, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 18, 4, 8, 9, 20, 4, 6, 12, 6, 5, 20, 12, 8, 9, 16, 10, 16, 12, 8, 15, 4, 15, 8, 6, 5, 16, 12, 4, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 8, 8, 12, 16, 2, 4, 12, 3, 5, 20, 12, 8, 9, 16, 10, 12, 9, 8, 9, 4, 15, 8, 12, 5, 20, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 16, 8, 9, 16, 2, 4, 9, 9, 5, 20, 12, 8, 12, 16, 5, 16, 12, 8, 12, 8, 20, 8, 6, 5, 16, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 4, 10, 12, 20, 4, 10, 15, 15, 5, 20, 12, 10, 15, 20, 5, 16, 12, 8, 15, 8, 20, 8, 9, 5, 16, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 12, 16, 6, 12, 16, 6, 6, 9, 6, 5, 16, 12, 8, 6, 16, 15, 16, 12, 8, 12, 12, 15, 6, 6, 15, 12, 12, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 9, 4, 8, 9, 16, 4, 8, 12, 12, 15, 16, 6, 4, 6, 20, 15, 12, 12, 2, 15, 4, 20, 6, 9, 10, 12, 9, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 15, 4, 8, 12, 20, 6, 4, 15, 12, 5, 20, 9, 10, 15, 20, 5, 16, 15, 10, 15, 4, 25, 10, 15, 5, 20, 9, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 16, 4, 3, 20, 4, 4, 12, 12, 10, 20, 9, 4, 9, 12, 5, 4, 9, 2, 15, 4, 20, 6, 12, 5, 16, 6, 6, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 9, 4, 4, 6, 16, 4, 8, 12, 9, 5, 20, 6, 4, 9, 20, 10, 16, 9, 6, 15, 8, 20, 4, 12, 5, 20, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 9, 20, 8, 3, 12, 8, 2, 15, 6, 20, 12, 15, 8, 12, 8, 10, 20, 15, 6, 15, 16, 15, 8, 9, 20, 16, 15, 6, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 8, 8, 9, 12, 6, 6, 12, 9, 5, 16, 6, 6, 9, 12, 15, 12, 12, 6, 12, 12, 15, 6, 9, 10, 12, 12, 8, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 15, 8, 6, 9, 16, 4, 2, 9, 9, 5, 20, 15, 6, 6, 16, 15, 16, 12, 10, 15, 12, 5, 6, 6, 20, 12, 15, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 20, 8, 9, 20, 4, 10, 15, 12, 15, 20, 15, 2, 6, 4, 10, 20, 15, 10, 15, 20, 20, 8, 9, 20, 12, 15, 6, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 10, 3, 16, 8, 10, 15, 12, 20, 20, 9, 8, 15, 20, 25, 4, 15, 2, 12, 12, 25, 10, 15, 5, 12, 15, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 8, 8, 9, 16, 4, 8, 9, 9, 10, 16, 6, 8, 9, 16, 10, 8, 9, 6, 12, 8, 10, 8, 6, 10, 16, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 16, 6, 6, 16, 8, 6, 12, 15, 5, 20, 12, 10, 15, 16, 10, 16, 15, 2, 12, 8, 15, 6, 9, 5, 16, 6, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 4, 12, 12, 10, 15, 16, 4, 6, 15, 12, 25, 20, 15, 10, 9, 8, 5, 16, 15, 8, 6, 4, 20, 10, 12, 15, 16, 15, 10, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 4, 8, 9, 8, 2, 6, 12, 12, 5, 20, 12, 8, 9, 20, 20, 20, 15, 8, 9, 8, 15, 2, 9, 20, 12, 15, 10, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 9, 8, 8, 6, 20, 6, 8, 12, 12, 15, 12, 6, 8, 9, 20, 20, 8, 12, 4, 9, 16, 15, 8, 9, 10, 16, 6, 10, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 9, 20, 8, 9, 16, 6, 8, 15, 12, 5, 16, 12, 10, 12, 8, 10, 16, 12, 8, 12, 12, 10, 8, 12, 20, 12, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 6, 6, 12, 6, 6, 9, 12, 20, 12, 9, 6, 12, 16, 15, 12, 12, 2, 9, 16, 15, 8, 15, 25, 16, 12, 6, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 12, 10, 3, 20, 2, 2, 15, 12, 15, 20, 12, 10, 12, 16, 5, 20, 15, 2, 15, 12, 5, 8, 12, 5, 16, 15, 8, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 6, 15, 20, 8, 8, 9, 15, 15, 20, 12, 8, 9, 16, 15, 16, 3, 2, 15, 4, 20, 6, 9, 20, 20, 12, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 12, 8, 6, 15, 4, 8, 6, 12, 15, 25, 12, 6, 6, 15, 20, 25, 20, 3, 10, 3, 20, 20, 6, 15, 25, 4, 9, 10, 10, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 6, 12, 6, 12, 20, 6, 4, 12, 6, 5, 16, 12, 6, 6, 16, 25, 16, 12, 8, 15, 20, 10, 4, 6, 10, 8, 15, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 16, 2, 12, 20, 8, 2, 15, 9, 5, 20, 12, 10, 9, 20, 20, 20, 12, 6, 15, 8, 10, 6, 9, 5, 8, 9, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 12, 8, 8, 9, 12, 4, 8, 6, 12, 20, 8, 3, 10, 12, 12, 20, 12, 3, 8, 12, 4, 20, 2, 12, 15, 20, 6, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 12, 16, 8, 12, 20, 8, 8, 15, 12, 5, 16, 9, 10, 15, 20, 25, 20, 15, 8, 15, 4, 10, 8, 9, 5, 12, 6, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 20, 6, 12, 16, 4, 2, 15, 6, 5, 20, 15, 8, 6, 16, 15, 20, 15, 10, 12, 4, 5, 6, 12, 5, 12, 15, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 9, 4, 8, 3, 12, 2, 10, 3, 9, 20, 12, 3, 10, 3, 12, 15, 16, 9, 2, 9, 16, 20, 2, 12, 15, 12, 3, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 12, 4, 8, 6, 20, 2, 8, 12, 15, 5, 16, 3, 8, 12, 12, 10, 4, 12, 6, 12, 4, 15, 10, 9, 5, 20, 9, 10, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 12, 6, 6, 20, 2, 4, 15, 9, 5, 20, 12, 10, 12, 20, 5, 20, 6, 4, 12, 8, 10, 6, 12, 5, 20, 3, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 6, 20, 2, 9, 8, 8, 4, 12, 15, 20, 8, 15, 8, 9, 16, 15, 4, 6, 6, 3, 8, 5, 4, 9, 20, 8, 15, 4, 10, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 8, 6, 9, 20, 2, 4, 9, 6, 5, 20, 9, 4, 9, 16, 5, 8, 9, 6, 15, 4, 10, 6, 9, 5, 20, 6, 6, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 16, 2, 12, 12, 6, 4, 12, 9, 5, 4, 6, 2, 12, 16, 15, 8, 12, 8, 15, 16, 10, 2, 3, 15, 8, 15, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 9, 16, 4, 6, 16, 6, 4, 9, 12, 10, 4, 12, 6, 12, 8, 15, 8, 9, 10, 15, 16, 15, 6, 9, 15, 12, 9, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 15, 12, 6, 12, 16, 4, 8, 15, 15, 5, 20, 15, 10, 9, 8, 5, 20, 12, 10, 12, 4, 10, 4, 6, 5, 20, 12, 8, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 6, 16, 6, 6, 12, 8, 4, 9, 6, 10, 12, 12, 6, 6, 8, 20, 16, 9, 4, 9, 16, 10, 4, 6, 15, 12, 12, 4, 6, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 8, 3, 16, 2, 8, 12, 3, 5, 20, 9, 8, 12, 20, 5, 8, 12, 2, 15, 12, 25, 8, 12, 5, 20, 9, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 9, 12, 4, 9, 4, 10, 10, 15, 15, 20, 4, 15, 10, 9, 12, 25, 20, 15, 10, 3, 20, 25, 10, 12, 15, 4, 12, 10, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 16, 8, 12, 16, 8, 8, 6, 12, 10, 16, 12, 4, 12, 16, 15, 12, 6, 4, 12, 4, 20, 4, 15, 20, 16, 9, 6, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 9, 4, 6, 3, 16, 4, 8, 9, 6, 10, 12, 6, 6, 9, 16, 5, 8, 6, 2, 12, 12, 15, 4, 9, 5, 12, 3, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 4, 10, 6, 20, 6, 4, 12, 15, 5, 20, 12, 8, 15, 20, 20, 16, 15, 2, 15, 12, 25, 10, 15, 5, 20, 6, 10, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 12, 4, 10, 3, 12, 4, 8, 9, 15, 25, 16, 6, 10, 3, 20, 20, 16, 9, 4, 6, 8, 15, 2, 6, 10, 16, 3, 10, 6, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 9, 16, 6, 9, 20, 8, 6, 15, 15, 15, 20, 15, 6, 12, 12, 20, 20, 9, 8, 15, 16, 20, 4, 9, 15, 12, 12, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 9, 4, 6, 9, 16, 4, 6, 12, 9, 5, 16, 9, 8, 9, 16, 20, 8, 12, 10, 12, 12, 15, 8, 9, 10, 12, 6, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 9, 8, 10, 9, 16, 4, 6, 9, 12, 15, 20, 9, 2, 9, 20, 5, 12, 9, 6, 15, 4, 25, 10, 12, 5, 20, 9, 8, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 4, 6, 15, 16, 6, 4, 15, 12, 10, 20, 12, 6, 9, 12, 10, 8, 9, 8, 12, 12, 15, 6, 9, 5, 16, 12, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 16, 8, 12, 16, 8, 6, 15, 12, 15, 20, 15, 10, 15, 16, 5, 20, 15, 4, 12, 8, 10, 8, 12, 15, 12, 12, 10, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 12, 6, 12, 20, 4, 8, 15, 12, 10, 20, 15, 8, 12, 16, 5, 12, 9, 8, 12, 4, 20, 10, 12, 15, 16, 9, 10, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 6, 6, 16, 2, 8, 9, 9, 5, 20, 12, 8, 9, 16, 5, 16, 3, 6, 12, 4, 20, 2, 3, 5, 20, 12, 10, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 15, 16, 8, 15, 20, 4, 8, 12, 6, 10, 20, 12, 10, 12, 4, 5, 16, 12, 10, 3, 4, 5, 4, 6, 25, 20, 15, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 6, 15, 16, 10, 9, 12, 6, 10, 12, 6, 25, 16, 12, 10, 12, 16, 20, 12, 9, 10, 15, 4, 20, 2, 6, 15, 12, 9, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 6, 16, 8, 6, 16, 8, 2, 12, 9, 10, 16, 12, 6, 12, 12, 20, 16, 12, 4, 12, 12, 5, 8, 12, 10, 12, 12, 8, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 10, 12, 8, 6, 12, 8, 6, 4, 12, 9, 10, 20, 12, 8, 6, 12, 5, 20, 12, 10, 9, 12, 10, 8, 9, 10, 16, 9, 8, 10, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 9, 4, 6, 9, 16, 8, 8, 9, 9, 15, 16, 9, 2, 3, 16, 10, 8, 12, 10, 15, 20, 15, 6, 9, 15, 16, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 16, 6, 9, 12, 8, 2, 6, 6, 20, 20, 15, 8, 15, 16, 15, 16, 15, 6, 15, 16, 15, 6, 9, 5, 16, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 12, 20, 6, 12, 4, 10, 2, 9, 15, 25, 4, 15, 8, 12, 20, 20, 4, 3, 10, 3, 20, 5, 10, 15, 25, 12, 15, 6, 10, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 8, 6, 9, 16, 4, 6, 12, 12, 10, 20, 12, 4, 12, 12, 10, 8, 12, 4, 12, 8, 15, 2, 9, 15, 16, 12, 6, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 4, 4, 12, 12, 4, 6, 12, 3, 10, 20, 12, 6, 9, 8, 10, 12, 6, 6, 12, 12, 10, 8, 12, 10, 12, 9, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 12, 12, 8, 9, 16, 8, 6, 12, 9, 10, 20, 9, 4, 9, 12, 10, 12, 9, 8, 15, 4, 15, 6, 9, 15, 12, 9, 4, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 15, 16, 8, 12, 16, 8, 4, 12, 9, 15, 20, 15, 10, 6, 8, 5, 20, 9, 10, 6, 16, 20, 4, 12, 20, 16, 12, 6, 8, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 9, 20, 2, 15, 4, 6, 6, 12, 12, 15, 16, 15, 10, 15, 16, 20, 4, 12, 10, 3, 20, 20, 8, 12, 25, 16, 15, 6, 6, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 4, 8, 6, 16, 4, 8, 15, 15, 20, 20, 12, 8, 15, 20, 5, 16, 12, 2, 15, 4, 15, 8, 15, 10, 20, 6, 8, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 16, 6, 6, 20, 6, 4, 12, 6, 25, 16, 15, 8, 6, 16, 15, 16, 6, 8, 12, 16, 10, 6, 6, 15, 4, 12, 4, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 9, 20, 2, 15, 16, 6, 4, 9, 3, 25, 4, 15, 8, 6, 16, 10, 16, 3, 6, 15, 20, 15, 2, 3, 15, 8, 15, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 12, 6, 9, 12, 6, 6, 12, 12, 15, 16, 12, 6, 12, 16, 15, 16, 12, 6, 12, 12, 15, 6, 12, 15, 20, 12, 6, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 4, 8, 6, 20, 8, 10, 9, 12, 5, 20, 12, 4, 9, 20, 5, 12, 6, 8, 15, 12, 20, 2, 3, 5, 16, 12, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 12, 8, 6, 16, 2, 4, 12, 9, 10, 16, 6, 8, 9, 8, 5, 16, 12, 6, 15, 12, 5, 4, 12, 20, 16, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 12, 8, 8, 15, 16, 6, 4, 12, 3, 20, 16, 15, 8, 6, 12, 20, 16, 9, 10, 12, 16, 5, 6, 3, 20, 4, 15, 2, 10, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 12, 8, 6, 15, 8, 6, 2, 12, 15, 20, 20, 15, 8, 6, 8, 5, 20, 12, 10, 15, 12, 5, 6, 3, 5, 12, 15, 10, 10, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 8, 3, 20, 8, 2, 12, 12, 5, 20, 15, 6, 15, 20, 20, 16, 15, 4, 15, 8, 5, 8, 12, 5, 20, 15, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 15, 4, 10, 9, 16, 4, 10, 12, 9, 5, 20, 6, 10, 6, 16, 5, 12, 15, 4, 9, 8, 20, 10, 9, 5, 12, 9, 8, 4, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 8, 6, 3, 16, 6, 4, 12, 12, 10, 16, 12, 6, 12, 4, 5, 20, 3, 2, 15, 4, 20, 6, 12, 5, 16, 12, 4, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 2, 6, 12, 8, 3, 8, 10, 8, 9, 9, 15, 12, 3, 10, 9, 8, 5, 12, 6, 8, 3, 20, 20, 6, 6, 5, 4, 9, 6, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 4, 4, 6, 12, 4, 6, 12, 9, 10, 12, 9, 4, 9, 16, 10, 8, 6, 4, 15, 8, 15, 2, 9, 10, 16, 12, 6, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 15, 4, 8, 3, 20, 4, 4, 12, 12, 15, 20, 9, 10, 15, 8, 5, 20, 12, 6, 9, 4, 10, 6, 9, 5, 20, 9, 8, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 15, 12, 10, 15, 16, 6, 6, 12, 9, 10, 20, 9, 10, 9, 20, 20, 20, 15, 8, 15, 4, 10, 10, 3, 20, 20, 12, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 15, 4, 8, 3, 20, 4, 8, 15, 15, 5, 20, 12, 10, 15, 20, 5, 16, 15, 2, 15, 4, 20, 8, 9, 10, 20, 12, 10, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 15, 20, 4, 6, 8, 6, 2, 12, 6, 15, 12, 3, 6, 3, 4, 15, 8, 9, 8, 3, 12, 10, 4, 9, 5, 8, 12, 6, 4, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 9, 12, 8, 6, 16, 6, 6, 15, 3, 20, 20, 12, 8, 6, 12, 10, 12, 15, 8, 3, 12, 20, 6, 9, 15, 16, 15, 8, 8, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 12, 12, 6, 6, 20, 2, 4, 12, 12, 10, 16, 15, 6, 12, 12, 5, 20, 9, 2, 12, 12, 10, 6, 15, 15, 16, 15, 2, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 10, 12, 16, 8, 12, 8, 6, 8, 3, 12, 10, 16, 12, 8, 12, 12, 15, 16, 15, 10, 3, 16, 25, 2, 15, 20, 4, 12, 10, 10, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 8, 9, 20, 2, 10, 12, 15, 20, 20, 12, 8, 15, 16, 10, 12, 15, 2, 15, 4, 20, 8, 12, 5, 20, 12, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 12, 8, 6, 9, 16, 4, 6, 9, 9, 10, 16, 12, 8, 12, 16, 15, 12, 9, 8, 9, 8, 15, 6, 9, 10, 16, 9, 4, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 12, 8, 6, 16, 6, 4, 12, 12, 5, 20, 12, 6, 9, 16, 15, 16, 12, 6, 12, 8, 15, 6, 12, 20, 16, 9, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 15, 4, 6, 12, 16, 6, 6, 12, 9, 5, 20, 12, 8, 9, 8, 5, 8, 9, 10, 12, 4, 20, 6, 3, 20, 16, 12, 8, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 15, 20, 6, 12, 20, 2, 2, 15, 9, 5, 20, 15, 10, 9, 20, 5, 20, 15, 6, 15, 4, 15, 6, 3, 5, 20, 3, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 15, 16, 8, 12, 16, 6, 4, 9, 9, 15, 20, 12, 10, 9, 16, 15, 16, 15, 10, 12, 8, 15, 6, 12, 20, 20, 12, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 12, 12, 6, 12, 16, 4, 8, 9, 6, 10, 16, 15, 4, 6, 16, 20, 20, 6, 10, 12, 16, 10, 4, 9, 10, 16, 9, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 15, 4, 8, 12, 16, 4, 8, 15, 6, 10, 20, 6, 10, 12, 12, 10, 8, 15, 4, 12, 8, 25, 8, 12, 15, 16, 6, 10, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 8, 4, 9, 16, 6, 8, 9, 9, 10, 20, 6, 4, 9, 20, 10, 12, 9, 6, 12, 12, 15, 6, 9, 15, 16, 9, 4, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 16, 8, 12, 16, 8, 2, 15, 6, 20, 16, 12, 6, 9, 16, 20, 20, 12, 6, 12, 16, 5, 8, 9, 15, 16, 15, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 16, 10, 3, 16, 8, 2, 15, 15, 25, 20, 12, 10, 15, 20, 5, 20, 15, 2, 15, 4, 20, 8, 15, 5, 20, 12, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 15, 4, 8, 12, 12, 8, 2, 15, 6, 20, 20, 15, 8, 6, 16, 5, 16, 3, 8, 12, 4, 20, 2, 15, 10, 20, 15, 8, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 4, 8, 9, 16, 2, 8, 12, 9, 5, 20, 12, 6, 9, 16, 10, 8, 12, 6, 9, 8, 15, 10, 12, 5, 20, 3, 4, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 4, 6, 6, 16, 4, 10, 15, 12, 15, 16, 12, 4, 15, 16, 20, 12, 9, 2, 12, 8, 25, 8, 12, 5, 8, 12, 4, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 12, 4, 10, 3, 16, 4, 4, 15, 15, 20, 12, 15, 10, 15, 20, 25, 20, 15, 2, 12, 16, 10, 10, 15, 5, 16, 15, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 8, 10, 9, 20, 4, 8, 15, 6, 10, 16, 9, 6, 12, 16, 10, 16, 12, 6, 12, 8, 15, 8, 9, 10, 16, 6, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 4, 4, 12, 16, 4, 8, 12, 15, 5, 20, 3, 6, 15, 16, 20, 16, 9, 8, 12, 8, 25, 2, 12, 15, 16, 6, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 15, 16, 4, 12, 20, 4, 8, 9, 9, 5, 16, 12, 6, 9, 16, 25, 20, 9, 8, 12, 20, 10, 6, 3, 5, 8, 9, 8, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 12, 4, 10, 3, 20, 4, 4, 15, 15, 25, 12, 15, 10, 9, 20, 25, 4, 3, 10, 15, 20, 25, 10, 15, 5, 4, 15, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 9, 16, 4, 12, 12, 8, 4, 12, 15, 20, 4, 15, 8, 12, 12, 15, 8, 12, 6, 9, 16, 15, 8, 9, 20, 8, 15, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 8, 4, 12, 16, 4, 8, 6, 6, 10, 16, 6, 4, 6, 16, 5, 16, 9, 8, 12, 8, 15, 4, 6, 10, 16, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 4, 8, 6, 16, 6, 4, 12, 9, 10, 20, 12, 6, 9, 16, 15, 16, 12, 4, 12, 12, 20, 8, 12, 10, 20, 12, 8, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 6, 9, 16, 2, 8, 15, 12, 5, 20, 15, 8, 12, 20, 5, 16, 15, 8, 12, 4, 15, 4, 15, 15, 20, 15, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 8, 6, 12, 20, 2, 6, 12, 6, 15, 20, 9, 6, 9, 16, 5, 16, 9, 8, 9, 4, 20, 8, 9, 15, 20, 9, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 15, 20, 8, 15, 20, 2, 10, 9, 9, 5, 20, 12, 4, 12, 16, 5, 12, 12, 10, 15, 4, 10, 6, 6, 5, 12, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 10, 12, 20, 2, 4, 9, 12, 5, 20, 3, 6, 12, 16, 5, 16, 15, 6, 12, 4, 20, 8, 15, 25, 16, 12, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 8, 6, 9, 12, 4, 6, 15, 3, 10, 16, 12, 8, 12, 12, 10, 16, 12, 6, 15, 16, 15, 6, 9, 5, 12, 9, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 15, 8, 6, 9, 16, 8, 10, 12, 6, 15, 16, 6, 4, 9, 20, 25, 4, 15, 6, 12, 16, 20, 6, 9, 10, 16, 12, 4, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 8, 8, 6, 16, 4, 8, 12, 12, 5, 20, 6, 4, 9, 16, 5, 8, 12, 8, 15, 8, 20, 8, 12, 15, 16, 9, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 8, 8, 3, 16, 8, 10, 15, 12, 5, 20, 9, 10, 12, 20, 10, 12, 12, 4, 12, 8, 25, 8, 9, 20, 16, 6, 10, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 4, 10, 12, 16, 4, 8, 15, 6, 5, 20, 9, 6, 9, 16, 5, 16, 12, 4, 15, 4, 20, 8, 12, 5, 20, 3, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 10, 12, 8, 8, 12, 16, 8, 8, 6, 15, 15, 16, 9, 10, 15, 16, 20, 4, 15, 10, 6, 20, 15, 10, 12, 25, 12, 12, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 12, 10, 9, 16, 2, 4, 15, 6, 15, 16, 12, 8, 9, 12, 10, 16, 15, 4, 15, 16, 20, 10, 12, 5, 20, 9, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 15, 16, 8, 12, 16, 4, 6, 9, 12, 20, 16, 12, 8, 9, 8, 10, 20, 12, 10, 15, 8, 5, 8, 12, 15, 16, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 6, 20, 4, 12, 12, 8, 2, 9, 6, 15, 12, 15, 8, 9, 8, 20, 20, 9, 10, 9, 16, 5, 6, 3, 20, 12, 12, 8, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 16, 8, 6, 16, 4, 4, 12, 15, 10, 20, 12, 8, 12, 8, 5, 20, 15, 4, 15, 4, 10, 8, 12, 10, 20, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 15, 16, 10, 9, 16, 4, 2, 15, 12, 5, 20, 15, 8, 9, 12, 10, 20, 9, 8, 15, 8, 20, 10, 6, 15, 20, 9, 10, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 12, 8, 6, 16, 8, 4, 15, 12, 5, 20, 12, 6, 12, 16, 25, 20, 15, 6, 15, 4, 15, 4, 9, 5, 12, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 12, 4, 6, 12, 16, 8, 8, 12, 12, 10, 20, 9, 6, 9, 16, 20, 8, 9, 6, 15, 16, 20, 8, 9, 10, 20, 9, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 16, 8, 12, 12, 6, 4, 12, 9, 5, 16, 6, 8, 9, 12, 15, 8, 6, 4, 6, 12, 15, 8, 6, 15, 12, 9, 4, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 12, 8, 6, 16, 6, 8, 15, 9, 15, 12, 9, 6, 12, 12, 5, 8, 12, 4, 9, 12, 10, 8, 12, 10, 12, 9, 10, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 8, 8, 6, 12, 4, 2, 9, 6, 5, 20, 15, 6, 6, 16, 15, 20, 12, 2, 15, 4, 25, 8, 12, 5, 20, 12, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 8, 8, 6, 20, 8, 10, 12, 9, 5, 16, 9, 10, 15, 4, 15, 20, 15, 2, 15, 12, 10, 6, 3, 15, 8, 9, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 12, 16, 4, 15, 4, 8, 4, 15, 15, 20, 8, 12, 2, 12, 16, 25, 8, 3, 10, 6, 16, 10, 10, 15, 20, 8, 12, 4, 4, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 9, 12, 8, 3, 8, 6, 4, 12, 6, 20, 12, 15, 2, 15, 20, 20, 16, 9, 4, 12, 16, 20, 8, 9, 5, 8, 12, 10, 2, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 16, 4, 12, 12, 8, 4, 9, 3, 10, 20, 15, 4, 9, 12, 20, 20, 15, 6, 9, 8, 10, 4, 6, 20, 12, 12, 6, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 4, 6, 6, 16, 4, 6, 12, 15, 10, 20, 9, 8, 9, 16, 5, 12, 9, 4, 12, 8, 20, 8, 12, 10, 16, 9, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 12, 10, 6, 16, 6, 8, 12, 15, 5, 20, 6, 6, 12, 20, 5, 12, 12, 4, 12, 4, 15, 8, 12, 10, 20, 3, 8, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 9, 4, 8, 3, 20, 4, 10, 15, 12, 5, 20, 3, 6, 15, 20, 20, 20, 15, 10, 12, 4, 25, 10, 15, 5, 8, 9, 8, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 9, 4, 8, 3, 12, 8, 2, 15, 15, 20, 20, 9, 6, 9, 8, 25, 12, 15, 2, 15, 8, 15, 6, 15, 5, 12, 15, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 12, 12, 4, 12, 8, 8, 8, 9, 6, 10, 4, 15, 8, 12, 12, 20, 20, 9, 10, 9, 12, 20, 8, 12, 10, 12, 9, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 16, 4, 6, 20, 6, 2, 9, 12, 10, 20, 15, 4, 15, 16, 10, 20, 12, 2, 6, 4, 5, 6, 12, 10, 16, 15, 6, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 9, 16, 4, 3, 20, 6, 4, 9, 9, 10, 20, 12, 8, 6, 16, 5, 16, 12, 4, 12, 16, 25, 6, 9, 20, 20, 12, 8, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 9, 16, 8, 9, 16, 6, 4, 12, 6, 20, 12, 12, 8, 9, 16, 10, 16, 12, 6, 9, 12, 10, 6, 6, 15, 12, 12, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 12, 4, 8, 12, 20, 4, 8, 15, 15, 5, 20, 3, 8, 9, 20, 5, 8, 9, 8, 15, 4, 25, 8, 6, 5, 20, 3, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 12, 20, 4, 6, 20, 8, 2, 6, 3, 10, 20, 15, 10, 3, 16, 25, 20, 15, 4, 3, 16, 5, 4, 3, 5, 8, 15, 2, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 10, 9, 12, 8, 9, 16, 4, 6, 12, 12, 10, 16, 12, 4, 9, 8, 10, 12, 9, 6, 6, 8, 10, 6, 12, 20, 16, 12, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 8, 8, 12, 16, 4, 8, 12, 9, 15, 20, 6, 6, 9, 16, 5, 12, 12, 8, 12, 4, 10, 6, 9, 15, 16, 12, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 10, 15, 8, 8, 12, 20, 2, 6, 12, 12, 10, 20, 15, 10, 12, 20, 5, 20, 12, 10, 15, 4, 5, 6, 9, 10, 12, 9, 6, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 6, 16, 10, 9, 16, 8, 8, 15, 15, 20, 12, 12, 6, 15, 20, 20, 16, 15, 2, 15, 12, 20, 10, 15, 10, 8, 12, 10, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 12, 4, 2, 12, 8, 4, 6, 12, 9, 5, 20, 12, 6, 6, 12, 10, 20, 12, 8, 9, 8, 20, 4, 9, 20, 12, 12, 8, 8, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 4, 8, 9, 16, 4, 8, 12, 12, 5, 20, 9, 8, 9, 16, 15, 8, 12, 4, 12, 8, 20, 6, 12, 5, 16, 12, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 6, 4, 4, 3, 12, 4, 10, 9, 6, 10, 20, 6, 2, 6, 8, 5, 4, 6, 6, 12, 20, 25, 6, 15, 10, 16, 6, 10, 4, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 12, 6, 3, 12, 6, 4, 9, 12, 15, 20, 12, 6, 12, 16, 10, 16, 9, 2, 15, 8, 10, 6, 12, 10, 16, 9, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 16, 8, 3, 12, 4, 4, 15, 9, 15, 16, 12, 8, 9, 12, 5, 16, 15, 6, 6, 12, 5, 8, 9, 10, 16, 15, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 15, 4, 8, 12, 20, 2, 8, 15, 6, 5, 20, 9, 8, 9, 16, 10, 16, 15, 8, 12, 16, 25, 6, 9, 10, 12, 6, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 10, 6, 8, 4, 3, 8, 6, 8, 6, 9, 15, 8, 9, 4, 6, 8, 20, 8, 9, 4, 9, 16, 20, 10, 12, 15, 8, 9, 6, 2, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 8, 3, 16, 4, 10, 12, 15, 20, 20, 6, 8, 15, 16, 5, 4, 12, 2, 12, 4, 25, 6, 15, 20, 20, 12, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 9, 4, 8, 12, 16, 6, 6, 15, 12, 5, 16, 9, 8, 9, 20, 20, 16, 9, 8, 15, 12, 15, 6, 6, 5, 12, 9, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 10, 9, 16, 6, 10, 12, 9, 10, 20, 6, 6, 12, 12, 5, 4, 9, 2, 9, 12, 25, 8, 9, 5, 16, 9, 6, 4, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 8, 6, 9, 16, 4, 6, 9, 9, 5, 20, 9, 6, 9, 16, 10, 16, 9, 4, 12, 12, 15, 4, 9, 10, 12, 9, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 6, 12, 16, 8, 8, 12, 9, 20, 20, 12, 4, 12, 16, 5, 12, 9, 4, 12, 16, 20, 6, 12, 20, 16, 15, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 15, 16, 6, 9, 16, 2, 4, 9, 6, 5, 20, 12, 6, 9, 16, 15, 16, 12, 8, 12, 4, 10, 6, 6, 5, 20, 9, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 4, 8, 9, 16, 2, 6, 9, 12, 10, 16, 6, 4, 12, 16, 10, 4, 12, 4, 15, 8, 20, 6, 15, 5, 20, 3, 8, 2, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 12, 8, 6, 6, 16, 8, 6, 12, 9, 5, 20, 9, 6, 6, 8, 20, 12, 12, 4, 12, 12, 20, 6, 9, 10, 8, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 10, 3, 20, 2, 15, 4, 10, 4, 6, 15, 20, 4, 15, 8, 9, 16, 25, 12, 15, 8, 3, 20, 5, 8, 12, 25, 4, 12, 2, 6, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 12, 8, 3, 16, 4, 8, 15, 15, 10, 20, 12, 6, 15, 20, 5, 16, 9, 2, 12, 8, 15, 8, 15, 20, 16, 12, 8, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 3, 8, 10, 3, 12, 10, 8, 15, 6, 5, 12, 12, 8, 15, 16, 25, 12, 12, 2, 15, 16, 25, 10, 12, 5, 12, 12, 6, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 8, 6, 12, 20, 2, 6, 15, 3, 20, 20, 15, 10, 9, 20, 5, 12, 9, 6, 12, 4, 15, 6, 9, 10, 20, 9, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 12, 6, 15, 20, 8, 8, 15, 12, 5, 20, 3, 10, 6, 20, 5, 12, 9, 10, 15, 4, 20, 2, 12, 5, 20, 12, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 6, 4, 8, 12, 16, 6, 8, 12, 9, 5, 16, 6, 10, 9, 20, 20, 4, 12, 8, 12, 16, 15, 6, 6, 10, 20, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 12, 10, 12, 16, 6, 6, 15, 15, 15, 16, 9, 8, 15, 20, 15, 12, 15, 8, 12, 4, 5, 10, 12, 5, 20, 15, 10, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 4, 8, 3, 12, 6, 6, 12, 12, 20, 16, 9, 6, 9, 12, 15, 8, 9, 2, 15, 12, 20, 8, 12, 20, 16, 9, 2, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 10, 15, 4, 8, 9, 20, 2, 6, 9, 12, 5, 20, 12, 10, 9, 8, 5, 8, 12, 4, 6, 4, 25, 8, 12, 15, 20, 6, 10, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 12, 8, 6, 16, 10, 4, 15, 9, 20, 20, 15, 6, 12, 20, 20, 20, 15, 2, 12, 16, 10, 8, 6, 5, 4, 9, 4, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 12, 8, 12, 16, 4, 6, 12, 6, 5, 20, 12, 8, 12, 16, 10, 12, 3, 8, 15, 12, 20, 8, 9, 10, 12, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 8, 6, 12, 16, 4, 6, 9, 12, 10, 20, 12, 6, 12, 16, 10, 16, 9, 8, 15, 4, 15, 6, 6, 20, 12, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 6, 6, 16, 4, 9, 16, 8, 4, 9, 12, 5, 20, 12, 8, 12, 12, 20, 20, 15, 6, 12, 12, 15, 4, 9, 20, 20, 15, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 15, 16, 10, 3, 16, 2, 4, 15, 12, 5, 20, 12, 6, 15, 20, 20, 16, 12, 2, 12, 4, 25, 10, 12, 5, 20, 15, 6, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 12, 12, 8, 3, 16, 8, 6, 15, 15, 25, 20, 15, 10, 15, 16, 10, 20, 15, 4, 15, 16, 10, 4, 12, 10, 12, 15, 4, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 9, 8, 8, 9, 16, 8, 8, 15, 12, 10, 16, 9, 8, 12, 20, 20, 8, 12, 2, 12, 4, 20, 6, 12, 10, 16, 6, 6, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 16, 10, 6, 16, 6, 2, 15, 12, 10, 20, 15, 8, 12, 16, 5, 20, 12, 2, 12, 8, 10, 6, 15, 20, 20, 15, 8, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 9, 12, 8, 6, 20, 6, 4, 15, 9, 5, 16, 12, 6, 12, 16, 10, 16, 12, 6, 12, 8, 10, 8, 6, 10, 12, 6, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 12, 6, 12, 8, 6, 4, 15, 9, 10, 16, 15, 6, 9, 20, 15, 20, 9, 6, 12, 16, 15, 6, 9, 15, 12, 12, 10, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 6, 4, 8, 9, 12, 4, 2, 12, 6, 25, 12, 3, 6, 12, 16, 15, 4, 12, 4, 9, 20, 15, 10, 9, 10, 12, 12, 6, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 15, 4, 8, 3, 20, 8, 4, 15, 15, 25, 16, 12, 10, 15, 20, 20, 20, 15, 2, 15, 16, 10, 6, 15, 10, 16, 9, 4, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 15, 4, 4, 3, 16, 8, 2, 15, 15, 5, 20, 15, 8, 12, 8, 20, 20, 12, 2, 12, 4, 10, 6, 12, 20, 20, 6, 8, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 4, 8, 6, 16, 4, 10, 12, 9, 5, 20, 6, 6, 9, 16, 5, 4, 15, 2, 12, 4, 15, 4, 12, 15, 16, 12, 6, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 6, 9, 20, 4, 8, 15, 15, 5, 20, 9, 4, 12, 16, 5, 20, 15, 6, 15, 12, 10, 4, 12, 10, 16, 15, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 4, 6, 6, 16, 4, 8, 9, 12, 10, 20, 9, 6, 12, 16, 10, 12, 9, 6, 9, 4, 20, 6, 12, 5, 20, 3, 8, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 15, 12, 8, 9, 20, 2, 6, 12, 9, 5, 20, 9, 4, 9, 16, 5, 12, 9, 8, 15, 4, 10, 6, 12, 5, 16, 12, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 4, 6, 3, 12, 4, 6, 3, 9, 5, 20, 9, 6, 9, 16, 5, 4, 9, 4, 12, 4, 5, 6, 12, 10, 12, 12, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 15, 4, 10, 15, 20, 2, 8, 15, 15, 5, 20, 12, 10, 15, 16, 5, 12, 15, 10, 15, 4, 10, 10, 12, 15, 20, 3, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 8, 8, 6, 20, 2, 6, 15, 6, 5, 20, 9, 10, 12, 20, 10, 8, 15, 4, 15, 8, 20, 8, 15, 10, 8, 6, 10, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 4, 8, 3, 20, 2, 4, 9, 15, 10, 20, 12, 8, 12, 20, 15, 12, 15, 2, 12, 4, 5, 8, 15, 25, 16, 15, 6, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 9, 20, 4, 9, 4, 6, 6, 12, 12, 15, 8, 15, 4, 9, 16, 20, 16, 9, 10, 3, 20, 10, 8, 12, 20, 12, 12, 6, 4, 3)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 8, 8, 9, 16, 4, 4, 15, 9, 15, 20, 15, 8, 9, 16, 10, 16, 15, 8, 12, 16, 15, 8, 6, 20, 12, 15, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 9, 4, 8, 6, 20, 10, 4, 12, 6, 5, 20, 3, 4, 12, 16, 10, 16, 12, 6, 15, 8, 25, 8, 6, 10, 16, 9, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 16, 8, 9, 16, 4, 6, 9, 9, 5, 20, 12, 6, 9, 20, 15, 20, 9, 6, 15, 4, 10, 6, 9, 5, 20, 9, 8, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 8, 10, 6, 8, 6, 8, 15, 12, 10, 20, 12, 10, 12, 8, 15, 16, 15, 4, 15, 4, 10, 10, 12, 20, 20, 9, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 12, 16, 8, 12, 16, 8, 2, 12, 3, 10, 20, 15, 10, 6, 16, 10, 20, 12, 8, 12, 8, 5, 8, 3, 10, 16, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 4, 12, 20, 6, 12, 20, 4, 2, 12, 9, 5, 16, 15, 6, 6, 16, 15, 20, 15, 8, 6, 8, 5, 6, 3, 5, 16, 12, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 6, 6, 20, 2, 9, 12, 10, 6, 12, 15, 25, 4, 15, 6, 6, 8, 25, 8, 9, 6, 6, 20, 5, 10, 9, 15, 4, 15, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 4, 8, 9, 20, 2, 8, 15, 12, 10, 20, 9, 8, 12, 8, 5, 8, 6, 2, 15, 4, 25, 10, 15, 5, 20, 6, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 4, 12, 8, 6, 6, 16, 6, 4, 9, 6, 5, 16, 12, 6, 9, 12, 20, 12, 9, 8, 12, 8, 10, 4, 3, 20, 16, 12, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 8, 6, 16, 4, 4, 9, 6, 15, 20, 12, 6, 9, 16, 5, 8, 9, 4, 12, 4, 15, 4, 9, 5, 20, 12, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 8, 10, 6, 20, 8, 4, 15, 12, 5, 20, 6, 10, 15, 20, 5, 16, 15, 6, 15, 8, 20, 8, 12, 10, 20, 12, 10, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 12, 6, 15, 16, 8, 6, 15, 12, 10, 20, 15, 8, 12, 12, 20, 20, 12, 8, 12, 16, 15, 4, 12, 20, 20, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 10, 12, 16, 8, 12, 16, 4, 4, 12, 9, 20, 16, 12, 8, 9, 8, 5, 20, 12, 8, 9, 8, 10, 6, 9, 20, 16, 15, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 20, 6, 6, 20, 6, 2, 15, 3, 5, 20, 15, 10, 9, 20, 25, 20, 15, 4, 15, 4, 20, 6, 6, 5, 20, 15, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 4, 8, 6, 16, 4, 10, 15, 15, 5, 20, 6, 8, 15, 16, 5, 4, 9, 4, 12, 4, 20, 6, 9, 5, 8, 3, 8, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 16, 10, 3, 20, 4, 8, 15, 12, 10, 20, 12, 8, 9, 16, 20, 16, 12, 2, 12, 16, 25, 10, 15, 5, 20, 12, 4, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 8, 15, 12, 2, 15, 12, 8, 2, 15, 6, 20, 20, 15, 8, 6, 16, 5, 20, 15, 10, 12, 12, 5, 2, 9, 20, 20, 15, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 3, 8, 8, 12, 12, 6, 6, 9, 12, 15, 16, 15, 4, 9, 12, 20, 16, 6, 8, 9, 16, 15, 6, 9, 15, 16, 9, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 9, 16, 8, 9, 16, 8, 8, 9, 6, 10, 8, 12, 10, 9, 20, 20, 12, 15, 2, 9, 20, 10, 6, 9, 20, 4, 15, 10, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 16, 8, 6, 20, 4, 2, 12, 3, 5, 20, 12, 4, 12, 16, 5, 20, 9, 4, 15, 8, 5, 8, 12, 15, 20, 15, 2, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 4, 8, 15, 20, 8, 6, 9, 12, 5, 20, 9, 8, 12, 16, 10, 12, 12, 10, 12, 8, 20, 6, 12, 20, 20, 12, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 10, 15, 20, 8, 15, 12, 4, 4, 15, 9, 10, 16, 12, 10, 6, 8, 5, 20, 12, 8, 6, 8, 15, 8, 9, 20, 16, 15, 8, 10, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 4, 6, 3, 20, 2, 8, 6, 15, 5, 20, 6, 4, 9, 16, 5, 4, 6, 4, 12, 4, 25, 4, 12, 10, 20, 9, 8, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 4, 12, 8, 10, 6, 16, 4, 6, 6, 9, 20, 16, 3, 8, 9, 16, 15, 16, 9, 4, 9, 12, 20, 6, 9, 15, 12, 6, 10, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (3, 10, 3, 16, 4, 6, 12, 6, 4, 9, 12, 15, 4, 15, 6, 12, 12, 20, 4, 12, 8, 6, 16, 15, 2, 9, 10, 4, 9, 8, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 12, 20, 6, 15, 12, 6, 6, 12, 6, 15, 16, 12, 10, 9, 16, 5, 20, 15, 10, 9, 12, 5, 6, 3, 15, 12, 12, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 9, 16, 6, 9, 16, 8, 2, 9, 9, 10, 20, 12, 6, 9, 16, 20, 16, 12, 6, 12, 16, 10, 6, 9, 10, 12, 15, 8, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 2, 6, 16, 10, 9, 20, 10, 4, 6, 6, 5, 4, 15, 6, 12, 8, 20, 4, 12, 4, 15, 20, 10, 2, 9, 5, 12, 9, 8, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 9, 4, 10, 3, 8, 6, 8, 15, 12, 10, 12, 6, 10, 15, 8, 10, 20, 15, 8, 12, 16, 5, 10, 12, 20, 8, 15, 10, 10, 6)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 12, 8, 6, 16, 4, 6, 15, 12, 10, 16, 12, 6, 9, 12, 10, 20, 12, 4, 12, 8, 15, 6, 12, 10, 20, 9, 8, 4, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 4, 4, 3, 20, 8, 6, 9, 15, 5, 20, 3, 2, 12, 20, 25, 4, 9, 2, 15, 4, 25, 6, 15, 15, 20, 9, 6, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 16, 2, 15, 20, 2, 2, 15, 12, 10, 20, 15, 8, 3, 16, 5, 16, 3, 8, 15, 16, 5, 2, 3, 5, 20, 12, 10, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 8, 8, 6, 16, 6, 6, 12, 12, 15, 20, 9, 6, 9, 16, 10, 8, 12, 4, 12, 16, 10, 6, 12, 5, 16, 15, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 9, 20, 6, 15, 8, 8, 2, 12, 3, 5, 16, 15, 10, 6, 20, 15, 20, 15, 10, 3, 12, 5, 6, 3, 10, 20, 15, 10, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 15, 16, 6, 3, 20, 2, 6, 3, 3, 5, 16, 15, 8, 15, 4, 15, 20, 9, 10, 15, 12, 5, 2, 9, 5, 20, 3, 2, 2, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 15, 16, 10, 12, 20, 2, 10, 15, 15, 5, 20, 12, 8, 15, 20, 5, 20, 15, 2, 3, 8, 15, 8, 3, 20, 20, 15, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 16, 6, 9, 16, 10, 4, 15, 9, 25, 20, 15, 8, 9, 12, 20, 20, 9, 4, 12, 16, 10, 4, 6, 20, 12, 15, 10, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 15, 12, 8, 12, 16, 4, 4, 12, 12, 5, 20, 12, 8, 12, 8, 5, 16, 12, 6, 6, 4, 20, 6, 9, 10, 16, 12, 10, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 12, 12, 6, 9, 16, 8, 6, 9, 9, 15, 16, 9, 6, 9, 12, 15, 20, 9, 8, 12, 4, 15, 8, 9, 15, 20, 12, 6, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 9, 4, 8, 3, 16, 10, 8, 9, 15, 10, 20, 12, 4, 12, 16, 25, 4, 9, 2, 12, 12, 10, 8, 15, 10, 12, 12, 8, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 8, 6, 12, 20, 2, 6, 12, 12, 10, 20, 12, 8, 12, 16, 5, 16, 9, 4, 12, 8, 20, 6, 12, 15, 16, 6, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 4, 12, 4, 10, 6, 20, 8, 8, 15, 9, 5, 20, 9, 8, 15, 16, 20, 8, 15, 4, 15, 16, 15, 8, 9, 5, 12, 6, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 8, 10, 3, 16, 6, 4, 12, 12, 20, 20, 9, 10, 15, 16, 10, 12, 12, 4, 15, 8, 10, 8, 9, 10, 20, 12, 8, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (9, 8, 12, 16, 8, 12, 4, 4, 8, 12, 6, 20, 16, 15, 8, 9, 16, 10, 20, 15, 10, 9, 20, 15, 4, 12, 20, 12, 6, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 15, 4, 8, 12, 20, 4, 10, 15, 15, 25, 20, 12, 8, 9, 20, 25, 16, 12, 10, 15, 8, 20, 2, 6, 15, 16, 15, 10, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 15, 12, 6, 3, 20, 2, 4, 12, 9, 10, 20, 9, 10, 12, 16, 5, 12, 12, 2, 12, 8, 15, 6, 12, 5, 20, 12, 6, 2, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 15, 16, 8, 9, 16, 4, 4, 15, 12, 20, 20, 15, 10, 12, 16, 5, 16, 9, 8, 12, 8, 15, 8, 9, 10, 20, 12, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 15, 16, 8, 15, 20, 2, 10, 6, 3, 5, 20, 12, 8, 12, 12, 5, 12, 12, 10, 12, 20, 20, 6, 6, 10, 20, 3, 8, 10, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 12, 12, 6, 12, 4, 2, 2, 12, 15, 5, 20, 6, 8, 9, 16, 25, 12, 15, 4, 12, 20, 25, 10, 9, 5, 20, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 2, 12, 16, 8, 15, 20, 6, 4, 6, 3, 5, 20, 15, 8, 3, 8, 20, 20, 12, 10, 3, 16, 10, 8, 6, 20, 16, 15, 8, 10, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 8, 12, 20, 8, 12, 20, 6, 8, 9, 3, 10, 20, 12, 10, 9, 8, 15, 16, 15, 6, 9, 16, 5, 4, 9, 10, 16, 15, 6, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 10, 12, 4, 8, 3, 12, 6, 10, 12, 12, 25, 12, 12, 2, 15, 20, 5, 4, 3, 2, 15, 16, 25, 2, 9, 15, 20, 12, 2, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 12, 4, 10, 3, 20, 2, 10, 12, 15, 5, 20, 12, 10, 15, 20, 10, 8, 12, 4, 15, 4, 25, 8, 15, 5, 20, 12, 8, 8, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 12, 20, 10, 3, 12, 2, 4, 15, 3, 10, 16, 12, 10, 9, 16, 20, 16, 15, 4, 9, 20, 10, 6, 15, 20, 16, 15, 6, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 16, 10, 6, 20, 2, 2, 15, 3, 5, 20, 12, 8, 12, 16, 10, 16, 12, 6, 15, 4, 5, 6, 12, 5, 20, 3, 8, 4, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 8, 15, 8, 6, 9, 16, 4, 8, 15, 9, 5, 16, 12, 10, 9, 16, 25, 8, 12, 6, 12, 12, 15, 4, 12, 15, 8, 15, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 6, 15, 12, 8, 12, 16, 4, 10, 15, 12, 5, 20, 12, 8, 9, 20, 5, 16, 12, 8, 15, 4, 25, 8, 12, 20, 20, 15, 8, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 8, 15, 4, 6, 12, 16, 6, 10, 12, 12, 10, 16, 6, 8, 6, 12, 5, 4, 12, 8, 12, 12, 20, 6, 6, 15, 16, 9, 6, 8, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 6, 15, 4, 8, 6, 16, 8, 6, 12, 12, 15, 16, 12, 4, 12, 8, 15, 8, 12, 4, 12, 12, 10, 6, 12, 15, 12, 9, 8, 6, 9)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 6, 12, 4, 8, 3, 16, 2, 2, 9, 9, 10, 16, 12, 8, 9, 12, 5, 16, 12, 8, 3, 8, 5, 8, 3, 5, 16, 12, 10, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 9, 4, 8, 6, 20, 8, 8, 12, 12, 5, 12, 9, 6, 12, 20, 20, 12, 12, 4, 15, 8, 20, 6, 12, 10, 8, 9, 10, 4, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 4, 15, 12, 6, 9, 16, 10, 4, 15, 12, 10, 16, 12, 6, 15, 16, 25, 12, 12, 4, 6, 16, 5, 6, 9, 15, 16, 12, 8, 6, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (12, 2, 15, 4, 10, 6, 20, 2, 10, 15, 15, 15, 20, 6, 8, 15, 20, 10, 4, 12, 6, 15, 8, 15, 10, 12, 5, 20, 9, 8, 6, 15)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (6, 4, 6, 4, 8, 12, 16, 8, 4, 15, 6, 5, 8, 6, 8, 6, 20, 20, 12, 6, 8, 15, 16, 25, 6, 6, 10, 12, 6, 2, 8, 12)
INSERT [dbo].[server_info]([XE01], [XE02], [XE03], [XE04], [XE05], [XE06], [XE07], [XE08], [XE09], [XE10], [XE11], [XE12], [XE13], [XE14], [XE15], [XE16], [XE17], [XE18], [XE19], [XE20], [XE21], [XE22], [XE23], [XE24], [XE25], [XE26], [XE27], [XE28], [XE29], [XE30], [XE31], [XE32]) VALUES (15, 2, 12, 4, 8, 3, 16, 8, 4, 12, 15, 5, 16, 12, 6, 12, 16, 20, 8, 12, 4, 12, 16, 20, 6, 12, 5, 8, 12, 6, 4, 12)


SELECT * FROM server_info


-- Factor Analysis
-- extract factor loadings

DECLARE @Rcode NVARCHAR(MAX)
SET @Rcode = N'
	## with actual FA funcitons
	library(psych)
	library(Hmisc)
	## for data munching and visualization
	library(ggplot2)
	library(plyr)
	library(pastecs)

	server.feature <- InputDataSet

	server.feature$XE12[server.feature$XE12=="25"]<-NA
	server.feature$XE18[server.feature$XE18=="25"]<-NA
	server.feature$XE24[server.feature$XE24=="25"]<-NA
	server.feature$XE27[server.feature$XE27=="25"]<-NA

	fa.model <- fa(server.feature
               ,7
               ,fm="pa"
               ,scores="regression"
               ,use="pairwise"
               ,rotate="varimax") #can use WLS - weighted least squares

	fa.loadings <- as.list.data.frame(fa.model$loadings)
	OutputDataSet <- data.frame(fa.loadings)
'

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = @Rcode
	,@input_data_1 = N'SELECT * FROM server_info'
WITH RESULT SETS
((
	 PA1 NUMERIC(16,3)
	,PA2 NUMERIC(16,3)
	,PA3 NUMERIC(16,3)
	,PA4 NUMERIC(16,3)
	,PA5 NUMERIC(16,3)
	,PA6 NUMERIC(16,3)
	,PA7 NUMERIC(16,3)
)) 

/*
---
--- WORK LOADS
---

*/

USE [master];
GO

CREATE DATABASE Workloads;
GO

USE Workloads;
GO

DROP TABLE IF EXISTS WLD;
GO

CREATE TABLE WLD
(WL_ID VARCHAR(5)
,Param1 TINYINT
,Param2 TINYINT
);
GO

INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 39, 43)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 28, 36)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 26, 31)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 16, 18)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 23, 29)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 40, 37)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 38, 38)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 42, 46)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 23, 28)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 22, 21)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 38, 35)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 31, 26)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 29, 43)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 45, 51)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 44, 47)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 26, 18)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 30, 30)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 31, 35)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 20, 26)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 27, 44)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 34, 34)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 38, 28)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 23, 32)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 28, 26)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL1', 47, 64)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 31, 21)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 48, 42)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 25, 43)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 23, 11)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 10, 8)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 26, 27)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 18, 20)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 32, 39)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 13, 0)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 39, 24)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 22, 15)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 28, 27)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 29, 35)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 13, 23)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 32, 31)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 21, 28)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 10, 9)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 41, 36)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 13, 15)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 40, 37)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 37, 37)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 9, 14)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 24, 7)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 32, 8)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL2', 21, 12)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 27, 21)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 29, 41)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 47, 48)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 28, 15)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 22, 26)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 42, 31)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 25, 15)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 27, 30)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 23, 26)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 24, 31)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 21, 23)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 50, 47)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 22, 26)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 39, 22)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 9, 28)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 30, 17)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 22, 33)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 45, 43)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 34, 39)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 30, 32)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 19, 20)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 36, 27)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 32, 19)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 32, 25)
INSERT [dbo].[WLD] ([WL_ID], [Param1], [Param2]) VALUES (N'WL3', 27, 19);
GO

SELECT * FROM [dbo].[WLD]

EXEC sp_execute_external_script
 @language = N'R'
,@script = N'
			library(car)
			library(ggplot2)
			dataset <- InputDataSet
			dataset$WL_ID <- as.numeric(recode(dataset$WL_ID, "''WL1''=1; ''WL2''=2;''WL3''=3"))
			dataset$Param1 <- as.numeric(dataset$Param1)
			dataset$Param2 <- as.numeric(dataset$Param2)

			m.dist <- mahalanobis(dataset, colMeans(dataset), cov(dataset))
			dataset$maha_dist <- round(m.dist)

			# Mahalanobis Outliers - Threshold set to 7
			dataset$outlier_mah <- "No"
			dataset$outlier_mah[dataset$maha_dist > 7] <- "Yes"

			 image_file = tempfile();  
			jpeg(filename = image_file);  

			# Scatterplot for checking outliers using Mahalanobis 
			ggplot(dataset, aes(x = Param1, y = Param2, color = outlier_mah)) +
			  geom_point(size = 5, alpha = 0.6) +
			  labs(title = "Mahalanobis distances for multivariate regression outliers",
				   subtitle = "Comparison on 1 parameter for three synthetic Workloads") +
			  xlab("Parameter 1") +
			  ylab("Parameter 2") +
			  scale_x_continuous(breaks = seq(5, 55, 5)) +
			  scale_y_continuous(breaks = seq(0, 70, 5))    + geom_abline(aes(intercept = 12.5607 , slope = 0.5727))

			  dev.off(); 
			OutputDataSet <- data.frame(data=readBin(file(image_file, "rb"), what=raw(), n=1e6))'
,@input_data_1 = N'SELECT * FROM WLD'



-- clean up
USE [master];
GO
DROP DATABASE Workloads;
GO

/*
---
--- DISK SPACE
---

*/

USE [master];
GO



CREATE DATABASE FixSizeDB
 CONTAINMENT = NONE
 ON  PRIMARY
( NAME = N'FixSizeDB_2', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER2017\MSSQL\DATA\FixSizeDB_2.mdf' , 
SIZE = 8192KB , FILEGROWTH = 0)
 LOG ON
( NAME = N'FixSizeDB_2_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER2017\MSSQL\DATA\FixSizeDB_2_log.ldf',
SIZE = 8192KB , FILEGROWTH = 0)
GO
ALTER DATABASE FixSizeDB_2 SET COMPATIBILITY_LEVEL = 140
GO
ALTER DATABASE FixSizeDB_2 SET RECOVERY SIMPLE
GO


USE FixSizeDB;
GO



CREATE TABLE DataPack
       (
         DataPackID BIGINT IDENTITY NOT NULL
        ,col1 VARCHAR(1000) NOT NULL
        ,col2 VARCHAR(1000) NOT NULL
        )
Populating the DataPack table will be done with the following simple WHILE loop: 
DECLARE @i INT = 1;
BEGIN TRAN
       WHILE @i <= 1000
              BEGIN
                     INSERT dbo.DataPack(col1, col2)
                           SELECT
                                    REPLICATE('A',200)
                                   ,REPLICATE('B',300);
                     SET @i = @i + 1;
              END
COMMIT;
GO


SELECT
    t.NAME AS TableName
    ,s.Name AS SchemaName
    ,p.rows AS RowCounts
    ,SUM(a.total_pages) * 8 AS TotalSpaceKB
    ,SUM(a.used_pages) * 8 AS UsedSpaceKB
    ,(SUM(a.total_pages) - SUM(a.used_pages)) * 8 AS UnusedSpaceKB
FROM
    sys.tables t
INNER JOIN sys.indexes AS i
       ON t.OBJECT_ID = i.object_id
INNER JOIN sys.partitions AS p
       ON i.object_id = p.OBJECT_ID
       AND i.index_id = p.index_id
INNER JOIN sys.allocation_units AS a
       ON p.partition_id = a.container_id
LEFT OUTER JOIN sys.schemas AS s
       ON t.schema_id = s.schema_id
WHERE
            t.NAME NOT LIKE 'dt%'
    AND t.is_ms_shipped = 0
    AND i.OBJECT_ID > 255
    AND t.Name = 'DataPack'
GROUP BY t.Name, s.Name, p.Rows





DECLARE @nof_steps INT = 0
WHILE @nof_steps < 15
BEGIN
       BEGIN TRAN
              -- insert some data
              DECLARE @i INT = 1;
              WHILE @i <= 1000 -- step is 100 rows
                                  BEGIN
                                         INSERT dbo.DataPack(col1, col2)
                                                SELECT
                                                         REPLICATE('A',FLOOR(RAND()*200))
                                                        ,REPLICATE('B',FLOOR(RAND()*300));
                                         SET @i = @i + 1;
                                  END
              -- run statistics on table
              INSERT INTO dbo.DataPack
              SELECT
                     t.NAME AS TableName
                     ,s.Name AS SchemaName
                     ,p.rows AS RowCounts
                     ,SUM(a.total_pages) * 8 AS TotalSpaceKB
                     ,SUM(a.used_pages) * 8 AS UsedSpaceKB
                     ,(SUM(a.total_pages) - SUM(a.used_pages)) * 8 AS UnusedSpaceKB
                     ,GETDATE() AS TimeMeasure
              FROM 
                           sys.tables AS t
                     INNER JOIN sys.indexes AS i
                     ON t.OBJECT_ID = i.object_id
                     INNER JOIN sys.partitions AS p
                     ON i.object_id = p.OBJECT_ID
                     AND i.index_id = p.index_id
                     INNER JOIN sys.allocation_units AS a
                     ON p.partition_id = a.container_id
                     LEFT OUTER JOIN sys.schemas AS s
                     ON t.schema_id = s.schema_id
              WHERE
                            t.NAME NOT LIKE 'dt%'
                     AND t.is_ms_shipped = 0
                     AND t.name = 'DataPack'
                     AND i.OBJECT_ID > 255
              GROUP BY t.Name, s.Name, p.Rows
              WAITFOR DELAY '00:00:02'
       COMMIT;
END


DECLARE @RScript nvarchar(max)
SET @RScript = N'
                            library(Hmisc)     
                            mydata <- InputDataSet
                            all_sub <- mydata[2:3]
                            c <- cor(all_sub, use="complete.obs", method="pearson")
                            t <- rcorr(as.matrix(all_sub), type="pearson")
                             c <- cor(all_sub, use="complete.obs", method="pearson")
                            c <- data.frame(c)
                            OutputDataSet <- c'
DECLARE @SQLScript nvarchar(max)
SET @SQLScript = N'SELECT
                                          TableName
                                         ,RowCounts
                                         ,UsedSpaceKB
                                         ,TimeMeasure
                                         FROM DataPack_Info_SMALL'
EXECUTE sp_execute_external_script
        @language = N'R'
       ,@script = @RScript
       ,@input_data_1 = @SQLScript
       WITH result SETS ((RowCounts VARCHAR(100)
                         ,UsedSpaceKB  VARCHAR(100)));
GO


--- generating inserts and deletes

DECLARE @nof_steps INT = 0
WHILE @nof_steps < 15
BEGIN
       BEGIN TRAN
              -- insert some data
              DECLARE @i INT = 1;
              DECLARE @insertedRows INT = 0;
              DECLARE @deletedRows INT = 0;
              DECLARE @Rand DECIMAL(10,2) = RAND()*10
              IF @Rand < 5
                BEGIN
                                  WHILE @i <= 1000 -- step is 100 rows
                                                       BEGIN
                                                              INSERT dbo.DataPack(col1, col2)
                                                                     SELECT
                                                                             REPLICATE('A',FLOOR(RAND()*200))  -- pages are filling up differently
                                                                            ,REPLICATE('B',FLOOR(RAND()*300));
                                                               SET @i = @i + 1;
                                                       END
                                  SET @insertedRows = 1000                                
                     END

               IF @Rand  >= 5
                     BEGIN                                             
                                  SET @deletedRows = (SELECT COUNT(*) FROM dbo.DataPack WHERE DataPackID % 3 = 0)
                                  DELETE FROM dbo.DataPack
                                                WHERE
                                  DataPackID % 3 = 0 OR DataPackID % 5 = 0

                     END
              -- run statistics on table
              INSERT INTO dbo.DataPack_Info_LARGE
              SELECT
                     t.NAME AS TableName
                     ,s.Name AS SchemaName
                     ,p.rows AS RowCounts
                     ,SUM(a.total_pages) * 8 AS TotalSpaceKB
                     ,SUM(a.used_pages) * 8 AS UsedSpaceKB
                     ,(SUM(a.total_pages) - SUM(a.used_pages)) * 8 AS UnusedSpaceKB
                     ,GETDATE() AS TimeMeasure
                     ,CASE WHEN @Rand < 5 THEN 'Insert'
                             WHEN @Rand >= 5 THEN 'Delete'
                             ELSE 'meeeh' END AS Operation
                     ,CASE WHEN @Rand < 5 THEN @insertedRows
                             WHEN @Rand >= 5 THEN @deletedRows
                             ELSE 0 END AS NofRowsOperation
              FROM 
                           sys.tables AS t
                     INNER JOIN sys.indexes AS i
                     ON t.OBJECT_ID = i.object_id
                     INNER JOIN sys.partitions AS p
                     ON i.object_id = p.OBJECT_ID
                     AND i.index_id = p.index_id
                     INNER JOIN sys.allocation_units AS a
                     ON p.partition_id = a.container_id
                     LEFT OUTER JOIN sys.schemas AS s
                     ON t.schema_id = s.schema_id

              WHERE
                            t.NAME NOT LIKE 'dt%'
                     AND t.is_ms_shipped = 0
                     AND t.name = 'DataPack'
                     AND i.OBJECT_ID > 255
              GROUP BY t.Name, s.Name, p.Rows
              WAITFOR DELAY '00:00:01'
       COMMIT;
END


--- calculate the correlations again:
DECLARE @RScript nvarchar(max)
SET @RScript = N'
                            library(Hmisc)     
                            mydata <- InputDataSet
                            all_sub <- mydata[2:3]
                            c <- cor(all_sub, use="complete.obs", method="pearson")
                            c <- data.frame(c)
                            OutputDataSet <- c'
DECLARE @SQLScript nvarchar(max)
SET @SQLScript = N'SELECT
                                          TableName
                                         ,RowCounts
                                         ,UsedSpaceKB
                                         ,TimeMeasure
                                         FROM DataPack_Info_LARGE'
EXECUTE sp_execute_external_script
        @language = N'R'
       ,@script = @RScript
       ,@input_data_1 = @SQLScript
       WITH result SETS ( (
                                          RowCounts VARCHAR(100)
                                         ,UsedSpaceKB  VARCHAR(100)
                         )); 
GO






DECLARE @RScript1 nvarchar(max)
SET @RScript1 = N'
                            library(Hmisc)     
                            mydata <- InputDataSet
                            all_sub <- mydata[4:5]
                            c <- cor(all_sub, use="complete.obs", method="pearson")
                            c <- data.frame(c)
                            OutputDataSet <- c'

DECLARE @SQLScript1 nvarchar(max)
SET @SQLScript1 = N'SELECT

                                          TableName
                                         ,RowCounts
                                         ,TimeMeasure
                                         ,UsedSpaceKB 
                                         ,UnusedSpaceKB
                                         FROM DataPack_Info_SMALL
                                         WHERE RowCounts <> 0'
EXECUTE sp_execute_external_script
        @language = N'R'
       ,@script = @RScript1
       ,@input_data_1 = @SQLScript1
       WITH result SETS ( (
                                          RowCounts VARCHAR(100)
                                         ,UsedSpaceKB  VARCHAR(100)
                                         ));


DECLARE @RScript2 nvarchar(max)
SET @RScript2 = N'
                            library(Hmisc)     
                            mydata <- InputDataSet
                            all_sub <- mydata[4:5]
                            c <- cor(all_sub, use="complete.obs", method="pearson")
                            c <- data.frame(c)
                            OutputDataSet <- c'
DECLARE @SQLScript2 nvarchar(max)
SET @SQLScript2 = N'SELECT
                                          TableName
                                         ,RowCounts
                                         ,TimeMeasure
                                         ,UsedSpaceKB 
                                         ,UnusedSpaceKB
                                         FROM DataPack_Info_LARGE
                                         WHERE NofRowsOperation <> 0
                                         AND RowCounts <> 0'

EXECUTE sp_execute_external_script
        @language = N'R'
       ,@script = @RScript2
       ,@input_data_1 = @SQLScript2
       WITH result SETS ( (
                                          RowCounts VARCHAR(100)
                                         ,UsedSpaceKB  VARCHAR(100)
                                         )
                                   );
GO


SELECT
  TableName
 ,Operation
 ,NofRowsOperation
 ,UsedSpaceKB
 ,UnusedSpaceKB
FROM dbo.DataPack_Info_LARGE


--- prediction

-- GLM prediction
DECLARE @SQL_input AS NVARCHAR(MAX)
SET @SQL_input = N'SELECT
                                  TableName
                                  ,CASE WHEN Operation = ''Insert'' THEN 1 ELSE 0 END AS Operation
                                  ,NofRowsOperation
                                  ,UsedSpaceKB
                                  ,UnusedSpaceKB
                                   FROM dbo.DataPack_Info_LARGE
                                   WHERE
                                         NofRowsOperation <> 0';

DECLARE @R_code AS NVARCHAR(MAX)
SET @R_code = N'library(RevoScaleR)
                library(dplyr)
                DPLogR <- rxGlm(UsedSpaceKB ~ Operation + NofRowsOperation + UnusedSpaceKB, data = DataPack_info, family = Gamma)
                df_predict <- data.frame(TableName=("DataPack"), Operation=(1), NofRowsOperation=(451), UnusedSpaceKB=(20))
                predictions <- rxPredict(modelObject = DPLogR, data = df_predict, outData = NULL,  
                                predVarNames = "UsedSpaceKB", type = "response",checkFactorLevels=FALSE);
                OutputDataSet <- predictions'

EXEC sys.sp_execute_external_script
     @language = N'R'
    ,@script = @R_code
    ,@input_data_1 = @SQL_input
    ,@input_data_1_name = N'DataPack_info'
       WITH RESULT SETS ((
                         UsedSpaceKB_predict INT
                         ));
GO



CREATE PROCEDURE Predict_UsedSpace
(
 @TableName NVARCHAR(100)
,@Operation CHAR(1)  -- 1  = Insert; 0 = Delete
,@NofRowsOperation NVARCHAR(10)
,@UnusedSpaceKB NVARCHAR(10)
)
AS
DECLARE @SQL_input AS NVARCHAR(MAX)
SET @SQL_input = N'SELECT
                                  TableName
                                  ,CASE WHEN Operation = ''Insert'' THEN 1 ELSE 0 END AS Operation
                                  ,NofRowsOperation
                                  ,UsedSpaceKB
                                  ,UnusedSpaceKB
                                   FROM dbo.DataPack_Info_LARGE
                                   WHERE
                                         NofRowsOperation <> 0';
DECLARE @R_code AS NVARCHAR(MAX)
SET @R_code = N'library(RevoScaleR)
                DPLogR <- rxGlm(UsedSpaceKB ~ Operation + NofRowsOperation + UnusedSpaceKB, data = DataPack_info, family = Gamma)
                df_predict <- data.frame(TableName=("'+@TableName+'"), Operation=('+@Operation+'), 
                          NofRowsOperation=('+@NofRowsOperation+'), UnusedSpaceKB=('+@UnusedSpaceKB+'))
                predictions <- rxPredict(modelObject = DPLogR, data = df_predict, outData = NULL,  predVarNames = "UsedSpaceKB", type = "response",checkFactorLevels=FALSE);
                OutputDataSet <- predictions'

EXEC sys.sp_execute_external_script
     @language = N'R'
    ,@script = @R_code
    ,@input_data_1 = @SQL_input
    ,@input_data_1_name = N'DataPack_info'

WITH RESULT SETS ((
                                    UsedSpaceKB_predict INT
                                   ));
GO


EXECUTE Predict_UsedSpace
                     @TableName = 'DataPack'
                     ,@Operation = 1
                     ,@NofRowsOperation = 120
                     ,@UnusedSpaceKB = 2;
GO

EXECUTE Predict_UsedSpace
                     @TableName = 'DataPack'
                     ,@Operation = 1
                     ,@NofRowsOperation = 500
                     ,@UnusedSpaceKB = 12;
GO
