-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimTransactionType

CREATE   PROCEDURE assumed.LoadDimTransactionType
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT
			 ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate	= SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimTransactionType
		
		--OPENBOX--------------------------------
		SELECT *
		  INTO #DimTransactionType
		  FROM( 
			SELECT
				 TransactionTypeCode= CAST(tp.sCode        AS VARCHAR(10))
				,TransactionType	= CAST(tp.sPremiumType AS VARCHAR(50))
				,Category			= 'Premium Transaction Type'
				,Source 			= 'OPENBOX'
			FROM SRC_LLOYDS_DB.dbo.TypeofPremium tp
			UNION ALL
			SELECT
				 TransactionTypeCode= CAST(tod.sCode      AS VARCHAR(10))
				,TransactionType 	= CAST(tod.sDeduction AS VARCHAR(50))
				,Category 			= 'Deduction Transaction Type'
				,Source 			= 'OPENBOX'
			FROM SRC_LLOYDS_DB.dbo.TypeofDeduction tod	
			UNION ALL
			SELECT
				 TransactionTypeCode= tt.sTransactionCode
				,TransactionType	= tt.sTransaction
				,Category			= 'Claim Transaction Type'
				,Source				= 'OPENBOX'
			 FROM SRC_LLOYDS_DB.dbo.TRANSACTIONTYPE tt
			WHERE EXISTS (SELECT DISTINCT cm.lTransactionTypeKey
						    FROM SRC_LLOYDS_DB.dbo.ClaimMovement AS cm
						   WHERE cm.lTransactionTypeKey = tt.lTransactionTypeKey)
			--TIRS------------------------------------
			UNION ALL
			SELECT
				 TransactionTypeCode= CAST(xtc.trans_cd AS VARCHAR(10))
				,TransactionType	= CAST(xtc.desc_txt AS VARCHAR(50))
				,Category			= 'Claim Transaction Type'
				,Source 			= 'TIRS'
			FROM SRC_TIRS_DB.dbo.xrf_trans_cds xtc
			UNION ALL
			SELECT
				 TransactionTypeCode= CAST(xdt.doc_type_cd AS VARCHAR(10))
				,TransactionType 	= CAST(xdt.desc_txt AS VARCHAR(50))
				,Category 			= 'Document Type'
				,Source 			= 'TIRS'
			FROM SRC_TIRS_DB.dbo.xrf_doc_type xdt
			UNION ALL
			SELECT
				 TransactionTypeCode= 'MIX'
				,TransactionType 	= 'Mixed Document Types'
				,Category 			= 'Document Type'
				,Source 			= 'TIRS'
			UNION ALL
			SELECT
				 TransactionTypeCode= 'FIRV IBNR'
				,TransactionType 	= 'FIRV IBNR'
				,Category 			= 'FIRV IBNR'
				,Source 			= 'TIRS'
			--Topside--------------------------------
			UNION ALL
			SELECT
				 TransactionTypeCode= 'Topside'
				,TransactionType	= 'Topside'
				,Category			= 'Topside'
				,Source 			= 'Topside'
			--Other--------------------------------
			UNION ALL
			SELECT
				 TransactionTypeCode= 'N/A'
				,TransactionType 	= 'N/A'
				,Category 			= 'N/A'
				,Source 			= 'N/A'
			UNION ALL
			SELECT
				 TransactionTypeCode= 'Uncoded'
				,TransactionType 	= 'Uncoded'
				,Category 			= 'Uncoded'
				,Source 			= 'Uncoded'
		) t

		-- Loading logic
		ALTER TABLE #DimTransactionType ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT('', s.TransactionType))
		FROM #DimTransactionType s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(TransactionTypeCode VARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL
		,Category VARCHAR(30) COLLATE DATABASE_DEFAULT NOT NULL
		,Source VARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (TransactionTypeCode, Category, Source)
		)

		INSERT INTO #LoadOperation
			(TransactionTypeCode
			,Category
			,Source
			,Operation
			)
		SELECT TransactionTypeCode = COALESCE(t.TransactionTypeCode COLLATE DATABASE_DEFAULT, s.TransactionTypeCode COLLATE DATABASE_DEFAULT)
			,Category = COALESCE(t.Category COLLATE DATABASE_DEFAULT, s.Category COLLATE DATABASE_DEFAULT)
			,Source = COALESCE(t.Source COLLATE DATABASE_DEFAULT, s.Source COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.DimTransactionTypeID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.DimTransactionType t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimTransactionType s
			ON s.TransactionTypeCode = t.TransactionTypeCode COLLATE DATABASE_DEFAULT
			AND s.Category = t.Category COLLATE DATABASE_DEFAULT
			AND s.Source = t.Source COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimTransactionType t
		INNER JOIN #LoadOperation lo
			ON lo.TransactionTypeCode = t.TransactionTypeCode
			AND lo.Category = t.Category
			AND lo.Source = t.Source
			AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimTransactionType
			(StartDate
			,TransactionTypeCode
			,TransactionType
			,Category
			,Source
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.TransactionTypeCode
			,s.TransactionType
			,s.Category
			,s.Source
			,s.DataHash
		FROM #DimTransactionType s
		INNER JOIN #LoadOperation lo
			ON lo.TransactionTypeCode = s.TransactionTypeCode COLLATE DATABASE_DEFAULT
			AND lo.Category = s.Category COLLATE DATABASE_DEFAULT
			AND lo.Source = s.Source COLLATE DATABASE_DEFAULT
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
