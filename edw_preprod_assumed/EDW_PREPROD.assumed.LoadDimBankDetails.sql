-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimBankDetails


CREATE   PROCEDURE assumed.LoadDimBankDetails
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
		
		DROP TABLE IF EXISTS #DimBankDetails
		
		SELECT BankDetailCode = x.BankDetailCode
			,Account = REPLACE(x.Account, '-', '')
			,AccountCurrency = x.AccountCurrency
			,SwiftCode = CASE WHEN x.SwiftCode IS NOT NULL AND LEN(x.SwiftCode) = 8 THEN x.SwiftCode + 'XXX' ELSE x.SwiftCode END
			,AccountName = x.AccountName
			,ABA = x.ABA
			,TransitNumber = x.TransitNumber
			,ContactName = x.ContactName
			,IBAN = REPLACE(x.IBAN, ' ', '')
			,SortCode = x.SortCode
			,BSB = x.BSB
			,BankName = x.BankName
			,BankAddress1 = x.BankAddress1
			,BankAddress2 = x.BankAddress2
			,BankAddress3 = x.BankAddress3
			,BankCity = x.BankCity
			,BankState = x.BankState
			,BankCountry = x.BankCountry
			,SourceCreatedDate = x.SourceCreatedDate
		INTO #DimBankDetails
		FROM (
			SELECT BankDetailCode	= pa.account_key
				,Account			= NULLIF(LTRIM(RTRIM(pa.account_no)), '')
				,AccountCurrency	= NULLIF(LTRIM(RTRIM(cn.curr_iso_cd)), '')
				,SwiftCode			= NULLIF(LTRIM(RTRIM(pa.swift_code)), '')
				,AccountName		= NULLIF(LTRIM(RTRIM(pa.account_nm)), '')
				,ABA				= NULLIF(LTRIM(RTRIM(pa.aba_no)), '')
				,TransitNumber		= NULLIF(LTRIM(RTRIM(pa.transit_no)), '')
				,ContactName		= NULLIF(LTRIM(RTRIM(pa.contact_nm)), '')
				,IBAN				= NULLIF(LTRIM(RTRIM(pa.iban_no)), '')
				,SortCode			= pa.sort_cd
				,BSB				= pa.bsb
				,BankName			= NULLIF(LTRIM(RTRIM(pnb.full_nm)), '')
				,BankAddress1		= NULLIF(LTRIM(RTRIM(pbb.addr_1)), '')
				,BankAddress2		= NULLIF(LTRIM(RTRIM(pbb.addr_2)), '')
				,BankAddress3		= NULLIF(LTRIM(RTRIM(pbb.addr_3)), '')
				,BankCity			= NULLIF(LTRIM(RTRIM(pbb.city)), '')
				,BankState			= NULLIF(LTRIM(RTRIM(pbb.[state])), '')
				,BankCountry		= NULLIF(LTRIM(RTRIM(icmb.ISOCountryCode)), '')
				,SourceCreatedDate	= COALESCE(dbd.SourceCreatedDate, pa.touch_dt)
			FROM SRC_TIRS_DB.dbo.xrf_prod_accounts pa
			INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
				ON cn.curr_cd = pa.curr_cd
			INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_branches pbb
				ON pbb.prod_br_key = pa.bank_br_key
			INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_names pnb
				ON pnb.prod_key = pbb.prod_key
			INNER JOIN #ISOCountryMap icmb
				ON icmb.country_cd = pbb.country_cd
			LEFT JOIN assumed.DimBankDetails dbd
				ON dbd.BankDetailCode = pa.account_key
			) x
		UNION ALL
		SELECT BankDetailCode = 0
			,Account = 'Uncoded'
			,AccountCurrency = 'Uncoded'
			,SwiftCode = 'Uncoded'
			,AccountName = 'Uncoded'
			,ABA = 'Uncoded'
			,TransitNumber = 'Uncoded'
			,ContactName = 'Uncoded'
			,IBAN = 'Uncoded'
			,SortCode = 0
			,BSB = 0
			,BankName = 'Uncoded'
			,BankAddress1 = 'Uncoded'
			,BankAddress2 = 'Uncoded'
			,BankAddress3 = 'Uncoded'
			,BankCity = 'Uncoded'
			,BankState = 'Uncoded'
			,BankCountry = 'Uncoded'
			,SourceCreatedDate = NULL
		UNION ALL
		SELECT BankDetailCode = -1
			,Account = 'N/A'
			,AccountCurrency = 'N/A'
			,SwiftCode = 'N/A'
			,AccountName = 'N/A'
			,ABA = 'N/A'
			,TransitNumber = 'N/A'
			,ContactName = 'N/A'
			,IBAN = 'N/A'
			,SortCode = -1
			,BSB = -1
			,BankName = 'N/A'
			,BankAddress1 = 'N/A'
			,BankAddress2 = 'N/A'
			,BankAddress3 = 'N/A'
			,BankCity = 'N/A'
			,BankState = 'N/A'
			,BankCountry = 'N/A'
			,SourceCreatedDate = NULL
			
		ALTER TABLE #DimBankDetails ADD DataHashType1 BINARY(20) NULL

		UPDATE s
		SET DataHashType1 = HASHBYTES('SHA1', CONCAT(s.Account
			, '|', s.AccountCurrency
			, '|', s.SwiftCode
			, '|', s.AccountName
			, '|', s.ABA
			, '|', s.TransitNumber
			, '|', s.ContactName
			, '|', s.IBAN
			, '|', s.SortCode
			, '|', s.BSB
			, '|', s.BankName
			, '|', s.BankAddress1
			, '|', s.BankAddress2
			, '|', s.BankAddress3
			, '|', s.BankCity
			, '|', s.BankState
			, '|', s.BankCountry
			, '|', s.SourceCreatedDate
			))
		FROM #DimBankDetails s
		
		DROP TABLE IF EXISTS #LoadOperation
		
		CREATE TABLE #LoadOperation
		(BankDetailCode INT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (BankDetailCode)
		)

		INSERT INTO #LoadOperation
			(BankDetailCode
			,Operation
			)
		SELECT BankDetailCode = COALESCE(t.BankDetailCode, s.BankDetailCode)
			,Operation = CASE WHEN t.DimBankDetailsID IS NULL THEN 'I' WHEN s.DataHashType1 IS NULL THEN 'D' WHEN t.DataHashType1 != s.DataHashType1 THEN 'U' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimBankDetails t
			) t
		FULL JOIN #DimBankDetails s
			ON COALESCE(s.BankDetailCode, 0) = COALESCE(t.BankDetailCode, 0) 
		WHERE t.DataHashType1 IS NULL
			OR s.DataHashType1 IS NULL
			OR t.DataHashType1 != s.DataHashType1
			
		BEGIN TRAN

		UPDATE t
		SET UpdateDate = p.NewStartDate
			,Account = s.Account
			,AccountCurrency = s.AccountCurrency
			,SwiftCode = s.SwiftCode
			,AccountName = s.AccountName
			,ABA = s.ABA
			,TransitNumber = s.TransitNumber
			,ContactName = s.ContactName
			,IBAN = s.IBAN
			,SortCode = s.SortCode
			,BSB = s.BSB
			,BankName = s.BankName
			,BankAddress1 = s.BankAddress1
			,BankAddress2 = s.BankAddress2
			,BankAddress3 = s.BankAddress3
			,BankCity = s.BankCity
			,BankState = s.BankState
			,BankCountry = s.BankCountry
			,SourceCreatedDate = s.SourceCreatedDate
			,DataHashType1 = s.DataHashType1
		FROM assumed.DimBankDetails t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.BankDetailCode, 0) = COALESCE(t.BankDetailCode, 0)
			AND lo.Operation IN ('U', '1')
		INNER JOIN #DimBankDetails s
			ON COALESCE(s.BankDetailCode, 0) = COALESCE(t.BankDetailCode, 0)
		CROSS JOIN #Parameters p
		
		INSERT INTO assumed.DimBankDetails
			(StartDate
			,UpdateDate
			,BankDetailCode	
			,Account			
			,AccountCurrency	
			,SwiftCode		
			,AccountName		
			,ABA				
			,TransitNumber	
			,ContactName		
			,IBAN			
			,SortCode		
			,BSB				
			,BankName		
			,BankAddress1	
			,BankAddress2	
			,BankAddress3	
			,BankCity		
			,BankState		
			,BankCountry	
			,SourceCreatedDate
			,DataHashType1
			)
		SELECT StartDate = p.NewStartDate
			,UpdateDate = p.NewStartDate
			,s.BankDetailCode	
			,s.Account			
			,s.AccountCurrency	
			,s.SwiftCode		
			,s.AccountName		
			,s.ABA				
			,s.TransitNumber	
			,s.ContactName		
			,s.IBAN			
			,s.SortCode		
			,s.BSB				
			,s.BankName		
			,s.BankAddress1	
			,s.BankAddress2	
			,s.BankAddress3	
			,s.BankCity		
			,s.BankState		
			,s.BankCountry	
			,s.SourceCreatedDate
			,s.DataHashType1
		FROM #DimBankDetails s
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.BankDetailCode, 0) = COALESCE(s.BankDetailCode, 0)
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