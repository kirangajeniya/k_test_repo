-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: Load_MappingTreatyType

CREATE   PROCEDURE assumed.Load_MappingTreatyType
AS
BEGIN TRY
	DROP TABLE IF EXISTS #Parameters

	SELECT
		 ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
		,NewStartDate	= SYSDATETIME()
	INTO #Parameters

	BEGIN TRANSACTION
		;WITH SRC_Mapping AS
		(SELECT DISTINCT 
				TRTY_FAC_NAME		= m.TRTY_FAC_NAME		COLLATE DATABASE_DEFAULT,
				PRO_RATA_XOL_NAME	= m.PRO_RATA_XOL_NAME	COLLATE DATABASE_DEFAULT,
				RPT_OFF_NAME		= m.RPT_OFF_NAME		COLLATE DATABASE_DEFAULT,
				TREATY_TYPE		= CASE  WHEN TRTY_FAC_NAME = 'FAC' AND PRO_RATA_XOL_NAME = 'Pro Rata' AND RPT_OFF_NAME LIKE '%Fac%'
										THEN 'FAP'
										WHEN TRTY_FAC_NAME = 'FAC' AND PRO_RATA_XOL_NAME = 'Pro Rata'
										THEN 'RTY'
										WHEN TRTY_FAC_NAME = 'FAC' AND PRO_RATA_XOL_NAME = 'XOL' AND RPT_OFF_NAME LIKE '%Fac%'
										THEN 'FNP'
										WHEN TRTY_FAC_NAME = 'FAC' AND PRO_RATA_XOL_NAME = 'XOL'
										THEN 'RXL'
										WHEN TRTY_FAC_NAME = 'Treaty' AND PRO_RATA_XOL_NAME = 'Pro Rata'
										THEN 'RTY'
										WHEN TRTY_FAC_NAME = 'Treaty' AND PRO_RATA_XOL_NAME = 'XOL'
										THEN 'RXL'
										ELSE 'Uncoded' END  COLLATE DATABASE_DEFAULT,
				CreatedDate		= p.NewStartDate
		  FROM dbo.MAP_CONTRACT_EDW	AS m
		 CROSS JOIN #Parameters		AS p
		 WHERE ISNULL(PLCY_SRC,'') <> ''
		   AND TRTY_FAC_NAME <> 'Not classified at this level'
		)
		MERGE Assumed.MappingTreatyType	AS t
		USING SRC_Mapping				AS s
		ON  s.TRTY_FAC_NAME		= t.TRTY_FAC_NAME
		AND s.PRO_RATA_XOL_NAME	= t.PRO_RATA_XOL_NAME
		AND s.RPT_OFF_NAME		= t.RPT_OFF_NAME

		WHEN NOT MATCHED BY TARGET
		THEN INSERT 
			(TRTY_FAC_NAME
			,PRO_RATA_XOL_NAME
			,RPT_OFF_NAME
			,TREATY_TYPE
			,CreatedDate
			)
			VALUES
			(s.TRTY_FAC_NAME
			,s.PRO_RATA_XOL_NAME
			,s.RPT_OFF_NAME
			,s.TREATY_TYPE
			,s.CreatedDate
			)
		WHEN MATCHED 
		THEN UPDATE 
			 SET t.TREATY_TYPE	= s.TREATY_TYPE
		WHEN NOT MATCHED BY SOURCE
		THEN DELETE;

	DECLARE @RowsProcessed		BIGINT		= @@ROWCOUNT
	DECLARE @ProcessName		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
	DECLARE @LastIdentity		BIGINT		= SCOPE_IDENTITY()
	DECLARE @ProcessingStarted	DATETIME	= (SELECT p.NewStartDate FROM #Parameters p)
	DECLARE @ProcessingEnded	DATETIME	= GETDATE()
	DECLARE @SourceDataDate		DATETIME	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

	COMMIT

	EXEC ETL.dbo.update_etl_controller 
		 @ps_process_name			= @ProcessName
		,@pn_rows_processed			= @RowsProcessed
		,@pdt_data_datetime			= @SourceDataDate
		,@pdt_process_start_datetime= @ProcessingStarted
		,@pdt_process_end_datetime	= @ProcessingEnded
		,@pn_error_number			= 0
		,@ps_comment				= NULL
		,@pn_max_processed_event_id = @LastIdentity
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0
	BEGIN
		ROLLBACK
	END

	DECLARE @ErrorDescription	VARCHAR(8000)	= CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
	DECLARE @ErrorNumber		INT				= ERROR_NUMBER()
	DECLARE @ErrorMessage		VARCHAR(8000)	= ERROR_MESSAGE()
	DECLARE @ErrorSeverity		INT				= ERROR_SEVERITY()
	DECLARE @ErrorState			INT				= ERROR_STATE()
	DECLARE @ProcessNameC		VARCHAR(100)	= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
	DECLARE @ProcessingStartedC DATETIME		= (SELECT p.NewStartDate FROM #Parameters p)
	DECLARE @ProcessingEndedC	DATETIME		= GETDATE()
	DECLARE @SourceDataDateC	DATETIME		= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

	EXEC ETL.dbo.update_etl_controller 
		 @ps_process_name			= @ProcessNameC
		,@pn_rows_processed			= 0
		,@pdt_data_datetime			= @SourceDataDateC
		,@pdt_process_start_datetime= @ProcessingStartedC
		,@pdt_process_end_datetime	= @ProcessingEndedC
		,@pn_error_number			= @ErrorNumber
		,@ps_comment				= @ErrorDescription
		,@pn_max_processed_event_id = 0

	EXEC ETL.dbo.insert_error_log 
		 @process_name	= @ProcessNameC
		,@object_name	= 0
		,@user_message	= @ErrorDescription
		,@status		= 0
		,@remedy		= 'Contact EDW team'

	RAISERROR(@ErrorDescription, @ErrorSeverity, @ErrorState)
END CATCH