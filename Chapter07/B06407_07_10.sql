DECLARE @logit_model VARBINARY(MAX) = 
	(SELECT TOP 1 [Model] 
	FROM [dbo].[NYCTaxiModel]
	WHERE [IsRealTimeScoring] = 1
	ORDER BY [CreatedOn] DESC);


EXEC dbo.sp_rxPredict 
    @model = @logit_model,
    @inputData = N'SELECT
				2 AS passenger_count, 
				10 AS trip_distance, 
				1950 AS trip_time_in_secs, 
				dbo.fnCalculateDistance(47.643272, 
					-122.127235,  
					47.620529, 
					-122.349297) AS direct_distance';
