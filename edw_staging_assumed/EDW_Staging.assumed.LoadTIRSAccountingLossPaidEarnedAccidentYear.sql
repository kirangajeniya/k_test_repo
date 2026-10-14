-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSAccountingLossPaidEarnedAccidentYear

CREATE   PROCEDURE [assumed].[LoadTIRSAccountingLossPaidEarnedAccidentYear]
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
		DROP TABLE IF EXISTS #TIRSAccountingLossPaidEarnedAccidentYear
		
		SELECT
			 x.CONTRACT_NBR
			,x.byline_key
			,x.doc_key
			,x.doc_type_cd
			,x.due_dt
			,x.acct_from_dt
			,x.acct_to_dt
			,x.assumed_ceded_flg
			,x.TIRS_ORIG_CURR_CD
			,x.LOB_NAME
			,x.reg_date
			,x.bill_co_br_key
			,x.AccidentYear
			,x.Summable_LOSS_PAID
			,x.SUMMABLE_LOSS_PAID_USD
			,x.SUMMABLE_LOSS_EXP_PAID
			,x.SUMMABLE_LOSS_EXP_PAID_USD
			,x.SUMMABLE_LAE
			,x.SUMMABLE_LAE_USD
			,x.SUMMABLE_CASH_LOSS_ADV_AMT
			,x.SUMMABLE_CASH_LOSS_ADV_AMT_USD
			,x.SUMMABLE_CASH_LOSS_REFUND
			,x.SUMMABLE_CASH_LOSS_REFUND_USD
			,x.SUMMABLE_funds_released_losses
			,x.SUMMABLE_funds_released_losses_USD
			,x.SUMMABLE_reinstatement_premium
			,x.SUMMABLE_reinstatement_premium_USD
		INTO #TIRSAccountingLossPaidEarnedAccidentYear
		FROM (
			SELECT alp.CONTRACT_NBR
				,alp.byline_key
				,alp.doc_key
				,alp.assumed_ceded_flg
				,alp.TIRS_ORIG_CURR_CD
				,alp.LOB_NAME
				,alp.reg_date
				,alp.doc_type_cd
				,alp.due_dt
			    ,alp.acct_from_dt
			    ,alp.acct_to_dt
				,alp.bill_co_br_key
				,AccidentYear = per.AccidentYear
				,SUMMABLE_LOSS_PAID = CAST(SUM(ROUND(alp.Summable_LOSS_PAID * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(alp.Summable_LOSS_PAID * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_LOSS_PAID_USD = CAST(SUM(ROUND(alp.SUMMABLE_LOSS_PAID_USD * per.CurrentAllocation, 2) - ROUND(alp.SUMMABLE_LOSS_PAID_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
				,SUMMABLE_LOSS_EXP_PAID = CAST(SUM(ROUND(alp.SUMMABLE_LOSS_EXP_PAID * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(alp.SUMMABLE_LOSS_EXP_PAID * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_LOSS_EXP_PAID_USD = CAST(SUM(ROUND(alp.SUMMABLE_LOSS_EXP_PAID_USD * per.CurrentAllocation, 2) - ROUND(alp.SUMMABLE_LOSS_EXP_PAID_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
				,SUMMABLE_LAE = CAST(SUM(ROUND(alp.SUMMABLE_LAE * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(alp.SUMMABLE_LAE * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_LAE_USD = CAST(SUM(ROUND(alp.SUMMABLE_LAE_USD * per.CurrentAllocation, 2) - ROUND(alp.SUMMABLE_LAE_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
				,SUMMABLE_CASH_LOSS_ADV_AMT = CAST(SUM(ROUND(alp.SUMMABLE_CASH_LOSS_ADV_AMT * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(alp.SUMMABLE_CASH_LOSS_ADV_AMT * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_CASH_LOSS_ADV_AMT_USD = CAST(SUM(ROUND(alp.SUMMABLE_CASH_LOSS_ADV_AMT_USD * per.CurrentAllocation, 2) - ROUND(alp.SUMMABLE_CASH_LOSS_ADV_AMT_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
				,SUMMABLE_CASH_LOSS_REFUND = CAST(SUM(ROUND(alp.SUMMABLE_CASH_LOSS_REFUND * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(alp.SUMMABLE_CASH_LOSS_REFUND * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_CASH_LOSS_REFUND_USD = CAST(SUM(ROUND(alp.SUMMABLE_CASH_LOSS_REFUND_USD * per.CurrentAllocation, 2) - ROUND(alp.SUMMABLE_CASH_LOSS_REFUND_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
				,SUMMABLE_funds_released_losses = CAST(SUM(ROUND(alp.SUMMABLE_funds_released_losses * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(alp.SUMMABLE_funds_released_losses * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_funds_released_losses_USD = CAST(SUM(ROUND(alp.SUMMABLE_funds_released_losses_USD * per.CurrentAllocation, 2) - ROUND(alp.SUMMABLE_funds_released_losses_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
				,SUMMABLE_reinstatement_premium = CAST(SUM(ROUND(alp.SUMMABLE_reinstatement_premium * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(alp.SUMMABLE_reinstatement_premium * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_reinstatement_premium_USD = CAST(SUM(ROUND(alp.SUMMABLE_reinstatement_premium_USD * per.CurrentAllocation, 2) - ROUND(alp.SUMMABLE_reinstatement_premium_USD * per.PreviousAllocation, 2)) AS DECIMAL(19,2))
			FROM EDW_Staging.assumed.TIRSAccountingLossPaid alp
			INNER JOIN EDW_Staging.assumed.ProportionalEarningRate per
				ON per.Contract_NBR = alp.CONTRACT_NBR
				AND alp.reg_date BETWEEN per.MovementRegDateStart AND per.MovementRegDateEnd
				AND per.EndDate = '31 Dec 9999'
			INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names xcn
				ON xcn.curr_cd = alp.TIRS_ORIG_CURR_CD
			LEFT JOIN EDW_Staging.assumed.CurrencyDecimalPlaces cdp
				ON cdp.CurrencyCode = xcn.curr_iso_cd
				AND cdp.EndDate = '31 Dec 9999'
			WHERE alp.EndDate = '31 Dec 9999'
			GROUP BY alp.CONTRACT_NBR
				,alp.byline_key
				,alp.doc_key
				,alp.assumed_ceded_flg
				,alp.TIRS_ORIG_CURR_CD
				,alp.LOB_NAME
				,alp.reg_date
				,alp.doc_type_cd
				,alp.due_dt
				,alp.acct_from_dt
			    ,alp.acct_to_dt
				,alp.bill_co_br_key
				,per.AccidentYear
			) x
		WHERE NOT (SUMMABLE_LOSS_PAID = 0
					AND SUMMABLE_LOSS_PAID_USD = 0
					AND SUMMABLE_LOSS_EXP_PAID = 0
					AND SUMMABLE_LOSS_EXP_PAID_USD = 0
					AND SUMMABLE_LAE = 0
					AND SUMMABLE_LAE_USD = 0
					AND SUMMABLE_CASH_LOSS_ADV_AMT = 0
					AND SUMMABLE_CASH_LOSS_ADV_AMT_USD = 0
					AND SUMMABLE_CASH_LOSS_REFUND = 0
					AND SUMMABLE_CASH_LOSS_REFUND_USD = 0
					AND SUMMABLE_funds_released_losses = 0
					AND SUMMABLE_funds_released_losses_USD = 0
					AND SUMMABLE_reinstatement_premium = 0
					AND SUMMABLE_reinstatement_premium_USD = 0
					)	

		-- Loading logic
		ALTER TABLE #TIRSAccountingLossPaidEarnedAccidentYear ADD DataHash BINARY(20) NULL

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
								 ,s.SUMMABLE_FUNDS_RELEASED_LOSSES
								 ,s.SUMMABLE_FUNDS_RELEASED_LOSSES_USD
								 ,s.SUMMABLE_REINSTATEMENT_PREMIUM
								 ,s.SUMMABLE_REINSTATEMENT_PREMIUM_USD
								 ,s.acct_from_dt
								 ,s.acct_to_dt
								 ,s.bill_co_br_key
								 ,s.doc_key
								 ))
		FROM #TIRSAccountingLossPaidEarnedAccidentYear s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,byline_key INT NOT NULL
		,assumed_ceded_flg CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NULL
		,LOB_NAME VARCHAR(255) COLLATE DATABASE_DEFAULT NULL
		,reg_date DATE NULL
		,AccidentYear INT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, byline_key, assumed_ceded_flg, TIRS_ORIG_CURR_CD, LOB_NAME, reg_date, AccidentYear)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,byline_key
			,assumed_ceded_flg
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,AccidentYear
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,byline_key = COALESCE(t.byline_key, s.byline_key)
			,assumed_ceded_flg = COALESCE(t.assumed_ceded_flg COLLATE DATABASE_DEFAULT, s.assumed_ceded_flg COLLATE DATABASE_DEFAULT)
			,TIRS_ORIG_CURR_CD = COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
			,LOB_NAME = COALESCE(t.LOB_NAME COLLATE DATABASE_DEFAULT, s.LOB_NAME COLLATE DATABASE_DEFAULT)
			,reg_date = COALESCE(t.reg_date, s.reg_date)
			,AccidentYear = COALESCE(t.AccidentYear, s.AccidentYear)
			,Operation = CASE WHEN t.TIRSAccountingLossPaidEarnedAccidentYearID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSAccountingLossPaidEarnedAccidentYear t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #TIRSAccountingLossPaidEarnedAccidentYear s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.byline_key = t.byline_key
			AND s.assumed_ceded_flg = t.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			AND COALESCE(s.TIRS_ORIG_CURR_CD, '^&*') = COALESCE(t.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.LOB_NAME, '^&*') = COALESCE(t.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(s.reg_date, '1 Jan 1900') = COALESCE(t.reg_date, '1 Jan 1900')
			AND COALESCE(s.AccidentYear, -1) = COALESCE(t.AccidentYear, -1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSAccountingLossPaidEarnedAccidentYear t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND lo.byline_key = t.byline_key
			AND lo.assumed_ceded_flg = t.assumed_ceded_flg
			AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*') = COALESCE(t.TIRS_ORIG_CURR_CD, '^&*')
			AND COALESCE(lo.LOB_NAME, '^&*') = COALESCE(t.LOB_NAME, '^&*')
			AND COALESCE(lo.reg_date, '1 Jan 1900') = COALESCE(t.reg_date, '1 Jan 1900')
			AND COALESCE(lo.AccidentYear, -1) = COALESCE(t.AccidentYear, -1)
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSAccountingLossPaidEarnedAccidentYear
			(StartDate
			,CONTRACT_NBR
			,byline_key
			,doc_type_cd
			,due_dt
			,assumed_ceded_flg
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,AccidentYear
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
			,SUMMABLE_FUNDS_RELEASED_LOSSES
			,SUMMABLE_FUNDS_RELEASED_LOSSES_USD
			,SUMMABLE_REINSTATEMENT_PREMIUM
			,SUMMABLE_REINSTATEMENT_PREMIUM_USD
			,acct_from_dt
			,acct_to_dt
			,bill_co_br_key
			,doc_key
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.byline_key
			,s.doc_type_cd
			,s.due_dt
			,s.assumed_ceded_flg
			,s.TIRS_ORIG_CURR_CD
			,s.LOB_NAME
			,s.reg_date
			,s.AccidentYear
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
			,s.SUMMABLE_FUNDS_RELEASED_LOSSES
			,s.SUMMABLE_FUNDS_RELEASED_LOSSES_USD
			,s.SUMMABLE_REINSTATEMENT_PREMIUM
			,s.SUMMABLE_REINSTATEMENT_PREMIUM_USD
			,s.acct_from_dt
			,s.acct_to_dt
			,s.bill_co_br_key
			,s.doc_key
			,s.DataHash
		FROM #TIRSAccountingLossPaidEarnedAccidentYear s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.byline_key = s.byline_key
			AND lo.assumed_ceded_flg = s.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*') = COALESCE(s.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.LOB_NAME, '^&*') = COALESCE(s.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.reg_date, '1 Jan 1900') = COALESCE(s.reg_date, '1 Jan 1900')
			AND COALESCE(lo.AccidentYear, -1) = COALESCE(s.AccidentYear, -1)
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
