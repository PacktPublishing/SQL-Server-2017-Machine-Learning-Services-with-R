-- Only applicable for SQL Server 2017
DECLARE @logit_model VARBINARY(MAX) = 
	(SELECT TOP 1 [Model] 
	FROM [dbo].[NYCTaxiModel]
	WHERE [IsRealTimeScoring] = 1
	ORDER BY [CreatedOn] DESC);

WITH d AS (
	SELECT	2 AS passenger_count, 
			10 AS trip_distance, 
			1950 AS trip_time_in_secs, 
			dbo.fnCalculateDistance(47.643272, 
				-122.127235,  
				47.620529, 
				-122.349297) AS direct_distance)
SELECT  *
FROM PREDICT( MODEL = @logit_model, DATA = d) 
WITH (tipped_Pred FLOAT) p;
