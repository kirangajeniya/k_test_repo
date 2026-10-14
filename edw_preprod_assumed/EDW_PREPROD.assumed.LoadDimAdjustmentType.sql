-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimAdjustmentType

CREATE   PROCEDURE assumed.LoadDimAdjustmentType
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimAdjustmentType
		
		SELECT DISTINCT AdjustmentType
		INTO #DimAdjustmentType
		FROM (
			SELECT x.AdjustmentType
			FROM (VALUES('Uncoded')
				,('N/A')
				,('Minus Informational')
				,('Plus Informational')
				,('Topside')
				,('TopSide Plus')
				,('TopSide Minus')
				,('CutOff')
				) x (AdjustmentType)
				UNION
				/* Temporary - for migration*/
				SELECT DISTINCT AdjustmentType
				FROM EDW_PREPROD.dbo.RS_TIRS_UNDERWRITING_OLD
			) s
			
		-- Loading logic
		ALTER TABLE #DimAdjustmentType ADD DataHash BINARY(20) NULL;

		UPDATE s
		SET DataHash = 0x0000000000000000000000000000000000000000
		FROM #DimAdjustmentType s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(AdjustmentType VARCHAR(400) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (AdjustmentType)
		)

		INSERT INTO #LoadOperation
			(AdjustmentType
			,Operation
			)
		SELECT AdjustmentType = left(COALESCE(t.AdjustmentType COLLATE DATABASE_DEFAULT, s.AdjustmentType COLLATE DATABASE_DEFAULT), 400)
			,Operation = CASE WHEN t.DimAdjustmentTypeID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.DimAdjustmentType t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimAdjustmentType s
			ON s.AdjustmentType = t.AdjustmentType COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimAdjustmentType t
		INNER JOIN #LoadOperation lo
			ON lo.AdjustmentType = t.AdjustmentType
			AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimAdjustmentType
			(StartDate
			,AdjustmentType
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.AdjustmentType
			,s.DataHash
		FROM #DimAdjustmentType s
		INNER JOIN #LoadOperation lo
			ON lo.AdjustmentType = s.AdjustmentType COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('I', 'U')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U')), 0)
		DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
		DECLARE @ProcessingStarted DATETIME = (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEnded DATETIME = GETDATE()
		DECLARE @SourceDataDate DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessName
			,@pn_rows_processed = @RowsProcessed
			,@pdt_data_datetime = @SourceDataDate
			,@pdt_process_start_datetime = @ProcessingStarted
			,@pdt_process_end_datetime = @ProcessingEnded
			,@pn_error_number = 0
			,@ps_comment = NULL
			,@pn_max_processed_event_id = @LastIdentity
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			ROLLBACK
		END

		DECLARE @ErrorDescription VARCHAR(8000) = CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @ErrorNumber INT = ERROR_NUMBER()
		DECLARE @ErrorMessage VARCHAR(8000) = ERROR_MESSAGE()
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
		DECLARE @ErrorState INT = ERROR_STATE()
		DECLARE @ProcessNameC VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME = (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEndedC DATETIME = GETDATE()
		DECLARE @SourceDataDateC DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessNameC
			,@pn_rows_processed = 0
			,@pdt_data_datetime = @SourceDataDateC
			,@pdt_process_start_datetime = @ProcessingStartedC
			,@pdt_process_end_datetime = @ProcessingEndedC
			,@pn_error_number = @ErrorNumber
			,@ps_comment = @ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log @process_name = @ProcessNameC
			,@object_name = 0
			,@user_message = @ErrorDescription
			,@status = 0
			,@remedy = 'Contact EDW team'

		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState)
	END CATCH
END
