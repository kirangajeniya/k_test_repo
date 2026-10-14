-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadProportionalEarningRate

CREATE   PROCEDURE assumed.LoadProportionalEarningRate
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
		
		DROP TABLE IF EXISTS #CurrentPeriod
			
		SELECT CurrentAccountingPeriod = CAST(x.AccountingPeriodDate AS DATE)
			,CurrentAccountingPeriodStart = x.AccountingStartDate
			,CurrentAccountingPeriodEnd = x.AccountingEndDate
			-- percentage of current account period completed (exclude today)
			,CurrentAccountingPeriodPercentRemaining = DATEDIFF(DAY, x.AccountingStartDate, CAST(SYSDATETIME() AS DATE)) / (DATEDIFF(DAY, x.AccountingStartDate, x.AccountingEndDate) + 1.0)
		INTO #CurrentPeriod
		FROM (
			SELECT AccountingPeriodDate = ap.accounting_period_date
				,AccountingStartDate = CAST(DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (ORDER BY ap.accounting_period_key)) AS DATE)
				,AccountingEndDate = CAST(ap.accounting_period_close_date AS DATE)
			FROM Insight.dbo.accounting_periods ap
			) x
		WHERE x.AccountingStartDate IS NOT NULL
			AND CAST(SYSDATETIME() AS DATE) BETWEEN x.AccountingStartDate AND x.AccountingEndDate
			
		-- create earnings rates for each period by prorating earning rates for the period and prior periods such that it is fully earned by the period
		DROP TABLE IF EXISTS #ProportionalEarningRate
		
		SELECT x.Contract_NBR
			,x.MovementRegDateStart
			,x.MovementRegDateEnd
			,x.AccidentYear
			,CurrentAllocation = x.ProRatedAlloc
			,PreviousAllocation = CAST(COALESCE(LAG(x.ProRatedAlloc) OVER (PARTITION BY x.CONTRACT_NBR, x.MovementRegDateStart ORDER BY x.AccidentYear), 0) AS DECIMAL(9,6))
		INTO #ProportionalEarningRate
		FROM (
			SELECT c.Contract_NBR
				,c.MovementRegDateStart
				,c.MovementRegDateEnd
				,AccidentYear = YEAR(t2.Reg_Date)
				,ProRatedAlloc = CASE WHEN t2.Reg_Date = c.MovementRegDateStart THEN 1 ELSE t2.Earning_Allocation_RT_PCT * c.InitialAlloc / c.Earning_Allocation_RT_PCT END
				,LatestPerAccidentYear = ROW_NUMBER() OVER (PARTITION BY c.Contract_NBR, c.MovementRegDateStart, YEAR(t2.Reg_Date) ORDER BY t2.Reg_Date DESC)
			FROM (
				SELECT tcer.Contract_NBR
					,MovementRegDateStart = CAST(tcer.Reg_Date AS DATE)
					,MovementRegDateEnd = CAST(COALESCE(DATEADD(MONTH, -1, LEAD(tcer.Reg_Date) OVER (PARTITION BY tcer.Contract_NBR ORDER BY tcer.Reg_Date)), '1 Dec 9999') AS DATE)
					,InitialAlloc = COALESCE(LAG(tcer.Earning_Allocation_RT_PCT) OVER (PARTITION BY tcer.CONTRACT_NBR ORDER BY tcer.Reg_Date) * 1 / tcer.Earning_Allocation_RT_PCT, 1)
					,Earning_Allocation_RT_PCT = COALESCE(LAG(tcer.Earning_Allocation_RT_PCT) OVER (PARTITION BY tcer.CONTRACT_NBR ORDER BY tcer.Reg_Date), tcer.Earning_Allocation_RT_PCT)
				FROM EDW_PREPROD.dbo.TIRS_Contract_Earning_Rates tcer
				INNER JOIN #CurrentPeriod cp
					ON cp.CurrentAccountingPeriod >= tcer.Reg_Date
				) c
			INNER JOIN EDW_PREPROD.dbo.TIRS_Contract_Earning_Rates t2
				ON t2.reg_DATE <= c.MovementRegDateStart
				AND t2.CONTRACT_NBR = c.CONTRACT_NBR
				AND t2.Earning_Allocation_RT_PCT IS NOT NULL
			) x
		WHERE x.LatestPerAccidentYear = 1
		

		-- Loading logic
		ALTER TABLE #ProportionalEarningRate ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.MovementRegDateEnd
			, '|', s.CurrentAllocation
			, '|', s.PreviousAllocation))
		FROM #ProportionalEarningRate s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL
		,MovementRegDateStart DATE NOT NULL
		,AccidentYear INT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, MovementRegDateStart, AccidentYear)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,MovementRegDateStart
			,AccidentYear
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,MovementRegDateStart = COALESCE(t.MovementRegDateStart, s.MovementRegDateStart)
			,AccidentYear = COALESCE(t.AccidentYear, s.AccidentYear)
			,Operation = CASE WHEN t.ProportionalEarningRateID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.ProportionalEarningRate t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #ProportionalEarningRate s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.MovementRegDateStart = t.MovementRegDateStart
			AND s.AccidentYear = t.AccidentYear
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.ProportionalEarningRate t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND lo.MovementRegDateStart = t.MovementRegDateStart
			AND lo.AccidentYear = t.AccidentYear
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.ProportionalEarningRate
			(StartDate
			,CONTRACT_NBR
			,MovementRegDateStart
			,MovementRegDateEnd
			,AccidentYear
			,CurrentAllocation
			,PreviousAllocation
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.MovementRegDateStart
			,s.MovementRegDateEnd
			,s.AccidentYear
			,s.CurrentAllocation
			,s.PreviousAllocation
			,s.DataHash
		FROM #ProportionalEarningRate s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.MovementRegDateStart = s.MovementRegDateStart
			AND lo.AccidentYear = s.AccidentYear
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
