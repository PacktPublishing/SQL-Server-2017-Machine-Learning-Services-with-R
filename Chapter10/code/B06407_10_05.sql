--
-- Test rxLinMod Performance on Memory-Optimized Table with Clustered Columnstore index
-- 

-- Create Memory Optimized table 
CREATE TABLE [dbo].[AirFlights_MODCS] 
(  
	 [ID]	INT IDENTITY(1,1) NOT NULL PRIMARY KEY NONCLUSTERED
	,[ArrDelay]	SMALLINT
	,[CRSDepTime] DECIMAL(6,4)
	,[DayOfWeek]	VARCHAR(10) 
) WITH (MEMORY_OPTIMIZED=ON, DURABILITY = SCHEMA_AND_DATA);
GO

-- Insert AirFlights data into the table.
INSERT INTO [dbo].[AirFlights_MODCS]
(
	 [ArrDelay]		
	,[CRSDepTime]	
	,[DayOfWeek]	
)
SELECT 
	 [ArrDelay]		
	,[CRSDepTime]	
	,[DayOfWeek]	
FROM [dbo].[AirFlights];
GO

-- Create ColumnStore index to the table.
ALTER TABLE [dbo].[AirFlights_MODCS]
ADD INDEX CCI_Airflights_MODCS CLUSTERED COLUMNSTORE
GO

-- Test Preformance against Memory Optimized Table with Clustered ColumnStore Index
EXEC dbo.usp_TestPerformance '[dbo].[AirFlights_MODCS]'
GO