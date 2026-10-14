-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadBridgeContractBroker


CREATE   PROCEDURE assumed.LoadBridgeContractBroker
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #AssumedCeded
		
		SELECT x.assumed_ceded_flg
			,x.trty_key
			,x.CONTRACT_NBR
		INTO #AssumedCeded
		FROM (
			SELECT t.assumed_ceded_flg
				,t.trty_key
				,CONTRACT_NBR = CONCAT(LEFT(tm.trty_no, 5), tm.und_yr)
				,MostRecent = ROW_NUMBER() OVER (PARTITION BY CONCAT(LEFT(tm.trty_no, 5), tm.und_yr) ORDER BY t.trty_key DESC)
			FROM (
				SELECT DISTINCT ad.assumed_ceded_flg
					,trty_key = CASE WHEN ad.assumed_ceded_flg = 'A' THEN ad.trty_key ELSE ad.ceded_trty_key END
				FROM SRC_TIRS_DB.dbo.acct_doc ad
				) t
			INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
				ON tm.trty_key = t.trty_key
			) x
		WHERE MostRecent = 1
		UNION
		SELECT DISTINCT assumed_ceded_flg = 'C'
			,tm.trty_key
			,CONTRACT_NBR = CONCAT(LEFT(tm.trty_no, 5), tm.und_yr)
		FROM SRC_TIRS_DB.dbo.trty_participant tp
		INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = tp.trty_key
		
		DROP TABLE IF EXISTS #BridgeContractBrokerSource
		
		SELECT ac.assumed_ceded_flg
			,ac.CONTRACT_NBR
			,tp.participant_br_key
			,brkr_br_key = COALESCE(tp.brkr_br_key, tm.brkr_br_key)
			,bill_co_br_key = COALESCE(tp.brkr_br_key, tm.bill_co_br_key)
		INTO #BridgeContractBrokerSource
		FROM #AssumedCeded ac
		INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = ac.trty_key
		LEFT JOIN SRC_TIRS_DB.dbo.trty_participant tp
			ON tp.trty_key = ac.trty_key
			AND ac.assumed_ceded_flg = 'C'
		
		DROP TABLE IF EXISTS #LookupDefault
		
		SELECT DimParticipantUncoded = (SELECT dp.DimParticipantID FROM EDW_PREPROD.assumed.DimParticipant dp WHERE dp.Participant = 'Uncoded' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
			,DimParticipantNA = (SELECT dp.DimParticipantID FROM EDW_PREPROD.assumed.DimParticipant dp WHERE dp.Participant = 'N/A' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
			,DimBrokerUncoded = (SELECT dp.DimBrokerID FROM EDW_PREPROD.assumed.DimBroker dp WHERE dp.BRKR_COMPANY_CD = 'Uncoded' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
			,DimBrokerNA = (SELECT dp.DimBrokerID FROM EDW_PREPROD.assumed.DimBroker dp WHERE dp.BRKR_COMPANY_CD = 'N/A' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
			,DimBillingUncoded = (SELECT dp.DimBillingID FROM EDW_PREPROD.assumed.DimBilling dp WHERE dp.BILL_COMPANY_CD = 'Uncoded' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
			,DimBillingNA = (SELECT dp.DimBillingID FROM EDW_PREPROD.assumed.DimBilling dp WHERE dp.BILL_COMPANY_CD = 'N/A' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
		INTO #LookupDefault
		
		DROP TABLE IF EXISTS #BridgeContractBroker
		
		SELECT dc.DimContractID
			,AssumedCeded = s.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			,DimParticipantID = CASE WHEN s.participant_br_key IS NULL THEN ld.DimParticipantNA ELSE COALESCE(dp.DimParticipantID, ld.DimParticipantUncoded) END
			,DimBrokerID = CASE WHEN s.brkr_br_key IS NULL THEN ld.DimBrokerNA ELSE COALESCE(db.DimBrokerID, ld.DimBrokerUncoded) END
			,DimBillingID = CASE WHEN s.bill_co_br_key IS NULL THEN ld.DimBillingNA ELSE COALESCE(dbi.DimBillingID, ld.DimBillingUncoded) END
		INTO #BridgeContractBroker
		FROM #BridgeContractBrokerSource s
		CROSS JOIN #LookupDefault ld
		INNER JOIN assumed.DimContract dc
			ON dc.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND dc.EndDate = '31 Dec 9999'
		LEFT JOIN assumed.DimParticipant dp
			ON dp.Participant_Key = CAST(s.participant_br_key AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
			AND dp.EndDate = '31 Dec 9999'
		LEFT JOIN assumed.DimBroker db
			ON db.BRKR_COMPANY_CD = CAST(s.brkr_br_key AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
			AND db.EndDate = '31 Dec 9999'
		LEFT JOIN assumed.DimBilling dbi
			ON dbi.BILL_COMPANY_CD = CAST(s.bill_co_br_key AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
			AND dbi.EndDate = '31 Dec 9999'
		
		        

		-- Loading logic
		ALTER TABLE #BridgeContractBroker ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = 0x0000000000000000000000000000000000000000
		FROM #BridgeContractBroker s

		-- check/enforce uniqueness on the dimension source data
		CREATE UNIQUE INDEX assumed_BridgeContractBroker_UK ON #BridgeContractBroker (DimContractID, AssumedCeded, DimParticipantID, DimBrokerID, DimBillingID)

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(DimContractID INT NOT NULL
		,AssumedCeded CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,DimParticipantID INT NOT NULL
		,DimBrokerID INT NOT NULL
		,DimBillingID INT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (DimContractID, AssumedCeded, DimParticipantID, DimBrokerID, DimBillingID)
		)

		INSERT INTO #LoadOperation
			(DimContractID
			,AssumedCeded
			,DimParticipantID
			,DimBrokerID
			,DimBillingID
			,Operation
			)
		SELECT DimContractID = COALESCE(t.DimContractID, s.DimContractID)
			,AssumedCeded = COALESCE(t.AssumedCeded COLLATE DATABASE_DEFAULT, s.AssumedCeded COLLATE DATABASE_DEFAULT)
			,DimParticipantID = COALESCE(t.DimParticipantID, s.DimParticipantID)
			,DimBrokerID = COALESCE(t.DimBrokerID, s.DimBrokerID)
			,DimBillingID = COALESCE(t.DimBillingID, s.DimBillingID)
			,Operation = CASE WHEN t.BridgeContractBrokerID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.BridgeContractBroker t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #BridgeContractBroker s
			ON s.DimContractID = t.DimContractID
			AND s.AssumedCeded = t.AssumedCeded COLLATE DATABASE_DEFAULT
			AND s.DimParticipantID = t.DimParticipantID
			AND s.DimBrokerID = t.DimBrokerID
			AND s.DimBillingID = t.DimBillingID
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.BridgeContractBroker t
		INNER JOIN #LoadOperation lo
			ON lo.DimContractID = t.DimContractID
			AND lo.AssumedCeded = t.AssumedCeded
			AND lo.DimParticipantID = t.DimParticipantID
			AND lo.DimBrokerID = t.DimBrokerID
			AND lo.DimBillingID = t.DimBillingID
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.BridgeContractBroker
			(StartDate
			,DimContractID
			,AssumedCeded
			,DimParticipantID
			,DimBrokerID
			,DimBillingID
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.DimContractID
			,s.AssumedCeded
			,s.DimParticipantID
			,s.DimBrokerID
			,s.DimBillingID
			,s.DataHash
		FROM #BridgeContractBroker s
		INNER JOIN #LoadOperation lo
			ON lo.DimContractID = s.DimContractID
			AND lo.AssumedCeded = s.AssumedCeded COLLATE DATABASE_DEFAULT
			AND lo.DimParticipantID = s.DimParticipantID
			AND lo.DimBrokerID = s.DimBrokerID
			AND lo.DimBillingID = s.DimBillingID
			AND lo.Operation IN ('I', 'U')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U', 'D')), 0)
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
