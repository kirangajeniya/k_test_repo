-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimParticipant

CREATE   PROCEDURE assumed.LoadDimParticipant
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimParticipant
				
		SELECT x.Participant_Key
			,Participant = COALESCE(LEFT(x.Participant, 80), '')
			,FairfaxAbbrv = COALESCE(LEFT(x.FairfaxAbbrv, 20), '')
			,Address1 = xpb.addr_1
			,Address2 = xpb.addr_2
			,Address3 = xpb.addr_3
			,City = xpb.city
			,Zip = xpb.zip_cd
			,State = xpb.state
			,Country = xc.desc_txt
			,Telephone = xpb.telephone
			,SourceCreatedDate = COALESCE(dp.SourceCreatedDate, xpb.touch_dt)
		INTO #DimParticipant
		FROM (
			SELECT tph.Participant_Key
				,tph.Participant
				,tph.FairfaxAbbrv
				,MostRecent = ROW_NUMBER() OVER (PARTITION BY tph.Participant_Key ORDER BY tph.ID DESC)
			FROM dbo.TIRS_PARTICIPANT_HISTORY tph
			) x
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_prod_branches xpb
			ON xpb.prod_br_key = x.Participant_Key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_country xc
			ON xc.country_cd = xpb.country_cd
		LEFT JOIN assumed.DimParticipant dp
			ON dp.EndDate = '31 Dec 9999'
			AND dp.Participant_Key = x.Participant_Key			
		WHERE x.MostRecent = 1
		UNION ALL
		SELECT Participant_Key = -1
			,Participant = 'Uncoded'
			,FairfaxAbbrv = 'Uncoded'
			,Address1 = 'Uncoded'
			,Address2 = 'Uncoded'
			,Address3 = 'Uncoded'
			,City = 'Uncoded'
			,Zip = 'Uncoded'
			,State = 'Uncoded'
			,Country = 'Uncoded'
			,Telephone = 'Uncoded'
			,SourceCreatedDate = NULL
		UNION ALL
		SELECT Participant_Key = -2
			,Participant = 'N/A'
			,FairfaxAbbrv = 'N/A'
			,Address1 = 'N/A'
			,Address2 = 'N/A'
			,Address3 = 'N/A'
			,City = 'N/A'
			,Zip = 'N/A'
			,State = 'N/A'
			,Country = 'N/A'
			,Telephone = 'N/A'
			,SourceCreatedDate = NULL		
		
		        

		-- Loading logic
		ALTER TABLE #DimParticipant ADD DataHash BINARY(20) NULL
		ALTER TABLE #DimParticipant ADD DataHashType1 BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.Participant
			,s.FairfaxAbbrv))
		FROM #DimParticipant s

		UPDATE s
		SET DataHashType1 = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.Address1
			,s.Address2
			,s.Address3
			,s.City
			,s.Zip
			,s.State
			,s.Country
			,s.Telephone
			,s.SourceCreatedDate))
		FROM #DimParticipant s

		-- check/enforce uniqueness on the dimension source data
		CREATE UNIQUE INDEX assumed_DimParticipant_UK ON #DimParticipant (Participant_Key)

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(Participant_Key INT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (Participant_Key)
		)

		INSERT INTO #LoadOperation
			(Participant_Key
			,Operation
			)
		SELECT Participant_Key = COALESCE(t.Participant_Key, s.Participant_Key)
			,Operation = CASE WHEN t.DimParticipantID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimParticipant t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimParticipant s
			ON s.Participant_Key = t.Participant_Key
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimParticipant t
		INNER JOIN #LoadOperation lo
			ON lo.Participant_Key = t.Participant_Key
			AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		UPDATE t
		SET UpdateDate = p.NewStartDate
			,Address1 = s.Address1
			,Address2 = s.Address2
			,Address3 = s.Address3
			,City = s.City
			,Zip = s.Zip
			,State = s.State
			,Country = s.Country
			,Telephone = s.Telephone
			,SourceCreatedDate = s.SourceCreatedDate
			,DataHashType1 = s.DataHashType1
		FROM assumed.DimParticipant t
		INNER JOIN #LoadOperation lo
			ON lo.Participant_Key = t.Participant_Key
			AND lo.Operation IN ('U', '1')
		INNER JOIN #DimParticipant s
			ON s.Participant_Key = t.Participant_Key
		CROSS JOIN #Parameters p

		INSERT INTO assumed.DimParticipant
			(StartDate
			,UpdateDate
			,Participant_Key
			,Participant
			,FairfaxAbbrv
			,Address1
			,Address2
			,Address3
			,City
			,Zip
			,State
			,Country
			,Telephone
			,SourceCreatedDate
			,DataHash
			,DataHashType1
			)
		SELECT StartDate = p.NewStartDate
			,UpdateDate = p.NewStartDate
			,s.Participant_Key
			,s.Participant
			,s.FairfaxAbbrv
			,s.Address1
			,s.Address2
			,s.Address3
			,s.City
			,s.Zip
			,s.State
			,s.Country
			,s.Telephone
			,s.SourceCreatedDate
			,s.DataHash
			,s.DataHashType1
		FROM #DimParticipant s
		INNER JOIN #LoadOperation lo
			ON lo.Participant_Key = s.Participant_Key
			AND lo.Operation IN ('I', 'U', '2')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U', '1', '2')), 0)
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
