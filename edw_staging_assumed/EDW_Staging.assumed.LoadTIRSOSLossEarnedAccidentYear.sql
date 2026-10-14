-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSOSLossEarnedAccidentYear

CREATE   PROCEDURE assumed.LoadTIRSOSLossEarnedAccidentYear
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
		
		DROP TABLE IF EXISTS #TIRSOSLossEarnedAccidentYear
		
		SELECT x.CONTRACT_NBR
			,x.assumed_ceded_flg
			,x.TIRS_ORIG_CURR_CD
			,x.LOB_NAME
			,x.reg_date
			,x.bill_co_br_key
			,x.AccidentYear
			,x.SUMMABLE_OS_LOSS
			,x.SUMMABLE_OS_LOSS_USD
			,x.SUMMABLE_OS_LOSS_EXP
			,x.SUMMABLE_OS_LOSS_EXP_USD
		INTO #TIRSOSLossEarnedAccidentYear
		FROM (
			SELECT olm.CONTRACT_NBR
				,olm.assumed_ceded_flg
				,olm.TIRS_ORIG_CURR_CD
				,olm.LOB_NAME
				,olm.reg_date
				,olm.bill_co_br_key
				,AccidentYear = per.AccidentYear
				,SUMMABLE_OS_LOSS = CAST(SUM(ROUND(olm.SUMMABLE_OS_LOSS * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(olm.SUMMABLE_OS_LOSS * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_OS_LOSS_USD = CAST(SUM(ROUND((ROUND(olm.SUMMABLE_OS_LOSS * per.CurrentAllocation, 2) - ROUND(olm.SUMMABLE_OS_LOSS * per.PreviousAllocation, 2)) * xcc.xch_rt, 2)) AS DECIMAL(19,2))
				,SUMMABLE_OS_LOSS_EXP = CAST(SUM(ROUND(olm.SUMMABLE_OS_LOSS_EXP * per.CurrentAllocation, COALESCE(cdp.DecPlaces, 2)) - ROUND(olm.SUMMABLE_OS_LOSS_EXP * per.PreviousAllocation, COALESCE(cdp.DecPlaces, 2))) AS DECIMAL(19,2))
				,SUMMABLE_OS_LOSS_EXP_USD = CAST(SUM(ROUND((ROUND(olm.SUMMABLE_OS_LOSS_EXP * per.CurrentAllocation, 2) - ROUND(olm.SUMMABLE_OS_LOSS_EXP * per.PreviousAllocation, 2)) * xcc.xch_rt, 2)) AS DECIMAL(19,2))
			FROM EDW_Staging.assumed.TIRSOSLossMovement olm
			INNER JOIN EDW_Staging.assumed.ProportionalEarningRate per
				ON per.Contract_NBR = olm.CONTRACT_NBR
				AND olm.reg_date BETWEEN per.MovementRegDateStart AND per.MovementRegDateEnd
				AND per.EndDate = '31 Dec 9999'
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xcc
				ON olm.TIRS_ORIG_CURR_CD = xcc.curr_cd COLLATE DATABASE_DEFAULT
					AND olm.reg_date = xcc.xch_rt_dt
			LEFT JOIN EDW_Staging.assumed.CurrencyDecimalPlaces cdp
				ON cdp.CurrencyCode = xcc.curr_iso_cd
				AND cdp.EndDate = '31 Dec 9999'
			WHERE olm.EndDate = '31 Dec 9999'
			GROUP BY olm.CONTRACT_NBR
				,olm.assumed_ceded_flg
				,olm.TIRS_ORIG_CURR_CD
				,olm.LOB_NAME
				,olm.reg_date
				,olm.bill_co_br_key
				,per.AccidentYear
			) x
		WHERE NOT (x.SUMMABLE_OS_LOSS = 0
			AND x.SUMMABLE_OS_LOSS_EXP = 0
			AND x.SUMMABLE_OS_LOSS_USD = 0
			AND x.SUMMABLE_OS_LOSS_EXP_USD = 0
			)
		

		-- Loading logic
		ALTER TABLE #TIRSOSLossEarnedAccidentYear ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.bill_co_br_key
			, '|', s.SUMMABLE_OS_LOSS
			, '|', s.SUMMABLE_OS_LOSS_USD
			, '|', s.SUMMABLE_OS_LOSS_EXP
			, '|', s.SUMMABLE_OS_LOSS_EXP_USD))
		FROM #TIRSOSLossEarnedAccidentYear s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,assumed_ceded_flg CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,LOB_NAME VARCHAR(255) COLLATE DATABASE_DEFAULT NOT NULL
		,reg_date DATE NOT NULL
		,AccidentYear INT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, assumed_ceded_flg, TIRS_ORIG_CURR_CD, LOB_NAME, reg_date, AccidentYear)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,assumed_ceded_flg
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,AccidentYear
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,assumed_ceded_flg = COALESCE(t.assumed_ceded_flg COLLATE DATABASE_DEFAULT, s.assumed_ceded_flg COLLATE DATABASE_DEFAULT)
			,TIRS_ORIG_CURR_CD = COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
			,LOB_NAME = COALESCE(t.LOB_NAME COLLATE DATABASE_DEFAULT, s.LOB_NAME COLLATE DATABASE_DEFAULT)
			,reg_date = COALESCE(t.reg_date, s.reg_date)
			,AccidentYear = COALESCE(t.AccidentYear, s.AccidentYear)
			,Operation = CASE WHEN t.TIRSOSLossEarnedAccidentYearID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSOSLossEarnedAccidentYear t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #TIRSOSLossEarnedAccidentYear s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.assumed_ceded_flg = t.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			AND s.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND s.LOB_NAME = t.LOB_NAME COLLATE DATABASE_DEFAULT
			AND s.reg_date = t.reg_date
			AND COALESCE(s.AccidentYear, -1) = COALESCE(t.AccidentYear, -1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSOSLossEarnedAccidentYear t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND lo.assumed_ceded_flg = t.assumed_ceded_flg
			AND lo.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD
			AND lo.LOB_NAME = t.LOB_NAME
			AND lo.reg_date = t.reg_date
			AND COALESCE(lo.AccidentYear, -1) = COALESCE(t.AccidentYear, -1)
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSOSLossEarnedAccidentYear
			(StartDate
			,CONTRACT_NBR
			,assumed_ceded_flg
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,bill_co_br_key
			,AccidentYear
			,SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_USD
			,SUMMABLE_OS_LOSS_EXP
			,SUMMABLE_OS_LOSS_EXP_USD
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.assumed_ceded_flg
			,s.TIRS_ORIG_CURR_CD
			,s.LOB_NAME
			,s.reg_date
			,s.bill_co_br_key
			,s.AccidentYear
			,s.SUMMABLE_OS_LOSS
			,s.SUMMABLE_OS_LOSS_USD
			,s.SUMMABLE_OS_LOSS_EXP
			,s.SUMMABLE_OS_LOSS_EXP_USD
			,s.DataHash
		FROM #TIRSOSLossEarnedAccidentYear s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.assumed_ceded_flg = s.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			AND lo.TIRS_ORIG_CURR_CD = s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND lo.LOB_NAME = s.LOB_NAME COLLATE DATABASE_DEFAULT
			AND lo.reg_date = s.reg_date
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
