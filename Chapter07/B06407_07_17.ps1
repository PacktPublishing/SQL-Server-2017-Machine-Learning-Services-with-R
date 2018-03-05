
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server=.;Database=Taxi;Integrated Security=True"
$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.CommandText = "EXEC [dbo].[uspPredictTipSingleMode] 
    @passenger_count	= 2
	,@trip_distance	= 10
	,@trip_time_in_secs	= 35
	,@pickup_latitude	= 47.643272
	,@pickup_longitude	= -122.127235
	,@dropoff_latitude	= 47.620529
	,@dropoff_longitude	= -122.349297
	 "
$SqlCmd.Connection = $SqlConnection
$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$SqlAdapter.SelectCommand = $SqlCmd
$DataSet = New-Object System.Data.DataSet
$SqlAdapter.Fill($DataSet)
$SqlConnection.Close()
$DataSet.Tables[0] 
