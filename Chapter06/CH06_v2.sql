USE RentalDB;
GO

SELECT TOP 10 * FROM rental_data


EXEC sp_execute_external_Script
@LANGUAGE = N'R'
,@script = N'
dr_rent <- InputDataSet
dr_rent <- data.frame(dr_rent)
OutputDataSet <- data.frame(cor(dr_rent$Holiday, dr_rent$RentalCount))
'
,@input_data_1 = N'SELECT  Holiday, RentalCount FROM rental_data'
WITH RESULT SETS ((
cor NUMERIC(10,3)
));
GO


EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'
    dr_rent <- InputDataSet
    dr_rent <- data.frame(dr_rent)
    cor_HR <- cor(dr_rent$Holiday, dr_rent$RentalCount)
    cor_FR <- cor(as.numeric(dr_rent$FWeekDay), dr_rent$RentalCount)
    cor_MR <- cor(dr_rent$Month, dr_rent$RentalCount)
    cor_YR <- cor(dr_rent$Year,dr_rent$RentalCount)
    d <- data.frame(cbind(cor_HR, cor_FR, cor_MR, cor_YR))
    OutputDataSet <- d'
,@input_data_1 = N'SELECT  Holiday, RentalCount,Month,FWeekDay, Year FROM rental_data'
    WITH RESULT SETS ((
    cor_HR NUMERIC(10,3)
    ,cor_FR NUMERIC(10,3)
    ,cor_MR NUMERIC(10,3)
    ,cor_YR NUMERIC(10,3)
    ));
    GO


/*
Let's try all the correlations between variables
*/

EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'
   library(corrplot)
   dr_rent <- InputDataSet

		dr_rent$FWeekDay <- as.numeric(dr_rent$FWeekDay)
		dr_rent$FHoliday <- as.numeric(dr_rent$FHoliday)
		dr_rent$FSnow <- as.numeric(dr_rent$FSnow)

   cor.mtest <- function(mat, ...) {
        mat <- as.matrix(mat)
        n <- ncol(mat)
        p.mat<- matrix(NA, n, n)
        diag(p.mat) <- 0
        for (i in 1:(n - 1)) {
            for (j in (i + 1):n) {
            tmp <- cor.test(mat[, i], mat[, j], ...)
            p.mat[i, j] <- p.mat[j, i] <- tmp$p.value
            }
        }
        colnames(p.mat) <- rownames(p.mat) <- colnames(mat)
        p.mat
        }
     # matrix of the p-value of the correlation
    p.mat <- cor.mtest(dr_rent)

    R<-cor(dr_rent)

    col <- colorRampPalette(c("#BB4444", "#EE9988", "#FFFFFF", "#77AADD", "#4477AA"))

    image_file = tempfile();  
    jpeg(filename = image_file);  
   
plot_corr <- corrplot(R, method="color", col=col(200),  
                type="upper", order="hclust", 
                addCoef.col = "black", # Add coefficient of correlation
                tl.col="black", tl.srt=45, #Text label color and rotation
                # Combine with significance
                p.mat = p.mat, sig.level = 0.01, insig = "blank", 
                # hide correlation coefficient on the principal diagonal
                diag=FALSE)
    dev.off(); 
OutputDataSet <- data.frame(data=readBin(file(image_file, "rb"), what=raw(), n=1e6));  '
 
,@input_data_1 = N'SELECT  *  FROM rental_data'
    WITH RESULT SETS ((
  correlation_plot varbinary(max)
    ));
 GO


 
/*
And calculate Gini mean (using RandomForest library)
*/
EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'install.packages("randomForest")'

EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'
   library(randomForest)
    dr_rent  <- InputDataSet
    fit_RF <- randomForest(factor(dr_rent$RentalCount)~., data=dr_rent)
     vp_rf <- importance(fit_RF)
	
	vp_rf<- data.frame(vp_rf)
	imena <- row.names(vp_rf)
	vp_rf <- data.frame(cbind(imena, vp_rf))
    OutputDataSet <- vp_rf'

,@input_data_1 = N'SELECT  *  FROM rental_data'
    WITH RESULT SETS ((
   Variable NVARCHAR(200)
  ,MeanDecreaseGini NUMERIC(16,5)
    ));
 GO

 /*

*******************************************************************
*******************************************************************
*******************************************************************

################## REVOSCALE #########################
Supervised!
*******************************************************************
*******************************************************************
*******************************************************************

 */

 -- rxLinMod

 EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'
            library(RevoScaleR)
            dr_rent <- InputDataSet
            Formula_supervised =  RentalCount ~ Year + Month + Day  + WeekDay + Snow + Holiday             
            #Create Linear Model 
            rent_lm <- rxLinMod(formula=Formula_supervised, data = dr_rent)

            #PREDICT   
            rent_Pred <- rxPredict(modelObject = rent_lm, data = dr_rent, extraVarsToWrite=c("RentalCount","Year","Month","Day"), writeModelVars = TRUE)
            OutputDataSet <- data.frame(rent_Pred)
'
,@input_data_1 = N'SELECT RentalCount,Year, Month, Day, WeekDay,Snow,Holiday  FROM rental_data'
    WITH RESULT SETS ((
 RentalCount_Pred    NUMERIC(16,3)
 ,RentalCount  NUMERIC(16,3)
 ,Year INT
 ,Month INT
 ,Day INT
 ,WeekDay INT  
 ,Snow  INT 
 ,Holiday INT
    ));
 GO

 -- rxGlm

 EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'
            library(RevoScaleR)
            dr_rent <- InputDataSet
            Formula_supervised =  RentalCount ~ Year + Month + Day  + WeekDay + Snow + Holiday             
            rent_lm <- rxLinMod(formula=Formula_supervised, data = dr_rent)

            #PREDICT   
			rent_glm <- rxGlm(formula = Formula_supervised, family = Gamma, dropFirst = TRUE, data = dr_rent)
			rent_Pred <- rxPredict(modelObject = rent_glm, data = dr_rent, extraVarsToWrite=c("RentalCount","Year","Month","Day"), writeModelVars = TRUE)
            OutputDataSet <- data.frame(rent_Pred)
			
		'
,@input_data_1 = N'SELECT RentalCount,Year, Month, Day, WeekDay,Snow,Holiday  FROM rental_data'
    WITH RESULT SETS ((
 RentalCount_Pred    NUMERIC(16,3)
 ,RentalCount  NUMERIC(16,3)
 ,Year INT
 ,Month INT
 ,Day INT
 ,WeekDay INT  
 ,Snow  INT 
 ,Holiday INT
    ));
 GO

 -- rxDTree

EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'
            library(RevoScaleR)
            dr_rent <- InputDataSet
            Formula_supervised =  RentalCount ~ Year + Month + Day  + WeekDay + Snow + Holiday             
            
            #PREDICT   
			rent_dt <- rxDTree(formula = Formula_supervised, data = dr_rent)
			rent_Pred <- rxPredict(modelObject = rent_dt, data = dr_rent, extraVarsToWrite=c("RentalCount","Year","Month","Day"), writeModelVars = TRUE)
            OutputDataSet <- data.frame(rent_Pred)
			
		'
,@input_data_1 = N'SELECT RentalCount,Year, Month, Day, WeekDay,Snow,Holiday  FROM rental_data'
    WITH RESULT SETS ((
 RentalCount_Pred    NUMERIC(16,3)
 ,RentalCount  NUMERIC(16,3)
 ,Year INT
 ,Month INT
 ,Day INT
 ,WeekDay INT  
 ,Snow  INT 
 ,Holiday INT
    ));
 GO

/*
Comparing all three algorithms:
rxDTree, rxLinMod, rxGlm
*/

DECLARE @temp table (
 RentalCount_Pred_LinMod    NUMERIC(16,3)
 ,RentalCount  NUMERIC(16,3)
 ,Year INT
 ,Month INT
 ,Day INT
    );

INSERT INTO  @temp (rentalCount_pred_linmod, rentalcount, year, month, day)
EXEC sp_execute_external_Script
 @LANGUAGE = N'R'
,@script = N'
            library(RevoScaleR)
            dr_rent <- InputDataSet
            Formula_supervised =  RentalCount ~ Year + Month + Day  + WeekDay + Snow + Holiday             
            
            #PREDICT   
			rent_dt <- rxDTree(formula = Formula_supervised, data = dr_rent)
			rent_Pred <- rxPredict(modelObject = rent_dt, data = dr_rent, extraVarsToWrite=c("RentalCount","Year","Month","Day"), writeModelVars = TRUE)
            OutputDataSet <- data.frame(rent_Pred)		'
,@input_data_1 = N'SELECT RentalCount,Year, Month, Day, WeekDay,Snow,Holiday  FROM rental_data'


/*
Spitting data   
*/
DROP TABLE IF EXISTS  dbo.Train_rental_data;
GO

-- We can set 70% of the original data
-- IN SQL Server
SELECT 
 TOP (70) PERCENT 
 *
INTO dbo.Train_rental_data
  FROM rental_data
ORDER BY ABS(CAST(BINARY_CHECKSUM(RentalCount, NEWID()) as int)) ASC
-- (318 rows affected) 

-- Or we can set by the year; year 2013 and 2014 for training and 2015 for testing? making it cca 70% for training as well
SELECT COUNT(*), YEAR FROM rental_data GROUP BY YEAR


-- or in R
  EXEC sp_execute_external_Script
	 @language = N'R'
	,@script = N'
			library(caTools)
			
			set.seed(2910) 
			dr_rent <- InputDataSet
			Split <- .70
			sample = sample.split(dr_rent$RentalCount, SplitRatio = Split)
			train_dr_rent <- subset(dr_rent, sample == TRUE)
			test_dr_rent  <- subset(dr_rent, sample == FALSE)
            OutputDataSet <- data.frame(train_dr_rent)
			
		'
,@input_data_1 = N'SELECT * FROM rental_data'
    WITH RESULT SETS ((
	 [Year] INT
	,[Month] INT
	,[Day] INT
	,[RentalCount] INT
	,[WeekDay] INT
	,[Holiday] INT
	,[Snow] INT
	,[FHoliday] INT
	,[FSnow] INT
	,[FWeekDay] INT
    ));
 GO


 -- or using: rxExecuteSQLDDL and RxOdbcData for storing back into the database

 -- Variables to keep
 -- and creating formula
  EXEC sp_execute_external_Script
	 @language = N'R'
	,@script = N'
			library(RevoScaleR)
			dr_rent <- InputDataSet
            variables_all <- rxGetVarNames(dr_rent)
            variables_to_remove <- c("FSnow", "FWeekDay", "FHoliday")
            traning_variables <- variables_all[!(variables_all %in% c("RentalCount", variables_to_remove))]
            #use as.formula to create an object
            #formula <- as.formula(paste("RentalCount ~", paste(traning_variables, collapse = "+")))
			formula <- paste("RentalCount ~", paste(traning_variables, collapse = "+"))
            OutputDataSet <- data.frame(formula)'
,@input_data_1 = N'SELECT * FROM dbo.Train_rental_data'
    WITH RESULT SETS ((
	 [Formula_supervised] NVARCHAR(1000)
    ));
 GO

-- Set the compute context to SQL for model training. 
-- to in-database engine and not R Server (see the path changed)
rxSetComputeContext(local)
rxSetComputeContext(sql)


-- CREATE TABLE for model storing
DROP TABLE IF EXISTS Rental_data_models;
GO

CREATE TABLE [dbo].Rental_data_models
(
	 [model_name] VARCHAR(100) NOT NULL
	,[model] VARBINARY(MAX) NOT NULL
	,Created SMALLDATETIME NOT NULL DEFAULT(GETDATE())
	,Accuracy INT NULL
);
GO




-- Random forest

DROP PROCEDURE IF EXISTS dbo.forest_model;
GO


CREATE OR ALTER PROCEDURE dbo.forest_model  (
	 @trained_model VARBINARY(MAX) OUTPUT
	,@accuracy FLOAT OUTPUT
	)
AS
BEGIN
    EXEC sp_execute_external_script
     @language = N'R'
    ,@script = N'
			library(RevoScaleR)
			library(caTools)
            library(MLmetrics)

		
			dr_rent <- InputDataSet
			set.seed(2910) 
			Split <- .70
			sample = sample.split(dr_rent$RentalCount, SplitRatio = Split)
			train_dr_rent <- subset(dr_rent, sample == TRUE)
			test_dr_rent  <- subset(dr_rent, sample == FALSE)
			
			y_train <- train_dr_rent$RentalCount
			y_test <- test_dr_rent$RentalCount


            variables_all <- rxGetVarNames(dr_rent)
            variables_to_remove <- c("FSnow", "FWeekDay", "FHoliday")
            traning_variables <- variables_all[!(variables_all %in% c("RentalCount", variables_to_remove))]
            formula <- as.formula(paste("RentalCount ~", paste(traning_variables, collapse = "+")))

			forest_model <- rxDForest(formula = formula,
                          data = train_dr_rent,
                          nTree = 40,
                          minSplit = 10,
                          minBucket = 5,
                          cp = 0.00005,
                          seed = 5)

			trained_model <- as.raw(serialize(forest_model, connection=NULL))
		
			#calculating accuracy
            y_predicted<- rxPredict(forest_model,test_dr_rent)

            predict_forest <-data.frame(actual=y_test,pred=y_predicted)
            #ConfMat <- confusionMatrix(table(predict_forest$actual,predict_forest$RentalCount_Pred))
            #accuracy <- ConfMat$overall[1]
            accu <- LogLoss(y_pred = predict_forest$RentalCount_Pred , y_true =predict_forest$actual)
            accuracy <- accu'


	,@input_data_1 = N'SELECT * FROM dbo.rental_data'
	,@params = N'@trained_model VARBINARY(MAX) OUTPUT, @accuracy FLOAT OUTPUT'
    ,@trained_model = @trained_model OUTPUT
	,@accuracy = @accuracy OUTPUT;
END;
GO

 
DECLARE @model VARBINARY(MAX);
DECLARE @accur FLOAT;
EXEC dbo.forest_model @model OUTPUT, @accur OUTPUT;
INSERT INTO [dbo].[Rental_data_models] (model_name, model, accuracy) VALUES('Random_forest_V1', @model, @accur);
GO

SELECT * FROM [dbo].[Rental_data_models];

-- Gradient boosting                          
CREATE OR ALTER PROCEDURE dbo.btree_model  (
	 @trained_model VARBINARY(MAX) OUTPUT
	,@accuracy FLOAT OUTPUT
	)
AS
BEGIN
    EXEC sp_execute_external_script
     @language = N'R'
    ,@script = N'
			library(RevoScaleR)
			library(caTools)
            library(MLmetrics)

		
			dr_rent <- InputDataSet
			set.seed(2910) 
			Split <- .70
			sample = sample.split(dr_rent$RentalCount, SplitRatio = Split)
			train_dr_rent <- subset(dr_rent, sample == TRUE)
			test_dr_rent  <- subset(dr_rent, sample == FALSE)
			
			y_train <- train_dr_rent$RentalCount
			y_test <- test_dr_rent$RentalCount


            variables_all <- rxGetVarNames(dr_rent)
            variables_to_remove <- c("FSnow", "FWeekDay", "FHoliday")
            traning_variables <- variables_all[!(variables_all %in% c("RentalCount", variables_to_remove))]
            formula <- as.formula(paste("RentalCount ~", paste(traning_variables, collapse = "+")))

            btree_model <- rxBTrees(formula = formula
                                    ,data = train_dr_rent
                                    ,learningRate = 0.05
                                    ,minSplit = 10
                                    ,minBucket = 5
                                    ,cp = 0.0005
                                    ,nTree = 40
                                    ,seed = 5
                                    ,lossFunction = "gaussian")

			trained_model <- as.raw(serialize(btree_model, connection=NULL))
		
			#calculating accuracy
            y_predicted<- rxPredict(btree_model,test_dr_rent)

            predict_btree <-data.frame(actual=y_test,pred=y_predicted)
            #ConfMat <- confusionMatrix(table(predict_btree$actual,predict_btree$RentalCount_Pred))
            #accuracy <- ConfMat$overall[1]
            accu <- LogLoss(y_pred = predict_btree$RentalCount_Pred , y_true =predict_btree$actual)
            accuracy <- accu'


	,@input_data_1 = N'SELECT * FROM dbo.rental_data'
	,@params = N'@trained_model VARBINARY(MAX) OUTPUT, @accuracy FLOAT OUTPUT'
    ,@trained_model = @trained_model OUTPUT
	,@accuracy = @accuracy OUTPUT;
END;
GO




DECLARE @model VARBINARY(MAX);
DECLARE @accur FLOAT;
EXEC dbo.btree_model @model OUTPUT, @accur OUTPUT;
INSERT INTO [dbo].[Rental_data_models] (model_name, model, accuracy) VALUES('Gradient_boosting_V1', @model, @accur);
GO


CREATE OR ALTER PROCEDURE dbo.glm_model  (
	 @trained_model VARBINARY(MAX) OUTPUT
	,@accuracy FLOAT OUTPUT
	)
AS
BEGIN
    EXEC sp_execute_external_script
     @language = N'R'
    ,@script = N'
			library(RevoScaleR)
			library(caTools)
            library(MLmetrics)

		
			dr_rent <- InputDataSet
			set.seed(2910) 
			Split <- .70
			sample = sample.split(dr_rent$RentalCount, SplitRatio = Split)
			train_dr_rent <- subset(dr_rent, sample == TRUE)
			test_dr_rent  <- subset(dr_rent, sample == FALSE)
			
			y_train <- train_dr_rent$RentalCount
			y_test <- test_dr_rent$RentalCount


            variables_all <- rxGetVarNames(dr_rent)
            variables_to_remove <- c("FSnow", "FWeekDay", "FHoliday")
            traning_variables <- variables_all[!(variables_all %in% c("RentalCount", variables_to_remove))]
            formula <- as.formula(paste("RentalCount ~", paste(traning_variables, collapse = "+")))

            glm_model <- rxGlm(formula = formula
                                    ,data = train_dr_rent
                                    ,family = Gamma
                                    ,dropFirst = TRUE
                                    ,variableSelection = rxStepControl(scope = ~ Year + Month + Snow + Holiday + Day + WeekDay))

			trained_model <- as.raw(serialize(glm_model, connection=NULL))
		
			#calculating accuracy
            y_predicted<- rxPredict(glm_model,test_dr_rent)

            predict_glm <-data.frame(actual=y_test,pred=y_predicted)
            #ConfMat <- confusionMatrix(table(predict_glm$actual,predict_glm$RentalCount_Pred))
            #accuracy <- ConfMat$overall[1]
            accu <- LogLoss(y_pred = predict_glm$RentalCount_Pred , y_true =predict_glm$actual)
            accuracy <- accu'


	,@input_data_1 = N'SELECT * FROM dbo.rental_data'
	,@params = N'@trained_model VARBINARY(MAX) OUTPUT, @accuracy FLOAT OUTPUT'
    ,@trained_model = @trained_model OUTPUT
	,@accuracy = @accuracy OUTPUT;
END;
GO




DECLARE @model VARBINARY(MAX);
DECLARE @accur FLOAT;
EXEC dbo.glm_model @model OUTPUT, @accur OUTPUT;
INSERT INTO [dbo].[Rental_data_models] (model_name, model, accuracy) VALUES('General_linear_model_V1', @model, @accur);
GO


SELECT * FROM Rental_data_models


CREATE OR ALTER PROCEDURE dbo.model_eval 
AS
BEGIN
    EXEC sp_execute_external_script
     @language = N'R'
    ,@script = N'
			library(RevoScaleR)
			library(caTools)
            library(MLmetrics)

            #evaluate_model function; Source: Microsoft
            evaluate_model <- function(observed, predicted_probability, threshold, model_name) { 
            
            # Given the observed labels and the predicted probability, plot the ROC curve and determine the AUC.
            data <- data.frame(observed, predicted_probability)
            data$observed <- as.numeric(as.character(data$observed))
            if(model_name =="RF"){
                rxRocCurve(actualVarName = "observed", predVarNames = "predicted_probability", data = data, numBreaks = 1000, title = "RF" )
            }else{
                rxRocCurve(actualVarName = "observed", predVarNames = "predicted_probability", data = data, numBreaks = 1000, title = "GBT" )
            }
            ROC <- rxRoc(actualVarName = "observed", predVarNames = "predicted_probability", data = data, numBreaks = 1000)
            auc <- rxAuc(ROC)
            
            # Given the predicted probability and the threshold, determine the binary prediction.
            predicted <- ifelse(predicted_probability > threshold, 1, 0) 
            predicted <- factor(predicted, levels = c(0, 1)) 
            
            # Build the corresponding Confusion Matrix, then compute the Accuracy, Precision, Recall, and F-Score.
            confusion <- table(observed, predicted)
            print(model_name)
            print(confusion) 
            tp <- confusion[1, 1] 
            fn <- confusion[1, 2] 
            fp <- confusion[2, 1] 
            tn <- confusion[2, 2] 
            accuracy <- (tp + tn) / (tp + fn + fp + tn) 
            precision <- tp / (tp + fp) 
            recall <- tp / (tp + fn) 
            fscore <- 2 * (precision * recall) / (precision + recall) 
            
            # Return the computed metrics.
            metrics <- list("Accuracy" = accuracy, 
                            "Precision" = precision, 
                            "Recall" = recall, 
                            "F-Score" = fscore,
                            "AUC" = auc) 
            return(metrics) 
            } 


            RF_Scoring <- rxPredict(forest_model, data = train_dr_rent, overwrite = T, type = "response",extraVarsToWrite = c("RentalCount"))

            Prediction_RF <- rxImport(inData = RF_Scoring, stringsAsFactors = T, outFile = NULL)
            observed <- Prediction_RF$RentalCount

            # Compute the performance metrics of the model.
            Metrics_RF <- evaluate_model(observed = observed, predicted_probability = Prediction_RF$RentalCount_Pred , model_name = "RF", threshold=50)

            # Make Predictions, then import them into R. The observed Conversion_Flag is kept through the argument extraVarsToWrite.
            GBT_Scoring <- rxPredict(btree_model,data = train_dr_rent, overwrite = T, type="prob",extraVarsToWrite = c("RentalCount"))

            Prediction_GBT <- rxImport(inData = GBT_Scoring, stringsAsFactors = T, outFile = NULL)
            observed <- Prediction_GBT$RentalCount


            # Compute the performance metrics of the model.
            Metrics_GBT <- evaluate_model(observed = observed, predicted_probability = Prediction_GBT$RentalCount_Pred, model_name = "GBT", threshold=50)

            eval <- data.frame(acc= c(Metrics_RF$Accuracy, Metrics_GBT$Accuracy), modelname=c("RF", "GBT"))
            OuputDataSet <- data.frame(eval)'
END            



----- Predictions

CREATE OR ALTER  PROCEDURE [dbo].[Predicting_rentalCount] 
(
		 @model VARCHAR(30)
		,@query NVARCHAR(MAX)
)
AS
BEGIN
	DECLARE @nar_model VARBINARY(MAX) = (SELECT model FROM [dbo].[Rental_data_models] WHERE model_name = @model);

	EXEC sp_execute_external_script
		 @language = N'R'
		,@script = N'

				#input from query
				new_data <- InputDataSet
				
				#model from query
				model <- unserialize(nar_model)			

				#prediction
				prediction <- rxPredict(model,data = new_data, overwrite = TRUE, type="response",extraVarsToWrite = c("RentalCount"))
				Prediction_New <- rxImport(inData = prediction, stringsAsFactors = T, outFile = NULL)

				OutputDataSet <- data.frame(Prediction_New)

				'
		,@input_data_1 =  @query
		,@params = N'@nar_model VARBINARY(MAX)'
		,@nar_model = @nar_model
	WITH RESULT SETS((		 
		  Prediction_new NVARCHAR(1000)
		 ,OrigPredictecCount NVARCHAR(1000)
	))
END;




-- Example of running predictions agains selected model
EXEC [dbo].[Predicting_rentalCount]  
	 @model = N'Random_forest_V1'
	,@query = N'SELECT 
					2014 AS Year
					,5 AS Month
					,12 AS Day
					,1 AS WeekDay
					,0 AS Holiday
					,0 AS Snow
					,0 AS RentalCount'
					

--Prediction_new	OrigPredictecCount
-- 278.996			0

SELECT 
* 
FROM Rental_data
WHERE [year] = 2014
AND [day] = 12


-----
--- Procedure for reporting -  clustering
-----

DROP PROCEDURE IF EXISTS dbo.clustering_rentalcount;
GO

CREATE OR ALTER  PROCEDURE [dbo].[Clustering_rentalCount] 
(
		 @nof_clusters VARCHAR(2)
)
AS
BEGIN

DECLARE @SQLStat NVARCHAR(4000)
SET @SQLStat = 'SELECT  * FROM rental_data'
DECLARE @RStat NVARCHAR(4000)
SET @RStat = 'library(ggplot2)
			  library(RevoScaleR)
			  library(cluster)
              image_file <- tempfile()
                       jpeg(filename = image_file, width = 400, height = 400)

                       DF <- data.frame(dr_rent)
						# and remove the Fholidays and Fsnow variables
						DF <- DF[c(1,2,3,4,5,6,7)]

						XDF <- paste(tempfile(), "xdf", sep=".")
						if (file.exists(XDF)) file.remove(XDF)
						rxDataStep(inData = DF, outFile = XDF)


						# grab 3 random rows for starting 
						centers <- DF[sample.int(NROW(DF), 3, replace = TRUE),] 

						#create formula
						Formula =  ~ Year + Month + Day + RentalCount + WeekDay + Holiday + Snow ##exclude holidays

						# Example using an XDF file as a data source
						#rxKmeans(formula = Formula, data = XDF, centers = centers)
						#z <- rxKmeans(formula=Formula, data = DF, centers = centers)

						rxKmeans(formula = Formula, data = XDF, numClusters='+@nof_clusters+')
						z <- rxKmeans(formula=Formula, data = DF, numClusters='+@nof_clusters+')

						clusplot(DF, z$cluster, color=TRUE, shade=TRUE, labels=4, lines=0, plotchar = TRUE)


                       dev.off()
                    OutputDataSet <- data.frame(data=readBin(file(image_file, "rb"), what=raw(), n=1e6))'

EXECUTE sp_execute_external_script
        @language = N'R'
       ,@script = @RStat
       ,@input_data_1 = @SQLStat
       ,@input_data_1_name = N'dr_rent'
WITH RESULT SETS ((plot varbinary(max)))
END;
GO

DROP PROCEDURE IF EXISTS dbo.Clustering_rentalCount_centers;
GO

CREATE OR ALTER  PROCEDURE [dbo].[Clustering_rentalCount_centers] 
(
		 @nof_clusters VARCHAR(2)
)
AS
BEGIN

DECLARE @SQLStat NVARCHAR(4000)
SET @SQLStat = 'SELECT  * FROM rental_data'
DECLARE @RStat NVARCHAR(4000)
SET @RStat = 'library(ggplot2)
			  library(RevoScaleR)
			  library(cluster)

                       DF <- data.frame(dr_rent)
						# and remove the Fholidays and Fsnow variables
						DF <- DF[c(1,2,3,4,5,6,7)]

						XDF <- paste(tempfile(), "xdf", sep=".")
						if (file.exists(XDF)) file.remove(XDF)
						rxDataStep(inData = DF, outFile = XDF)


						# grab 3 random rows for starting 
						centers <- DF[sample.int(NROW(DF), 3, replace = TRUE),] 

						#create formula
						Formula =  ~ Year + Month + Day + RentalCount + WeekDay + Holiday + Snow ##exclude holidays

						# Example using an XDF file as a data source
						#rxKmeans(formula = Formula, data = XDF, centers = centers)
						#z <- rxKmeans(formula=Formula, data = DF, centers = centers)

						rxKmeans(formula = Formula, data = XDF, numClusters='+@nof_clusters+')
						z <- rxKmeans(formula=Formula, data = DF, numClusters='+@nof_clusters+')


                    OutputDataSet <- data.frame(z$centers)'

EXECUTE sp_execute_external_script
        @language = N'R'
       ,@script = @RStat
       ,@input_data_1 = @SQLStat
       ,@input_data_1_name = N'dr_rent'
WITH RESULT SETS ((
 [Year] INT       
,[Month] INT       
,[Day] INT
,RentalCount INT
,[WeekDay] INT
,Holiday INT
,Snow INT
))
END;
GO

DROP PROCEDURE IF EXISTS dbo.[ScreePlot_rentalCount];
GO

CREATE OR ALTER  PROCEDURE [dbo].[ScreePlot_rentalCount] 
AS
BEGIN

DECLARE @SQLStat NVARCHAR(4000)
SET @SQLStat = 'SELECT  * FROM rental_data'
DECLARE @RStat NVARCHAR(4000)
SET @RStat = 'library(ggplot2)
			  library(RevoScaleR)
			  library(cluster)
              image_file <- tempfile()
                       jpeg(filename = image_file, width = 400, height = 400)

                       DF <- data.frame(dr_rent)
						# and remove the Fholidays and Fsnow variables
						DF <- DF[c(1,2,3,4,5,6,7)]

						XDF <- paste(tempfile(), "xdf", sep=".")
						if (file.exists(XDF)) file.remove(XDF)
						rxDataStep(inData = DF, outFile = XDF)


						# grab 3 random rows for starting 
						centers <- DF[sample.int(NROW(DF), 3, replace = TRUE),] 

						#create formula
						Formula =  ~ Year + Month + Day + RentalCount + WeekDay + Holiday + Snow ##exclude holidays

						wss <- (nrow(DF) - 1) * sum(apply(DF, 2, var))
						for (i in 2:20)
						  wss[i] <- sum(kmeans(DF, centers = i)$withinss)
						plot(1:20, wss, type = "b", xlab = "Number of Clusters", ylab = "Within groups sum of squares")

					
                       dev.off()
                    OutputDataSet <- data.frame(data=readBin(file(image_file, "rb"), what=raw(), n=1e6))'

EXECUTE sp_execute_external_script
        @language = N'R'
       ,@script = @RStat
       ,@input_data_1 = @SQLStat
       ,@input_data_1_name = N'dr_rent'
WITH RESULT SETS ((plot varbinary(max)))
END;
GO
