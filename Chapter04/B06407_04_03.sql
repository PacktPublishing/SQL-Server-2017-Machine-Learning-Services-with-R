USE WideWorldImporters
GO

-- Part 1: Get Monthly Order count and Order amount 
-- per Sales Person in Year 2015.
DECLARE @SQLScript NVARCHAR(MAX)
SET @SQLScript = N'SELECT DATEFROMPARTS(YEAR(o.[OrderDate]), 
MONTH(o.[OrderDate]), 1) AS OrderMonth,
    sp.[PreferredName] AS SalesPerson,
    COUNT(DISTINCT o.[OrderID]) AS OrderCount,
    SUM(ol.[Quantity] * ol.[UnitPrice]) AS TotalAmount
FROM [Sales].[Orders] o
    INNER JOIN [Sales].[OrderLines] ol
        ON ol.[OrderID] = o.[OrderID]
    INNER JOIN [Application].[People] sp
        ON sp.[PersonID] = o.[SalespersonPersonID]
WHERE sp.[ValidTo] >= GETDATE()
    AND YEAR(o.[OrderDate]) = 2015
GROUP BY
DATEFROMPARTS(YEAR(o.[OrderDate]), 
MONTH(o.[OrderDate]), 1),
    sp.[PreferredName];'
	
-- Part 2: Prepare the R-script that will produce the visualization.
DECLARE @RScript NVARCHAR(MAX)
SET @RScript = N'library(ggplot2); 
    image_file = tempfile(); 
    jpeg(filename = image_file, width=1000, height=400); 
    d <- InputDataSet[InputDataSet$SalesPerson %in% c("Amy", "Jack", "Hudson"), ];
    print(qplot(x = TotalAmount, y = OrderCount, data = d, color = SalesPerson, main = "Monthly Orders"));
    dev.off()
    OutputDataSet <- data.frame(
            data=readBin(file(image_file,"rb"),
            what=raw(),n=1e6));'

-- Part 3: Execute R in TSQL to get the binary representation of the image.
EXECUTE sp_execute_external_script
     @language = N'R'
    ,@script = @RScript
    ,@input_data_1 = @SQLScript
WITH RESULT SETS ((plot VARBINARY(MAX)));
