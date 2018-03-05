CREATE PROCEDURE dbo.usp_AnalyzeOrdersUsingAnova
(
	@StartDate DATE = '20150101',
	@EndDate DATE = '20151231'
)
/**********************************************************
 * Purpose: Determine if Monthly Orders (Total Amount in $) 
 *			has no dependency on Sales Person.
 * Parameters:	
 *	@StartDate	- The start date of the Orders table
 *	@EndDate	- The end date of Orders table
 * Example on how to execute:
 *	EXEC dbo.usp_AnalyzeOrdersUsingAnova
 *		 @StartDate = '20150101'
 *		,@EndDate = '20151231'
 *****************************************************************/
AS
BEGIN 
	
	DECLARE @input_query NVARCHAR(MAX); 
	DECLARE @RAOV NVARCHAR(MAX);

	-- The SQL query representing Input data set.
	-- Get the monthly orders from each Sales between 
	-- specific date and time.
	SET @input_query = N'
	SELECT
		DATEFROMPARTS(YEAR(o.[OrderDate]), 
		   MONTH(o.[OrderDate]), 1) AS OrderMonth,
		sp.[PreferredName] AS SalesPerson,
		COUNT(DISTINCT o.[OrderID]) AS OrderCount,
		SUM(ol.[Quantity] * ol.[UnitPrice]) AS TotalAmount
	FROM[Sales] .[Orders] o
		INNER JOIN[Sales] .[OrderLines] ol
			ON ol.[OrderID] = o.[OrderID]
		INNER JOIN[Application] .[People] sp
			ON sp.[PersonID] = o.[SalespersonPersonID]
	WHERE sp.[ValidTo] >= GETDATE()
		AND o.[OrderDate] BETWEEN ''' + 
CAST(@StartDate AS VARCHAR(30)) + ''' AND ''' +
CAST(@EndDate AS VARCHAR(30)) + '''
	GROUP BY
		DATEFROMPARTS(YEAR(o.[OrderDate]), 
MONTH(o.[OrderDate]), 1),
		sp.[PreferredName];'

	-- The R code that tests if Total Amount has no strong 
	-- dependency to Sales Person
	-- Note: Null Hypothesis (H0) in this case is Total Amount 
	--		has no strong dependency to Sales Person.
	--		The closer p-value to 0 we can reject the H0.
	SET @RAOV = N'a = aov(TotalAmount ~ SalesPerson, 
	data = InputDataSet);
		m <- summary(a);
		library(plyr);
		x <- data.frame(RowID = 1:nrow(m[[1]]), 
			Attribute = rownames(m[[1]]));
		OutputDataSet <- cbind(x, ldply(m, data.frame));'

	-- Using R Services produce the output as a table
	EXEC sp_execute_external_script @language = N'R'
		,@script = @RAOV 
		,@input_data_1 = @input_query
		,@input_data_1_name = N'InputDataSet'
		,@output_data_1_name = N'OutputDataSet' 
		WITH RESULT SETS (([RowID]	INT,
					[Attribute]	NVARCHAR(50), 
					[DF]		NUMERIC(20,10),
					[SumSq]	NUMERIC(20,10),
					[MeanSq]	NUMERIC(20,10),
					[FValue]	FLOAT,
					[Pr(>F)]	FLOAT
					));

END
