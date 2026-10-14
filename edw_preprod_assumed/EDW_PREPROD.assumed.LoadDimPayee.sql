-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimPayee

CREATE   PROCEDURE assumed.LoadDimPayee
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT NewStartDate = SYSDATETIME()
		INTO #Parameters

		DROP TABLE IF EXISTS #ISOCountryMap
		
		SELECT c.country_cd
			,ISOCountryCode = COALESCE(x.ISOCountryCode, c.country_abbrv)
		INTO #ISOCountryMap
		FROM SRC_TIRS_DB.dbo.xrf_country c
		LEFT JOIN (
			VALUES(24, 'AR')
			,(182, 'AU')
			,(77, 'BH')
			,(148, 'PT')
			,(364, 'ZZ')
			,(365, 'BY')
			,(81, 'BE')
			,(41, 'BM')
			,(388, 'ZZ')
			,(25, 'BO')
			,(44, 'BQ')
			,(249, 'BW')
			,(26, 'BR')
			,(366, 'BF')
			,(163, 'MM')
			,(3, 'CA')
			,(22, 'ZZ')
			,(175, 'IC')
			,(251, 'CV')
			,(216, 'ZZ')
			,(252, 'KY')
			,(253, 'CF')
			,(322, 'ZZ')
			,(380, 'GB')
			,(28, 'CL')
			,(61, 'CN')
			,(29, 'CO')
			,(255, 'KM')
			,(224, 'CG')
			,(323, 'CD')
			,(15, 'CR')
			,(47, 'CW')
			,(191, 'CY')
			,(310, 'CZ')
			,(56, 'DO')
			,(30, 'SR')
			,(332, 'TL')
			,(31, 'EC')
			,(285, 'SV')
			,(359, 'ZZ')
			,(86, 'FI')
			,(87, 'FR')
			,(368, 'ZZ')
			,(240, 'DE')
			,(88, 'DE')
			,(261, 'ZZ')
			,(90, 'GR')
			,(369, 'CY')
			,(10, 'GU')
			,(16, 'GT')
			,(27, 'GY')
			,(370, 'ZZ')
			,(17, 'HN')
			,(144, 'HK')
			,(236, 'HU')
			,(105, 'IS')
			,(64, 'IN')
			,(69, 'ID')
			,(93, 'IE')
			,(70, 'IL')
			,(94, 'IT')
			,(242, 'CI')
			,(7, 'JM')
			,(67, 'JP')
			,(170, 'JO')
			,(372, 'KH')
			,(314, 'ZZ')
			,(205, 'KW')
			,(317, 'ZZ')
			,(292, 'LT')
			,(373, 'MG')
			,(278, 'PT')
			,(132, 'MY')
			,(215, 'ZZ')
			,(222, 'MU')
			,(18, 'MX')
			,(212, 'UM')
			,(374, 'ME')
			,(111, 'MA')
			,(230, 'MZ')
			,(315, 'MM')
			,(313, 'ZZ')
			,(8, 'NP')
			,(91, 'NL')
			,(275, 'VU')
			,(183, 'NZ')
			,(2, 'OM')
			,(246, 'OM')
			,(381, 'ZZ')
			,(162, 'PK')
			,(20, 'PA')
			,(34, 'PE')
			,(71, 'PH')
			,(97, 'PL')
			,(98, 'PT')
			,(303, 'RU')
			,(118, 'JP')
			,(203, 'MP')
			,(60, 'SA')
			,(375, 'GB')
			,(358, 'RS')
			,(376, 'AE')
			,(201, 'SL')
			,(9, 'SG')
			,(192, 'ZA')
			,(389, 'ZZ')
			,(167, 'ES')
			,(188, 'MA')
			,(125, 'LK')
			,(377, 'VI')
			,(378, 'VI')
			,(179, 'KN')
			,(159, 'LC')
			,(193, 'MF')
			,(199, 'SD')
			,(187, 'SE')
			,(117, 'PF')
			,(168, 'TW')
			,(72, 'TH')
			,(158, 'VG')
			,(57, 'TT')
			,(114, 'TN')
			,(189, 'TR')
			,(299, 'TM')
			,(238, 'RU')
			,(379, 'AE')
			,(352, 'ZZ')
			,(387, 'ZZ')
			,(35, 'UY')
			,(36, 'VE')
			,(176, 'VN')
			,(213, 'UM')
			,(320, 'VC')
			,(1, 'ZZ')
			,(239, 'ZZ')
			,(382, 'ZW')
			) x (TIRSCountryCode, ISOCountryCode)
			ON x.TIRSCountryCode = c.country_cd
		ORDER BY c.desc_txt
		
		
		DROP TABLE IF EXISTS #PayeeBranchKey
		
		SELECT PayeeKey = bill_co_br_key
		INTO #PayeeBranchKey
		FROM SRC_TIRS_DB.dbo.trty_master tm
		UNION
		SELECT PayeeKey = c.payee_br_key
		FROM SRC_TIRS_DB.dbo.claim c
		UNION
		SELECT PayeeKey = tp.brkr_br_key
		FROM SRC_TIRS_DB.dbo.trty_participant tp
		
		DROP TABLE IF EXISTS #DimPayee
		
		SELECT PayeeCode = pbp.prod_br_key
			,PayeeName = pnp.full_nm
			,PayeeAddress1 = pbp.addr_1
			,PayeeAddress2 = pbp.addr_2
			,PayeeAddress3 = pbp.addr_3
			,PayeeCity = pbp.city
			,PayeeState = pbp.[state]
			,PayeeCountry = icmp.ISOCountryCode
			,PayeeEmail = pbp.email
			,PayeeTelephone = pbp.telephone
			,SourceCreatedDate = COALESCE(dp.SourceCreatedDate, pbp.touch_dt)
		INTO #DimPayee
		FROM #PayeeBranchKey pbk
		INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_branches pbp
			ON pbp.prod_br_key = pbk.PayeeKey
		INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_names pnp
			ON pnp.prod_key = pbp.prod_key
		INNER JOIN #ISOCountryMap icmp
			ON icmp.country_cd = pbp.country_cd
		LEFT JOIN assumed.DimPayee dp
			ON dp.PayeeCode = pbp.prod_br_key			
		UNION ALL
		SELECT PayeeCode = 0
			,PayeeName = 'Uncoded'
			,PayeeAddress1 = 'Uncoded'
			,PayeeAddress2 = 'Uncoded'
			,PayeeAddress3 = 'Uncoded'
			,PayeeCity = 'Uncoded'
			,PayeeState = 'Uncoded'
			,PayeeCountry = 'UNCODED'
			,PayeeEmail = 'Uncoded'
			,PayeeTelephone = 'Uncoded'
			,SourceCreatedDate = NULL
		UNION ALL
		SELECT PayeeCode = -1
			,PayeeName = 'N/A'
			,PayeeAddress1 = 'N/A'
			,PayeeAddress2 = 'N/A'
			,PayeeAddress3 = 'N/A'
			,PayeeCity = 'N/A'
			,PayeeState = 'N/A'
			,PayeeCountry = 'N/A'
			,PayeeEmail = 'N/A'
			,PayeeTelephone = 'N/A'
			,SourceCreatedDate = NULL
			
		ALTER TABLE #DimPayee ADD DataHashType1 BINARY(20) NULL

		UPDATE s
		SET DataHashType1 = HASHBYTES('SHA1', CONCAT(s.PayeeName
			, '|', s.PayeeAddress1
			, '|', s.PayeeAddress2
			, '|', s.PayeeAddress3
			, '|', s.PayeeCity
			, '|', s.PayeeState
			, '|', s.PayeeCountry
			, '|', s.PayeeEmail
			, '|', s.PayeeTelephone
			, '|', s.SourceCreatedDate
			))
		FROM #DimPayee s
		
		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(PayeeCode INT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (PayeeCode)
		)

		INSERT INTO #LoadOperation
			(PayeeCode
			,Operation
			)
		SELECT PayeeCode = COALESCE(t.PayeeCode, s.PayeeCode)
			,Operation = CASE WHEN t.DimPayeeID IS NULL THEN 'I' WHEN s.DataHashType1 IS NULL THEN 'D' WHEN t.DataHashType1 != s.DataHashType1 THEN 'U' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimPayee t
			) t
		FULL JOIN #DimPayee s
			ON COALESCE(s.PayeeCode, 0) = COALESCE(t.PayeeCode, 0) 
		WHERE t.DataHashType1 IS NULL
			OR s.DataHashType1 IS NULL
			OR t.DataHashType1 != s.DataHashType1
			
		BEGIN TRAN

		UPDATE t
		SET UpdateDate = p.NewStartDate
			,PayeeCode = s.PayeeCode
			,PayeeName = s.PayeeName
			,PayeeAddress1 = s.PayeeAddress1
			,PayeeAddress2 = s.PayeeAddress2
			,PayeeAddress3 = s.PayeeAddress3
			,PayeeCity = s.PayeeCity
			,PayeeState = s.PayeeState
			,PayeeCountry = s.PayeeCountry
			,PayeeEmail = s.PayeeEmail
			,PayeeTelephone = s.PayeeTelephone
			,SourceCreatedDate = s.SourceCreatedDate
			,DataHashType1 = s.DataHashType1
		FROM assumed.DimPayee t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.PayeeCode, 0) = COALESCE(t.PayeeCode, 0)
			AND lo.Operation IN ('U', '1')
		INNER JOIN #DimPayee s
			ON COALESCE(s.PayeeCode, 0) = COALESCE(t.PayeeCode, 0)
		CROSS JOIN #Parameters p
		
		INSERT INTO assumed.DimPayee
			(StartDate
			,UpdateDate
			,PayeeCode
			,PayeeName
			,PayeeAddress1
			,PayeeAddress2
			,PayeeAddress3
			,PayeeCity
			,PayeeState
			,PayeeCountry
			,PayeeEmail
			,PayeeTelephone
			,SourceCreatedDate
			,DataHashType1
			)
		SELECT StartDate = p.NewStartDate
			,UpdateDate = p.NewStartDate
			,s.PayeeCode
			,s.PayeeName
			,s.PayeeAddress1
			,s.PayeeAddress2
			,s.PayeeAddress3
			,s.PayeeCity
			,s.PayeeState
			,s.PayeeCountry
			,s.PayeeEmail
			,s.PayeeTelephone
			,s.SourceCreatedDate
			,s.DataHashType1
		FROM #DimPayee s
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.PayeeCode, 0) = COALESCE(s.PayeeCode, 0)
			AND lo.Operation IN ('I')
		CROSS JOIN #Parameters p
		
		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U')), 0)
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