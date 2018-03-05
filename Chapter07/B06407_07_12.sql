-- Create a new role 
CREATE ROLE TutorialDBRUser AUTHORIZATION dbo
GO

-- Assign the role to a new member JulieGuest2 so that the login
-- can connect to the database Tutorial DB.
ALTER ROLE TutorialDBRUser ADD MEMBER JulieGuest2
GO

-- Allow members of TutorialDBRUser to read and write. 
ALTER ROLE db_datareader ADD MEMBER TutorialDBRUser
GO

ALTER ROLE db_datareader ADD MEMBER TutorialDBRUser
GO

-- Allow members of TutorialDBRUser to run external script
GRANT EXECUTE ANY EXTERNAL SCRIPT TO [TutorialDBRUser]
GO

-- Allow members of TutorialDBRUser to run a specific 
-- stored procedure.
GRANT EXECUTE ON [dbo].[predict_rentals] TO [TutorialDBRUser]
GO
