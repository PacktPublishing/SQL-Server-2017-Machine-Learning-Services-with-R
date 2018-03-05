library(RODBC);

connStr <- "Driver=SQL Server;Server=MsSQLGirl;
Database=WideWorldImporters;trusted_connection=true";
dbHandle <- odbcDriverConnect(connStr);

# Define the query to be run
order_query = 
  "SELECT DATEFROMPARTS(YEAR(o.[OrderDate]), 
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
    AND o.[OrderDate] BETWEEN '20150101' AND '20151231'
GROUP BY
DATEFROMPARTS(YEAR(o.[OrderDate]), 
MONTH(o.[OrderDate]), 1),
    sp.[PreferredName];"

# Get the data set from SQL into the orders variable in R
orders <- sqlQuery(dbHandle, order_query);

orders;
