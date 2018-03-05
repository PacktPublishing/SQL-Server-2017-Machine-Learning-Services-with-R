CREATE PROCEDURE dbo.usp_CreateMonthlySalesPlot
(
	@StartDate DATE = '20150101',
	@EndDate DATE = '20151231'
)
/**********************************************************
 * Purpose: Determine if Monthly Orders (Total Amount in $) 
 *			has no dependency on Sales Person.
 * Parameter:	
 *	@StartDate	- Observation start date in the Orders table
 *	@EndDate	- Observation end date in the Orders table
 * Example on how to execute:
 *	EXEC dbo.usp_AnalyzeOrdersUsingAnova
 *		 @StartDate = '20150101'
 *		,@EndDate = '20151231'
 **********************************************************/
AS
BEGIN 
	
	DECLARE @input_query NVARCHAR(MAX); 
	DECLARE @RPlot NVARCHAR(MAX);

	-- The SQL query representing Input data set.
	-- Get the monthly orders from each Sales between 
		specfic date and time.
	SET @input_query = N'
	SELECT
		DATEFROMPARTS(YEAR(o.[OrderDate]), 
MONTH(o.[OrderDate]), 1) AS OrderMonth,
		sp.[PreferredName] AS SalesPerson,
		COUNT(DISTINCT o.[OrderID]) AS OrderCount,
		SUM(ol.[Quantity] * ol.[UnitPrice]) AS TotalAmount
	FROM [Sales] .[Orders] o
		INNER JOIN [Sales] .[OrderLines] ol
			ON ol.[OrderID] = o.[OrderID]
		INNER JOIN [Application] .[People] sp
			ON sp.[PersonID] = o.[SalespersonPersonID]
	WHERE sp.[ValidTo] >= GETDATE()
		AND o.[OrderDate] BETWEEN ''' + 
CAST(@StartDate AS VARCHAR(30)) + 
''' AND ''' + 
CAST(@EndDate AS VARCHAR(30)) + '''
	GROUP BY
		DATEFROMPARTS(YEAR(o.[OrderDate]), MONTH(o.[OrderDate]), 1),
		sp.[PreferredName];'

	
	-- The R code that produces the plot.
	SET @RPlot = N'library(ggplot2); 
	image_file = tempfile(); 
	jpeg(filename = image_file, width=600, height=800); 
	a <- qplot(y = TotalAmount, x = OrderMonth, 
        data = InputDataSet,
        color = SalesPerson, 
        facets = ~SalesPerson,
        main = "Monthly Orders");
	a + scale_x_date(date_labels = "%b");		
	plot(a);
	dev.off(); 
	OutputDataSet <-  data.frame(
data=readBin(file(image_file,"rb"),
what=raw(),n=1e6));	
'
	EXEC sp_execute_external_script @language = N'R'
		,@script = @RPlot 
		,@input_data_1 = @input_query
		,@input_data_1_name = N'InputDataSet'
		,@output_data_1_name = N'OutputDataSet' 
		WITH RESULT SETS (( [plot] VARBINARY(MAX)));

END
