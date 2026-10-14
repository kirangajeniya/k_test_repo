-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRS_UW_Staging

CREATE   PROCEDURE [assumed].[LoadTIRS_UW_Staging]
	@fullLoad BIT = 0
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
			,IncrementalLoad = ~@fullLoad & CAST(COALESCE((SELECT TOP 1 1 FROM assumed.TIRS_UW_Staging WHERE SubSet = 1), 0) AS BIT) -- ensure a full load if the target table is empty
			,ChangedSince = DATEADD(DAY, -1, (SELECT MAX(StartDate) FROM assumed.TIRS_UW_Staging WHERE SubSet = 1))
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #Filter
		
		SELECT DISTINCT CONTRACT_NBR = LEFT(ad.trty_no, 5) + LEFT(ad.und_yr, 4)
		INTO #Filter
		FROM #Parameters prm
		INNER JOIN SRC_TIRS_DB.dbo.acct_byline ab
			ON prm.IncrementalLoad = 0
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
		UNION
		SELECT DISTINCT s.CONTRACT_NBR
		FROM assumed.TIRS_UW_Staging s
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 0
		WHERE s.EndDate = '31 Dec 9999'
		UNION
		SELECT DISTINCT CONTRACT_NBR = LEFT(ad.trty_no, 5) + LEFT(ad.und_yr, 4)
		FROM #Parameters prm
		INNER JOIN SRC_TIRS_DB.dbo.acct_byline ab
			ON prm.IncrementalLoad = 1
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master ceded_tm
			ON ceded_tm.trty_key = ad.Ceded_trty_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_doc_type dc
			ON AD.doc_type_cd = DC.doc_type_cd
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = ab.pr_cls_cd
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xt
			ON xt.curr_cd = ad.curr_cd
			AND xt.xch_rt_dt = CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATETIME)
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line aslob
			ON lob.annl_stmt_key = aslob.annl_stmt_key
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = ad.trty_key
		WHERE ab.touch_dt > prm.ChangedSince
			OR ad.create_dt > prm.ChangedSince
			OR ad.touch_dt > prm.ChangedSince
			OR ceded_tm.create_dt > prm.ChangedSince
			OR ceded_tm.touch_dt > prm.ChangedSince
			OR dc.touch_dt > prm.ChangedSince
			OR lob.touch_dt > prm.ChangedSince
			OR xt.touch_dt > prm.ChangedSince
			OR aslob.touch_dt > prm.ChangedSince
			OR tm.touch_dt > prm.ChangedSince
		--------------------------------------------------------------------------------		
		-- #TIRS_UW_Staging
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #TIRS_UW_Staging

		SELECT *
		  INTO #TIRS_UW_Staging		
		  FROM (
			SELECT 
				 byline_key					= 10000000000 + ab.byline_key
				,TREATY_NBR					= TRIM(CAST(ad.trty_no AS VARCHAR(5)))		COLLATE DATABASE_DEFAULT
				,UNDERWRITING_YEAR			= TRIM(CAST(ad.und_yr  AS VARCHAR(4)))		COLLATE DATABASE_DEFAULT
				,CONTRACT_NBR				= CONCAT(TRIM(CAST(ad.trty_no AS VARCHAR(5))), TRIM(CAST(ad.und_yr AS VARCHAR(4)))) 			COLLATE DATABASE_DEFAULT
				,CEDED_CONTRACT_NBR			= CONCAT(TRIM(CAST(ceded_tm.trty_no AS VARCHAR(5))), TRIM(CAST(ceded_tm.und_yr AS VARCHAR(4))))	COLLATE DATABASE_DEFAULT
				,ASSUMED_CEDED_FLG			= ad.assumed_ceded_flg						COLLATE DATABASE_DEFAULT
				,TIRS_ORIG_CURR_CD			= TRIM(ad.curr_cd)							COLLATE DATABASE_DEFAULT
				,ASLOB						= RTRIM(LTRIM(am.ASLOB))					COLLATE DATABASE_DEFAULT
				,LOB_NAME 					= TRIM(lob.desc_txt)						COLLATE DATABASE_DEFAULT
				,doc_key                    = ad.doc_key
				,reg_date					= CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
				,due_date					= COALESCE(ad.due_dt, ad.receive_dt) 
				,acct_from_dt				= ad.acct_from_dt 
				,acct_to_dt					= ad.acct_to_dt 
				,doc_type_cd				= ad.doc_type_cd
				,trty_key					= ad.trty_key
				,pr_cls_cd					= ab.pr_cls_cd
				,bill_company_cd			= tm.bill_co_br_key
				---
				,SUMMABLE_WRTN_PREM_ALL_DOC_TYPES		= COALESCE(ab.prem_wr,0)
				,SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD	= COALESCE(ab.prem_wr * xt.xch_rt,0)
			
				,SUMMABLE_Brokerage						= COALESCE(ab.Brokerage,0)
				,SUMMABLE_Brokerage_USD					= COALESCE(ab.Brokerage* xt.xch_rt,0)
			
				,SUMMABLE_Commission					= COALESCE(AB.Comm,0)
				,SUMMABLE_Commission_USD				= COALESCE(AB.Comm* xt.xch_rt,0)																	
			
				,SUMMABLE_tax_nonrefund					= COALESCE(AB.tax_nonrefund,0)
				,SUMMABLE_tax_nonrefund_USD				= COALESCE(AB.tax_nonrefund* xt.xch_rt,0)
			
				,SUMMABLE_tax_on_prem					= COALESCE(AB.tax_on_prem,0)
				,SUMMABLE_tax_on_prem_USD				= COALESCE(AB.tax_on_prem* xt.xch_rt,0)
			
				,SUMMABLE_Tax_refund					= COALESCE(AB.Tax_refund,0)
				,SUMMABLE_Tax_refund_USD				= COALESCE(AB.Tax_refund* xt.xch_rt,0)
							
				,SUMMABLE_Profit_Commission_Paid		= COALESCE(AB.pft_comm_pd,0)
				,SUMMABLE_Profit_Commission_Paid_USD	= COALESCE(AB.pft_comm_pd* xt.xch_rt,0)
			
				,SUMMABLE_Sliding_Scale_Commission		= COALESCE(AB.sldg_comm_amt,0)
				,SUMMABLE_Sliding_Scale_Commission_USD	= COALESCE(AB.sldg_comm_amt* xt.xch_rt,0)
			
				,SUMMABLE_Overrider_Commission			= COALESCE(AB.overrider_comm_amt,0)
				,SUMMABLE_Overrider_Commission_USD		= COALESCE(AB.overrider_comm_amt* xt.xch_rt,0)
			
				,SUMMABLE_Provisional_Commission		= COALESCE(AB.prov_comm_amt,0)
				,SUMMABLE_Provisional_Commission_USD	= COALESCE(AB.prov_comm_amt* xt.xch_rt,0)
			
				,SUMMABLE_Deferred_Commission			= COALESCE(AB.deferred_comm_amt,0)
				,SUMMABLE_Deferred_Commission_USD		= COALESCE(AB.deferred_comm_amt* xt.xch_rt,0)
			
				,SUMMABLE_int_funds_wth					= COALESCE(AB. int_funds_wth,0)
				,SUMMABLE_int_funds_wth_USD				= COALESCE(AB. int_funds_wth* xt.xch_rt,0)
							
				,SUMMABLE_int_funds_gross				= COALESCE(AB.int_funds_gross,0)
				,SUMMABLE_int_funds_gross_USD			= COALESCE(AB.int_funds_gross* xt.xch_rt,0)
			
				,SUMMABLE_fire_prevent_fund				= COALESCE(AB.fire_prevent_fund,0)
				,SUMMABLE_fire_prevent_fund_USD			= COALESCE(AB.fire_prevent_fund* xt.xch_rt,0)
						
				,SUMMABLE_xch_diff						= COALESCE(AB.xch_diff,0)
				,SUMMABLE_xch_diff_USD					= COALESCE(AB.xch_diff* xt.xch_rt,0)
			
				,SUMMABLE_NO_CLM_RBT					= COALESCE(AB.no_clm_rebate,0)
				,SUMMABLE_NO_CLM_RBT_USD				= COALESCE(AB.no_clm_rebate* xt.xch_rt,0)		
			
				,SUMMABLE_funds_withheld_premium		= COALESCE(AB.funds_wth_prem,0)
				,SUMMABLE_funds_withheld_premium_USD	= COALESCE(AB.funds_wth_prem* xt.xch_rt,0)
			
				,SUMMABLE_funds_released_premium		= COALESCE(-AB.funds_rel_prem,0)
				,SUMMABLE_funds_released_premium_USD	= COALESCE(-AB.funds_rel_prem* xt.xch_rt,0)
						
				,SUMMABLE_funds_withheld_losses			= COALESCE(AB.funds_wth_loss,0)
				,SUMMABLE_funds_withheld_losses_USD		= COALESCE(AB.funds_wth_loss* xt.xch_rt,0)
			
				,SUMMABLE_funds_released_losses			= COALESCE(-AB.funds_rel_loss,0)
				,SUMMABLE_funds_released_losses_USD		= COALESCE(-AB.funds_rel_loss* xt.xch_rt,0)
			
				,SUMMABLE_deferred_withheld				= COALESCE(AB.def_prem_wth,0)
				,SUMMABLE_deferred_withheld_USD			= COALESCE(AB.def_prem_wth* xt.xch_rt,0)
			
				,SUMMABLE_deferred_released				= COALESCE(-AB.def_prem_rel,0)
				,SUMMABLE_deferred_released_USD			= COALESCE(-AB.def_prem_rel* xt.xch_rt,0) 
				
				,SUMMABLE_WRTN_PREM_Reinstatement_Premium		= CONVERT(MONEY, IIF(dc.desc_txt ='Reinstatement Premium' AND COALESCE(ab.prem_wr,0) <>0, COALESCE(ab.prem_wr,0) ,0))
				,SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD	= CONVERT(MONEY, IIF(dc.desc_txt ='Reinstatement Premium' AND COALESCE(ab.prem_wr,0) <>0, COALESCE(ab.prem_wr * xt.xch_rt,0) ,0))
			
				,SUMMABLE_WRTN_PREM_No_Claims_Rebate			= CONVERT(MONEY, IIF(dc.desc_txt ='No Claims Rebate' AND COALESCE(ab.prem_wr,0) <>0, COALESCE(ab.prem_wr,0) ,0))
				,SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD		= CONVERT(MONEY, IIF(dc.desc_txt ='No Claims Rebate' AND COALESCE(ab.prem_wr,0) <>0, COALESCE(ab.prem_wr * xt.xch_rt,0) ,0))
			
			FROM SRC_TIRS_DB.dbo.acct_byline				AS ab
			INNER JOIN SRC_TIRS_DB.dbo.acct_doc				AS ad		ON ab.doc_key = ad.doc_key
			INNER JOIN #Filter								AS f		ON f.CONTRACT_NBR = CONCAT(TRIM(CAST(ad.trty_no AS VARCHAR(5))), TRIM(CAST(ad.und_yr AS VARCHAR(4))))
			LEFT  JOIN SRC_TIRS_DB.dbo.trty_master			AS tm		ON tm.trty_key = ad.trty_key
			LEFT  JOIN SRC_TIRS_DB.dbo.trty_master			AS ceded_tm ON ceded_tm.trty_key = ad.Ceded_trty_key
			LEFT  JOIN SRC_TIRS_DB.dbo.xrf_doc_type 		AS dc		ON ad.doc_type_cd = dc.doc_type_cd
			LEFT  JOIN SRC_TIRS_DB.dbo.xrf_lob_cds			AS lob		ON lob.lob_cd = ab.pr_cls_cd
			LEFT  JOIN SRC_TIRS_DB.dbo.xrf_curr_cds			AS xt		ON xt.curr_cd = ad.curr_cd
																		AND xt.xch_rt_dt = CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATETIME)
			LEFT  JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line	AS aslob	ON lob.annl_stmt_key = aslob.annl_stmt_key
			LEFT  JOIN EDW_STAGING.dbo.TIRS_ASLOBCodeMapping AS am  	ON am.pro_xol_flg=tm.pro_xol_flg COLLATE DATABASE_DEFAULT AND am.annl_stmt_ln=aslob.annl_stmt_ln COLLATE DATABASE_DEFAULT
			
			WHERE ad.status_flg = 'P'
				AND NOT (COALESCE(ab.prem_wr,0) = 0
					AND COALESCE(ab.Brokerage,0) = 0
					AND COALESCE(AB.Comm,0) = 0
					AND COALESCE(AB.tax_nonrefund,0) = 0
					AND COALESCE(AB.tax_on_prem,0) = 0
					AND COALESCE(AB.Tax_refund,0) = 0
					AND COALESCE(AB.pft_comm_pd,0) = 0
					AND COALESCE(AB.sldg_comm_amt,0) = 0
					AND COALESCE(AB.overrider_comm_amt,0) = 0
					AND COALESCE(AB.prov_comm_amt,0) = 0
					AND COALESCE(AB.deferred_comm_amt,0) = 0
					AND COALESCE(AB.int_funds_wth,0) = 0
					AND COALESCE(AB.int_funds_gross,0) = 0
					AND COALESCE(AB.fire_prevent_fund,0) = 0
					AND COALESCE(AB.xch_diff,0) = 0
					AND COALESCE(AB.no_clm_rebate,0) = 0
					AND COALESCE(AB.funds_wth_prem,0) = 0
					AND COALESCE(-AB.funds_rel_prem,0) = 0
					AND COALESCE(AB.funds_wth_loss,0) = 0
					AND COALESCE(-AB.funds_rel_loss,0) = 0
					AND COALESCE(AB.def_prem_wth,0) = 0
					AND COALESCE(-AB.def_prem_rel,0) = 0
					AND CONVERT(MONEY, IIF(dc.desc_txt ='Reinstatement Premium' AND COALESCE(ab.prem_wr,0) <>0, COALESCE(ab.prem_wr,0) ,0)) = 0
					AND CONVERT(MONEY, IIF(dc.desc_txt ='No Claims Rebate' AND COALESCE(ab.prem_wr,0) <>0, COALESCE(ab.prem_wr,0) ,0)) = 0
					)
		) AS stg

		-- Loading logic
		ALTER TABLE #TIRS_UW_Staging ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', 
						CONCAT_WS('|',s.TREATY_NBR
									 ,s.UNDERWRITING_YEAR
									 ,s.CEDED_CONTRACT_NBR
									 ,s.ASSUMED_CEDED_FLG
									 ,s.TIRS_ORIG_CURR_CD
									 ,s.ASLOB
									 ,s.LOB_NAME
									 ,s.reg_date
									 ,s.due_date
									 ,s.doc_type_cd
									 ,s.trty_key
									 ,s.pr_cls_cd									 
									 ,s.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES
									 ,s.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD
									 ,s.SUMMABLE_Brokerage
									 ,s.SUMMABLE_Brokerage_USD
									 ,s.SUMMABLE_Commission
									 ,s.SUMMABLE_Commission_USD
									 ,s.SUMMABLE_tax_nonrefund
									 ,s.SUMMABLE_tax_nonrefund_USD
									 ,s.SUMMABLE_tax_on_prem
									 ,s.SUMMABLE_tax_on_prem_USD
									 ,s.SUMMABLE_Tax_refund
									 ,s.SUMMABLE_Tax_refund_USD
									 ,s.SUMMABLE_Profit_Commission_Paid
									 ,s.SUMMABLE_Profit_Commission_Paid_USD
									 ,s.SUMMABLE_Sliding_Scale_Commission
									 ,s.SUMMABLE_Sliding_Scale_Commission_USD
									 ,s.SUMMABLE_Overrider_Commission
									 ,s.SUMMABLE_Overrider_Commission_USD
									 ,s.SUMMABLE_Provisional_Commission
									 ,s.SUMMABLE_Provisional_Commission_USD
									 ,s.SUMMABLE_Deferred_Commission
									 ,s.SUMMABLE_Deferred_Commission_USD
									 ,s.SUMMABLE_int_funds_wth
									 ,s.SUMMABLE_int_funds_wth_USD
									 ,s.SUMMABLE_int_funds_gross
									 ,s.SUMMABLE_int_funds_gross_USD
									 ,s.SUMMABLE_fire_prevent_fund
									 ,s.SUMMABLE_fire_prevent_fund_USD
									 ,s.SUMMABLE_xch_diff
									 ,s.SUMMABLE_xch_diff_USD
									 ,s.SUMMABLE_NO_CLM_RBT
									 ,s.SUMMABLE_NO_CLM_RBT_USD
									 ,s.SUMMABLE_funds_withheld_premium
									 ,s.SUMMABLE_funds_withheld_premium_USD
									 ,s.SUMMABLE_funds_released_premium
									 ,s.SUMMABLE_funds_released_premium_USD
									 ,s.SUMMABLE_funds_withheld_losses
									 ,s.SUMMABLE_funds_withheld_losses_USD
									 ,s.SUMMABLE_funds_released_losses
									 ,s.SUMMABLE_funds_released_losses_USD
									 ,s.SUMMABLE_deferred_withheld
									 ,s.SUMMABLE_deferred_withheld_USD
									 ,s.SUMMABLE_deferred_released
									 ,s.SUMMABLE_deferred_released_USD
									 ,s.SUMMABLE_WRTN_PREM_Reinstatement_Premium
									 ,s.SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD
									 ,s.SUMMABLE_WRTN_PREM_No_Claims_Rebate
									 ,s.SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD
									 ,s.acct_from_dt 
									 ,s.acct_to_dt									 
									 ,s.doc_key
									 ,s.bill_company_cd
									 ))
		FROM #TIRS_UW_Staging s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,byline_key BIGINT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, byline_key)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,byline_key
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,byline_key = COALESCE(t.byline_key, s.byline_key)
			,Operation = CASE WHEN t.TIRS_UW_StagingID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRS_UW_Staging t
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			WHERE t.EndDate = '31 Dec 9999'
				AND t.SubSet = 1
			) t
		FULL JOIN (
			SELECT s.*
			FROM #TIRS_UW_Staging s
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			) s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND COALESCE(s.byline_key, -1) = COALESCE(t.byline_key, -1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRS_UW_Staging t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND COALESCE(lo.byline_key, -1) = COALESCE(t.byline_key, -1)
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'
			AND t.SubSet = 1

		INSERT INTO assumed.TIRS_UW_Staging
			(StartDate
			,SubSet
			,byline_key
			,TREATY_NBR
			,UNDERWRITING_YEAR
			,CONTRACT_NBR
			,CEDED_CONTRACT_NBR
			,ASSUMED_CEDED_FLG
			,TIRS_ORIG_CURR_CD
			,ASLOB
			,LOB_NAME
			,reg_date
			,due_date
			,doc_type_cd
			,trty_key
			,pr_cls_cd			
			,SUMMABLE_WRTN_PREM_ALL_DOC_TYPES
			,SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD
			,SUMMABLE_Brokerage
			,SUMMABLE_Brokerage_USD
			,SUMMABLE_Commission
			,SUMMABLE_Commission_USD
			,SUMMABLE_tax_nonrefund
			,SUMMABLE_tax_nonrefund_USD
			,SUMMABLE_tax_on_prem
			,SUMMABLE_tax_on_prem_USD
			,SUMMABLE_Tax_refund
			,SUMMABLE_Tax_refund_USD
			,SUMMABLE_Profit_Commission_Paid
			,SUMMABLE_Profit_Commission_Paid_USD
			,SUMMABLE_Sliding_Scale_Commission
			,SUMMABLE_Sliding_Scale_Commission_USD
			,SUMMABLE_Overrider_Commission
			,SUMMABLE_Overrider_Commission_USD
			,SUMMABLE_Provisional_Commission
			,SUMMABLE_Provisional_Commission_USD
			,SUMMABLE_Deferred_Commission
			,SUMMABLE_Deferred_Commission_USD
			,SUMMABLE_int_funds_wth
			,SUMMABLE_int_funds_wth_USD
			,SUMMABLE_int_funds_gross
			,SUMMABLE_int_funds_gross_USD
			,SUMMABLE_fire_prevent_fund
			,SUMMABLE_fire_prevent_fund_USD
			,SUMMABLE_xch_diff
			,SUMMABLE_xch_diff_USD
			,SUMMABLE_NO_CLM_RBT
			,SUMMABLE_NO_CLM_RBT_USD
			,SUMMABLE_funds_withheld_premium
			,SUMMABLE_funds_withheld_premium_USD
			,SUMMABLE_funds_released_premium
			,SUMMABLE_funds_released_premium_USD
			,SUMMABLE_funds_withheld_losses
			,SUMMABLE_funds_withheld_losses_USD
			,SUMMABLE_funds_released_losses
			,SUMMABLE_funds_released_losses_USD
			,SUMMABLE_deferred_withheld
			,SUMMABLE_deferred_withheld_USD
			,SUMMABLE_deferred_released
			,SUMMABLE_deferred_released_USD
			,SUMMABLE_WRTN_PREM_Reinstatement_Premium
			,SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD
			,SUMMABLE_WRTN_PREM_No_Claims_Rebate
			,SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD
			,acct_from_dt	
			,acct_to_dt	
			,doc_key
			,bill_company_cd
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,SubSet = 1
			,s.byline_key
			,s.TREATY_NBR
			,s.UNDERWRITING_YEAR
			,s.CONTRACT_NBR
			,s.CEDED_CONTRACT_NBR
			,s.ASSUMED_CEDED_FLG
			,s.TIRS_ORIG_CURR_CD
			,s.ASLOB
			,s.LOB_NAME
			,s.reg_date
			,s.due_date	
			,s.doc_type_cd
			,s.trty_key
			,s.pr_cls_cd
			,s.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES
			,s.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD
			,s.SUMMABLE_Brokerage
			,s.SUMMABLE_Brokerage_USD
			,s.SUMMABLE_Commission
			,s.SUMMABLE_Commission_USD
			,s.SUMMABLE_tax_nonrefund
			,s.SUMMABLE_tax_nonrefund_USD
			,s.SUMMABLE_tax_on_prem
			,s.SUMMABLE_tax_on_prem_USD
			,s.SUMMABLE_Tax_refund
			,s.SUMMABLE_Tax_refund_USD
			,s.SUMMABLE_Profit_Commission_Paid
			,s.SUMMABLE_Profit_Commission_Paid_USD
			,s.SUMMABLE_Sliding_Scale_Commission
			,s.SUMMABLE_Sliding_Scale_Commission_USD
			,s.SUMMABLE_Overrider_Commission
			,s.SUMMABLE_Overrider_Commission_USD
			,s.SUMMABLE_Provisional_Commission
			,s.SUMMABLE_Provisional_Commission_USD
			,s.SUMMABLE_Deferred_Commission
			,s.SUMMABLE_Deferred_Commission_USD
			,s.SUMMABLE_int_funds_wth
			,s.SUMMABLE_int_funds_wth_USD
			,s.SUMMABLE_int_funds_gross
			,s.SUMMABLE_int_funds_gross_USD
			,s.SUMMABLE_fire_prevent_fund
			,s.SUMMABLE_fire_prevent_fund_USD
			,s.SUMMABLE_xch_diff
			,s.SUMMABLE_xch_diff_USD
			,s.SUMMABLE_NO_CLM_RBT
			,s.SUMMABLE_NO_CLM_RBT_USD
			,s.SUMMABLE_funds_withheld_premium
			,s.SUMMABLE_funds_withheld_premium_USD
			,s.SUMMABLE_funds_released_premium
			,s.SUMMABLE_funds_released_premium_USD
			,s.SUMMABLE_funds_withheld_losses
			,s.SUMMABLE_funds_withheld_losses_USD
			,s.SUMMABLE_funds_released_losses
			,s.SUMMABLE_funds_released_losses_USD
			,s.SUMMABLE_deferred_withheld
			,s.SUMMABLE_deferred_withheld_USD
			,s.SUMMABLE_deferred_released
			,s.SUMMABLE_deferred_released_USD
			,s.SUMMABLE_WRTN_PREM_Reinstatement_Premium
			,s.SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD
			,s.SUMMABLE_WRTN_PREM_No_Claims_Rebate
			,s.SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD
			,s.acct_from_dt	
			,s.acct_to_dt	
			,s.doc_key
			,bill_company_cd
			,s.DataHash
		FROM #TIRS_UW_Staging s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.byline_key, -1) = COALESCE(s.byline_key, -1)
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