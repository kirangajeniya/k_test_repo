-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimAccidentYear

CREATE   PROCEDURE assumed.LoadDimAccidentYear
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimAccidentYear
		
		SELECT AccidentYear = '-1'
			,CAT_KEY = 'Uncoded'
			,CatCode = 'Uncoded'
			,L04 = 'Uncoded'
		INTO #DimAccidentYear
		UNION ALL (
		SELECT DISTINCT tch.AccidentYear
			,CAT_KEY = NULLIF(tch.CAT_KEY, '')
			,CatCode = NULLIF(tch.CatCode, '')
			,tch.L04
		FROM EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY tch
		UNION
		SELECT DISTINCT rtct.AccidentYear
			,CAT_KEY = NULLIF(rtct.CAT_KEY, '')
			,CatCode = NULLIF(rtct.CatCode, '')
			,rtct.L04
		FROM EDW_PREPROD.dbo.RS_TIRS_CLAIMS_TOPSIDE rtct
		UNION
		-- manual entries - data that exists historically in RS_TIRS_CLAIMS, but isn't generated anymore by the code, so not clear where the data came from originally
		SELECT x.AccidentYear
			,x.CAT_KEY	
			,x.CatCode
			,x.L04
		FROM (
			VALUES('2010', NULL, NULL, '2020')
				,('2019', '1308', 'CVD20', '2020CAT01')
			) x (AccidentYear, CAT_KEY, CatCode, L04)
		UNION
		SELECT DISTINCT AccidentYear = CAST(COALESCE(YEAR(tcl.DateOfLoss), tcl.YOA) AS VARCHAR(4))
			,CAT_KEY = NULLIF(tcl.CatCode, '-9999')
			,CatCode = NULL
			,L04 = x.L04
		FROM EDW_PREPROD.lloyds.TBL_CLAIM_LLYDS tcl
		OUTER APPLY (
			SELECT TOP 1 L04 = NULLIF(l4m.L4, '')
			FROM DM_DataStandard.dbo.L4Mapping l4m
			WHERE ISNULL(NULLIF(l4m.accidentyear, '%'), ISNULL(YEAR(tcl.DateOfLoss), '')) = ISNULL(YEAR(tcl.DateOfLoss), '')
				AND ISNULL(NULLIF(l4m.cat_key, '%'), COALESCE(tcl.CatCode, '')) = COALESCE(tcl.CatCode, '')
				AND ISNULL(NULLIF(l4m.Source_System, '%'), 'Openbox') = 'Openbox'
			ORDER BY l4m.Priority_Key DESC
			) x
		WHERE tcl.BusinessType = 'Assumed'
			AND tcl.PolicySource = 'Openbox'
		)
		
		INSERT INTO #DimAccidentYear
			(AccidentYear
			,CAT_KEY
			,CatCode
			,L04
			)
		SELECT x.AccidentYear
			,x.CAT_KEY
			,x.CatCode
			,x.L04
		FROM (
			SELECT dacy.AccidentYear
				,dacy.CAT_KEY
				,CatCode = NULL
				,L04 = dacy.AccidentYear
			FROM #DimAccidentYear dacy
			WHERE dacy.AccidentYear != '-1'
			) x
		LEFT JOIN #DimAccidentYear dacy
			ON dacy.AccidentYear = x.AccidentYear
			AND COALESCE(dacy.CAT_KEY, '%^&') = COALESCE(x.CAT_KEY, '%^&')
			AND COALESCE(dacy.CatCode, '%^&') = COALESCE(x.CatCode, '%^&')
			AND dacy.L04 = x.L04
		WHERE dacy.AccidentYear IS NULL
		

		-- Loading logic
		ALTER TABLE #DimAccidentYear ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = 0x0000000000000000000000000000000000000000
		FROM #DimAccidentYear s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(AccidentYear CHAR(7) COLLATE DATABASE_DEFAULT NOT NULL
		,CAT_KEY VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,CatCode VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,L04 VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (AccidentYear, CAT_KEY, CatCode, L04)
		)

		INSERT INTO #LoadOperation
			(AccidentYear
			,CAT_KEY
			,CatCode
			,L04
			,Operation
			)
		SELECT AccidentYear = COALESCE(t.AccidentYear COLLATE DATABASE_DEFAULT, s.AccidentYear COLLATE DATABASE_DEFAULT)
			,CAT_KEY = COALESCE(t.CAT_KEY COLLATE DATABASE_DEFAULT, s.CAT_KEY COLLATE DATABASE_DEFAULT)
			,CatCode = COALESCE(t.CatCode COLLATE DATABASE_DEFAULT, s.CatCode COLLATE DATABASE_DEFAULT)
			,L04 = COALESCE(t.L04 COLLATE DATABASE_DEFAULT, s.L04 COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.DimAccidentYearID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.DimAccidentYear t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimAccidentYear s
			ON s.AccidentYear = t.AccidentYear COLLATE DATABASE_DEFAULT
			AND COALESCE(s.CAT_KEY, '^&*') = COALESCE(t.CAT_KEY, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.CatCode, '^&*') = COALESCE(t.CatCode, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.L04, '^&*') = COALESCE(t.L04, '^&*') COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimAccidentYear t
		INNER JOIN #LoadOperation lo
			ON lo.AccidentYear = t.AccidentYear
			AND COALESCE(lo.CAT_KEY, '^&*') = COALESCE(t.CAT_KEY, '^&*')
			AND COALESCE(lo.CatCode, '^&*') = COALESCE(t.CatCode, '^&*')
			AND COALESCE(lo.L04, '^&*') = COALESCE(t.L04, '^&*')
			AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimAccidentYear
			(StartDate
			,AccidentYear
			,CAT_KEY
			,CatCode
			,L04
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.AccidentYear
			,s.CAT_KEY
			,s.CatCode
			,s.L04
			,s.DataHash
		FROM #DimAccidentYear s
		INNER JOIN #LoadOperation lo
			ON lo.AccidentYear = s.AccidentYear COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.CAT_KEY, '^&*') = COALESCE(s.CAT_KEY, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.CatCode, '^&*') = COALESCE(s.CatCode, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.L04, '^&*') = COALESCE(s.L04, '^&*') COLLATE DATABASE_DEFAULT
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
