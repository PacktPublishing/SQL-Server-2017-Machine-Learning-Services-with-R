setwd("C:\\Users\\Tomaz\\Documents\\06-SQL\\6-Knjige\\02 - R\\CH05 - TK")

##########################################################################################
###
### Importing data / datasets using SAS, SPSS and ODBC drivers (From SQL Server)
###
##########################################################################################

## functions
library(RevoScaleR)
ls("package:RevoScaleR")


# importing SAS
orig_sampleDir <- file.path(rxGetOption("sampleDataDir"))
# [1] "C:/Program Files/Microsoft SQL Server/140/R_SERVER/library/RevoScaleR/SampleData"

SampleSASFile <- file.path(("C:\\Users\\Tomaz\\Documents\\06-SQL\\6-Knjige\\02 - R\\CH05 - TK"), "sas_data.sas7bdat")

#import into Dataframe
sasDS <- RxSasData(SampleSASFile, stringsAsFactors = TRUE, 
                   colClasses = c(income = "integer", gender= "integer", count="integer"),rowsPerRead = 1000)
rxHistogram( ~F(gender)|F(income), data = sasDS)



# importing SPSS
SampleSPSSFile <- file.path(("C:\\Users\\Tomaz\\Documents\\06-SQL\\6-Knjige\\02 - R\\CH05 - TK"), "spss_data.sav")

#import into Dataframe
spssDS <- RxSpssData(SampleSPSSFile, stringsAsFactors = TRUE, 
                   colClasses = c(income = "integer", gender= "integer", count="integer"),rowsPerRead = 1000)
rxHistogram( ~F(income)|F(count), data = spssDS)


#Importing using ODBC

library(RevoScaleR)
sConnectStr <- "Driver={ODBC Driver 13 for SQL Server};Server=TOMAZK\\MSSQLSERVER2017;Database=AdventureWorks;Trusted_Connection=Yes"
sQuery = "SELECT  BusinessEntityID,[Name],SalesPersonID FROM [Sales].[Store] ORDER BY BusinessEntityID ASC"
sDS <-RxOdbcData(sqlQuery=sQuery, connectionString=sConnectStr)
df_sql <- data.frame(rxImport(sDS))


str(df_sql)


##########################################################################################
###
### Variable Creation, recoding, data transformation, missing values, sorting, merging....
###
##########################################################################################

head(df_sql, n=4)

# store data into XDF all 701 rows from df_sql
outfile <- file.path(rxGetOption("sampleDataDir"), "df_sql.xdf") #Make sure that the local user (running this code) has read/write access granted to sampleDataDir
rxDataStep(inData = df_sql, outFile = outfile, overwrite = TRUE)


# Variable Creation
var_info <- rxGetVarInfo(df_sql)
df <- data.frame(unlist(var_info))


#rxGetInfo
rxGetInfo(df_sql) 

rxGetInfo(df_sql, getVarInfo = TRUE) 

get_Info <- rxGetInfo(df_sql) 

Object_names <- c("Object Name", "Number of Rows", "Number of Variables")
Object_values <- c(get_Info$objName, get_Info$numRows, get_Info$numVars)
df_get_info <- data.frame(Object_names, Object_values)

get_Info$objName
get_Info$numRows
get_Info$numVars




# recoding data
df_sql$BusinessType <- NA
df_sql$BusinessType[df_sql$BusinessEntityID<=1000] <- "Car Business"
df_sql$BusinessType[df_sql$BusinessEntityID>1000] <- "Food Business"


#using rxDataSet for recoding data

# Use transformFunc to add new columns
myXformFunc <- function(dataList) {
  #dataList$BussEnt <- 100 * dataList$BusinessEntityID
  if (dataList$BusinessEntityID<=1000){dataList$BussEnt <- 1} else {dataList$BussEnt <- 2}
  return (dataList)
}

df_sql_new2 <- rxDataStep(inData = df_sql, transformFunc = myXformFunc)


#using rxDataSet for subsetting  data
rxDataStep(inData = df_sql, varsToKeep = NULL, rowSelection = (BusinessEntityID<=1000))



# Data Merging
someExtraData <- data.frame(BusinessEntityID = 1:600, department = rep(c("a", "b", "c", "d"), 25), Eff_score = rnorm(100))

Merged_data <- rxMerge(inData1 = df_sql, inData2 = someExtraData,
                       overwrite = TRUE, matchVars = "BusinessEntityID", type = "left",autoSort = TRUE)


rxOptions(df_sql)



#--------------------------------------------------
#  --- FUNCTIONS AND  DESCRIPTIVE STATISTICS
#--------------------------------------------------


# get some new data in
library(RevoScaleR)
sConnectStr <- "Driver={ODBC Driver 13 for SQL Server};Server=TOMAZK\\MSSQLSERVER2017;Database=AdventureWorks;Trusted_Connection=Yes"
sQuery = "SELECT * FROM [Sales].[vPersonDemographics] WHERE [DateFirstPurchase] IS NOT NULL"
sDS <-RxOdbcData(sqlQuery=sQuery, connectionString=sConnectStr)
df_sql <- data.frame(rxImport(sDS))


# for TotalChildren
d <- rxSummary(~ TotalChildren,  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"))

#for all (non-character variables)
d <- rxSummary(~.,  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"))


#ommiting categorical variables
d <- rxSummary(~.,  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"), categorical=c("MaritalStatus"))

#will fail!
summary <- rxSummary(~F(MaritalStatus),  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max","Sum","ValidObs", "MissingObs"))

# We need to define the levels of Factors
df_sql_r <- rxFactors(inData = df_sql, sortLevels = TRUE,
                        factorInfo = list(MS = list(levels = c("M","S"), otherLevel=NULL, varName="MaritalStatus")
                                          )
                        )
                          


d <- rxSummary(~MS, df_sql_r, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum")) # note that summaryStats will be ignored

dfc <- data.frame(d$categorical)

dfc


#combining the variables
d <- rxSummary(NumberCarsOwned ~ TotalChildren,  df_sql, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"))


d <- rxSummary(~ TotalChildren:F(MS), df_sql_r, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"))
d <- rxSummary(~F(MS):TotalChildren, df_sql_r, summaryStats = c( "Mean", "StdDev", "Min", "Max", "ValidObs", "MissingObs", "Sum"), categorical=c("MS"))

d <- data.frame(d$categorical)



# quantiles
rq <- data.frame(rxQuantile(data = df_sql, varName = "TotalChildren"))


# deciles
rxQuantile(data = df_sql, varName = "TotalChildren", probs = seq(from = 0, to = 1, by = .1))




# rxCrossTabs
d <- rxCrossTabs(N(NumberCarsOwned) ~ F(TotalChildren),  df_sql)

crosstab <- rxCrossTabs(N(NumberCarsOwned) ~ F(TotalChildren),  df_sql, means=FALSE) #means=TRUE
children <- c(0,1,2,3,4,5)
OutputDataSet <- data.frame(crosstab$sums, children)


barplot(OutputDataSet$V1, xlab = "Number of children",ylab = "Number of cars owned", beside=FALSE,
         legend.text = c("0 Child","1 Child","2 Child","3 Child","4 Child","5 Child"), col=c("magenta", "lightgreen", "lightblue", "yellow", "grey", "white"))

library(RColorBrewer)
barplot(OutputDataSet$V1, xlab = "Number of children",ylab = "Number of cars owned", beside=FALSE,
        legend.text = c("0 Child","1 Child","2 Child","3 Child","4 Child","5 Child"), col=brewer.pal(6, "Paired"))
  

brewer.pal(nrow(y), "Paired")

# rxMarginals

mar <- rxMarginals(rxCrossTabs(NumberCarsOwned ~ F(TotalChildren), data=df_sql, margin=TRUE, mean=FALSE))

mar$NumberCarsOwned$grand


rxHistogram(~NumberCarsOwned, data=df_sql)


rxHistogram(~F(MS), data=df_sql_r)

rxHistogram(~ NumberCarsOwned | F(MS), title="Cars owned per Marital Status",  numBreaks=10, data = df_sql_r)

rxLinePlot(as.numeric(log(TotalPurchaseYTD)) ~ as.factor(DateFirstPurchase), data = df_sql_r, rowSelection= 
             DateFirstPurchase >= "2001-07-01 00:00:00.000" & DateFirstPurchase <= "2001-07-17 00:00:00.000", type="p")



# combined
h1 <- rxHistogram(~NumberCarsOwned, data=df_sql)
h2 <- rxHistogram(~F(MS), data=df_sql_r)
#h3 <- rxHistogram(~ NumberCarsOwned | F(MS), title="Cars owned per Marital Status",  numBreaks=10, data = df_sql_r)
p1 <- rxLinePlot(as.numeric(log(TotalPurchaseYTD)) ~ as.factor(DateFirstPurchase), data = df_sql_r, rowSelection= 
             DateFirstPurchase >= "2001-07-01 00:00:00.000" & DateFirstPurchase <= "2001-07-17 00:00:00.000", type="p")

#library(UsingR)
print(h1, position = c(0, 0.5, 0.5, 1), more = TRUE)
print(h2, position = c(0.5, 0.5, 1, 1), more = TRUE)
#print(h3, position = c(0.5, 0.5, 0.5, 1), more = TRUE)
print(p1, position = c(0.5, 0.05, 1, 0.5))




#--------------------------------------------------
#  --- STATISTICAL TESTS
#--------------------------------------------------

#rxChiSquaredTest - Performs Chi-squared Test on xtabs object. Used with small data sets and does not chunk data.

#Occupation MS

df_sql_r$Occupation <- as.factor(df_sql_r$Occupation)
df_sql_r$MS <- as.factor(df_sql_r$MS)
testData <- data.frame(Occupation = df_sql_r$Occupation, Status=df_sql_r$MS)
d <- rxCrossTabs(~Occupation:Status,  testData, returnXtabs = TRUE)
chi_q <- rxChiSquaredTest(d)

chi_q$'X-squared'
chi_q$`p-value`

xs <- chi_q$'X-squared'
p <- chi_q$'p-value'
OutputDataSet <- data.frame(xs,p)


df_sql_r <- rxFactors(inData = df_sql, factorInfo = list(MS = list(levels = c("M","S"), otherLevel=NULL, varName="MaritalStatus")))
df_sql_r$Occupation <- as.factor(df_sql_r$Occupation)
df_sql_r$MS <- df_sql_r$MS
testData <- data.frame(Occupation = df_sql_r$Occupation, Status=df_sql_r$MS)
d <- rxCrossTabs(~Occupation:Status,  testData, returnXtabs = TRUE)
chi_q <- rxChiSquaredTest(d)


#rxKendallCor - Computes Kendall's Tau Rank Correlation Coefficient using xtabs object.
ken <- rxKendallCor(d, type = "b")

ken$`estimate 1`
ken$`p-value`

