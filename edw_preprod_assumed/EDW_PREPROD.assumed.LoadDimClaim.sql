-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimClaim

CREATE   PROCEDURE [assumed].[LoadDimClaim]
AS
BEGIN
    BEGIN TRY
        DROP TABLE IF EXISTS #Parameters
        DROP TABLE IF EXISTS #DimClaim;

        SELECT ClosingValidTo = DATEADD(NANOSECOND, -100, SYSDATETIME())
            ,NewValidFrom = SYSDATETIME()
        INTO #Parameters
		
        DROP TABLE IF EXISTS #OpenboxContractNumber
		SELECT DISTINCT mce.CONTRACT_NBR
			,PolicyReference = mce.CONTRACT_REFERENCE
		INTO #OpenboxContractNumber
		FROM dbo.MAP_CONTRACT_EDW mce
		WHERE mce.PLCY_SRC = 'OPENBOX'
			AND mce.END_DATE = '31 Dec 9999'

        -- Staging logic
        SELECT *
        INTO #DimClaim
        FROM (
            SELECT claim_source
                ,claim_number
                ,claim_code
                ,Claim_Sect_Code
                ,claim_type
                ,claim_status
                ,loss_date			= NULLIF(loss_date, '1900-01-01')
                ,advised_date		= NULLIF(advised_date, '1900-01-01')
                ,next_review_date	= NULLIF(next_review_date, '1900-01-01')
                ,action_name
                ,action_code
                ,cat_code
                ,CLAIMANT_NAME
                ,claim_handler_code
                ,claim_handler_name
                ,loss_area_code
                ,loss_area_name
                ,incident_desc
                ,nature_of_injury_desc
                ,nature_of_injury_group
                ,loss_cause_code
                ,loss_cause_name
                ,policy_number
                ,claim_name
                ,SourceSysKey
                ,SourceCreatedDate
            FROM (
                --TIRS data
                SELECT DISTINCT 'TIRS' AS claim_source
                    ,ISNULL(mtc.TIRS_CLM, '') AS claim_number
                    ,ISNULL(mtc.TIRS_CLM_CD, '') AS claim_code
                    ,ISNULL(mtc.TIRS_CLM_CD, '') AS Claim_Sect_Code
                    ,ISNULL(mtc.TIRS_CLM_TYP_NAME, '') AS claim_type
                    ,ISNULL(mtc.TIRS_CLM_STATUS_CD_NAME, '') AS claim_status
                    ,CAST(c.loss_dt AS DATE) AS loss_date
                    ,CAST(mtc.CLAIM_MASTER_ENTRY_DATE	AS DATE) AS advised_date
                    ,CAST(mtc.DIARY_DUE_DATE_DT			AS DATE) AS next_review_date
                    ,CASE 
                        WHEN ISNULL(mtc.CLM_TXN_NAME, '') IN ('Not classified at this level', '')
                            THEN 'Uncoded'
                        ELSE ISNULL(mtc.CLM_TXN_NAME, '')
                        END AS action_name
                    ,CASE 
                        WHEN ISNULL(mtc.CLM_TXN_CD, '') IN ('Not classified at this level', '')
                            THEN 'Uncoded'
                        ELSE ISNULL(mtc.CLM_TXN_CD, '')
                        END AS action_code
                    ,ISNULL(mtc.CLM_CAT_CD, '') AS cat_code
                    ,ISNULL(mtc.CLMT, '') AS CLAIMANT_NAME
                    ,ISNULL(mtc.EXMNR_CD, '') AS claim_handler_code
                    ,ISNULL(mtc.EXMNR_NAME, '') AS claim_handler_name
                    ,ISNULL(mtc.CNTY_CD, '') AS loss_area_code
                    ,ISNULL(mtc.CNTY_NAME, '') AS loss_area_name
                    ,ISNULL(mtc.LOSS_DESC_TEXT, '') AS incident_desc
                    ,ISNULL(mtc.CLM_NTR_NAME, '') AS nature_of_injury_desc
                    ,ISNULL(mtc.CLM_NTR_CD, '') AS nature_of_injury_group
                    ,ISNULL(mtc.INJR_TYP_CD, '') AS loss_cause_code
                    ,ISNULL(mtc.INJR_TYP_NAME, '') AS loss_cause_name
                    ,ISNULL(CONCAT(LEFT(tm.trty_no, 5), tm.und_yr) COLLATE DATABASE_DEFAULT, '') AS policy_number
                    ,ISNULL(mtc.TIRS_CLM_NAME, '') AS claim_name
                    ,4 AS SourceSysKey
                -- ,row_number() over(partition by TIRS_CLM,TIRS_CLM_CD,source_key order by TIRS_CLM,TIRS_CLM_CD,source_key asc) as rn
                    ,SourceCreatedDate = c.create_dt
                FROM [EDW_PREPROD].[dbo].[MAP_TIRS_CLM] mtc
                INNER JOIN (SRC_TIRS_DB.dbo.claim c
					INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
						ON tm.trty_key = c.trty_key
					)
                    ON CAST(c.clm_key AS VARCHAR(10)) = mtc.TIRS_CLM_CD COLLATE DATABASE_DEFAULT
                WHERE END_DATE = '9999-12-31'
                    AND ISNULL(TIRS_CLM_CD, '') NOT IN ('$NOOID', '-9999', 'Not classified at this level')
                    AND clm_txn = '$NOOID'
                -- )a where rn > 1 
                --tirs_clm = '100025238' and TIRS_CLM_CD='11734'
                
                UNION
                
                -- Openbox claim data
                SELECT claim_source COLLATE DATABASE_DEFAULT AS claim_source
                    ,claim_number COLLATE DATABASE_DEFAULT
                    ,claim_code COLLATE DATABASE_DEFAULT
                    ,Claim_Sect_Code COLLATE DATABASE_DEFAULT
                    ,claim_type COLLATE DATABASE_DEFAULT
                    ,claim_status COLLATE DATABASE_DEFAULT
                    ,loss_date
                    ,advised_date
                    ,next_review_date
                    ,action_name COLLATE DATABASE_DEFAULT
                    ,action_code COLLATE DATABASE_DEFAULT
                    ,cat_code COLLATE DATABASE_DEFAULT
                    ,CLAIMANT_NAME COLLATE DATABASE_DEFAULT
                    ,claim_handler_code COLLATE DATABASE_DEFAULT
                    ,claim_handler_name COLLATE DATABASE_DEFAULT
                    ,loss_area_code COLLATE DATABASE_DEFAULT
                    ,loss_area_name COLLATE DATABASE_DEFAULT
                    ,incident_desc COLLATE DATABASE_DEFAULT
                    ,nature_of_injury_desc COLLATE DATABASE_DEFAULT
                    ,nature_of_injury_group COLLATE DATABASE_DEFAULT
                    ,loss_cause_code COLLATE DATABASE_DEFAULT
                    ,loss_cause_name COLLATE DATABASE_DEFAULT
                    ,policy_number COLLATE DATABASE_DEFAULT
                    ,claim_name COLLATE DATABASE_DEFAULT
                    ,SourceSysKey
                    ,SourceCreatedDate = NULL
                FROM (
					SELECT claim_source = 'OPENBOX'
						,claim_number = CONCAT('LCL', c.lClaimKey) COLLATE DATABASE_DEFAULT
						,claim_code = CONCAT('LCL', c.lClaimKey) COLLATE DATABASE_DEFAULT
						,claim_sect_code = CONCAT('LCLS', cs.lClaimSectionKey) COLLATE DATABASE_DEFAULT
						,claim_type = 'Claim' COLLATE DATABASE_DEFAULT
						,claim_status = CASE WHEN esm.sEntityStateMember = 'Closed' THEN 'Finalised' ELSE esm.sEntityStateMember END COLLATE DATABASE_DEFAULT
						,loss_date = CAST(c.dtLossFrom AS DATE)
						,advised_date = CAST(c.dtClaim1stReported AS DATE)
						,next_review_date = CAST(c.dtReviewed AS DATE)
						,action_name = COALESCE(tosc.sServerityCode, 'Uncoded') COLLATE DATABASE_DEFAULT
						,action_code = COALESCE('CS' + tosc.sCode, '-9999') COLLATE DATABASE_DEFAULT
						,cat_code = COALESCE(toc.sCATCode, '-9999') COLLATE DATABASE_DEFAULT
						,claimant_name = COALESCE(pa.sReinsuredName, 'Uncoded') COLLATE DATABASE_DEFAULT
						,claim_handler_code = '-9999' COLLATE DATABASE_DEFAULT
						,claim_handler_name = 'Uncoded' COLLATE DATABASE_DEFAULT
						,loss_area_code = COALESCE(lac.AAAACD, '-9999') COLLATE DATABASE_DEFAULT
						,loss_area_name = COALESCE(c.sLocationDescription, 'Uncoded') COLLATE DATABASE_DEFAULT
						,incident_desc = 'Uncoded' COLLATE DATABASE_DEFAULT
						,nature_of_injury_desc = 'Uncoded' COLLATE DATABASE_DEFAULT
						,nature_of_injury_group = 'Uncoded' COLLATE DATABASE_DEFAULT
						,loss_cause_code = '-9999' COLLATE DATABASE_DEFAULT
						,loss_cause_name = 'Uncoded' COLLATE DATABASE_DEFAULT
						,policy_number = ocn.CONTRACT_NBR COLLATE DATABASE_DEFAULT
						,claim_name = c.sClaimDescription COLLATE DATABASE_DEFAULT
						,SourceSysKey = 1
					FROM SRC_LLOYDS_DB.dbo.ClaimSection cs
					INNER JOIN SRC_LLOYDS_DB.dbo.Claim c
						ON c.lClaimKey = cs.lClaimKey
					INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity pa
						ON pa.lPolicyActivityKey = c.lPolicyActivityKey
					INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer torl
						ON torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
					INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup topg
						ON topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
						AND topg.sCode = 'RI'
					INNER JOIN SRC_LLOYDS_DB.dbo.Policy p
						ON p.lPolicyKey = c.lPolicyKey
					INNER JOIN SRC_LLOYDS_DB.dbo.Entity e
						ON e.sEntity = 'Claim'
					INNER JOIN SRC_LLOYDS_DB.dbo.EntityInstanceStates eis
						ON eis.lInstanceKey = c.lClaimKey
						AND eis.lEntityKey = e.lEntityKey
					INNER JOIN SRC_LLOYDS_DB.dbo.EntitystateMembers esm
						ON esm.lEntitystatememberKey = eis.lEntityStateMemberKey
					LEFT JOIN SRC_LLOYDS_DB.dbo.TypeOfServerityCode tosc
						ON tosc.lTypeOfServerityCodeKey = c.lTypeOfServerityCodeKey
					LEFT JOIN SRC_LLOYDS_DB.dbo.TypeOfCAT toc
						ON toc.lCatCodeKey = c.lCatCodeKey
					LEFT JOIN SRC_LLOYDS_DB.dbo.Contact ac
						ON ac.lContactKey = pa.lReassuredContactKey
					LEFT JOIN SRC_GENIUS_DB.dbo.ZHAADF00_Area lac
						ON lac.AAAADS = c.sLocationDescription COLLATE DATABASE_DEFAULT
					LEFT JOIN #OpenboxContractNumber ocn
						ON ocn.PolicyReference = p.sPolicyReference COLLATE DATABASE_DEFAULT
                ) ob
            ) clm
            
            UNION ALL
            
            SELECT CONVERT([varchar](10), 'N/A') [claim_source]
                ,CONVERT([varchar](30), 'N/A') [claim_number]
                ,CONVERT([varchar](30), 'N/A') [claim_code]
                ,CONVERT([varchar](50), 'N/A') [claim_sect_code]
                ,CONVERT([varchar](30), 'N/A') [claim_type]
                ,CONVERT([varchar](50), 'N/A') [claim_status]
                ,CONVERT([date], NULL) [loss_date]
                ,CONVERT([date], NULL) [advised_date]
                ,CONVERT([date], NULL) [next_review_date]
                ,CONVERT([varchar](30), 'N/A') [action_name]
                ,CONVERT([varchar](10), 'N/A') [action_code]
                ,CONVERT([varchar](30), 'N/A') [cat_code]
                ,CONVERT([varchar](100), 'N/A') [claimant_name]
                ,CONVERT([varchar](50), 'N/A') [claim_handler_code]
                ,CONVERT([varchar](50), 'N/A') [claim_handler_name]
                ,CONVERT([varchar](50), 'N/A') [loss_area_code]
                ,CONVERT([varchar](80), 'N/A') [loss_area_name]
                ,CONVERT([varchar](2000), 'N/A') [incident_desc]
                ,CONVERT([varchar](100), 'N/A') [nature_of_injury_desc]
                ,CONVERT([varchar](30), 'N/A') [nature_of_injury_group]
                ,CONVERT([varchar](40), 'N/A') [loss_cause_code]
                ,CONVERT([varchar](100), 'N/A') [loss_cause_name]
                ,CONVERT([varchar](30), 'N/A') [policy_number]
                ,CONVERT([varchar](200), 'N/A') [claim_name]
                ,CONVERT([smallint], 0) [SourceSysKey]
                ,SourceCreatedDate = NULL
            
            UNION ALL
            
            SELECT CONVERT([varchar](10), 'Uncoded') [claim_source]
                ,CONVERT([varchar](30), 'Uncoded') [claim_number]
                ,CONVERT([varchar](30), 'Uncoded') [claim_code]
                ,CONVERT([varchar](50), 'Uncoded') [claim_sect_code]
                ,CONVERT([varchar](30), 'Uncoded') [claim_type]
                ,CONVERT([varchar](50), 'Uncoded') [claim_status]
                ,CONVERT([date], NULL) [loss_date]
                ,CONVERT([date], NULL) [advised_date]
                ,CONVERT([date], NULL) [next_review_date]
                ,CONVERT([varchar](30), 'Uncoded') [action_name]
                ,CONVERT([varchar](10), 'Uncoded') [action_code]
                ,CONVERT([varchar](30), 'Uncoded') [cat_code]
                ,CONVERT([varchar](100), 'Uncoded') [claimant_name]
                ,CONVERT([varchar](50), 'Uncoded') [claim_handler_code]
                ,CONVERT([varchar](50), 'Uncoded') [claim_handler_name]
                ,CONVERT([varchar](50), 'Uncoded') [loss_area_code]
                ,CONVERT([varchar](80), 'Uncoded') [loss_area_name]
                ,CONVERT([varchar](2000), 'Uncoded') [incident_desc]
                ,CONVERT([varchar](100), 'Uncoded') [nature_of_injury_desc]
                ,CONVERT([varchar](30), 'Uncoded') [nature_of_injury_group]
                ,CONVERT([varchar](40), 'Uncoded') [loss_cause_code]
                ,CONVERT([varchar](100), 'Uncoded') [loss_cause_name]
                ,CONVERT([varchar](30), 'Uncoded') [policy_number]
                ,CONVERT([varchar](200), 'Uncoded') [claim_name]
                ,CONVERT([smallint], 0) [SourceSysKey]
                ,SourceCreatedDate = NULL
        ) claim;

        -- Loading logic
        ALTER TABLE #DimClaim ADD DataHash BINARY (20) NULL;
        ALTER TABLE #DimClaim ADD DataHashType1 BINARY(20) NULL

        UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS (
				'|'
				,claim_type
				,claim_status
				,loss_date
				,advised_date
				,next_review_date
				,action_name
				,action_code
				,cat_code
				,CLAIMANT_NAME
				,claim_handler_code
				,claim_handler_name
				,loss_area_code
				,loss_area_name
				,incident_desc
				,nature_of_injury_desc
				,nature_of_injury_group
				,loss_cause_code
				,loss_cause_name
				,policy_number
				,claim_name
				))
			,DataHashType1 = HASHBYTES('SHA1', CONCAT (
				''
				,SourceCreatedDate
				))



        FROM #DimClaim s

        DROP TABLE IF EXISTS #LoadOperation

        CREATE TABLE #LoadOperation (
            claim_number VARCHAR(30) COLLATE DATABASE_DEFAULT NULL
            ,claim_code VARCHAR(30) COLLATE DATABASE_DEFAULT NULL
            ,claim_sect_code VARCHAR(50) COLLATE DATABASE_DEFAULT NULL
            ,SourceSysKey SMALLINT NOT NULL
            ,Operation CHAR(1) NOT NULL
            ,UNIQUE (
                claim_number
                ,claim_code
                ,claim_sect_code
                ,SourceSysKey
            )
        )

        INSERT INTO #LoadOperation (
            claim_number
            ,claim_code
            ,claim_sect_code
            ,SourceSysKey
            ,Operation
        )
        SELECT claim_number = COALESCE(t.claim_number COLLATE DATABASE_DEFAULT, s.claim_number COLLATE DATABASE_DEFAULT)
            ,claim_code = COALESCE(t.claim_code COLLATE DATABASE_DEFAULT, s.claim_code COLLATE DATABASE_DEFAULT)
            ,claim_sect_code = COALESCE(t.claim_sect_code COLLATE DATABASE_DEFAULT, s.claim_sect_code COLLATE DATABASE_DEFAULT)
            ,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
            ,Operation = CASE WHEN t.DimClaimID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash
					AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END            
        FROM (
            SELECT t.*
            FROM assumed.DimClaim t
            WHERE t.EndDate = '31 Dec 9999'
        ) t
        FULL JOIN #DimClaim s
            ON COALESCE(s.claim_number, '^&*') = COALESCE(t.claim_number, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(s.claim_code, '^&*') = COALESCE(t.claim_code, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(s.claim_sect_code, '^&*') = COALESCE(t.claim_sect_code, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(s.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
        WHERE t.DataHash IS NULL
            OR s.DataHash IS NULL
            OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1
			OR t.DataHashType1 IS NULL		            

        BEGIN TRANSACTION

		-- Type1
		UPDATE t
		SET SourceCreatedDate = s.SourceCreatedDate
			,DataHashType1 = s.DataHashType1
			,UpdateDate = p.NewValidFrom
		FROM assumed.DimClaim t
		INNER JOIN #LoadOperation lo
            ON COALESCE(lo.claim_number, '^&*') = COALESCE(t.claim_number, '^&*') COLLATE DATABASE_DEFAULT
                            AND COALESCE(lo.claim_code, '^&*') = COALESCE(t.claim_code, '^&*') COLLATE DATABASE_DEFAULT
                            AND COALESCE(lo.claim_sect_code, '^&*') = COALESCE(t.claim_sect_code, '^&*') COLLATE DATABASE_DEFAULT
                            AND COALESCE(lo.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
                            AND lo.Operation IN ('U', '1')
		INNER JOIN #DimClaim s
            ON COALESCE(s.claim_number, '^&*') = COALESCE(t.claim_number, '^&*') COLLATE DATABASE_DEFAULT
                            AND COALESCE(s.claim_code, '^&*') = COALESCE(t.claim_code, '^&*') COLLATE DATABASE_DEFAULT
                            AND COALESCE(s.claim_sect_code, '^&*') = COALESCE(t.claim_sect_code, '^&*') COLLATE DATABASE_DEFAULT
                            AND COALESCE(s.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
		CROSS JOIN #Parameters p
		WHERE p.NewValidFrom BETWEEN t.StartDate
				AND t.EndDate

        -- Type2
        UPDATE t
        SET EndDate = p.ClosingValidTo
        FROM assumed.DimClaim t
        INNER JOIN #LoadOperation lo
            ON COALESCE(lo.claim_number, '^&*') = COALESCE(t.claim_number, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(lo.claim_code, '^&*') = COALESCE(t.claim_code, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(lo.claim_sect_code, '^&*') = COALESCE(t.claim_sect_code, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(lo.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
                AND lo.Operation IN ('U', '2')
        CROSS JOIN #Parameters p
        WHERE t.EndDate = '31 Dec 9999'        

        INSERT INTO assumed.DimClaim (
            [StartDate]
            ,[claim_source]
            ,[claim_number]
            ,[claim_code]
            ,[claim_sect_code]
            ,[claim_type]
            ,[claim_status]
            ,[loss_date]
            ,[advised_date]
            ,[next_review_date]
            ,[action_name]
            ,[action_code]
            ,[cat_code]
            ,[claimant_name]
            ,[claim_handler_code]
            ,[claim_handler_name]
            ,[loss_area_code]
            ,[loss_area_name]
            ,[incident_desc]
            ,[nature_of_injury_desc]
            ,[nature_of_injury_group]
            ,[loss_cause_code]
            ,[loss_cause_name]
            ,[policy_number]
            ,[claim_name]
            ,[SourceSysKey]
            ,[DataHash]
			,DataHashType1
			,UpdateDate
			,SourceCreatedDate            
        )
        SELECT StartDate = p.NewValidFrom
            ,s.[claim_source]
            ,s.[claim_number]
            ,s.[claim_code]
            ,s.[claim_sect_code]
            ,s.[claim_type]
            ,s.[claim_status]
            ,s.[loss_date]
            ,s.[advised_date]
            ,s.[next_review_date]
            ,s.[action_name]
            ,s.[action_code]
            ,s.[cat_code]
            ,s.[claimant_name]
            ,s.[claim_handler_code]
            ,s.[claim_handler_name]
            ,s.[loss_area_code]
            ,s.[loss_area_name]
            ,s.[incident_desc]
            ,s.[nature_of_injury_desc]
            ,s.[nature_of_injury_group]
            ,s.[loss_cause_code]
            ,s.[loss_cause_name]
            ,s.[policy_number]
            ,s.[claim_name]
            ,s.[SourceSysKey]
            ,s.[DataHash]
            ,s.DataHashType1 
			,UpdateDate = p.NewValidFrom
			,s.SourceCreatedDate
        FROM #DimClaim s
        INNER JOIN #LoadOperation lo
            ON COALESCE(s.claim_number, '^&*') = COALESCE(lo.claim_number, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(s.claim_code, '^&*') = COALESCE(lo.claim_code, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(s.claim_sect_code, '^&*') = COALESCE(lo.claim_sect_code, '^&*') COLLATE DATABASE_DEFAULT
                AND COALESCE(lo.SourceSysKey, -1) = COALESCE(s.SourceSysKey, -1)
                AND lo.Operation IN ('I', 'U', '2')
        CROSS JOIN #Parameters p

        COMMIT

        DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
        DECLARE @RowsProcessed BIGINT = COALESCE((
                    SELECT COUNT(0)
                    FROM #LoadOperation
                    WHERE Operation IN ('I', 'U')
                ), 0)
        DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
        DECLARE @ProcessingStarted DATETIME = (
                SELECT p.NewValidFrom
                FROM #Parameters p
            )
        DECLARE @ProcessingEnded DATETIME = GETDATE()
        DECLARE @SourceDataDate DATETIME = (
                SELECT [sql_date]
                FROM ETL.dbo.[day]
                WHERE today = 1
            )

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

        DECLARE @ErrorDescription VARCHAR(8000) = CONCAT (
                'Error: '
                ,ERROR_NUMBER()
                ,' - '
                ,ERROR_MESSAGE()
                ,'; '
                ,'Occurred in procedure: ' + ERROR_PROCEDURE() + ', '
                ,'Line '
                ,ERROR_LINE()
            )
        DECLARE @ErrorNumber INT = ERROR_NUMBER()
        DECLARE @ErrorMessage VARCHAR(8000) = ERROR_MESSAGE()
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrorState INT = ERROR_STATE()
        DECLARE @ProcessNameC VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
        DECLARE @ProcessingStartedC DATETIME = (
                SELECT p.NewValidFrom
                FROM #Parameters p
            )
        DECLARE @ProcessingEndedC DATETIME = GETDATE()
        DECLARE @SourceDataDateC DATETIME = (
                SELECT [sql_date]
                FROM ETL.dbo.[day]
                WHERE today = 1
            )

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

        RAISERROR (
                @ErrorMessage
                ,@ErrorSeverity
                ,@ErrorState
            )
    END CATCH
END
