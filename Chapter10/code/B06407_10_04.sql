--
-- Test rxLinMod Performance on Memory-Optimized Table with Primary Key
--

-- Change database to prep for Memory-Optimized
ALTER DATABASE PerfTuning 
	ADD FILEGROUP PerfTuningMOD CONTAINS MEMORY_OPTIMIZED_DATA;

ALTER DATABASE PerfTuning 
	ADD FILE (NAME='PerfTuningMOD', 
	FILENAME='C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\PerfTuningMOD.ndf') 
	TO FILEGROUP PerfTuningMOD;

ALTER DATABASE PerfTuning 
	SET MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT=ON  
GO  

-- Create Memory-Optimized table. 
CREATE TABLE [dbo].[AirFlights_MOD] 
(  
	 [ID]	INT IDENTITY(1,1) NOT NULL PRIMARY KEY NONCLUSTERED
	,[ArrDelay]	SMALLINT
	,[CRSDepTime]	DECIMAL(6,4)
	,[DayOfWeek]	NVARCHAR(10) 
) WITH (MEMORY_OPTIMIZED=ON, DURABILITY = SCHEMA_AND_DATA);

GO

-- Insert the data into Memory-Optimized table
INSERT INTO [dbo].[AirFlights_MOD]
(
	 [ArrDelay]		
	,[CRSDepTime]	
	,[DayOfWeek]	
)
SELECT 
	 [ArrDelay]		
	,[CRSDepTime]	
	,[DayOfWeek]	
FROM [dbo].[AirFlights] 
GO

-- Test Preformance against Memory Optimized Table
EXEC dbo.usp_TestPerformance '[dbo].[AirFlights_MOD]'
