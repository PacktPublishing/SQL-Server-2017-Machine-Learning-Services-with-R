--
-- Test rxLinMod Performance on Table with Clustered ColumnStore Index
--

-- Create a simple AirFlights table 
CREATE TABLE AirFlights_CS
(
	 [ID]			INT NOT NULL IDENTITY(1,1)
	,[ArrDelay]		SMALLINT
	,[CRSDepTime]	DECIMAL(6,4)
	,[DayOfWeek]	NVARCHAR(10) 
);
GO

-- Insert the data into the columnstore table.
INSERT INTO [dbo].[AirFlights_CS]
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

-- Create  Clustered ColumnStore Index to the new table.
CREATE CLUSTERED COLUMNSTORE INDEX CCI_Airflights_CS ON [dbo].[AirFlights_CS] 
GO

-- Test Preformance against Memory Optimized Table
EXEC dbo.usp_TestPerformance '[dbo].[AirFlights_CS]'
GO