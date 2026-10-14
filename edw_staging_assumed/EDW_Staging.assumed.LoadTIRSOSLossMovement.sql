-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSOSLossMovement

CREATE   PROCEDURE assumed.LoadTIRSOSLossMovement
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
		
		DROP TABLE IF EXISTS #TIRSOSLossCumulative
		
		SELECT x.CONTRACT_NBR	
			,x.assumed_ceded_flg
			,x.TIRS_ORIG_CURR_CD
			,x.LOB_NAME
			,x.acct_to_dt
			,x.reg_date
			,x.bill_co_br_key
			,x.os_loss
			,x.os_loss_exp
		INTO #TIRSOSLossCumulative
		FROM (
				SELECT CONTRACT_NBR = tolb.CONTRACT_NBR
					,assumed_ceded_flg = tolb.assumed_ceded_flg
					,TIRS_ORIG_CURR_CD = tolb.TIRS_ORIG_CURR_CD
					,LOB_NAME = tolb.LOB_NAME
					,acct_to_dt = tolb.acct_to_dt
					,reg_date = tolb.reg_date
					,bill_co_br_key = tolb.bill_co_br_key
					,max_acct_to_dt = MAX(tolb.acct_to_dt) OVER (PARTITION BY tolb.CONTRACT_NBR, tolb.assumed_ceded_flg, tolb.TIRS_ORIG_CURR_CD ORDER BY tolb.reg_date)
					,os_loss = ROUND(SUM(tolb.os_loss) OVER (PARTITION BY tolb.CONTRACT_NBR, tolb.assumed_ceded_flg, tolb.TIRS_ORIG_CURR_CD, tolb.acct_to_dt, tolb.LOB_NAME ORDER BY tolb.reg_date), COALESCE(cdp.DecPlaces, 2))
					,os_loss_exp = ROUND(SUM(tolb.os_loss_exp) OVER (PARTITION BY tolb.CONTRACT_NBR, tolb.assumed_ceded_flg, tolb.TIRS_ORIG_CURR_CD, tolb.acct_to_dt, tolb.LOB_NAME ORDER BY tolb.reg_date), COALESCE(cdp.DecPlaces, 2))
				FROM EDW_Staging.assumed.TIRSOSLOSSBalance tolb
				INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names xcn
					ON xcn.curr_cd = tolb.TIRS_ORIG_CURR_CD
				LEFT JOIN EDW_Staging.assumed.CurrencyDecimalPlaces cdp
					ON cdp.CurrencyCode = xcn.curr_iso_cd
					AND cdp.EndDate = '31 Dec 9999'
				WHERE tolb.EndDate = '31 Dec 9999'
			) x
		WHERE x.acct_to_dt = x.max_acct_to_dt -- only interested in the latest account per date balances, ignore any earlier ones
		
		DROP TABLE IF EXISTS #TIRSOSLossMovement
		
		SELECT CONTRACT_NBR = y.CONTRACT_NBR
			,TIRS_ORIG_CURR_CD = y.TIRS_ORIG_CURR_CD
			,LOB_NAME = y.LOB_NAME
			,reg_date = y.reg_date
			,bill_co_br_key = y.bill_co_br_key
			,assumed_ceded_flg = y.assumed_ceded_flg
			,SUMMABLE_OS_LOSS = SUM(COALESCE(y.os_loss, 0))
			,SUMMABLE_OS_LOSS_EXP = SUM(COALESCE(y.os_loss_exp, 0))
		INTO #TIRSOSLossMovement
		FROM (
			-- convert the balances to movements
			SELECT CONTRACT_NBR = olc.CONTRACT_NBR
				,assumed_ceded_flg = olc.assumed_ceded_flg
				,TIRS_ORIG_CURR_CD = olc.TIRS_ORIG_CURR_CD
				,LOB_NAME = olc.LOB_NAME
				,reg_date = olc.reg_date
				,bill_co_br_key = olc.bill_co_br_key
				,os_loss = olc.os_loss - COALESCE(LAG(olc.os_loss) OVER (PARTITION BY olc.CONTRACT_NBR, olc.assumed_ceded_flg, olc.TIRS_ORIG_CURR_CD, olc.LOB_NAME ORDER BY olc.reg_date), 0)
				,os_loss_exp = olc.os_loss_exp - COALESCE(LAG(olc.os_loss_exp) OVER (PARTITION BY olc.CONTRACT_NBR, olc.assumed_ceded_flg, olc.TIRS_ORIG_CURR_CD, olc.LOB_NAME ORDER BY olc.reg_date), 0)
			FROM #TIRSOSLossCumulative olc
			) y
		GROUP BY y.CONTRACT_NBR
			,y.assumed_ceded_flg
			,y.reg_date
			,y.bill_co_br_key
			,y.TIRS_ORIG_CURR_CD
			,y.LOB_NAME
		HAVING NOT (SUM(COALESCE(y.os_loss, 0)) = 0
			AND SUM(COALESCE(y.os_loss_exp, 0)) = 0
			)
		

		-- Loading logic
		ALTER TABLE #TIRSOSLossMovement ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.SUMMABLE_OS_LOSS
			, '|', s.bill_co_br_key
			, '|', s.SUMMABLE_OS_LOSS_EXP))
		FROM #TIRSOSLossMovement s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,LOB_NAME VARCHAR(255) COLLATE DATABASE_DEFAULT NOT NULL
		,reg_date DATE NOT NULL
		,assumed_ceded_flg CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, TIRS_ORIG_CURR_CD, LOB_NAME, reg_date, assumed_ceded_flg)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,assumed_ceded_flg
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,TIRS_ORIG_CURR_CD = COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
			,LOB_NAME = COALESCE(t.LOB_NAME COLLATE DATABASE_DEFAULT, s.LOB_NAME COLLATE DATABASE_DEFAULT)
			,reg_date = COALESCE(t.reg_date, s.reg_date)
			,assumed_ceded_flg = COALESCE(t.assumed_ceded_flg COLLATE DATABASE_DEFAULT, s.assumed_ceded_flg COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.TIRSOSLossMovementID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSOSLossMovement t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #TIRSOSLossMovement s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND s.LOB_NAME = t.LOB_NAME COLLATE DATABASE_DEFAULT
			AND s.reg_date = t.reg_date
			AND s.assumed_ceded_flg = t.assumed_ceded_flg COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSOSLossMovement t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND lo.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD
			AND lo.LOB_NAME = t.LOB_NAME
			AND lo.reg_date = t.reg_date
			AND lo.assumed_ceded_flg = t.assumed_ceded_flg
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSOSLossMovement
			(StartDate
			,CONTRACT_NBR
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,reg_date
			,bill_co_br_key
			,assumed_ceded_flg
			,SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_EXP
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.TIRS_ORIG_CURR_CD
			,s.LOB_NAME
			,s.reg_date
			,s.bill_co_br_key
			,s.assumed_ceded_flg
			,s.SUMMABLE_OS_LOSS
			,s.SUMMABLE_OS_LOSS_EXP
			,s.DataHash
		FROM #TIRSOSLossMovement s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.TIRS_ORIG_CURR_CD = s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND lo.LOB_NAME = s.LOB_NAME COLLATE DATABASE_DEFAULT
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
