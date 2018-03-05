/*
Chapter 03 - Code #2
Tomaž Kaštrun
*/
--SICN-KASTRUN

USE [SQLR];
GO

-- SECURITY


USE [master]
GO
CREATE LOGIN [RR1] WITH PASSWORD=N'Read!2$16', DEFAULT_DATABASE=[SQLR], CHECK_EXPIRATION=ON, CHECK_POLICY=ON
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [RR1]
GO
USE [SQLR]
GO
CREATE USER [RR1] FOR LOGIN [RR1]
GO
USE [SQLR]
GO
ALTER USER [RR1] WITH DEFAULT_SCHEMA=[dbo]
GO
USE [SQLR]
GO
ALTER ROLE [db_datareader] ADD MEMBER [RR1]
GO



EXECUTE AS USER = 'RR1';  
GO

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'OutputDataSet <- InputDataSet'
	,@input_data_1 = N'SELECT 1 AS Numb UNION ALL SELECT 2;'
WITH RESULT SETS
((
    Res INT
))


REVERT;
GO


GRANT EXECUTE ANY EXTERNAL SCRIPT TO [RR1];
GO



--EXEC sp_addrolemember 'db_datareader', RR1;
--GO




--- Post Installation process

EXEC sp_configure  'external scripts enabled';
GO


---- External script

EXEC sys.sp_execute_external_script  
	 @language =N'R'
	,@script=N'OutputDataSet<-InputDataSet'
	,@input_data_1 =N'select 1 as hello'
WITH RESULT SETS ((
			[hello] int not null
				));

GO




SELECT * FROM sys.dm_external_script_requests 

SELECT * FROM sys.dm_external_script_execution_stats



----------------------------
--- Resource Governon
----------------------------

USE RevoTestDB;
GO

--- restore RevoTestDB

-- Before enabling Resource Governor

-- TEST 1 - performance normal; no resource governor
EXECUTE  sp_execute_external_script
                 @language = N'R'
                ,@script = N'
            library(RevoScaleR)
            f <- formula(as.numeric(ArrDelay) ~ as.numeric(DayOfWeek) + CRSDepTime)
            s <- system.time(mod <- rxLinMod(formula = f, data = AirLine))
            OutputDataSet <-  data.frame(system_time = s[3]);'
                ,@input_data_1 = N'SELECT * FROM AirlineDemoSmall'
                ,@input_data_1_name = N'AirLine'
-- WITH RESULT SETS UNDEFINED
WITH RESULT SETS 
            ((
                 Elapsed_time FLOAT
            ));

			 
/*
-- Running Time: 00:00:21
-- elapsed time: 1,43

(1 row(s) affected)
STDOUT message(s) from external script: 
Rows Read: 600000, Total Rows Processed: 600000, Total Chunk Time: 0.055 seconds 
Computation time: 0.113 seconds.

*/


-- Enable Resource Governor
ALTER RESOURCE GOVERNOR RECONFIGURE;  
GO



-- Default value
ALTER EXTERNAL RESOURCE POOL [default] 
WITH (AFFINITY CPU = AUTO)
GO

CREATE EXTERNAL RESOURCE POOL RService_Resource_Pool  
WITH (  
     MAX_CPU_PERCENT = 10  
    ,MAX_MEMORY_PERCENT = 5
);  

ALTER RESOURCE POOL [default] WITH (max_memory_percent = 60, max_cpu_percent=90);  
ALTER EXTERNAL RESOURCE POOL [default] WITH (max_memory_percent = 40, max_cpu_percent=10);  
ALTER RESOURCE GOVERNOR reconfigure;

ALTER RESOURCE GOVERNOR RECONFIGURE;  
GO




-- CREATING CLASSIFICATION FUNCTION
CREATE WORKLOAD GROUP R_workgroup WITH (importance = medium) USING "default", 
EXTERNAL "RService_Resource_Pool";  

ALTER RESOURCE GOVERNOR WITH (classifier_function = NULL);  
ALTER RESOURCE GOVERNOR reconfigure;  

USE master  
GO  
CREATE FUNCTION RG_Class_function()  
RETURNS sysname  
WITH schemabinding  
AS  
BEGIN  
    IF program_name() in ('Microsoft R Host', 'RStudio') RETURN 'R_workgroup';  
    RETURN 'default'  
    END;  
GO  

ALTER RESOURCE GOVERNOR WITH  (classifier_function = dbo.RG_Class_function);  
ALTER RESOURCE GOVERNOR reconfigure;  
GO

USE RevoTestDB;
GO

-- TEST 2 - performance normal; with governor
EXECUTE  sp_execute_external_script
                 @language = N'R'
                ,@script = N'
            library(RevoScaleR)
            f <- formula(as.numeric(ArrDelay) ~ as.numeric(DayOfWeek) + CRSDepTime)
            s <- system.time(mod <- rxLinMod(formula = f, data = AirLine))
            OutputDataSet <-  data.frame(system_time = s[3]);'
                ,@input_data_1 = N'SELECT * FROM AirlineDemoSmall'
                ,@input_data_1_name = N'AirLine'
-- WITH RESULT SETS UNDEFINED
WITH RESULT SETS 
            ((
                 Elapsed_time FLOAT
            ));

/*
-- Running Time: 00:00:03 
-- elapsed time: 0,63

(1 row(s) affected)
STDOUT message(s) from external script: 
Rows Read: 600000, Total Rows Processed: 600000, Total Chunk Time: 0.051 seconds 
Computation time: 0.057 seconds.


*/



--- instaslling packages

USE WideWorldImporters;
GO


----------------------
-- GENERAL INFORMATION
----------------------


-- Where do you find libraries on your server
EXECUTE sp_execute_external_script
       @language = N'R'
, @script = N'OutputDataSet <- data.frame(.libPaths());'
WITH RESULT SETS ((
       [DefaultLibraryName] VARCHAR(MAX) NOT NULL));
GO



-- You can create a table for libraries and populate all the necessary information
CREATE TABLE dbo.Libraries
	(
		 ID INT IDENTITY NOT NULL CONSTRAINT PK_RLibraries PRIMARY KEY CLUSTERED
		,Package NVARCHAR(50)
		,LibPath NVARCHAR(200)
		,[Version] NVARCHAR(20)
		,Depends NVARCHAR(200)
		,Imports NVARCHAR(200)
		,Suggests NVARCHAR(200)
		,Built NVARCHAR(20)
	)


INSERT INTO dbo.Libraries
EXECUTE sp_execute_external_script    
		@language = N'R'    
	   ,@script=N'x <- data.frame(installed.packages())
	   x2 <- x[,c(1:3,5,6,8,16)]
	   OutputDataSet<- x2'


SELECT * FROM Libraries
DROP TABLE dbo.Libraries



--  Simple execution 
-- is modified so we run a function that is available in a special library (and not in BASE set of packages)

EXECUTE sp_execute_external_script
	 @language = N'R'
	,@script = N'   library(Hmisc)
				    #Calculating correlations between two variables
					#df <- data.frame(value_of_correlation = cor(Customers_by_invoices$InvoiceV, Customers_by_invoices$CustCat, use="complete.obs", method="spearman"))
					u <- unlist(rcorr(Customers_by_invoices$InvoiceV, Customers_by_invoices$CustCat, type="spearman"))
				    statistical_significance <-as.character(u[10])
					OutputDataSet <- data.frame(statistical_significance)'
	,@input_data_1 = N'SELECT 
						 SUM(il.Quantity) AS InvoiceQ
						,SUM(il.ExtendedPrice) AS InvoiceV
						,c.CustomerID AS Customer
						,c.CustomerCategoryID AS CustCat
						

						FROM sales.InvoiceLines AS il
						INNER JOIN sales.Invoices AS i
						ON il.InvoiceID = i.InvoiceID
						INNER JOIN sales.Customers AS c
						ON c.CustomerID = i.CustomerID

						GROUP BY
							 c.CustomerID
							,c.CustomerCategoryID'

	,@input_data_1_name = N'Customers_by_invoices'
WITH RESULT SETS ((
					statistical_significance FLOAT(20)
					));
GO



--------------------------------
-- Installing missing libraries
--------------------------------


--InstallPackage using sp_execute_external_script
-- and showing it does not work
EXECUTE sp_execute_external_script    
       @language = N'R'    
      ,@script=N'install.packages("AUC")'


----------------------------------
-- Using R tools for Visual Studio
----------------------------------

-- #do not run this in SSMS
install.packages("AUC")

-- #problems with admi access
-- #library folder path can be different (!)
install.packages("AUC", lib = "C:/Program Files/Microsoft SQL Server/MSSQL13.MSSQLSERVER/R_SERVICES/library")


---------------------
-- Using XP_CMDSHELL
---------------------

-- enable xp_cmdshell
EXECUTE SP_CONFIGURE 'xp_cmdshell','1';
GO

RECONFIGURE;
GO 

EXEC xp_cmdshell '"C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\R_SERVICES\bin\R.EXE" cmd -e install.packages(''AUC'')';  
GO