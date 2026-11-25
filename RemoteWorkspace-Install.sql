:ON ERROR EXIT
-- Remote Workspace v0.3.0 - SQL Server 2016+
-- Run in SSMS as an authorized database administrator.
-- Creates a new database only; refuses to overwrite an existing database.
USE master;
GO
IF DB_ID(N'RemoteWorkspace') IS NOT NULL
    THROW 50001, 'RemoteWorkspace already exists. Stop and review before installing.', 1;
GO
-- Execute this script with SQLCMD mode enabled (Query > SQLCMD Mode).
CREATE DATABASE RemoteWorkspace;
GO
USE RemoteWorkspace;
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;
CREATE TABLE dbo.Servers (
    ServerId uniqueidentifier NOT NULL CONSTRAINT DF_Servers_Id DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    Name nvarchar(256) NOT NULL,
    Hostname nvarchar(253) NOT NULL,
    Port int NOT NULL CONSTRAINT DF_Servers_Port DEFAULT 3389 CHECK (Port BETWEEN 1 AND 65535),
    Folder nvarchar(1024) NOT NULL CONSTRAINT DF_Servers_Folder DEFAULT N'',
    Description nvarchar(max) NULL,
    RocketId uniqueidentifier NULL,
    ModifiedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedBy sysname NOT NULL DEFAULT ORIGINAL_LOGIN(),
    Version rowversion NOT NULL,
    CONSTRAINT CK_Servers_Name CHECK (LEN(LTRIM(RTRIM(Name))) > 0),
    CONSTRAINT CK_Servers_Host CHECK (LEN(LTRIM(RTRIM(Hostname))) > 0)
);
CREATE UNIQUE INDEX UX_Servers_RocketId ON dbo.Servers(RocketId) WHERE RocketId IS NOT NULL;
CREATE TABLE dbo.Favorites (
    UserSID varbinary(85) NOT NULL,
    ServerId uniqueidentifier NOT NULL REFERENCES dbo.Servers(ServerId) ON DELETE CASCADE,
    CONSTRAINT PK_Favorites PRIMARY KEY (UserSID, ServerId)
);
CREATE TABLE dbo.UserPreferences (
    UserSID varbinary(85) NOT NULL PRIMARY KEY,
    Settings nvarchar(max) NOT NULL CHECK (ISJSON(Settings)=1)
);
CREATE TABLE dbo.AuditLog (
    AuditId bigint IDENTITY PRIMARY KEY,
    EventTime datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    LoginName sysname NOT NULL DEFAULT ORIGINAL_LOGIN(),
    Action varchar(10) NOT NULL,
    ServerId uniqueidentifier NOT NULL,
    BeforeData nvarchar(max) NULL,
    AfterData nvarchar(max) NULL
);
CREATE TABLE dbo.SchemaVersion (Version int PRIMARY KEY, InstalledAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME());
INSERT dbo.SchemaVersion(Version) VALUES (1);
CREATE ROLE RW_Users;
CREATE ROLE RW_Admins;
ALTER ROLE RW_Users ADD MEMBER RW_Admins;
GRANT SELECT ON dbo.Servers TO RW_Users;
GRANT SELECT ON dbo.SchemaVersion TO RW_Users;
GRANT INSERT, UPDATE, DELETE ON dbo.Servers TO RW_Admins;
GRANT SELECT ON dbo.AuditLog TO RW_Admins;
EXEC(N'CREATE VIEW dbo.MyFavorites AS SELECT ServerId FROM dbo.Favorites WHERE UserSID = SUSER_SID(ORIGINAL_LOGIN());');
EXEC(N'CREATE PROCEDURE dbo.SetFavorite @ServerId uniqueidentifier, @Enabled bit AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 IF @Enabled = 1 BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.Favorites WITH (UPDLOCK,HOLDLOCK) WHERE UserSID=SUSER_SID(ORIGINAL_LOGIN()) AND ServerId=@ServerId)
   INSERT dbo.Favorites(UserSID,ServerId) VALUES(SUSER_SID(ORIGINAL_LOGIN()),@ServerId);
 END ELSE DELETE dbo.Favorites WHERE UserSID=SUSER_SID(ORIGINAL_LOGIN()) AND ServerId=@ServerId;
 COMMIT;
END');
GRANT SELECT ON dbo.MyFavorites TO RW_Users;
GRANT EXECUTE ON dbo.SetFavorite TO RW_Users;
EXEC(N'CREATE TRIGGER dbo.AuditServers ON dbo.Servers AFTER INSERT, UPDATE, DELETE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Action,ServerId,BeforeData,AfterData)
 SELECT CASE WHEN d.ServerId IS NULL THEN ''INSERT'' WHEN i.ServerId IS NULL THEN ''DELETE'' ELSE ''UPDATE'' END,
 COALESCE(i.ServerId,d.ServerId),
 CASE WHEN d.ServerId IS NOT NULL THEN (SELECT d.Name,d.Hostname,d.Port,d.Folder,d.Description,d.RocketId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) END,
 CASE WHEN i.ServerId IS NOT NULL THEN (SELECT i.Name,i.Hostname,i.Port,i.Folder,i.Description,i.RocketId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) END
 FROM inserted i FULL OUTER JOIN deleted d ON i.ServerId=d.ServerId;
END');
COMMIT;
GO
SELECT DB_NAME() AS DatabaseName, Version AS SchemaVersion FROM dbo.SchemaVersion;
GO
