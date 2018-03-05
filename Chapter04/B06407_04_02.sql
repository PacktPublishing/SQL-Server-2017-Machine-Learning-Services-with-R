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

-- Part 2: Prepare the R-script that will summarize the dataset.
DECLARE @RScript NVARCHAR(MAX)
SET @RScript = N'OutputDataSet <- as.data.frame(t(sapply(InputDataSet[, c("OrderCount", "TotalAmount")], summary)));
OutputDataSet <- cbind(Column = row.names(OutputDataSet), OutputDataSet);'

-- Part 3: Execute R in TSQL to get the monthly sales person's 
-- order count and total amount.
EXECUTE sp_execute_external_script
     @language = N'R'
    ,@script = @RScript
    ,@input_data_1 = @SQLScript
WITH RESULT SETS ((
            [Columns] NVARCHAR(30), [Min] FLOAT,
            [Q1] FLOAT, [Median] FLOAT,
            [Mean] FLOAT,  [Q3] FLOAT,
            [Max] FLOAT));
GO

