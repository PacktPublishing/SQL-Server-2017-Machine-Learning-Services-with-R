SELECT 
	[external_script_request_id] 
  , [language]
  , [degree_of_parallelism]
  , [external_user_name]
FROM sys.dm_external_script_requests;
