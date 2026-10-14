-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimClaimTransaction

CREATE   PROCEDURE assumed.LoadDimClaimTransaction
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimDefault
		
		SELECT DimClaimNA = (
				SELECT DimClaimID
				FROM assumed.DimClaim
				WHERE claim_number = 'N/A'
					AND claim_code = 'N/A'
					AND claim_sect_code = 'N/A'
					AND SourceSysKey = 0
					AND EndDate = '9999-12-31'
			)
			,DimClaimUnc = (
				SELECT DimClaimID
				FROM assumed.DimClaim
				WHERE claim_number = 'Uncoded'
					AND claim_code = 'Uncoded'
					AND claim_sect_code = 'Uncoded'
					AND SourceSysKey = 0
					AND EndDate = '9999-12-31'
			)
			,DimBankDetailsNA = (
				SELECT DimBankDetailsID
				FROM assumed.DimBankDetails
				WHERE Account = 'N/A'
			)
		INTO #DimDefault
		
		DROP TABLE IF EXISTS #DimClaimTransaction
				
		SELECT   ATT_TIRS_CLM_ID = atc.BE_ID
			,ATT_CLM_TXN_ID = act.BE_ID
			,ClaimCode = CAST(atc.TIRS_CLM_CD AS VARCHAR(20))
			,ClaimSectionCode = CAST(atc.TIRS_CLM_CD AS VARCHAR(20))
			,ClaimTransactionCode = CAST(act.CLM_TXN_CD AS VARCHAR(20))
			,AlternativeClaimTransactionCode = NULL
			,PaymentMethodCode = CAST(ct.pymt_type_cd AS VARCHAR(3)) COLLATE DATABASE_DEFAULT
			,PaymentMethod = LEFT(pt.desc_txt, 30)
			,Source = CAST('TIRS' AS VARCHAR(20))
			,invoice_no = ct.invoice_no
			,brkr_ref = c.brkr_clm_ref
			,their_reference = CONCAT(ct.invoice_no, ' ', c.brkr_clm_ref)
			,SourceSysKey = 4
			,BankDetailCode = ct.account_key
			,SourceCreatedDate = ct.entry_tm
			,Authoriser = CONCAT(su.first_name,' ',su.last_name)
			,AuthorisedDate = ct.entry_tm
		INTO #DimClaimTransaction
		FROM SRC_TIRS_DB.dbo.claim c
		INNER JOIN SRC_TIRS_DB.dbo.claim_trans ct
			ON ct.clm_key = c.clm_key
		INNER JOIN SRC_TIRS_DB.dbo.sec_users su
          	ON su.employee_key = ct.create_id
		INNER JOIN SRC_TIRS_DB.dbo.xrf_pymt_types pt
			ON pt.pymt_type_cd = ct.pymt_type_cd
		INNER JOIN EDW_PREPROD.dbo.ATT_TIRS_CLM atc
			ON atc.TIRS_CLM_CD = CAST(c.clm_key AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
			AND SYSDATETIME() BETWEEN atc.START_DATE AND atc.END_DATE
		INNER JOIN EDW_PREPROD.dbo.ATT_CLM_TXN act
			ON act.CLM_TXN_CD = CAST(ct.trans_key AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
			AND SYSDATETIME() BETWEEN act.START_DATE AND act.END_DATE
		UNION ALL
		SELECT DISTINCT  ATT_TIRS_CLM_ID = NULL
			,ATT_CLM_TXN_ID = NULL
			,ClaimCode = CAST('N/A' AS VARCHAR(20))
			,ClaimSectionCode = CAST('N/A' AS VARCHAR(20))
			,ClaimTransactionCode = CAST(COALESCE(CONVERT(NVARCHAR(30), DateOfLoss, 101), YOA) + COALESCE(CATCODE, '') AS VARCHAR(20))
			,AlternativeClaimTransactionCode = NULL
			,PaymentMethodCode = 'N/A'
			,PaymentMethod = 'N/A'
			,Source = CAST('OPENBOX' AS VARCHAR(20))
			,invoice_no = 'N/A'
			,brkr_ref = 'N/A'
			,their_reference = 'N/A'
			,SourceSysKey = 1
			,BankDetailCode = NULL
			,SourceCreatedDate = NULL
			,Authoriser = NULL
			,AuthorisedDate = NULL
	FROM EDW_PREPROD.lloyds.TBL_CLAIM_LLYDS
		UNION ALL
		SELECT DISTINCT  ATT_TIRS_CLM_ID = NULL
			,ATT_CLM_TXN_ID = NULL
			,ClaimCode = CONCAT('LCL', cm.lClaimKey) COLLATE DATABASE_DEFAULT
			,ClaimSectionCode = CONCAT('LCLS', cm.lClaimSectionKey) COLLATE DATABASE_DEFAULT
			,ClaimTransactionCode = tcl.lClaimMovementKey COLLATE DATABASE_DEFAULT
			,AlternativeClaimTransactionCode = CAST(COALESCE(CONVERT(NVARCHAR(30), DateOfLoss, 101), YOA) + COALESCE(CATCODE, '') AS VARCHAR(20)) COLLATE DATABASE_DEFAULT
			,PaymentMethodCode = 'N/A'
			,PaymentMethod = 'N/A'
			,Source = CAST('OPENBOX' AS VARCHAR(20))
			,invoice_no = c.sUCR COLLATE DATABASE_DEFAULT
			,brkr_ref = 'N/A'
			,their_reference = c.sUCR COLLATE DATABASE_DEFAULT
			,SourceSysKey = 1
			,BankDetailCode = NULL
			,SourceCreatedDate = cm.dtMovementDate
			,Authoriser = NULL
			,AuthorisedDate = cm.dtMovementDate
	FROM EDW_PREPROD.lloyds.TBL_CLAIM_LLYDS tcl
		INNER JOIN SRC_LLOYDS_DB.dbo.ClaimMovement cm
			ON cm.lClaimMovementKey = tcl.lClaimMovementKey
		INNER JOIN SRC_LLOYDS_DB.dbo.Claim c
			ON c.lClaimKey = cm.lClaimKey
		WHERE tcl.BusinessType = 'Assumed'
		UNION ALL
		SELECT ATT_TIRS_CLM_ID = NULL
			,ATT_CLM_TXN_ID = NULL
			,ClaimCode = 'Uncoded'
			,ClaimSectionCode = 'Uncoded'
			,ClaimTransactionCode = 'Uncoded'
			,AlternativeClaimTransactionCode = 'Uncoded'
			,PaymentMethodCode = 'Unc'
			,PaymentMethod = 'Uncoded'
			,invoice_no = 'Uncoded'
			,brkr_ref = 'Uncoded'
			,their_reference = 'Uncoded'
			,Source = CAST('Uncoded' AS VARCHAR(20))
			,SourceSysKey = 0
			,BankDetailCode = NULL
			,SourceCreatedDate = NULL
			,Authoriser = NULL
			,AuthorisedDate = NULL
		UNION ALL
		SELECT ATT_TIRS_CLM_ID = NULL
			,ATT_CLM_TXN_ID = NULL
			,ClaimCode = 'N/A'
			,ClaimSectionCode = 'N/A'
			,ClaimTransactionCode = 'N/A'
			,AlternativeClaimTransactionCode = 'N/A'
			,PaymentMethodCode = 'N/A'
			,PaymentMethod = 'N/A'
			,invoice_no = 'N/A'
			,brkr_ref = 'N/A'
			,their_reference = 'N/A'
			,Source = CAST('N/A' AS VARCHAR(20))
			,SourceSysKey = 0
			,BankDetailCode = NULL
			,SourceCreatedDate = NULL
			,Authoriser = NULL
			,AuthorisedDate = NULL
		
		ALTER TABLE #DimClaimTransaction ADD DimClaimID INT NULL
		
		UPDATE s
		SET DimClaimID = COALESCE(c.DimClaimID, p.DimClaimNA)
		FROM #DimClaimTransaction s
		CROSS JOIN #DimDefault p
		LEFT JOIN assumed.DimClaim c
			ON COALESCE(c.claim_code, '^&*') = COALESCE(s.ClaimCode, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(c.claim_sect_code, '^&*') = COALESCE(s.ClaimSectionCode, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(c.SourceSysKey, - 1) = COALESCE(s.SourceSysKey, - 1)
				AND c.EndDate = '9999-12-31'

		ALTER TABLE #DimClaimTransaction ADD Payee_DimBankDetailID INT NULL
		
		UPDATE s
		SET Payee_DimBankDetailID = COALESCE(b.DimBankDetailsID, p.DimBankDetailsNA)
		FROM #DimClaimTransaction s
		CROSS JOIN #DimDefault p
		LEFT JOIN assumed.DimBankDetails b
			ON b.BankDetailCode = s.BankDetailCode

		-- Loading logic
		ALTER TABLE #DimClaimTransaction ADD DataHash BINARY(20) NULL
		ALTER TABLE #DimClaimTransaction ADD DataHashType1 BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.ATT_TIRS_CLM_ID
			,s.ATT_CLM_TXN_ID
			,s.PaymentMethodCode
			,s.PaymentMethod
			,s.Source
			,s.SourceSysKey
			,s.Payee_DimBankDetailID
			,s.invoice_no
			,s.brkr_ref
			,s.their_reference
			,s.ClaimCode
			,s.ClaimSectionCode)) 
		FROM #DimClaimTransaction s

		UPDATE s
		SET DataHashType1 = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.DimClaimID
			,s.SourceCreatedDate
			,s.Authoriser
			,s.AuthorisedDate
			,s.AlternativeClaimTransactionCode))
		FROM #DimClaimTransaction s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(ClaimTransactionCode VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL
		,Source VARCHAR(20)
		,Operation CHAR(1) NOT NULL
		,UNIQUE (ClaimTransactionCode, Source)
		)

		INSERT INTO #LoadOperation
			(ClaimTransactionCode
			,Source
			,Operation
			)
		SELECT ClaimSectionCode = COALESCE(t.ClaimTransactionCode COLLATE DATABASE_DEFAULT, s.ClaimTransactionCode COLLATE DATABASE_DEFAULT)
			,s.Source
			,Operation = CASE WHEN t.DimClaimTransactionID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimClaimTransaction t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimClaimTransaction s
			ON  s.ClaimTransactionCode = t.ClaimTransactionCode COLLATE DATABASE_DEFAULT
			AND s.Source = t.Source COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimClaimTransaction t
		INNER JOIN #LoadOperation lo ON
			lo.ClaimTransactionCode = t.ClaimTransactionCode COLLATE DATABASE_DEFAULT
			AND lo.Source = t.Source COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		UPDATE t
		SET UpdateDate = p.NewStartDate
			,DimClaimID = s.DimClaimID
			,ClaimSectionCode = s.ClaimSectionCode
			,SourceCreatedDate = s.SourceCreatedDate
			,AlternativeClaimTransactionCode = s.AlternativeClaimTransactionCode
			,Authoriser = s.Authoriser
			,AuthorisedDate = s.AuthorisedDate			
			,DataHashType1 = s.DataHashType1
		FROM assumed.DimClaimTransaction t
		INNER JOIN #LoadOperation lo
			ON lo.ClaimTransactionCode = t.ClaimTransactionCode COLLATE DATABASE_DEFAULT
			AND lo.Source = t.Source COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('U', '1')
		INNER JOIN #DimClaimTransaction s
			ON s.ClaimTransactionCode = t.ClaimTransactionCode COLLATE DATABASE_DEFAULT
			AND s.Source = t.Source COLLATE DATABASE_DEFAULT
		CROSS JOIN #Parameters p

		INSERT INTO assumed.DimClaimTransaction
			(StartDate
			,UpdateDate
			,ATT_TIRS_CLM_ID
			,ATT_CLM_TXN_ID
			,ClaimCode
			,ClaimSectionCode
			,ClaimTransactionCode
			,AlternativeClaimTransactionCode
			,PaymentMethodCode
			,PaymentMethod
			,DimClaimID
			,Source
			,SourceSysKey
			,Payee_DimBankDetailID
			,invoice_no
			,brkr_ref
			,their_reference
			,DataHash
			,DataHashType1
			,SourceCreatedDate 
			,Authoriser 
			,AuthorisedDate
			)
		SELECT StartDate = p.NewStartDate
			,UpdateDate = p.NewStartDate
			,s.ATT_TIRS_CLM_ID
			,s.ATT_CLM_TXN_ID
			,s.ClaimCode
			,s.ClaimSectionCode
			,s.ClaimTransactionCode
			,s.AlternativeClaimTransactionCode
			,s.PaymentMethodCode
			,s.PaymentMethod
			,s.DimClaimID
			,s.Source
			,s.SourceSysKey
			,s.Payee_DimBankDetailID
			,s.invoice_no
			,s.brkr_ref
			,s.their_reference
			,s.DataHash
			,s.DataHashType1
			,s.SourceCreatedDate 
			,s.Authoriser 
			,s.AuthorisedDate

		FROM #DimClaimTransaction s
		INNER JOIN #LoadOperation lo
			ON lo.ClaimTransactionCode = s.ClaimTransactionCode COLLATE DATABASE_DEFAULT
			AND lo.Source = s.Source COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('I', 'U', '2')
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

