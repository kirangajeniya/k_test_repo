-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimDocument

CREATE   PROCEDURE [assumed].[LoadDimDocument]
	@fullLoad BIT = 0
AS
BEGIN
    BEGIN TRY
		/*
		EXEC assumed.LoadDimDocument 1

		DECLARE @fullLoad BIT = 0
		--*/

		--------------------------------------------------------------------------------		
		--	#Parameters
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #Parameters

  		SELECT
			 ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate	= SYSDATETIME()
			,ChangedSince	= (SELECT IIF(@fullLoad = 1, 0,
            (
				SELECT  COALESCE(MIN(ad.doc_key), 0x7FFFFFFF)
				FROM SRC_TIRS_DB.dbo.acct_doc ad
				INNER JOIN (
					SELECT ChangedSinceDate = MAX(x.ChangeDate)
					FROM assumed.DimDocument dd
					CROSS APPLY (
						VALUES(dd.StartDate)
							,(dd.UpdateDate)
						) x (ChangeDate)
					) c
					ON c.ChangedSinceDate < ad.touch_dt
					)
				)
			)
					INTO #Parameters      
		--------------------------------------------------------------------------------		
		-- Staging logic
		--------------------------------------------------------------------------------
        DROP TABLE IF EXISTS #DimDocument
		CREATE TABLE #DimDocument
		(
			 [doc_key]				VARCHAR(25) NULL
			,[SourceSysKey]			TINYINT NULL
			,[invoice_no]			VARCHAR(50) NULL
			,[brkr_ref]				VARCHAR(25) NULL
			,[their_reference]		VARCHAR(101) NULL
			,[SourceCreatedDate]	DATETIME2 (7) NULL
			,[Authoriser]			VARCHAR(41) NULL
			,[AuthorisedDate]		DATETIME2 (7) NULL
		);

		INSERT INTO #DimDocument
		(
			 [doc_key]
			,SourceSysKey
			,[invoice_no]
			,[brkr_ref]
			,[their_reference]
			,SourceCreatedDate
			,Authoriser
			,AuthorisedDate
		)
        SELECT doc_key = 'N/A'
			,SourceSysKey = NULL
			,invoice_no = 'N/A'
			,brkr_ref = 'N/A'
			,their_reference = 'N/A'
			,SourceCreatedDate = NULL
			,Authoriser = 'N/A'
			,AuthorisedDate = NULL
        UNION ALL
        SELECT doc_key = 'Uncoded'
			,SourceSysKey = NULL
			,invoice_no = 'Uncoded'
			,brkr_ref = 'Uncoded'
			,their_reference = 'Uncoded'
			,SourceCreatedDate = NULL
			,Authoriser = 'Uncoded'
			,AuthorisedDate = NULL
		UNION ALL
        SELECT
			 [doc_key]
			,SourceSysKey
			,[invoice_no]
			,[brkr_ref]
			,[their_reference] = CONCAT([invoice_no], ' ', [brkr_ref])
			,SourceCreatedDate
			,Authoriser
			,AuthorisedDate
        FROM (
            
		--------------------------------------------------------------------------------		
		-- TIRS 
		--------------------------------------------------------------------------------
			 SELECT 
				 doc_key	= CONVERT([varchar](25), NULLIF(doc_key,''))
				,SourceSysKey = 4
				,invoice_no = CONVERT([varchar](50), NULLIF(TRIM(invoice_no),'')) COLLATE DATABASE_DEFAULT 
				,brkr_ref	= CONVERT([varchar](25), NULLIF(TRIM(brkr_ref),''))   COLLATE DATABASE_DEFAULT
				,SourceCreatedDate = ad.perm_dt
				,Authoriser = CONCAT(su.first_name, ' ', su.last_name)
				,AuthorisedDate = ad.perm_dt
			  FROM SRC_TIRS_DB.dbo.acct_doc AS ad
				LEFT JOIN SRC_TIRS_DB.dbo.sec_users su
					ON su.employee_key = ad.perm_id
				WHERE doc_key >= (SELECT ChangedSince from #Parameters)
		 ) AS Document
		--------------------------------------------------------------------------------		
		-- OPENBOX 
		--------------------------------------------------------------------------------
			 UNION ALL
			 SELECT doc_key = CONVERT(VARCHAR(25), pl.lPolicyLiabilityKey)
				,SourceSysKey = 1
				,invoice_no = NULL
				,brkr_ref = ps.sUMR
				,their_reference = COALESCE(ps.sUMR, '')
				,SourceCreatedDate = ps.dtDateEntered
				,Authoriser = NULL
				,AuthorisedDate = ps.dtDateEntered
			FROM SRC_LLOYDS_DB.dbo.PolicyLiability pl
			INNER JOIN SRC_LLOYDS_DB.dbo.Policy p
				ON p.lPolicyKey = pl.lPolicyKey
				AND p.lActivePolicyActivityKey = pl.lPolicyActivityKey
			INNER JOIN SRC_LLOYDS_DB.dbo.PolicySection ps
				ON ps.lPolicySectionKey = pl.lPolicySectionKey
				AND ps.lPolicyActivityKey = pl.lPolicyActivityKey
			INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity pa
				ON pa.lPolicyActivityKey = pl.lPolicyActivityKey
			INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer torl
				ON torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
			INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup topg
				ON topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
				AND topg.sCode = 'RI'
			

		-- check/enforce uniqueness on the dimension source data
		CREATE UNIQUE INDEX IDX_#DimDocument ON #DimDocument(doc_key, SourceSysKey)

		ALTER TABLE #DimDocument ADD DataHash		BINARY(20) NULL
		ALTER TABLE #DimDocument ADD DataHashType1	BINARY(20) NULL

		--------------------------------------------------------------------------------		
		-- Hash calculation
		--------------------------------------------------------------------------------
		UPDATE s
		   SET DataHash		= HASHBYTES('SHA1', CONCAT_WS ('|', s.invoice_no,s.brkr_ref,s.their_reference))					-- Primary hash
			 , DataHashType1= HASHBYTES('SHA1', CONCAT_WS ('|', s.SourceCreatedDate,s.Authoriser,s.AuthorisedDate))	-- Secondary hash
		  FROM #DimDocument s

		--------------------------------------------------------------------------------		
		-- #LoadOperation
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation (
			 doc_key	VARCHAR(25) COLLATE DATABASE_DEFAULT NULL
			,SourceSysKey TINYINT NULL
			,Operation	CHAR(1) NOT NULL
			,UNIQUE (doc_key, SourceSysKey)
		)

		INSERT INTO #LoadOperation (
			 doc_key
			,SourceSysKey
			,Operation
			)
		SELECT
			 doc_key	= COALESCE(t.doc_key COLLATE DATABASE_DEFAULT, s.doc_key COLLATE DATABASE_DEFAULT)
			,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
			,Operation	= CASE  WHEN t.DimDocumentID  IS NULL	THEN 'I' 
								WHEN s.DataHash IS NULL	THEN 'D'
								WHEN t.DataHash != s.DataHash AND t.DataHashType1 != s.DataHashType1 THEN 'U'								
								WHEN t.DataHash != s.DataHash THEN '2' 
								ELSE '1' END
		FROM (
			SELECT DimDocumentID
				,doc_key
				,SourceSysKey
				,DataHash
				,DataHashType1
			FROM assumed.DimDocument
			WHERE EndDate = '9999-12-31' 
				 AND ((SourceSysKey = 4 AND TRY_CONVERT(INT,doc_key) >= (SELECT ChangedSince from #Parameters))
					OR COALESCE(SourceSysKey, 0) != 4
					)
			) t
		FULL JOIN #DimDocument s
			ON COALESCE(s.doc_key, '^&*') = COALESCE(t.doc_key, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1

		--------------------------------------------------------------------------------		
		-- DimDocument loading
		--------------------------------------------------------------------------------
		BEGIN TRANSACTION

		UPDATE t
		   SET
			 invoice_no		= s.invoice_no
			,brkr_ref		= s.brkr_ref
			,their_reference = s.their_reference
			,SourceCreatedDate = s.SourceCreatedDate
			,Authoriser = s.Authoriser
			,AuthorisedDate = s.AuthorisedDate
			,DataHashType1	= s.DataHashType1
			,UpdateDate		= p.NewStartDate
		FROM assumed.DimDocument	AS t
		CROSS JOIN #Parameters		AS p
		INNER JOIN #LoadOperation	AS lo	ON  COALESCE(lo.doc_key, '^&*') = COALESCE(t.doc_key, '^&*')
			AND COALESCE(lo.SourceSysKey, 0) = COALESCE(t.SourceSysKey, 0)
											AND lo.Operation IN ('U', '1')
		INNER JOIN #DimDocument		AS s	ON  COALESCE(s.doc_key, '^&*') = COALESCE(t.doc_key, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.SourceSysKey, 0) = COALESCE(t.SourceSysKey, 0)

		UPDATE t
		   SET EndDate = p.ClosingEndDate
		  FROM assumed.DimDocument	AS t
		 CROSS JOIN #Parameters		AS p
		 INNER JOIN #LoadOperation	AS lo	ON  COALESCE(lo.doc_key, '^&*') = COALESCE(t.doc_key, '^&*')
			AND COALESCE(lo.SourceSysKey, 0) = COALESCE(t.SourceSysKey, 0)
											AND lo.Operation IN ('U', '2')
		 WHERE t.EndDate = '9999-12-31'

		INSERT INTO assumed.DimDocument
			(StartDate
			,doc_key
			,invoice_no
			,brkr_ref
			,their_reference
			,SourceCreatedDate
			,Authoriser
			,AuthorisedDate
			,DataHash
			,DataHashType1
			,UpdateDate
			,SourceSysKey
			)
		SELECT
			 StartDate	= p.NewStartDate
			,s.doc_key
			,s.invoice_no
			,s.brkr_ref
			,s.their_reference
			,s.SourceCreatedDate
			,s.Authoriser
			,s.AuthorisedDate
			,s.DataHash
			,s.DataHashType1
			,UpdateDate = p.NewStartDate
			,s.SourceSysKey
		FROM #DimDocument			AS s
		CROSS JOIN #Parameters p
		INNER JOIN #LoadOperation	AS lo	ON  COALESCE(lo.doc_key, '^&*') = COALESCE(s.doc_key, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.SourceSysKey, 0) = COALESCE(s.SourceSysKey, 0)
											AND lo.Operation IN ('I', 'U', '2')
		COMMIT TRANSACTION

		DECLARE @ProcessName		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed		BIGINT		= COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U', '1', '2')), 0)
		DECLARE @LastIdentity		BIGINT		= SCOPE_IDENTITY()
		DECLARE @ProcessingStarted	DATETIME	= (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEnded	DATETIME	= GETDATE()
		DECLARE @SourceDataDate		DATETIME	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

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

		DECLARE @ErrorDescription	VARCHAR(800)= LEFT(CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE()),800)
		DECLARE @ErrorNumber		INT			= ERROR_NUMBER()
		DECLARE @ErrorMessage		VARCHAR(800)= ERROR_MESSAGE()
		DECLARE @ErrorSeverity		INT			= ERROR_SEVERITY()
		DECLARE @ErrorState			INT			= ERROR_STATE()
		DECLARE @ProcessNameC		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME	= (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEndedC	DATETIME	= GETDATE()
		DECLARE @SourceDataDateC	DATETIME	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

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

		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState)
	END CATCH
END