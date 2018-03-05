CREATE PROCEDURE [dbo].[uspTrainTipPredictionModelWithRealTimeScoring]
AS
BEGIN
	DECLARE @auc FLOAT;
	DECLARE @model VARBINARY(MAX);

	-- The data to be used for training
	DECLARE @inquery NVARCHAR(MAX) = N'
		SELECT 
			tipped, 
			fare_amount, 
			passenger_count,
			trip_time_in_secs,
			trip_distance,
			pickup_datetime, 
			dropoff_datetime,
			dbo.fnCalculateDistance(pickup_latitude, 
				pickup_longitude,  
				dropoff_latitude, 
				dropoff_longitude) as direct_distance
		FROM dbo.nyctaxi_sample
		TABLESAMPLE (10 PERCENT) REPEATABLE (98052)'

  -- Calculate the model based on the trained data and the AUC.
  EXEC sp_execute_external_script @language = N'R',
                                   @script = N'
		## Create model
		logitObj <- rxLogit(tipped ~ passenger_count + 
					trip_distance + 
					trip_time_in_secs + 
					direct_distance, 
					data = InputDataSet);
		summary(logitObj)

		## Serialize model 		
		## model <- serialize(logitObj, NULL);
		model <- rxSerializeModel(logitObj, 
realtimeScoringOnly = TRUE);
		predOutput <- rxPredict(modelObject = logitObj, 
				data = InputDataSet, outData = NULL, 
				predVarNames = "Score", type = "response", 
				writeModelVars = FALSE, overwrite = TRUE);
							
		library(''ROCR'');
		predOutput <- cbind(InputDataSet, predOutput);
		 
		auc <- rxAuc(rxRoc("tipped", "Score", predOutput));
		print(paste0("AUC of Logistic Regression Model:", auc));
		',
	  @input_data_1 = @inquery,	  
	  @output_data_1_name = N'trained_model',
	  @params = N'@auc FLOAT OUTPUT, @model VARBINARY(MAX) OUTPUT',
	  @auc = @auc OUTPUT,
	  @model = @model OUTPUT;
  
  -- Store the train model output and its AUC 
  INSERT INTO [dbo].[NYCTaxiModel] (Model, AUC, IsRealTimeScoring)
  SELECT @model, @auc, 1;

END
GO
