--
-- Test rxLinMod Performance on Table with Primary Key
--

-- Create procedure to insert data from XDF to SQL.
CREATE PROCEDURE [dbo].[usp_ImportXDFtoSQL]
AS
	DECLARE @RScript NVARCHAR(MAX)
	SET @RScript = N'library(RevoScaleR)
		rxOptions(sampleDataDir = "C:/Program Files/Microsoft SQL Server/140/R_SERVER/library/RevoScaleR/SampleData");
		outFile <-  file.path(rxGetOption("sampleDataDir"), "AirOnTime2012.xdf");
		OutputDataSet <- data.frame(rxReadXdf(file=outFile, varsToKeep=c("ArrDelay", "CRSDepTime","DayOfWeek")))'

	EXECUTE sp_execute_external_script
		 @language = N'R'
		,@script = @RScript
		WITH RESULT SETS ((
			[ArrDelay]		SMALLINT,
			[CRSDepTime]	DECIMAL(6,4),
			[DayOfWeek]		NVARCHAR(10)));
GO

-- Create a simple AirFlights table with Primary Key.
CREATE TABLE [dbo].[AirFlights]
(
	 [ID]			INT NOT NULL IDENTITY(1,1) 
	,[ArrDelay]		SMALLINT
	,[CRSDepTime]	DECIMAL(6,4)
	,[DayOfWeek]	NVARCHAR(10) 
	,CONSTRAINT PK_AirFlights PRIMARY KEY ([ID])
);
GO

-- Insert data from XDF to SQL.
INSERT INTO [dbo].[AirFlights]
EXECUTE [dbo].[usp_ImportXDFtoSQL]
GO

-- Create procedure do performance testing on a given table. 
CREATE PROCEDURE dbo.usp_TestPerformance (@TableName VARCHAR(50))
AS
	DECLARE @RScript NVARCHAR(MAX)
	SET @RScript = N'library(RevoScaleR)
					LMResults <- rxLinMod(ArrDelay ~ DayOfWeek, data = InputDataSet)
					OutputDataSet <- data.frame(LMResults$coefficients)'

	DECLARE @SQLScript nvarchar(max)
	SET @SQLScript = N'SELECT ArrDelay, DayOfWeek FROM ' + @TableName 
	SET STATISTICS TIME ON;
	EXECUTE sp_execute_external_script
		 @language = N'R'
		,@script = @RScript
		,@input_data_1 = @SQLScript
	WITH RESULT SETS ((
				Coefficient DECIMAL(10,5)
				));

	SET STATISTICS TIME OFF;
GO

-- Test Preformance against a simple AirFlights table with Primary Key
EXEC dbo.usp_TestPerformance '[dbo].[AirFlights]'
GO
