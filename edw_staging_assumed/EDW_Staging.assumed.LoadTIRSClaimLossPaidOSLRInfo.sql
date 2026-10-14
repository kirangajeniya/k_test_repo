-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSClaimLossPaidOSLRInfo

CREATE   PROCEDURE assumed.LoadTIRSClaimLossPaidOSLRInfo
AS
BEGIN TRY
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
		
		DROP TABLE IF EXISTS #TIRSClaimLossPaidOSLRInfo
		
		SELECT treaty_NBR = clpo.treaty_NBR
			,UNDERWRITING_YEAR = clpo.UNDERWRITING_YEAR
			,CONTRACT_NBR = clpo.CONTRACT_NBR
			,CEDED_CONTRACT_NBR = clpo.CEDED_CONTRACT_NBR
			,trans_key = clpo.trans_key
			,DataSet = clpo.DataSet
			,trans_cd = clpo.trans_cd
			,entry_dt = clpo.entry_dt
			,FromDate = clpo.FromDate
			,ToDate = clpo.ToDate
			,section_key = clpo.section_key
			,ORIGCURR_CD = clpo.ORIGCURR_CD
			,TIRS_ORIG_CURR_CD = clpo.TIRS_ORIG_CURR_CD
			,TIRS_ORIG_CURR_NAME = clpo.TIRS_ORIG_CURR_NAME
			,TIRS_LOB_NAME = clpo.TIRS_LOB_NAME
			,REG_DATE = clpo.REG_DATE
			,ASLOB = clpo.ASLOB
			,assumed_ceded_flg = clpo.assumed_ceded_flg
			,accidentyear = CAST(per.AccidentYear AS VARCHAR(4))
			,cat_key = ''
			,catcode = ''
			,TIRS_CLM_CD = clpo.TIRS_CLM_CD
			,Claim_NBR = clpo.Claim_NBR
			,bill_co_br_key = clpo.bill_co_br_key
			,solvency_II_regulatory_key = clpo.solvency_II_regulatory_key
			,adjustmenttype = 'minus informational'
			,SUMMABLE_LOSS_PAID = CAST(-SUM(ROUND(clpo.SUMMABLE_LOSS_PAID * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(clpo.SUMMABLE_LOSS_PAID * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
			,SUMMABLE_LOSS_PAID_USD = CAST(-SUM(ROUND(clpo.SUMMABLE_LOSS_PAID_USD * per.CurrentAllocation, 2) - ROUND(clpo.SUMMABLE_LOSS_PAID_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
			,SUMMABLE_LAE = CAST(-SUM(ROUND(clpo.SUMMABLE_LAE * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(clpo.SUMMABLE_LAE * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
			,SUMMABLE_LAE_USD = CAST(-SUM(ROUND(clpo.SUMMABLE_LAE_USD * per.CurrentAllocation, 2) - ROUND(clpo.SUMMABLE_LAE_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
			,SUMMABLE_OS_LOSS = CAST(-SUM(ROUND(clpo.SUMMABLE_OS_LOSS * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(clpo.SUMMABLE_OS_LOSS * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
			,SUMMABLE_OS_LOSS_USD = CAST(-SUM(ROUND(clpo.SUMMABLE_OS_LOSS_USD * per.CurrentAllocation, 2) - ROUND(clpo.SUMMABLE_OS_LOSS_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
			,SUMMABLE_OS_LOSS_EXP = CAST(-SUM(ROUND(clpo.SUMMABLE_OS_LOSS_EXP * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(clpo.SUMMABLE_OS_LOSS_EXP * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
			,SUMMABLE_OS_LOSS_EXP_USD = CAST(-SUM(ROUND(clpo.SUMMABLE_OS_LOSS_EXP_USD * per.CurrentAllocation, 2) - ROUND(clpo.SUMMABLE_OS_LOSS_EXP_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
			,SUMMABLE_REINSTATEMENT_PREMIUM = CAST(-SUM(ROUND(clpo.SUMMABLE_REINSTATEMENT_PREMIUM * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(clpo.SUMMABLE_REINSTATEMENT_PREMIUM * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
			,SUMMABLE_REINSTATEMENT_PREMIUM_USD = CAST(-SUM(ROUND(clpo.SUMMABLE_REINSTATEMENT_PREMIUM_USD * per.CurrentAllocation, 2) - ROUND(clpo.SUMMABLE_REINSTATEMENT_PREMIUM_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
		INTO #TIRSClaimLossPaidOSLRInfo
		FROM EDW_Staging.assumed.TIRSClaimLossPaidOSLR clpo
		LEFT JOIN EDW_Staging.assumed.CurrencyDecimalPlaces cdp
			ON cdp.CurrencyCode = clpo.ORIGCURR_CD COLLATE DATABASE_DEFAULT
		INNER JOIN EDW_Staging.assumed.ProportionalEarningRate per
			ON per.Contract_NBR = clpo.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND clpo.reg_date BETWEEN per.MovementRegDateStart AND per.MovementRegDateEnd
			AND per.EndDate = '31 Dec 9999'
		WHERE clpo.claim_description IN ('Informational Only', 'Sub Claim')
			AND clpo.EndDate = '31 Dec 9999'
		GROUP BY clpo.treaty_NBR
			,clpo.UNDERWRITING_YEAR
			,clpo.CONTRACT_NBR
			,clpo.CEDED_CONTRACT_NBR
			,clpo.trans_key
			,clpo.DataSet
			,clpo.trans_cd
			,clpo.entry_dt
			,clpo.FromDate
			,clpo.ToDate
			,clpo.section_key
			,clpo.ORIGCURR_CD
			,clpo.TIRS_ORIG_CURR_CD
			,clpo.TIRS_ORIG_CURR_NAME
			,clpo.TIRS_LOB_NAME
			,clpo.REG_DATE
			,clpo.ASLOB
			,clpo.assumed_ceded_flg
			,per.AccidentYear
			,clpo.TIRS_CLM_CD
			,clpo.Claim_NBR
			,clpo.bill_co_br_key
			,clpo.solvency_II_regulatory_key
		UNION ALL
		SELECT TREATY_NBR = clpo.TREATY_NBR
			,UNDERWRITING_YEAR = clpo.UNDERWRITING_YEAR
			,CONTRACT_NBR = clpo.CONTRACT_NBR
			,CEDED_CONTRACT_NBR = clpo.CEDED_CONTRACT_NBR
			,trans_key = clpo.trans_key
			,DataSet = clpo.DataSet
			,trans_cd = clpo.trans_cd
			,entry_dt = clpo.entry_dt
			,FromDate = clpo.FromDate
			,ToDate = clpo.ToDate
			,section_key = clpo.section_key
			,ORIGCURR_CD = clpo.ORIGCURR_CD
			,TIRS_ORIG_CURR_CD = clpo.TIRS_ORIG_CURR_CD
			,TIRS_ORIG_CURR_NAME = clpo.TIRS_ORIG_CURR_NAME
			,TIRS_LOB_NAME = clpo.TIRS_LOB_NAME
			,REG_DATE = clpo.REG_DATE
			,ASLOB = clpo.ASLOB
			,assumed_ceded_flg = clpo.assumed_ceded_flg
			,AccidentYear = clpo.AccidentYear
			,CAT_KEY = clpo.CAT_KEY
			,CatCode = clpo.CatCode
			,TIRS_CLM_CD = clpo.TIRS_CLM_CD
			,Claim_NBR = clpo.Claim_NBR
			,bill_co_br_key = clpo.bill_co_br_key
			,solvency_II_regulatory_key = clpo.solvency_II_regulatory_key
			,adjustmenttype = 'plus informational'
			,Summable_LOSS_PAID = clpo.Summable_LOSS_PAID
			,SUMMABLE_LOSS_PAID_USD = clpo.SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LAE = clpo.SUMMABLE_LAE
			,SUMMABLE_LAE_USD = clpo.SUMMABLE_LAE_USD
			,Summable_OS_LOSS = clpo.Summable_OS_LOSS
			,Summable_OS_LOSS_USD = clpo.Summable_OS_LOSS_USD
			,Summable_os_loss_exp = clpo.Summable_os_loss_exp
			,Summable_os_loss_exp_USD = clpo.Summable_os_loss_exp_USD
			,SUMMABLE_reinstatement_premium = clpo.SUMMABLE_reinstatement_premium
			,SUMMABLE_reinstatement_premium_USD = clpo.SUMMABLE_reinstatement_premium_USD
		FROM EDW_Staging.assumed.TIRSClaimLossPaidOSLR clpo
		WHERE claim_description IN ('Informational Only', 'Sub Claim')
			AND clpo.EndDate = '31 Dec 9999'
		        

		-- Loading logic
		ALTER TABLE #TIRSClaimLossPaidOSLRInfo ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.treaty_NBR
			,s.UNDERWRITING_YEAR
			,s.CONTRACT_NBR
			,s.CEDED_CONTRACT_NBR
			,s.trans_cd
			,s.entry_dt
			,s.FromDate
			,s.ToDate
			,s.section_key
			,s.ORIGCURR_CD
			,s.TIRS_ORIG_CURR_CD
			,s.TIRS_ORIG_CURR_NAME
			,s.TIRS_LOB_NAME
			,s.REG_DATE
			,s.ASLOB
			,s.assumed_ceded_flg
			,s.cat_key
			,s.CatCode
			,s.TIRS_CLM_CD
			,s.Claim_NBR
			,s.bill_co_br_key
			,s.solvency_II_regulatory_key
			,s.SUMMABLE_LOSS_PAID
			,s.SUMMABLE_LOSS_PAID_USD
			,s.SUMMABLE_LAE
			,s.SUMMABLE_LAE_USD
			,s.SUMMABLE_OS_LOSS
			,s.SUMMABLE_OS_LOSS_USD
			,s.SUMMABLE_OS_LOSS_EXP
			,s.SUMMABLE_OS_LOSS_EXP_USD
			,s.SUMMABLE_REINSTATEMENT_PREMIUM
			,s.SUMMABLE_REINSTATEMENT_PREMIUM_USD))
		FROM #TIRSClaimLossPaidOSLRInfo s

		-- check/enforce uniqueness on the dimension source data
		CREATE UNIQUE INDEX assumed_TIRSClaimLossPaidOSLRInfo_UK ON #TIRSClaimLossPaidOSLRInfo (trans_key, DataSet, AccidentYear, AdjustmentType)

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(trans_key INT NOT NULL
		,DataSet TINYINT NOT NULL
		,AccidentYear VARCHAR(4) COLLATE DATABASE_DEFAULT NULL
		,AdjustmentType VARCHAR(19) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (trans_key, DataSet, AccidentYear, AdjustmentType)
		)

		INSERT INTO #LoadOperation
			(trans_key
			,DataSet
			,AccidentYear
			,AdjustmentType
			,Operation
			)
		SELECT trans_key = COALESCE(t.trans_key, s.trans_key)
			,DataSet = COALESCE(t.DataSet, s.DataSet)
			,AccidentYear = COALESCE(t.AccidentYear COLLATE DATABASE_DEFAULT, s.AccidentYear COLLATE DATABASE_DEFAULT)
			,AdjustmentType = COALESCE(t.AdjustmentType COLLATE DATABASE_DEFAULT, s.AdjustmentType COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.TIRSClaimLossPaidOSLRInfoID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSClaimLossPaidOSLRInfo t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #TIRSClaimLossPaidOSLRInfo s
			ON s.trans_key = t.trans_key
			AND s.DataSet = t.DataSet
			AND COALESCE(s.AccidentYear, '^&*') = COALESCE(t.AccidentYear, '^&*') COLLATE DATABASE_DEFAULT
			AND s.AdjustmentType = t.AdjustmentType COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSClaimLossPaidOSLRInfo t
		INNER JOIN #LoadOperation lo
			ON lo.trans_key = t.trans_key
			AND lo.DataSet = t.DataSet
			AND COALESCE(lo.AccidentYear, '^&*') = COALESCE(t.AccidentYear, '^&*')
			AND lo.AdjustmentType = t.AdjustmentType
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSClaimLossPaidOSLRInfo
			(StartDate
			,treaty_NBR
			,UNDERWRITING_YEAR
			,CONTRACT_NBR
			,CEDED_CONTRACT_NBR
			,trans_key
			,DataSet
			,trans_cd
			,entry_dt
			,FromDate
			,ToDate
			,section_key
			,ORIGCURR_CD
			,TIRS_ORIG_CURR_CD
			,TIRS_ORIG_CURR_NAME
			,TIRS_LOB_NAME
			,REG_DATE
			,ASLOB
			,assumed_ceded_flg
			,AccidentYear
			,cat_key
			,CatCode
			,TIRS_CLM_CD
			,Claim_NBR
			,bill_co_br_key
			,solvency_II_regulatory_key
			,AdjustmentType
			,SUMMABLE_LOSS_PAID
			,SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LAE
			,SUMMABLE_LAE_USD
			,SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_USD
			,SUMMABLE_OS_LOSS_EXP
			,SUMMABLE_OS_LOSS_EXP_USD
			,SUMMABLE_REINSTATEMENT_PREMIUM
			,SUMMABLE_REINSTATEMENT_PREMIUM_USD
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.treaty_NBR
			,s.UNDERWRITING_YEAR
			,s.CONTRACT_NBR
			,s.CEDED_CONTRACT_NBR
			,s.trans_key
			,s.DataSet
			,s.trans_cd
			,s.entry_dt
			,s.FromDate
			,s.ToDate
			,s.section_key
			,s.ORIGCURR_CD
			,s.TIRS_ORIG_CURR_CD
			,s.TIRS_ORIG_CURR_NAME
			,s.TIRS_LOB_NAME
			,s.REG_DATE
			,s.ASLOB
			,s.assumed_ceded_flg
			,s.AccidentYear
			,s.cat_key
			,s.CatCode
			,s.TIRS_CLM_CD
			,s.Claim_NBR
			,s.bill_co_br_key
			,s.solvency_II_regulatory_key
			,s.AdjustmentType
			,s.SUMMABLE_LOSS_PAID
			,s.SUMMABLE_LOSS_PAID_USD
			,s.SUMMABLE_LAE
			,s.SUMMABLE_LAE_USD
			,s.SUMMABLE_OS_LOSS
			,s.SUMMABLE_OS_LOSS_USD
			,s.SUMMABLE_OS_LOSS_EXP
			,s.SUMMABLE_OS_LOSS_EXP_USD
			,s.SUMMABLE_REINSTATEMENT_PREMIUM
			,s.SUMMABLE_REINSTATEMENT_PREMIUM_USD
			,s.DataHash
		FROM #TIRSClaimLossPaidOSLRInfo s
		INNER JOIN #LoadOperation lo
			ON lo.trans_key = s.trans_key
			AND lo.DataSet = s.DataSet
			AND COALESCE(lo.AccidentYear, '^&*') = COALESCE(s.AccidentYear, '^&*') COLLATE DATABASE_DEFAULT
			AND lo.AdjustmentType = s.AdjustmentType COLLATE DATABASE_DEFAULT
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
