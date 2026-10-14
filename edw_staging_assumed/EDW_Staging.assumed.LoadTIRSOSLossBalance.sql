-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSOSLossBalance

CREATE   PROCEDURE assumed.LoadTIRSOSLossBalance
AS
BEGIN TRY
		SET NOCOUNT ON
		SET ANSI_WARNINGS OFF 

		DECLARE @v_ProcessName			VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @v_LastIdentity			BIGINT		= SCOPE_IDENTITY()
		DECLARE @v_ProcessingStarted	DATETIME	= GETDATE()
		DECLARE @v_ProcessingEnded		DATETIME	= GETDATE()
		DECLARE @v_SourceDataDate		DATE		= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)
		DECLARE @v_RowsProcessed		BIGINT		= 0
		DECLARE @v_Comment				VARCHAR(MAX)= 'IntegritySourceSetCheck='+CONVERT(VARCHAR,(SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ))

		IF (SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ) = 0
		BEGIN
		-------------------------------------------------------
		-- Update etl_controller, flag SUCCESS
		-------------------------------------------------------
			EXEC ETL.dbo.update_etl_controller 
				 @ps_process_name			= @v_ProcessName
				,@pn_rows_processed			= @v_RowsProcessed
				,@pdt_data_datetime			= @v_SourceDataDate
				,@pdt_process_start_datetime= @v_ProcessingStarted
				,@pdt_process_end_datetime	= @v_ProcessingEnded
				,@pn_error_number			= 0
				,@ps_comment				= @v_Comment
				,@pn_max_processed_event_id = @v_LastIdentity
			RETURN
		END
		-------------------------------------------------------
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #TIRSOSLossBalance
		
		SELECT CONTRACT_NBR = TRIM(CAST(ad.trty_no AS CHAR(5))) + TRIM(CAST(ad.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
			,ab.byline_key
			,doc_type_cd = COALESCE(ad.doc_type_cd, NULL)
			,TIRS_ORIG_CURR_CD = TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
			,LOB_NAME = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
			,acct_to_dt = CAST(acct_to_dt AS DATE)
			,reg_date = CAST(COALESCE(reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
			,tm.bill_co_br_key
			,assumed_ceded_flg = ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			,os_loss = COALESCE(ab.os_losses, 0)
			,os_loss_exp = COALESCE(ab.os_lae, 0)
			,due_dt = COALESCE(ad.due_dt, ad.receive_dt)
		INTO #TIRSOSLossBalance
		FROM src_tirs_db.dbo.acct_byline ab
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_doc_type dc
			ON ad.doc_type_cd = dc.doc_type_cd
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = ad.trty_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = ab.pr_cls_cd
		WHERE RTRIM(LTRIM(DC.desc_txt)) IN ('Portfolio', 'Reported', 'Accrual', 'Correction', 'Deposit', 'Cancellation')
			AND ad.status_flg = 'P'
		
		-- Calculate additional balances that appear to have been omitted from TIRS - where an LOB has been reported with a balance for a contract, currency before
		-- but is missing when other LOBs for the contract, currency are reported on a reg_date, provide a zero balance for that LOB on that reg_date
		DROP TABLE IF EXISTS #EarliestRegDatePerContractLOB
		
		SELECT CONTRACT_NBR = olbt.CONTRACT_NBR
			,assumed_ceded_flg = olbt.assumed_ceded_flg
			,TIRS_ORIG_CURR_CD = olbt.TIRS_ORIG_CURR_CD
			,LOB_NAME = olbt.LOB_NAME
			,MIN_Reg_DATE = MIN(olbt.Reg_DATE)
		INTO #EarliestRegDatePerContractLOB
		FROM #TIRSOSLossBalance olbt
		GROUP BY olbt.CONTRACT_NBR
			,olbt.TIRS_ORIG_CURR_CD
			,olbt.LOB_NAME
			,olbt.assumed_ceded_flg
		HAVING SUM(CASE WHEN olbt.os_loss != 0 OR olbt.os_loss_exp != 0 THEN 1 ELSE 0 END) > 0
		
		DROP TABLE IF EXISTS #EarliestRegDatePerReportingDate
		
		SELECT CONTRACT_NBR = CONTRACT_NBR
			,assumed_ceded_flg = assumed_ceded_flg
			,TIRS_ORIG_CURR_CD = TIRS_ORIG_CURR_CD
			,acct_to_dt = acct_to_dt
			,MIN_acct_to_Reg_DATE = MIN(reg_date)
		INTO #EarliestRegDatePerReportingDate
		FROM #TIRSOSLossBalance olbt
		GROUP BY CONTRACT_NBR
			,assumed_ceded_flg
			,TIRS_ORIG_CURR_CD
			,acct_to_dt
		
		INSERT INTO #TIRSOSLossBalance
			(CONTRACT_NBR
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,acct_to_dt
			,reg_date
			,bill_co_br_key
			,OS_LOSS
			,os_loss_exp
			,assumed_ceded_flg
			)
		SELECT CONTRACT_NBR = cl.CONTRACT_NBR
			,TIRS_ORIG_CURR_CD = cl.TIRS_ORIG_CURR_CD
			,LOB_NAME = cl.LOB_NAME
			,acct_to_dt = rd.acct_to_dt
			,reg_date = rd.MIN_acct_to_Reg_DATE
			,bill_co_br_key = olbt.bill_co_br_key
			,OS_LOSS = 0
			,os_loss_exp = 0
			,assumed_ceded_flg = cl.assumed_ceded_flg
		FROM #EarliestRegDatePerContractLOB cl
		INNER JOIN #EarliestRegDatePerReportingDate rd
			ON cl.CONTRACT_NBR = rd.CONTRACT_NBR
				AND cl.assumed_ceded_flg = rd.assumed_ceded_flg
				AND cl.TIRS_ORIG_CURR_CD = rd.TIRS_ORIG_CURR_CD
				AND rd.acct_to_dt >= cl.MIN_Reg_DATE
		LEFT JOIN #TIRSOSLossBalance olbt
			ON olbt.CONTRACT_NBR = cl.CONTRACT_NBR
				AND olbt.TIRS_ORIG_CURR_CD = cl.TIRS_ORIG_CURR_CD
				AND olbt.LOB_NAME = cl.LOB_NAME
				AND olbt.acct_to_dt = rd.acct_to_dt
		WHERE olbt.CONTRACT_NBR IS NULL
		

		-- Loading logic
		ALTER TABLE #TIRSOSLossBalance ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.doc_type_cd
			, '|', s.os_loss
			, '|', s.bill_co_br_key
			, '|', s.os_loss_exp
			, '|', s.due_dt))
		FROM #TIRSOSLossBalance s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,byline_key INT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,LOB_NAME VARCHAR(255) COLLATE DATABASE_DEFAULT NOT NULL
		,acct_to_dt DATE NOT NULL
		,reg_date DATE NOT NULL
		,assumed_ceded_flg CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, byline_key, TIRS_ORIG_CURR_CD, LOB_NAME, acct_to_dt, reg_date, assumed_ceded_flg)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,byline_key
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,acct_to_dt
			,reg_date
			,assumed_ceded_flg
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,byline_key = COALESCE(t.byline_key, s.byline_key)
			,TIRS_ORIG_CURR_CD = COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
			,LOB_NAME = COALESCE(t.LOB_NAME COLLATE DATABASE_DEFAULT, s.LOB_NAME COLLATE DATABASE_DEFAULT)
			,acct_to_dt = COALESCE(t.acct_to_dt, s.acct_to_dt)
			,reg_date = COALESCE(t.reg_date, s.reg_date)
			,assumed_ceded_flg = COALESCE(t.assumed_ceded_flg COLLATE DATABASE_DEFAULT, s.assumed_ceded_flg COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.TIRSOSLossBalanceID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSOSLossBalance t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #TIRSOSLossBalance s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND COALESCE(s.byline_key, -1) = COALESCE(t.byline_key, -1)
			AND s.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND s.LOB_NAME = t.LOB_NAME COLLATE DATABASE_DEFAULT
			AND s.acct_to_dt = t.acct_to_dt
			AND s.reg_date = t.reg_date
			AND s.assumed_ceded_flg = t.assumed_ceded_flg COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSOSLossBalance t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND COALESCE(lo.byline_key, -1) = COALESCE(t.byline_key, -1)
			AND lo.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD
			AND lo.LOB_NAME = t.LOB_NAME
			AND lo.acct_to_dt = t.acct_to_dt
			AND lo.reg_date = t.reg_date
			AND lo.assumed_ceded_flg = t.assumed_ceded_flg
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSOSLossBalance
			(StartDate
			,CONTRACT_NBR
			,byline_key
			,doc_type_cd
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,acct_to_dt
			,reg_date
			,bill_co_br_key
			,assumed_ceded_flg
			,os_loss
			,os_loss_exp
			,due_dt
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.byline_key
			,s.doc_type_cd
			,s.TIRS_ORIG_CURR_CD
			,s.LOB_NAME
			,s.acct_to_dt
			,s.reg_date
			,s.bill_co_br_key
			,s.assumed_ceded_flg
			,s.os_loss
			,s.os_loss_exp
			,s.due_dt
			,s.DataHash
		FROM #TIRSOSLossBalance s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.byline_key, -1) = COALESCE(s.byline_key, -1)
			AND lo.TIRS_ORIG_CURR_CD = s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND lo.LOB_NAME = s.LOB_NAME COLLATE DATABASE_DEFAULT
			AND lo.acct_to_dt = s.acct_to_dt
			AND lo.reg_date = s.reg_date
			AND lo.assumed_ceded_flg = s.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('I', 'U')
		CROSS JOIN #Parameters p

	COMMIT TRANSACTION

	-------------------------------------------------------
	-- Update etl_controller, flag SUCCESS
	-------------------------------------------------------
	SET @v_RowsProcessed	= COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U', 'D')), 0)
	SET @v_ProcessingEnded	= GETDATE()
	SET @v_LastIdentity		= SCOPE_IDENTITY()

	EXEC ETL.dbo.update_etl_controller 
		 @ps_process_name			= @v_ProcessName
		,@pn_rows_processed			= @v_RowsProcessed
		,@pdt_data_datetime			= @v_SourceDataDate
		,@pdt_process_start_datetime= @v_ProcessingStarted
		,@pdt_process_end_datetime	= @v_ProcessingEnded
		,@pn_error_number			= 0
		,@ps_comment				= @v_Comment
		,@pn_max_processed_event_id = @v_LastIdentity
END TRY

BEGIN CATCH        
        IF @@TRANCOUNT > 0 
			BEGIN ROLLBACK TRANSACTION;
        END
		/*Raise error to SQL Agent*/
		DECLARE @v_ErrorDescription	VARCHAR(MAX)= CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @v_ErrorNumber		INT			= ERROR_NUMBER()
		DECLARE @v_ErrorMessage		VARCHAR(MAX)= ERROR_MESSAGE()
		DECLARE @v_ErrorSeverity	INT			= ERROR_SEVERITY()
		DECLARE @v_ErrorState		INT			= ERROR_STATE()
			SET @v_ProcessingEnded	= GETDATE() 

		EXEC ETL.dbo.update_etl_controller 
			 @ps_process_name			= @v_ProcessName
			,@pn_rows_processed			= 0
			,@pdt_data_datetime			= @v_SourceDataDate
			,@pdt_process_start_datetime= @v_ProcessingStarted
			,@pdt_process_end_datetime	= @v_ProcessingEnded
			,@pn_error_number			= @v_ErrorNumber
			,@ps_comment				= @v_ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log 
			 @process_name	= @v_ProcessName
			,@object_name	= 0
			,@user_message	= @v_ErrorDescription
			,@status		= 0
			,@remedy		= 'Contact EDW team'

		RAISERROR(@v_ErrorMessage, @v_ErrorSeverity, @v_ErrorState)
END CATCH
