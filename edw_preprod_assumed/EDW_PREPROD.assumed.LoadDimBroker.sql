-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimBroker

CREATE   PROCEDURE assumed.LoadDimBroker
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #TIRSBroker

		SELECT DISTINCT tm.brkr_br_key
		INTO #TIRSBroker
		FROM SRC_TIRS_DB.dbo.trty_master tm
		UNION
		SELECT DISTINCT tp.brkr_br_key
		FROM SRC_TIRS_DB.dbo.trty_participant tp

		DROP TABLE IF EXISTS #opbtemp
		
		SELECT [CompanyCode] COLLATE Latin1_General_CI_AI AS [BRKR_COMPANY_CD]
			,[CompanyName] COLLATE Latin1_General_CI_AI AS [BRKR_COMPANY_NAME]
			,[AddressLine1] COLLATE Latin1_General_CI_AI AS [BRKR_ADDR_1]
			,[AddressLine2] COLLATE Latin1_General_CI_AI AS [BRKR_ADDR_2]
			,[AddressLine3] COLLATE Latin1_General_CI_AI AS [BRKR_ADDR_3]
			,[City] COLLATE Latin1_General_CI_AI AS [BRKR_CITY]
			,[DomicileCountryName] COLLATE Latin1_General_CI_AI AS [BRKR_COUNTRY]
			,[DomicileStateName] COLLATE Latin1_General_CI_AI AS [BRKR_STATE]
			,[PostalCode] COLLATE Latin1_General_CI_AI AS [BRKR_ZIP]
			,[NAIC] COLLATE Latin1_General_CI_AI AS [BRKR_NAIC]
			,[PARENT_KEY] COLLATE Latin1_General_CI_AI AS [BRKR_PARENT_KEY]
			,[PROD_KEY] COLLATE Latin1_General_CI_AI AS [BRKR_PROD_KEY]
			,[STATUS_FLG] COLLATE Latin1_General_CI_AI AS [BRKR_STATUS_FLG]
			,[TAX_ID] COLLATE Latin1_General_CI_AI AS [BRKR_TAX_ID]
			,[PROD_NBR] COLLATE Latin1_General_CI_AI AS [BRKR_PROD_NBR]
			,[PhoneNumber] COLLATE Latin1_General_CI_AI AS [BRKR_PHONE]
			,[dupIndex] AS dupindex
		INTO #opbTemp
		FROM (
		SELECT row_number() OVER (
				PARTITION BY Contact.lContactKey ORDER BY Contact.lContactKey
			) AS [dupIndex]
			,'LR' + CONVERT(VARCHAR(200), Contact.lContactKey) AS CompanyCode
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(CASE lTypeOfContactKey WHEN 2 THEN sCompanyName ELSE sContactReference END), ''), 'Uncoded')) AS CompanyName
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sCompanyName), ''), 'Uncoded')) AS LegalName
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sCompanyName), ''), 'Uncoded')) AS AddressName
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(AD.sSingleLineFormattedAddress), ''), 'Uncoded')) AS Address
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(AD.sFormattedAddress), ''), 'Uncoded')) AS AddressLine1
			,'Uncoded' AS AddressLine2
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(ZCity.sCity), ''), 'Uncoded')) AS AddressLine3
			,'Uncoded' AS AddressLine4
			,'Uncoded' AS AddressLine5
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(ZCity.sCity), ''), 'Uncoded')) AS City
			,'-9999' AS DomicileRegion
			,'Uncoded' AS DomicileRegionName
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(ZC.sCountryCode), ''), '-9999')) AS DomicileCountry
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(ZC.sCountry), ''), 'Uncoded')) AS DomicileCountryName
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(Zstate.sStateCode), ''), '-9999')) AS DomicileState
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(Zstate.sState), ''), 'Uncoded')) AS DomicileStateName
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sPostalCode_ZIP), ''), 'Uncoded')) AS PostalCode
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sFortune500), ''), 'Uncoded')) AS Fortune500
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sNAICCode), ''), 'Uncoded')) AS NAIC
			,'-9999' AS PARENT_KEY
			,CONVERT(VARCHAR(200), Contact.lContactKey) AS PROD_KEY -- 'LR' prefix not needed for bill,
			,'-9999' AS STATUS_FLG
			,COALESCE(NULLIF(TRIM(sIRSNumber), ''), '-9999') AS TAX_ID
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sBrokerCode), ''), '-9999')) AS PROD_NBR
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sMarketCapital), ''), 'Uncoded')) AS MarketCapital
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sAnnualRevenue), ''), 'Uncoded')) AS AnnualRevenue
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sDunnandBradstreetNumber), ''), 'Uncoded')) AS DunnandBradstreetNumber
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sPhone), ''), 'Uncoded')) AS PhoneNumber
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sFax), ''), 'Uncoded')) AS FaxNumber
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM('Uncoded'), ''), 'Uncoded')) AS SICCode
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sTicker), ''), 'Uncoded')) AS Ticker
			,CONVERT(VARCHAR(200), COALESCE(NULLIF(TRIM(sAMBestRating), ''), 'Uncoded')) AS AMBestRating
			,CASE WHEN TypeRole.sRoleCode = 'BKR' THEN 'Y' ELSE 'N' END AS BrokerFlag
			,'N' AS InsurerFlag
			,CASE WHEN TypeRole.sRoleCode IN ('ASD', 'REA') THEN 'Y' ELSE 'N' END AS AssuredFlag
			,'N' AS RSCBrokerFlag
			,CASE WHEN TypeRole.sRoleCode = 'BKR' THEN 'Y' ELSE 'N' END AS OriginalBrokerFlag
			,'N' AS CaptiveFlag
			,CASE WHEN TypeRole.sRoleCode IN ('ASD', 'REA') THEN 'Y' ELSE 'N' END AS ReassuredFlag
			,'N' AS ParticipantFlag
			,'N' AS RPIIFlag
			,'01/01/1900' AS RPIIEffectiveFrom
			,'01/01/1900' AS RPIIEffectiveTo
			,'-9999' AS ParentDBNumber
			,'N' AS ClaimantFlag
			,CASE WHEN TypeRole.sRoleCode IN ('ASD', 'REA') THEN 'Y' ELSE 'N' END AS CLM_AssuredFlag
			,CASE WHEN TypeRole.sRoleCode = 'BKR' THEN 'Y' ELSE 'N' END AS CLM_LossBrokerFlag
			,CASE WHEN TypeRole.sRoleCode = 'BKR' THEN 'Y' ELSE 'N' END AS PayeeFlag
			,'N' AS SettlementFlag
			,CASE WHEN TypeRole.sRoleCode = 'BKR' THEN 'Y' ELSE 'N' END AS TransactionBrokerFlag
			,'N' AS TransactionInsurerFlag
			,CASE WHEN TypeRole.sRoleCode IN ('ASD', 'REA') THEN 'Y' ELSE 'N' END AS TransactionAssuredFlag
			,'Uncoded' AS SL_Licence_No
			,'Uncoded' AS SLA_Number
			,CONVERT(VARCHAR(50), COALESCE(NULLIF(TRIM(sTotRevenue), ''), 'Uncoded')) AS TotRevenue
			,'N' AS ULCarrierFlag
			,CONVERT(VARCHAR(50), COALESCE(NULLIF(TRIM(sEmail), ''), 'Uncoded')) AS EMailAddress
			,CONVERT(VARCHAR(50), COALESCE(NULLIF(TRIM(sZone), ''), 'Uncoded')) AS Zone
			,'Uncoded' AS DRBrokerType
			,'Uncoded' AS DRBrokerDesignation
			,'Uncoded' AS DRPartnerType
			,'Uncoded' AS DRNotForProfitFlag
			,COALESCE(Contact.sBrokerCode, 'Uncoded') AS BrokerCode
			,Contact.lContactKey AS lContactKey
			,TypeRole.sRoleCode AS RoleCode
		FROM SRC_LLOYDS_DB.dbo.Contact Contact
		LEFT JOIN SRC_LLOYDS_DB.dbo.ContactRole ContactRole
			ON ContactRole.lContactKey = Contact.lContactKey
		LEFT JOIN SRC_LLOYDS_DB.dbo.ZoneCountry ZC
			ON ISNULL(Contact.lCountryKey, Contact.lContactNationalityCountryKey) = ZC.lCountryKey
		LEFT JOIN SRC_LLOYDS_DB.dbo.Address AD
			ON Contact.lBillingAddressKey = AD.lAddressKey
		LEFT JOIN SRC_LLOYDS_DB.dbo.ZoneCountry ZCAD
			ON AD.lZoneCountryKey = ZCAD.lCountryKey
		LEFT JOIN SRC_LLOYDS_DB.dbo.ZoneCity ZCity
			ON Contact.lContactCityAddressKey = ZCity.lCityKey
		LEFT JOIN SRC_LLOYDS_DB.dbo.ZoneState ZState
			ON Contact.lContactStateAddressKey = ZState.lStateKey
		LEFT JOIN SRC_LLOYDS_DB.dbo.TypeOfRole TypeRole
			ON ISNULL(ContactRole.lTypeofRoleKey, Contact.lTypeofMainRoleKey) = TypeRole.lTypeOfRoleKey
		WHERE TypeRole.sRoleCode IS NULL
			OR TypeRole.sRoleCode IN ('BKR', 'ASD', 'REA')
		) theTable
		WHERE theTable.dupIndex = 1
		
		DROP TABLE IF EXISTS #DimBroker
		
		SELECT *
		INTO #DimBroker
		FROM (
		-- TIRS BROKER DETAILS
		SELECT BC.BRKR_COMPANY_CD COLLATE Latin1_General_CI_AI AS BRKR_COMPANY_CD
			,BC.BRKR_COMPANY_NAME COLLATE Latin1_General_CI_AI AS BRKR_COMPANY_NAME
			,BC.BRKR_ADDR_1 COLLATE Latin1_General_CI_AI AS BRKR_ADDR_1
			,BC.BRKR_ADDR_2 COLLATE Latin1_General_CI_AI AS BRKR_ADDR_2
			,BC.BRKR_ADDR_3 COLLATE Latin1_General_CI_AI AS BRKR_ADDR_3
			,BC.BRKR_CITY COLLATE Latin1_General_CI_AI AS BRKR_CITY
			,BC.BRKR_NAIC COLLATE Latin1_General_CI_AI AS BRKR_NAIC
			,IIF(BC.BRKR_PARENT_KEY = 20838, 2762, BC.BRKR_PARENT_KEY) AS BRKR_PARENT_KEY -- update from [SSIS].[usp_TIRS_PostCleanup] which is being deactivated
			,BC.BRKR_PROD_KEY COLLATE Latin1_General_CI_AI AS BRKR_PROD_KEY
			,BC.BRKR_PROD_NBR COLLATE Latin1_General_CI_AI AS BRKR_PROD_NBR
			,BC.BRKR_STATUS_FLG COLLATE Latin1_General_CI_AI AS BRKR_STATUS_FLG
			,BC.BRKR_TAX_ID COLLATE Latin1_General_CI_AI AS BRKR_TAX_ID
			,BC.BRKR_PHONE COLLATE Latin1_General_CI_AI AS BRKR_PHONE
			,BC.BRKR_ZIP COLLATE Latin1_General_CI_AI AS BRKR_ZIP
			,BC.BRKR_COUNTRY COLLATE Latin1_General_CI_AI AS BRKR_COUNTRY
			,BC.BRKR_STATE COLLATE Latin1_General_CI_AI AS BRKR_STATE
			,ISNULL(P.PARENT_COMPANY_CD, 'Uncoded') COLLATE Latin1_General_CI_AI AS BRKR_PARENT_CD
			,ISNULL(P.PARENT_COMPANY_NAME, 'Uncoded') COLLATE Latin1_General_CI_AI AS BRKR_PARENT_COMP_NAME
			,4 AS SourceSysKey
			,SourceCreatedDate = COALESCE(db.SourceCreatedDate, xpb.touch_dt)
			,BrokerType = CASE WHEN bc.BRKR_COMPANY_CD = 1 THEN 'Direct to Customer' ELSE 'Broker' END
		FROM SRC_TIRS_DB.SSIS.vw_TIRS_UW_BrokerCompany BC
		LEFT JOIN SRC_TIRS_DB.SSIS.vw_TIRS_UW_BrokerParentCompany P
			ON BC.BRKR_PARENT_KEY = P.PARENT_COMPANY_CD
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_prod_branches xpb
			ON xpb.prod_br_key = bc.BRKR_COMPANY_CD
		LEFT JOIN assumed.DimBroker db
			ON db.EndDate = '31 Dec 9999'
				AND db.BRKR_COMPANY_CD = bc.BRKR_COMPANY_CD COLLATE DATABASE_DEFAULT
				AND db.SourceSysKey = 4

		UNION ALL

		SELECT BRKR_COMPANY_CD = CAST(tb.brkr_br_key AS VARCHAR(10))
			,BRKR_COMPANY_NAME = xpn.proper_nm COLLATE DATABASE_DEFAULT
			,BRKR_ADDR_1 = COALESCE(xpb.addr_1, 'Uncoded') COLLATE DATABASE_DEFAULT
			,BRKR_ADDR_2 = COALESCE(NULLIF(xpb.addr_2, ''), 'Uncoded') COLLATE DATABASE_DEFAULT
			,BRKR_ADDR_3 = COALESCE(NULLIF(xpb.addr_3, ''), 'Uncoded') COLLATE DATABASE_DEFAULT
			,BRKR_CITY = COALESCE(NULLIF(xpb.city, ''), 'Uncoded') COLLATE DATABASE_DEFAULT
			,BRKR_NAIC = COALESCE(NULLIF(xpn.naic_no, ''), '-9999') COLLATE DATABASE_DEFAULT
			,BRKR_PARENT_KEY = CAST(xpn.parent_key AS VARCHAR(10))
			,BRKR_PROD_KEY = CAST(xpb.prod_key AS VARCHAR(10))
			,BRKR_PROD_NBR = COALESCE(NULLIF(xpn.prod_no, ''), '-9999') COLLATE DATABASE_DEFAULT
			,BRKR_STATUS_FLG = xpb.status_flg COLLATE DATABASE_DEFAULT
			,BRKR_TAX_ID = COALESCE(NULLIF(xpn.tax_id, ''), '-9999') COLLATE DATABASE_DEFAULT
			,BRKR_PHONE = COALESCE(NULLIF(xpb.telephone, ''), '-9999') COLLATE DATABASE_DEFAULT
			,BRKR_ZIP = COALESCE(NULLIF(xpb.zip_cd, ''), 'Uncoded') COLLATE DATABASE_DEFAULT
			,BRKR_COUNTRY = COALESCE(NULLIF(xc.desc_txt, ''), 'Uncoded') COLLATE DATABASE_DEFAULT
			,BRKR_STATE = COALESCE(NULLIF(xpb.state, ''), 'Uncoded') COLLATE DATABASE_DEFAULT
			,BRKR_PARENT_CD = CAST(xpn.parent_key AS VARCHAR(10))
			,BRKR_PARENT_COMP_NAME = COALESCE(NULLIF(pxpn.proper_nm, ''), 'Uncoded') COLLATE DATABASE_DEFAULT
			,4 AS SourceSysKey
			,SourceCreatedDate = COALESCE(db.SourceCreatedDate, xpb.touch_dt)
			,BrokerType = CASE WHEN tb.brkr_br_key = 1 THEN 'Direct to Customer' ELSE 'Broker' END
		FROM #TIRSBroker tb
		LEFT JOIN SRC_TIRS_DB.SSIS.vw_TIRS_UW_BrokerCompany tubc
			ON tubc.BRKR_COMPANY_CD = tb.brkr_br_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_branches xpb
			ON xpb.prod_br_key = tb.brkr_br_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_names xpn
			ON xpn.prod_key = xpb.prod_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_names pxpn
			ON pxpn.prod_key = xpn.parent_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_country xc
			ON xc.country_cd = xpb.country_cd
		LEFT JOIN assumed.DimBroker db
			ON db.EndDate = '31 Dec 9999'
			AND db.BRKR_COMPANY_CD = CAST(tb.brkr_br_key AS VARCHAR(10))
			AND db.SourceSysKey = 4
		WHERE tubc.BRKR_COMPANY_CD IS NULL
					
		UNION ALL
					
		--OPENBOX BROKER DETAILS
		SELECT [BRKR_COMPANY_CD] COLLATE Latin1_General_CI_AI AS [BRKR_COMPANY_CD]
			,[BRKR_COMPANY_NAME] COLLATE Latin1_General_CI_AI AS [BRKR_COMPANY_NAME]
			,[BRKR_ADDR_1] COLLATE Latin1_General_CI_AI AS [BRKR_ADDR_1]
			,[BRKR_ADDR_2] COLLATE Latin1_General_CI_AI AS [BRKR_ADDR_2]
			,[BRKR_ADDR_3] COLLATE Latin1_General_CI_AI AS [BRKR_ADDR_3]
			,[BRKR_CITY] COLLATE Latin1_General_CI_AI AS [BRKR_CITY]
			,[BRKR_NAIC] COLLATE Latin1_General_CI_AI AS [BRKR_NAIC]
			,[BRKR_PARENT_KEY] COLLATE Latin1_General_CI_AI AS [BRKR_PARENT_KEY]
			,[BRKR_PROD_KEY] COLLATE Latin1_General_CI_AI AS [BRKR_PROD_KEY]
			,[BRKR_PROD_NBR] COLLATE Latin1_General_CI_AI AS [BRKR_PROD_NBR]
			,[BRKR_STATUS_FLG] COLLATE Latin1_General_CI_AI AS [BRKR_STATUS_FLG]
			,[BRKR_TAX_ID] COLLATE Latin1_General_CI_AI AS [BRKR_TAX_ID]
			,[BRKR_PHONE] COLLATE Latin1_General_CI_AI AS [BRKR_PHONE]
			,[BRKR_ZIP] COLLATE Latin1_General_CI_AI AS [BRKR_ZIP]
			,[BRKR_COUNTRY] COLLATE Latin1_General_CI_AI AS [BRKR_COUNTRY]
			,[BRKR_STATE] COLLATE Latin1_General_CI_AI AS [BRKR_STATE]
			,'Uncoded' AS BRKR_PARENT_CD
			,'Uncoded' AS BRKR_PARENT_COMP_NAME
			,1 AS SourceSysKey
			,SourceCreatedDate = NULL
			,BrokerType = 'Broker'
		FROM #opbTemp
					
		UNION ALL
					
		SELECT BRKR_COMPANY_CD = 'Uncoded'
			,BRKR_COMPANY_NAME = 'Uncoded'
			,BRKR_ADDR_1 = 'Uncoded'
			,BRKR_ADDR_2 = 'Uncoded'
			,BRKR_ADDR_3 = 'Uncoded'
			,BRKR_CITY = 'Uncoded'
			,BRKR_NAIC = 'Uncoded'
			,BRKR_PARENT_KEY = '0'
			,BRKR_PROD_KEY = '0'
			,BRKR_PROD_NBR = 'Uncoded'
			,BRKR_STATUS_FLG = '0'
			,BRKR_TAX_ID = '0'
			,BRKR_PHONE = 'Uncoded'
			,BRKR_ZIP = 'Uncoded'
			,BRKR_COUNTRY = 'Uncoded'
			,BRKR_STATE = 'Uncoded'
			,BRKR_PARENT_CD = 'Uncoded'
			,BRKR_PARENT_COMP_NAME = 'Uncoded'
			,SourceSysKey = 0
			,SourceCreatedDate = NULL
			,BrokerType = 'Uncoded'
					
		UNION ALL
					
		SELECT BRKR_COMPANY_CD = 'N/A'
			,BRKR_COMPANY_NAME = 'N/A'
			,BRKR_ADDR_1 = 'N/A'
			,BRKR_ADDR_2 = 'N/A'
			,BRKR_ADDR_3 = 'N/A'
			,BRKR_CITY = 'N/A'
			,BRKR_NAIC = 'N/A'
			,BRKR_PARENT_KEY = '0'
			,BRKR_PROD_KEY = '0'
			,BRKR_PROD_NBR = 'N/A'
			,BRKR_STATUS_FLG = '0'
			,BRKR_TAX_ID = '0'
			,BRKR_PHONE = 'N/A'
			,BRKR_ZIP = 'N/A'
			,BRKR_COUNTRY = 'N/A'
			,BRKR_STATE = 'N/A'
			,BRKR_PARENT_CD = 'N/A'
			,BRKR_PARENT_COMP_NAME = 'N/A'
			,SourceSysKey = 0
			,SourceCreatedDate = NULL
			,BrokerType = 'N/A'
		) BRKR;
		
		        

		-- Loading logic
		ALTER TABLE #DimBroker ADD DataHash BINARY(20) NULL
		ALTER TABLE #DimBroker ADD DataHashType1 BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.BRKR_ADDR_1
			,s.BRKR_ADDR_2
			,s.BRKR_ADDR_3
			,s.BRKR_CITY
			,s.BRKR_STATE
			,s.BRKR_COUNTRY
			,s.BRKR_COMPANY_NAME
			,s.BRKR_NAIC
			,s.BRKR_PARENT_KEY
			,s.BRKR_PROD_KEY
			,s.BRKR_STATUS_FLG
			,s.BRKR_TAX_ID
			,s.BRKR_PHONE
			,s.BRKR_ZIP
			,s.BRKR_PROD_NBR
			,s.BRKR_PARENT_CD
			,s.BRKR_PARENT_COMP_NAME))
		FROM #DimBroker s

		UPDATE s
		SET DataHashType1 = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.SourceCreatedDate
			,s.BrokerType))
		FROM #DimBroker s

		-- check/enforce uniqueness on the dimension source data
		CREATE UNIQUE INDEX assumed_DimBroker_UK ON #DimBroker (BRKR_COMPANY_CD, SourceSysKey)

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(BRKR_COMPANY_CD VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL
		,SourceSysKey SMALLINT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (BRKR_COMPANY_CD, SourceSysKey)
		)

		INSERT INTO #LoadOperation
			(BRKR_COMPANY_CD
			,SourceSysKey
			,Operation
			)
		SELECT BRKR_COMPANY_CD = COALESCE(t.BRKR_COMPANY_CD COLLATE DATABASE_DEFAULT, s.BRKR_COMPANY_CD COLLATE DATABASE_DEFAULT)
			,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
			,Operation = CASE WHEN t.DimBrokerID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimBroker t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimBroker s
			ON s.BRKR_COMPANY_CD = t.BRKR_COMPANY_CD COLLATE DATABASE_DEFAULT
			AND s.SourceSysKey = t.SourceSysKey
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimBroker t
		INNER JOIN #LoadOperation lo
			ON lo.BRKR_COMPANY_CD = t.BRKR_COMPANY_CD
			AND lo.SourceSysKey = t.SourceSysKey
			AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		UPDATE t
		SET UpdateDate = p.NewStartDate
			,SourceCreatedDate = s.SourceCreatedDate
			,BrokerType = s.BrokerType
			,DataHashType1 = s.DataHashType1
		FROM assumed.DimBroker t
		INNER JOIN #LoadOperation lo
			ON lo.BRKR_COMPANY_CD = t.BRKR_COMPANY_CD
			AND lo.SourceSysKey = t.SourceSysKey
			AND lo.Operation IN ('U', '1')
		INNER JOIN #DimBroker s
			ON s.BRKR_COMPANY_CD = t.BRKR_COMPANY_CD COLLATE DATABASE_DEFAULT
			AND s.SourceSysKey = t.SourceSysKey
		CROSS JOIN #Parameters p

		INSERT INTO assumed.DimBroker
			(StartDate
			,UpdateDate
			,BRKR_COMPANY_CD
			,BRKR_ADDR_1
			,BRKR_ADDR_2
			,BRKR_ADDR_3
			,BRKR_CITY
			,BRKR_STATE
			,BRKR_COUNTRY
			,BRKR_COMPANY_NAME
			,BRKR_NAIC
			,BRKR_PARENT_KEY
			,BRKR_PROD_KEY
			,BRKR_STATUS_FLG
			,BRKR_TAX_ID
			,BRKR_PHONE
			,BRKR_ZIP
			,BRKR_PROD_NBR
			,BRKR_PARENT_CD
			,BRKR_PARENT_COMP_NAME
			,SourceSysKey
			,SourceCreatedDate
			,BrokerType
			,DataHash
			,DataHashType1
			)
		SELECT StartDate = p.NewStartDate
			,UpdateDate = p.NewStartDate
			,s.BRKR_COMPANY_CD
			,s.BRKR_ADDR_1
			,s.BRKR_ADDR_2
			,s.BRKR_ADDR_3
			,s.BRKR_CITY
			,s.BRKR_STATE
			,s.BRKR_COUNTRY
			,s.BRKR_COMPANY_NAME
			,s.BRKR_NAIC
			,s.BRKR_PARENT_KEY
			,s.BRKR_PROD_KEY
			,s.BRKR_STATUS_FLG
			,s.BRKR_TAX_ID
			,s.BRKR_PHONE
			,s.BRKR_ZIP
			,s.BRKR_PROD_NBR
			,s.BRKR_PARENT_CD
			,s.BRKR_PARENT_COMP_NAME
			,s.SourceSysKey
			,s.SourceCreatedDate
			,s.BrokerType
			,s.DataHash
			,s.DataHashType1
		FROM #DimBroker s
		INNER JOIN #LoadOperation lo
			ON lo.BRKR_COMPANY_CD = s.BRKR_COMPANY_CD COLLATE DATABASE_DEFAULT
			AND lo.SourceSysKey = s.SourceSysKey
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
