-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSAccountingLossPaid

CREATE   PROCEDURE [assumed].[LoadTIRSAccountingLossPaid]
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
		DROP TABLE IF EXISTS #TIRSAccountingLossPaid

		SELECT *
		  INTO #TIRSAccountingLossPaid	
		  FROM (		
			SELECT
				 CONTRACT_NBR = CONCAT(CAST(ad.trty_no AS CHAR(5)), CAST(TRIM(ad.und_yr) AS CHAR(4))) COLLATE DATABASE_DEFAULT
				,ASSUMED_CEDED_FLG = ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
				,TIRS_ORIG_CURR_CD = TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
				,LOB_NAME = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
				,reg_date = CAST(COALESCE(reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
				,ab.byline_key
				,ad.doc_key
				,ad.doc_type_cd
				,due_dt = COALESCE(ad.due_dt, ad.receive_dt)
				,ad.acct_from_dt
				,ad.acct_to_dt
				,tm.bill_co_br_key
				,SUMMABLE_LOSS_PAID = COALESCE(ab.loss_pd, 0)
				,SUMMABLE_LOSS_PAID_USD = ROUND(COALESCE(ab.loss_pd, 0) * xt.xch_rt, 2)
				,SUMMABLE_LOSS_EXP_PAID = COALESCE(ab.xpns_amt, 0)
				,SUMMABLE_LOSS_EXP_PAID_USD = ROUND(COALESCE(ab.xpns_amt, 0) * xt.xch_rt, 2)
				,SUMMABLE_LAE = COALESCE(LAE, 0)
				,SUMMABLE_LAE_USD = ROUND(COALESCE(LAE, 0) * xt.xch_rt, 2)
				,SUMMABLE_CASH_LOSS_ADV_AMT = COALESCE(CASH_LOSS_ADV_AMT, 0)
				,SUMMABLE_CASH_LOSS_ADV_AMT_USD = ROUND(COALESCE(CASH_LOSS_ADV_AMT, 0) * xt.xch_rt, 2)
				,SUMMABLE_CASH_LOSS_REFUND = COALESCE(CASH_LOSS_REFUND, 0)
				,SUMMABLE_CASH_LOSS_REFUND_USD = ROUND(COALESCE(CASH_LOSS_REFUND, 0) * xt.xch_rt, 2)
				,SUMMABLE_funds_released_losses = COALESCE(-AB.funds_rel_loss, 0)
				,SUMMABLE_funds_released_losses_USD = ROUND(COALESCE(-AB.funds_rel_loss, 0) * xt.xch_rt, 2)
				,SUMMABLE_reinstatement_premium = COALESCE(CASE WHEN dc.desc_txt = 'Reinstatement Premium' AND ab.doc_no IS NOT NULL THEN AB.prem_wr END, 0)
				,SUMMABLE_reinstatement_premium_USD = ROUND(COALESCE(CASE WHEN dc.desc_txt = 'Reinstatement Premium' AND ab.doc_no IS NOT NULL THEN AB.prem_wr END, 0) * xt.xch_rt, 2)
			FROM SRC_TIRS_DB.dbo.acct_byline ab
			INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
				ON ab.doc_key = ad.doc_key
			INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
				ON tm.trty_key = ad.trty_key
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_doc_type dc
				ON ad.doc_type_cd = dc.doc_type_cd
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
				ON lob.lob_cd = ab.pr_cls_cd
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xt
				ON ad.curr_cd = xt.curr_cd
					AND CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATETIME) = xt.xch_rt_dt
			WHERE ad.status_flg = 'P'
				AND NOT (NULLIF(ab.loss_pd, 0) IS NULL
					AND NULLIF(ab.xpns_amt, 0) IS NULL
					AND NULLIF(ab.lae, 0) IS NULL
					AND NULLIF(ab.cash_loss_adv_amt, 0) IS NULL
					AND NULLIF(ab.cash_loss_refund, 0) IS NULL
					AND NULLIF(ab.funds_rel_loss, 0) IS NULL
					AND NULLIF(CASE WHEN dc.desc_txt = 'Reinstatement Premium' AND ab.doc_no IS NOT NULL THEN ab.prem_wr END, 0) IS NULL
					)
		) AS stg		

		-- Loading logic
		ALTER TABLE #TIRSAccountingLossPaid ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', 
						CONCAT_WS('|'
								 ,s.doc_type_cd
								 ,s.due_dt
								 ,s.SUMMABLE_LOSS_PAID
								 ,s.SUMMABLE_LOSS_PAID_USD
								 ,s.SUMMABLE_LOSS_EXP_PAID
								 ,s.SUMMABLE_LOSS_EXP_PAID_USD
								 ,s.SUMMABLE_LAE
								 ,s.SUMMABLE_LAE_USD
								 ,s.SUMMABLE_CASH_LOSS_ADV_AMT
								 ,s.SUMMABLE_CASH_LOSS_ADV_AMT_USD
								 ,s.SUMMABLE_CASH_LOSS_REFUND
								 ,s.SUMMABLE_CASH_LOSS_REFUND_USD
								 ,s.SUMMABLE_funds_released_losses
								 ,s.SUMMABLE_funds_released_losses_USD
								 ,s.SUMMABLE_reinstatement_premium
								 ,s.SUMMABLE_reinstatement_premium_USD
								 ,s.acct_from_dt
								 ,s.acct_to_dt
								 ,s.bill_co_br_key
								 ,s.doc_key
								))
		FROM #TIRSAccountingLossPaid s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,byline_key INT NOT NULL
		,assumed_ceded_flg CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NULL
		,LOB_NAME VARCHAR(255) COLLATE DATABASE_DEFAULT NULL
		,reg_date DATE NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, byline_key, assumed_ceded_flg, TIRS_ORIG_CURR_CD, LOB_NAME, reg_date)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,byline_key
			,assumed_ceded_flg
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,byline_key = COALESCE(t.byline_key, s.byline_key)
			,assumed_ceded_flg = COALESCE(t.assumed_ceded_flg COLLATE DATABASE_DEFAULT, s.assumed_ceded_flg COLLATE DATABASE_DEFAULT)
			,TIRS_ORIG_CURR_CD = COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
			,LOB_NAME = COALESCE(t.LOB_NAME COLLATE DATABASE_DEFAULT, s.LOB_NAME COLLATE DATABASE_DEFAULT)
			,reg_date = COALESCE(t.reg_date, s.reg_date)
			,Operation = CASE WHEN t.TIRSAccountingLossPaidID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSAccountingLossPaid t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #TIRSAccountingLossPaid s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.byline_key = t.byline_key
			AND s.assumed_ceded_flg = t.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			AND COALESCE(s.TIRS_ORIG_CURR_CD, '^&*') = COALESCE(t.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.LOB_NAME, '^&*') = COALESCE(t.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.reg_date, '1 Jan 1900') = COALESCE(t.reg_date, '1 Jan 1900')
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSAccountingLossPaid t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND lo.byline_key = t.byline_key
			AND lo.assumed_ceded_flg = t.assumed_ceded_flg
			AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*') = COALESCE(t.TIRS_ORIG_CURR_CD, '^&*')
			AND COALESCE(lo.LOB_NAME, '^&*') = COALESCE(t.LOB_NAME, '^&*')
			AND COALESCE(lo.reg_date, '1 Jan 1900') = COALESCE(t.reg_date, '1 Jan 1900')
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSAccountingLossPaid
			(StartDate
			,CONTRACT_NBR
			,byline_key
			,doc_type_cd
			,due_dt
			,assumed_ceded_flg
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,SUMMABLE_LOSS_PAID
			,SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LOSS_EXP_PAID
			,SUMMABLE_LOSS_EXP_PAID_USD
			,SUMMABLE_LAE
			,SUMMABLE_LAE_USD
			,SUMMABLE_CASH_LOSS_ADV_AMT
			,SUMMABLE_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_CASH_LOSS_REFUND
			,SUMMABLE_CASH_LOSS_REFUND_USD
			,SUMMABLE_funds_released_losses
			,SUMMABLE_funds_released_losses_USD
			,SUMMABLE_reinstatement_premium
			,SUMMABLE_reinstatement_premium_USD
			,acct_from_dt
			,acct_to_dt
			,bill_co_br_key
			,doc_key
			,DataHash
			)
		SELECT
			 StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.byline_key
			,s.doc_type_cd
			,s.due_dt
			,s.assumed_ceded_flg
			,s.TIRS_ORIG_CURR_CD
			,s.LOB_NAME
			,s.reg_date
			,s.SUMMABLE_LOSS_PAID
			,s.SUMMABLE_LOSS_PAID_USD
			,s.SUMMABLE_LOSS_EXP_PAID
			,s.SUMMABLE_LOSS_EXP_PAID_USD
			,s.SUMMABLE_LAE
			,s.SUMMABLE_LAE_USD
			,s.SUMMABLE_CASH_LOSS_ADV_AMT
			,s.SUMMABLE_CASH_LOSS_ADV_AMT_USD
			,s.SUMMABLE_CASH_LOSS_REFUND
			,s.SUMMABLE_CASH_LOSS_REFUND_USD
			,s.SUMMABLE_funds_released_losses
			,s.SUMMABLE_funds_released_losses_USD
			,s.SUMMABLE_reinstatement_premium
			,s.SUMMABLE_reinstatement_premium_USD
			,s.acct_from_dt
			,s.acct_to_dt
			,s.bill_co_br_key
			,s.doc_key
			,s.DataHash
		FROM #TIRSAccountingLossPaid s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR 		= s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.byline_key 		= s.byline_key
			AND lo.assumed_ceded_flg= s.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*') 	= COALESCE(s.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.LOB_NAME, '^&*') 			= COALESCE(s.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.reg_date, '1 Jan 1900') 	= COALESCE(s.reg_date, '1 Jan 1900')
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
