USE master
GO

EXEC sp_configure 'show advanced option', '1';  
RECONFIGURE; 
GO
EXEC sp_configure 'hadoop connectivity', 7; 
GO 
RECONFIGURE; 
GO

-- 1.	Create Master Key in your database where you’d like to create an external table connecting to the csv files in Azure Blob Storage. 
USE [AdventureWorks2016]
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD='MsSQLGirlLovesSQLServer2016&2017:)';
GO

-- 2.	Create Database Scoped Credential. 
CREATE DATABASE SCOPED CREDENTIAL MsSQLGirlAtAzureBlobStorage  
WITH IDENTITY = 'credential', Secret = 'Es3duvq+x9G5x+EFbuUmGo0salEi6Jsd59NI20KXespbiBG9RswLA4L1fuqs/59porPBay64YkRj/tvQ7XAMLA==';
GO

-- 3.	Create the external data source pointing to a container in the Azure Blob Storage. In this instance, open-data-sample is the name of the container, and mssqlgirl.blob.core.windows.net is the Azure Blob Storage location. 
CREATE EXTERNAL DATA SOURCE OpenDataSample
WITH (
    TYPE = HADOOP,
    LOCATION = 'wasbs://open-data-sample@mssqlgirl.blob.core.windows.net/',
    CREDENTIAL = MsSQLGirlAtAzureBlobStorage
);

-- 4.	Create the file format of the source files in the container. 
CREATE EXTERNAL FILE FORMAT csvformat 
WITH ( 
    FORMAT_TYPE = DELIMITEDTEXT, 
    FORMAT_OPTIONS ( 
        FIELD_TERMINATOR = ','
    ) 
);
GO

-- 5.	Create the following of the source files in the container. 
CREATE EXTERNAL TABLE EMSIncident
( 
	[Month Key]					INT,
	[Month-Year]					VARCHAR(30),
	[Total Incidents]				INT,
	[Austin Incidents]				INT,
	[Travis County Incidents]			INT,
	[Other Area Incidents]			INT,
	[Combined Austin & Travis Incidents]	INT,
	[Austin P1 Incidents]			INT,
	[Austin P2 Incidents]			INT,
	[Austin P3 Incidents]			INT,
	[Austin P4 Incidents]			INT,
	[Austin P5 Incidents]			INT,
	[Travis County P1 Incidents]		INT,
	[Travis County P2 Incidents]		INT,
	[Travis County P3 Incidents]		INT,
	[Travis County P4 Incidents]		INT,
	[Travis County P5 Incidents]		INT,
	[Overall On-Time Compliance]		VARCHAR(10),
	[Austin On-Time Compliance]			VARCHAR(10),
	[Travis County On-Time Compliance]		VARCHAR(10),
	[Austin P1 On-Time Compliance]		VARCHAR(10),
	[Austin P2 On-Time Compliance]		VARCHAR(10),
	[Austin P3 On-Time Compliance]		VARCHAR(10),
	[Austin P4 On-Time Compliance]		VARCHAR(10),
	[Austin P5 On-Time Compliance]		VARCHAR(10),
	[Travis County P1 On-Time Compliance]	VARCHAR(10),
	[Travis County P2 On-Time Compliance]	VARCHAR(10),
	[Travis County P3 On-Time Compliance]	VARCHAR(10),
	[Travis County P4 On-Time Compliance]	VARCHAR(10),
	[Travis County P5 On-Time Compliance]	VARCHAR(10),
	[Target On-Time Compliance]			VARCHAR(10)
) 
WITH 
( 
    LOCATION = '/EMS_-_Incidents_by_Month.csv', 
    DATA_SOURCE = OpenDataSample, 
    FILE_FORMAT = csvformat 
)

-- 6.	So now, we can do a select statement on the external table as an input to the R script.
DECLARE @input_query    NVARCHAR(MAX); 
DECLARE @RPlot          NVARCHAR(MAX);

SET @input_query = 'SELECT 
    CAST([Month-Year] AS DATE) AS [Date],
    [Total Incidents] AS [TotalIncidents]
FROM EMSIncident;'

SET @RPlot = 'library(ggplot2); 
    library(forecast);
    image_file = tempfile(); 
    jpeg(filename = image_file, width=1000, height=400); 

    #store as time series 
    myts <- ts(InputDataSet$TotalIncidents, 
        start = c(2010, 1), end = c(2017, 11),
         frequency = 12); 
    fit <- stl(myts, s.window = "period");

    # show the plot
    plot(fit, main = "EMS incidents");
    dev.off(); 

    # return the plot as dataframe
    OutputDataSet <-  data.frame(
        data=readBin(file(image_file,"rb"),
        what=raw(),n=1e6));'


EXEC sp_execute_external_script @language = N'R' 
    ,@script = @RPlot 
    ,@input_data_1 = @input_query
    ,@input_data_1_name = N'InputDataSet'
    ,@output_data_1_name = N'OutputDataSet' 
    WITH RESULT SETS (( [plot] VARBINARY(MAX)));    
