USE SQLR;
GO

/*

####~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
####  
####
####             CH 05
####
####
####~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

*/



-- function listing

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'require(RevoScaleR)
				OutputDataSet <- data.frame(ls("package:RevoScaleR"))'
WITH RESULT SETS
	(( Functions NVARCHAR(200) ))


-- importing SAS

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
	            library(RevoScaleR)
				#SampleSASFile <- file.path(("C:\\Users\\SI01017988\\Documents\\06-SQL\\6-Knjige\\02 - R\\CH05 - TK"), "sas_data.sas7bdat")
				SampleSASFile <- file.path(rxGetOption("sampleDataDir"), "sas_data.sas7bdat")
				#import into Dataframe
				OutputDataSet <- rxImport(SampleSASFile)
				'
WITH RESULT SETS
	((  
	 income  INT
	,gender  INT
	,[count] INT
	 ))


-- importing SPSS



EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
	            library(RevoScaleR)
				#SampleSPSSFile <- file.path(("C:\\Users\\SI01017988\\Documents\\06-SQL\\6-Knjige\\02 - R\\CH05 - TK"), "spss_data.sav")
				SampleSPSSFile <- file.path(rxGetOption("sampleDataDir"), "spss_data.sav")
				#import into Dataframe
				OutputDataSet <- rxImport(SampleSPSSFile)
				'
WITH RESULT SETS
	((  
	 income  INT
	,gender  INT
	,[count] INT
	 ))


-- importing data using ODBC

USE SQLR;
GO

EXECUTE AS USER = 'SICN-KASTRUN\MSSQLSERVER01'  
GO
-- YOUR CODE

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
	            library(RevoScaleR)
				sConnectStr <- "Driver={ODBC Driver 13 for SQL Server};Server=SICN-KASTRUN;Database=AdventureWorks;Trusted_Connection=Yes"
				#sConnectStr <- "Driver={sql2016};Server=SICN-KASTRUN;Database=AdventureWorks;Trusted_Connection=Yes"
				sQuery = "SELECT TOP 10 BusinessEntityID,[Name],SalesPersonID FROM [Sales].[Store] ORDER BY BusinessEntityID ASC"
				sDS <-RxOdbcData(sqlQuery=sQuery, connectionString=sConnectStr)
				OutputDataSet <- data.frame(rxImport(sDS))
				'
WITH RESULT SETS
	((  
	 BusinessEntityID  INT
	,[Name]  NVARCHAR(50)
	,SalesPersonID INT
	 ));


REVERT;
GO

-- check that the results are the same
USE AdventureWorks;
GO


SELECT 
TOP 10
 BusinessEntityID
,[Name]
,SalesPersonID
FROM [Sales].[Store]
ORDER BY BusinessEntityID ASC




--------------------------------------------------
--- VARIABLE CREATION and DATA TRANSFORMATION
--------------------------------------------------
USE AdventureWorks;
GO

/* rxDataStep 

equvivalent R code:
outfile <- file.path(rxGetOption("sampleDataDir"), "df_sql.xdf") 
rxDataStep(inData = df_sql, outFile = outfile, overwrite = TRUE)

*/

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			df_sql <- InputDataSet		
			df_sql4 <- data.frame(df_sql)
			outfile <- file.path(rxGetOption("sampleDataDir"), "df_sql4.xdf") 
			rxDataStep(inData = df_sql4, outFile = outfile, overwrite = TRUE)'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'


-- finding the working path
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			OutputDataSet <- data.frame(path = file.path(rxGetOption("sampleDataDir")))'			



-- extracting variable information
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet		
			var_info <- rxGetVarInfo(df_sql)
			OutputDataSet <- data.frame(unlist(var_info))'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'


--------------------
-- Variable creation
--------------------

-- Using rxGetVarInfo
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet		

			#var_info <- rxGetVarInfo(df_sql)
			OutputDataSet <- data.frame(unlist(var_info))'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'


-- Using rxGetInfo
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet		
			var_info <- rxGetInfo(df_sql)
			OutputDataSet <- data.frame(unlist(var_info))'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'


-- Using rxGetInfo 
-- with cleaner output
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet		
			get_Info <- rxGetInfo(df_sql)			
			Object_names <- c("Object Name", "Number of Rows", "Number of Variables")
			Object_values <- c(get_Info$objName, get_Info$numRows, get_Info$numVars)
			OutputDataSet <- data.frame(Object_names, Object_values)'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'
WITH RESULT SETS
	((  
	 ObjectName NVARCHAR(100)
	,ObjectValue NVARCHAR(MAX)
	 ));

--------------------
-- Variable recoding
--------------------

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			df_sql <- InputDataSet
			df_sql$BusinessEntityID_2 <- NA
			df_sql$BusinessEntityID_2[df_sql$BusinessEntityID<=1000] <- "Car Business"
			df_sql$BusinessEntityID_2[df_sql$BusinessEntityID>1000] <- "Food Business"
			OutputDataSet <- df_sql
			'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'
WITH RESULT SETS
	((  
	 BusinessEntityID INT
	,[Name] NVARCHAR(MAX)
	,SalesPersonID INT
	,TypeOfBusiness NVARCHAR(MAX)
	 ));


-- Using rx	DataStep	
-- for variable recoding and new variable creation
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			df_sql$BusinessEntityID_2 <- NA

			myXformFunc <- function(dataList) {
			  #dataList$BussEnt <- 100 * dataList$BusinessEntityID
			if (dataList$BusinessEntityID<=1000){dataList$BussEnt <- 1} else {dataList$BussEnt <- 2}
			return (dataList)
			}

			df_sql <- rxDataStep(inData = df_sql, transformFunc = myXformFunc)

			OutputDataSet <- df_sql
			'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'
WITH RESULT SETS
	((  
	 BusinessEntityID INT
	,[Name] NVARCHAR(MAX)
	,SalesPersonID INT
	,TypeOfBusiness NVARCHAR(MAX)
	 ));


-- Using rx	DataStep
-- for subsetting
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			df_sql_subset <- rxDataStep(inData = df_sql, varsToKeep = NULL, rowSelection = (BusinessEntityID<=1000))
			OutputDataSet <- df_sql_subset'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'
WITH RESULT SETS
	((  
	 BusinessEntityID INT
	,[Name] NVARCHAR(MAX)
	,SalesPersonID INT
	 ));

-- Data Merging
-- Using rxMerge

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			someExtraData <- data.frame(BusinessEntityID = 1:1200, department = rep(c("a", "b", "c", "d"), 25), Eff_score = rnorm(100))
			df_sql_merged <- rxMerge(inData1 = df_sql, inData2 = someExtraData, overwrite = TRUE, matchVars = "BusinessEntityID", type = "left",autoSort = TRUE)
			OutputDataSet <- df_sql_merged'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'
WITH RESULT SETS
	((  
	 BusinessEntityID INT
	,[Name] NVARCHAR(MAX)
	,SalesPersonID INT
	,Department CHAR(1)
	,Department_score FLOAT
	 ));


-- Data Merging
-- Using rxMerge
-- with changed order of dataframes, leaving the LEFT join.
-- this query will return different results as the same query above due to order of dataframes.

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			someExtraData <- data.frame(BusinessEntityID = 1:1200, department = rep(c("a", "b", "c", "d"), 25), Eff_score = rnorm(100))
			df_sql_merged <- rxMerge(inData1 = someExtraData , inData2 = df_sql , overwrite = TRUE, matchVars = "BusinessEntityID", type = "left",autoSort = TRUE)
			OutputDataSet <- df_sql_merged'
	,@input_data_1 = N'
			SELECT 
			 BusinessEntityID
			,[Name]
			,SalesPersonID
			FROM [Sales].[Store]'
WITH RESULT SETS
	((  
	 BusinessEntityID INT
	,[Name] NVARCHAR(MAX)
	,SalesPersonID INT
	,Department CHAR(1)
	,Department_score FLOAT
	 ));




--------------------------------------------------
--- FUNCTIONS AND  DESCRIPTIVE STATISTICS
--------------------------------------------------
USE AdventureWorks;
GO

-- descriptive statsitics
--We will be using following view
SELECT * FROM [Sales].[vPersonDemographics]

/*

-- View can be created with:

CREATE VIEW [Sales].[vPersonDemographics] 
AS 
SELECT 
    p.[BusinessEntityID] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        TotalPurchaseYTD[1]', 'money') AS [TotalPurchaseYTD] 
    ,CONVERT(datetime, REPLACE([IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        DateFirstPurchase[1]', 'nvarchar(20)') ,'Z', ''), 101) AS [DateFirstPurchase] 
    ,CONVERT(datetime, REPLACE([IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        BirthDate[1]', 'nvarchar(20)') ,'Z', ''), 101) AS [BirthDate] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        MaritalStatus[1]', 'nvarchar(1)') AS [MaritalStatus] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        YearlyIncome[1]', 'nvarchar(30)') AS [YearlyIncome] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        Gender[1]', 'nvarchar(1)') AS [Gender] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        TotalChildren[1]', 'integer') AS [TotalChildren] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        NumberChildrenAtHome[1]', 'integer') AS [NumberChildrenAtHome] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        Education[1]', 'nvarchar(30)') AS [Education] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        Occupation[1]', 'nvarchar(30)') AS [Occupation] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        HomeOwnerFlag[1]', 'bit') AS [HomeOwnerFlag] 
    ,[IndividualSurvey].[ref].[value](N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
        NumberCarsOwned[1]', 'integer') AS [NumberCarsOwned] 
FROM [Person].[Person] p 
CROSS APPLY p.[Demographics].nodes(N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey"; 
    /IndividualSurvey') AS [IndividualSurvey](ref) 
WHERE [Demographics] IS NOT NULL;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Displays the content from each element in the xml column Demographics for each customer in the Person.Person table.' , @level0type=N'SCHEMA',@level0name=N'Sales', @level1type=N'VIEW',@level1name=N'vPersonDemographics'
GO



*/
SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL


--rxSummary
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			summary <- rxSummary(~ TotalChildren,  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max","Sum","ValidObs", "MissingObs"))
			OutputDataSet <- summary$sDataFrame
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
	  VariableName NVARCHAR(MAX)
	 ,"Mean" NVARCHAR(100)
	 ,"StdDev" NVARCHAR(100)
	 ,"Min" NVARCHAR(100)
	 ,"Max" NVARCHAR(100)
	 ,"Sum" NVARCHAR(100)
	 ,"ValidObs" NVARCHAR(100)
	 ,"MissingObs" NVARCHAR(100)
	 ));



-- rxSummary for all variables
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			summary <- rxSummary(~.,  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max","Sum","ValidObs", "MissingObs"))
			OutputDataSet <- summary$sDataFrame
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
	  VariableName NVARCHAR(MAX)
	 ,"Mean" FLOAT
	 ,"StdDev" FLOAT
	 ,"Min" FLOAT
	 ,"Max" FLOAT
	 ,"Sum" FLOAT
	 ,"ValidObs" INT
	 ,"MissingObs" INT
	 ));

-- treating categorical values
-- will leave an empty data frame
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			
			df_sql_r <- rxFactors(inData = df_sql, sortLevels = TRUE,
                        factorInfo = list(MS = list(levels = c("M","S"), otherLevel=NULL, varName="MaritalStatus")
                                          )
                        )
			summary <- rxSummary(~MS,  df_sql_r, summaryStats = c( "Mean", "StdDev", "Min", "Max","Sum","ValidObs", "MissingObs"))
			OutputDataSet <- summary$sDataFrame
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
	  VariableName NVARCHAR(MAX)
	 ,"Mean" FLOAT	
	 ,"StdDev" FLOAT
	 ,"Min" FLOAT
	 ,"Max" FLOAT
	 ,"Sum" FLOAT
	 ,"ValidObs" INT
	 ,"MissingObs" INT
	 ));


-- treating categorical values
-- will leave an empty data frame
-- we need to use LIST categorical 
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			df_sql_r <- rxFactors(inData = df_sql, sortLevels = TRUE,
                        factorInfo = list(MS = list(levels = c("M","S"), otherLevel=NULL, varName="MaritalStatus")
                                          )
                        )
			summary <- rxSummary(~ MS,  df_sql_r)
			OutputDataSet <- data.frame(summary$categorical)
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
	  MS NVARCHAR(MAX)
	 ,"counts" INT
	 ));


-- combining numeric variables
-- for rxSummary
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			summary <- rxSummary(NumberCarsOwned ~ TotalChildren,  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"))
			OutputDataSet <- summary$sDataFrame
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
	  VariableName NVARCHAR(MAX)
	 ,"Mean" FLOAT
	 ,"StdDev" FLOAT
	 ,"Min" FLOAT
	 ,"Max" FLOAT
	 ,"Sum" FLOAT
	 ,"ValidObs" INT
	 ,"MissingObs" INT
	 ));


-- combining numeric variables and factor variables
-- for rxSummary
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			df_sql_r <- rxFactors(inData = df_sql, sortLevels = TRUE,factorInfo = list(MS = list(levels = c("M","S"), otherLevel=NULL, varName="MaritalStatus")))
			summary <- rxSummary(~F(MS):TotalChildren, df_sql_r, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"), categorical=c("MS"))
			OutputDataSet <- data.frame(summary$categorical)'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
	  Category NVARCHAR(MAX)
	 ,"MS" NVARCHAR(MAX)
	 ,"Means" FLOAT
	 ,"StDev" FLOAT
	 ,"Min" INT
	 ,"Max" INT
	 ,"Sum" INT
	 ,"ValidObs" INT
	 ));



-- rxMarginals

-- rxQuantile
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			quan <- rxQuantile(data = df_sql, varName = "TotalChildren")
			quan <- data.frame(quan)
			values <- c("0%","25%","50%","75%","100%")
			OutputDataSet <- data.frame(values,quan)
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
		Quartile NVARCHAR(100)
		,QValue FLOAT
	 ));


-- calculting deciles using rxQuantile
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			dec <- rxQuantile(data = df_sql, varName = "TotalChildren",  probs = seq(from = 0, to = 1, by = .1))
			dec <- data.frame(dec)
			values <- c("0%","10%","20%","30%","40%","50%","60%","70%","80%","90%","100%")
			OutputDataSet <- data.frame(values,dec)
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
		 Decile NVARCHAR(100)
		,DValue FLOAT
	 ));

-- rxCrossTabs
-- rxMarginals


EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			crosstab <- rxCrossTabs(N(NumberCarsOwned) ~ F(TotalChildren),  df_sql, means=FALSE) #means=TRUE
			children <- c(0,1,2,3,4,5)
			OutputDataSet <- data.frame(crosstab$sums, children)
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
		 NumberOfCarsOwnedSUM INT
		,NumberOfChildren INT
	 ));


/*
Visualizing this dataset using only R code:
library(RColorBrewer)
barplot(OutputDataSet$V1, xlab = "Number of children",ylab = "Number of cars owned", beside=FALSE,
        legend.text = c("0 Child","1 Child","2 Child","3 Child","4 Child","5 Child"), col=brewer.pal(6, "Paired"))
  

*/

-- crosstabulation using factors

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			crosstab <- rxCrossTabs(NumberCarsOwned ~ MaritalStatus,  df_sql, means=TRUE)
			status <- c("M","S")
			OutputDataSet <- data.frame(crosstab$sums, status)
			'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
		 NumberOfCarsOwnedSUM INT
		,MaritalStatus NVARCHAR(100)
	 ));


-- rxMarginals

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			df_sql <- InputDataSet
			mar <- rxMarginals(rxCrossTabs(NumberCarsOwned ~ F(TotalChildren), data=df_sql, margin=TRUE, mean=FALSE))
			OutputDataSet  <- data.frame(mar$NumberCarsOwned$grand)'
	,@input_data_1 = N'
			SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
		GrandTotal INT
	 ));

---- with graphs

-- rxHistogram

-- rxLinePlot


--- STATISTICAL TESTS

-- Chi-square

EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
		library(RevoScaleR)
		df_sql <- InputDataSet
		df_sql_r <- rxFactors(inData = df_sql, factorInfo = list(MS = list(levels = c("M","S"), otherLevel=NULL, varName="MaritalStatus")))
		df_sql_r$Occupation <- as.factor(df_sql_r$Occupation)
		df_sql_r$MS <- df_sql_r$MS
		testData <- data.frame(Occupation = df_sql_r$Occupation, Status=df_sql_r$MS)
		d <- rxCrossTabs(~Occupation:Status,  testData, returnXtabs = TRUE)
		chi_q <- rxChiSquaredTest(d)

		#results
		xs <- chi_q$''X-squared''
		p <- chi_q$''p-value''
		OutputDataSet <- data.frame(xs,p)'
	,@input_data_1 = N'
	SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
		 Chi_square_value NVARCHAR(100)
		,Stat_significance NVARCHAR(100)
	 ));


-- Kendall
EXEC sp_execute_external_script
	 @language = N'R'
	,@script = N'
		library(RevoScaleR)
		df_sql <- InputDataSet
		df_sql_r <- rxFactors(inData = df_sql, factorInfo = list(MS = list(levels = c("M","S"), otherLevel=NULL, varName="MaritalStatus")))
		df_sql_r$Occupation <- as.factor(df_sql_r$Occupation)
		df_sql_r$MS <- df_sql_r$MS
		testData <- data.frame(Occupation = df_sql_r$Occupation, Status=df_sql_r$MS)
		d <- rxCrossTabs(~Occupation:Status,  testData, returnXtabs = TRUE)
		ken <- rxKendallCor(d, type = "b")

		k<- ken$`estimate 1`
		p<- ken$`p-value`

		#results
		OutputDataSet <- data.frame(k,p)'
	,@input_data_1 = N'
	SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL'
WITH RESULT SETS
	((  
		 Kendall_value NVARCHAR(100)
		,Stat_significance NVARCHAR(100)
	 ));


