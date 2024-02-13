
function ExecSQL {
    param (
        [Parameter(Mandatory)]
        [string] $Query,
        [Parameter(Mandatory=$false)]
        [string] $database = "Phase24Test"
    )

    <# Envirnoment Variables #>
    $Server = "10.210.3.1"              #Test Server
    $DB = $database                     #Test database name
    $u = "sa"
    $p = "C@rg@s2020!"

    # $Server = "10.210.2.236"                #PROD Server
    # $DB = "Phase24ConversionScripts"        #PROD DB
    # $u = "sa"
    # $p = "Winter2019!"

    $Timeout = 30                     #60 minutes

    Invoke-Sqlcmd `
        -ServerInstance $Server `
        -Database $DB `
        -Username $u `
        -Password $p `
        -TrustServerCertificate `
        -QueryTimeout $Timeout `
        -Query $Query `
        | Select-Object * -ExcludeProperty ItemArray, Table, RowError, RowState, HasErrors
}

    $GetDBName = "Phase24Test"

    $GetVersion = ExecSQL "
                SELECT top 1 PackageName
				FROM cDeployment 
				WHERE cstDeploymentTypeID = 1 
                ORDER BY DeploymentEndDateTime desc 
                "
    
    $GetTables = ExecSQL "
                Select distinct c.table_name
	            FROM INFORMATION_SCHEMA.COLUMNS c
                JOIN INFORMATION_SCHEMA.TABLES t on c.TABLE_NAME = t.TABLE_NAME
                WHERE t.TABLE_TYPE='BASE TABLE'
                and c.TABLE_SCHEMA = 'dbo'
                and c.table_name not like ( '%[_]%' ) 
                and c.table_name not like '%QueryTemp%'
                order by c.table_name 
                "

    $GetRowCounts = ExecSQL "
                Select t.name TableName, i.rows TotalRowCount
                From sysobjects t inner join sysindexes i on i.id = t.id and i.indid in (0,1) 
                Where t.xtype = 'U'
                "

    $htmlParams = @{
        Title = "Data Dictionary for $GetDBName"
        Body = "<P><b>$GetDBName Ver. $($GetVersion.PackageName) </b></P>"
#        PreContent = "Database: $GetDBName"
#        PostContent = ""
    }

    $Report = $null
    foreach ($tbl in $GetTables.Table_name) {
        Write-Host $tbl
        $Fields = ExecSQL " 
            SELECT 
	            [Column_Name] = CAST(clmns.name AS VARCHAR(35)),
	            [Description] = substring(ISNULL(CAST(exprop.value AS VARCHAR(255)),''),1,250) + substring(ISNULL(CAST(exprop.value AS VARCHAR(500)),''),251,250),
	            [IsPrimaryKey] = CAST(ISNULL(idxcol.index_column_id, 0)AS VARCHAR(20)),
	            [IsForeignKey] = CAST(ISNULL(
		            (SELECT TOP 1 1
		            FROM sys.foreign_key_columns AS fkclmn
		            WHERE fkclmn.parent_column_id = clmns.column_id
		            AND fkclmn.parent_object_id = clmns.object_id
		            ), 0) AS VARCHAR(20)),
	            [DataType] = CAST(udt.name AS CHAR(15)),
	            [Length] = CAST(CAST(CASE 
				            WHEN typ.name IN (N'nchar', N'nvarchar') AND clmns.max_length <> -1 THEN clmns.max_length/2
				            ELSE clmns.max_length 
				            END AS INT
			            ) AS VARCHAR(20)),
	            [Numeric_Precision] = CAST(CAST(clmns.precision AS INT) AS VARCHAR(20)),
	            [Numeric_Scale] = CAST(CAST(clmns.scale AS INT) AS VARCHAR(20)),
	            [Nullable] = CAST(clmns.is_nullable AS VARCHAR(20)),
	            [Computed] = CAST(clmns.is_computed AS VARCHAR(20)),
	            [Identity] = CAST(clmns.is_identity AS VARCHAR(20)),
	            [Default_Value] = isnull(CAST(cnstr.definition AS VARCHAR(20)),'')
	        FROM sys.tables AS tbl
	            INNER JOIN sys.all_columns AS clmns				ON clmns.object_id=tbl.object_id
	            LEFT OUTER JOIN sys.indexes AS idx				ON idx.object_id = clmns.object_id AND 1 =idx.is_primary_key
	            LEFT OUTER JOIN sys.index_columns AS idxcol		ON idxcol.index_id = idx.index_id AND idxcol.column_id = clmns.column_id AND idxcol.object_id = clmns.object_id AND 0 = idxcol.is_included_column
	            LEFT OUTER JOIN sys.types AS udt				ON udt.user_type_id = clmns.user_type_id
	            LEFT OUTER JOIN sys.types AS typ				ON typ.user_type_id = clmns.system_type_id AND typ.user_type_id = typ.system_type_id
	            LEFT JOIN sys.default_constraints AS cnstr		ON cnstr.object_id=clmns.default_object_id
	            LEFT OUTER JOIN sys.extended_properties exprop	ON exprop.major_id = clmns.object_id AND exprop.minor_id = clmns.column_id AND exprop.name = 'MS_Description'
	        WHERE ( tbl.name = '$tbl' )
	        ORDER BY clmns.column_id ASC
        "

#        $Report += $Fields | ConvertTo-Html -Fragment -PreContent "<div id=""$tbl""><h2>$tbl</h2></div>""
        $Report += $Fields | ConvertTo-Html -Fragment -PreContent "<div><div id=""$tbl""><h2>$tbl</h2></div><div>RowCount: $($GetRowCounts.Where({ $_.TableName -eq $tbl }).TotalRowCount) </div></div>"
    }


    $title = $GetDBName + ' (' + $($GetVersion.PackageName) + ')'

    $style = '
        body {
            font-family: sans-serif;
        }
        table {
            font-size: 12px;
            width: 100%;
        }
		table, th {
			color: #000;
		}
        table, th, td {
            border: 1px solid #666;
			border-radius: 3px;
			padding: 5px;
        } 
        td:first-child {
            color: #000; 
            font-weight: bold;
            text-align: end;
        }
        h2 {
            margin-bottom: -15px;
        }
        div:nth-child(2) {
            text-align: end;
        }
    '


#    '<html><head><title>' + $GetDBName + ' (' + $GetVersion + ')</title><style>' + $style + '</style></head><body>' + $Report + '</body></html>' | Out-File $GetDBName"_DD2.html"
    '<html><head><title>' + $title + '</title><style>' + $style + '</style></head><body>' + $Report + '</body></html>' | Out-File $GetDBName"_DD2.html"
    