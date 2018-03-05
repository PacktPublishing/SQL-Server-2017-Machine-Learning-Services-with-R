CREATE PROCEDURE [dbo].[uspPredictTipSingleMode] 
	@passenger_count int = 0,
	@trip_distance float = 0,
	@trip_time_in_secs int = 0,
	@pickup_latitude float = 0,
	@pickup_longitude float = 0,
	@dropoff_latitude float = 0,
	@dropoff_longitude float = 0
AS
BEGIN

  DECLARE @inquery nvarchar(max) = N'
	SELECT 
		@passenger_count as passenger_count,
		@trip_distance as trip_distance,
		@trip_time_in_secs as trip_time_in_secs,
		[dbo].[fnCalculateDistance] (
			@pickup_latitude,
			@pickup_longitude,
			@dropoff_latitude,
			@dropoff_longitude) as direct_distance';

  DECLARE @lmodel2 varbinary(max);
  
  -- Get the latest non-real-time scoring model
  SET @lmodel2 = (SELECT TOP 1
			[Model]
			FROM [dbo].[NYCTaxiModel]
			WHERE IsRealTimeScoring = 0
			ORDER BY [CreatedOn] DESC);

  EXEC sp_execute_external_script @language = N'R',
	@script = N'
		mod <- unserialize(as.raw(model));
		print(summary(mod))
		OutputDataSet<-rxPredict(modelObject = mod, 
data = InputDataSet, 
					outData = NULL, predVarNames = "Score", 
					type = "response", 
writeModelVars = FALSE, 
overwrite = TRUE);
			str(OutputDataSet)
			print(OutputDataSet)',
		@input_data_1 = @inquery,
		@params = N'@model varbinary(max),
@passenger_count int,
@trip_distance float,
					@trip_time_in_secs INT ,
					@pickup_latitude FLOAT ,
					@pickup_longitude FLOAT ,
					@dropoff_latitude FLOAT ,
					@dropoff_longitude FLOAT',
        @model = @lmodel2,
		@passenger_count =@passenger_count ,
		@trip_distance=@trip_distance,
		@trip_time_in_secs=@trip_time_in_secs,
		@pickup_latitude=@pickup_latitude,
		@pickup_longitude=@pickup_longitude,
		@dropoff_latitude=@dropoff_latitude,
		@dropoff_longitude=@dropoff_longitude
  WITH RESULT SETS ((Score FLOAT));

END
GO
