# Animal FASTQ Report: 5DAY-BMD_FASTQ

## Overview

The `5DAY-BMD_FASTQ.sql` script extracts and consolidates genomic sequencing data (FASTQ file information) for animals across specified studies in the National Toxicology Program (NTP) Microarray Database (MNDB). The script generates a structured view combining animal subject metadata, dosing information, FASTQ file details, and chemical/study attributes.

## Purpose

This SQL script prepares a comprehensive dataset for 5-day BMD (Benchmark Dose) animal FASTQ reports by:
- Retrieving animal subject data filtered by user-specified study identifiers
- Joining treatment, species, and selection information
- Matching FASTQ file metadata from an external BMD dataset
- Enriching the dataset with chemical, study type, and regulatory information
- Outputting results to a view with controlled read access

## Key Inputs and Outputs

### Input
- **Database Source:** `MNDB/BMD_5D` (National Toxicology Program Microarray Database)
- **User Parameter:** `user_input_fastq` — A comma-separated list of depositor study numbers (entered at runtime in single quotes, e.g., `'STUDYID1','STUDYID2'`)

### Output
- **View Name:** `V_BMD_5DAY_FASTQ`
- **Access:** Read permissions granted to `CEBS_READER` role
- **Result Set:** Flat, denormalized table containing animal-level data with enriched metadata and timestamps

## Major Processing Steps and Data Flow

### Step 1: FASTQ CTE (Common Table Expression)
The `FASTQ` CTE performs the primary data extraction:

1. **Starting Point:** Retrieves distinct study-level records from `MNDB.RPTS_STUDY` where:
   - `depositor_study_number` matches user input
   - `is_deleted = 'F'` (excludes deleted records)

2. **Subject Join:** Joins with `MNDB.RPTS_SUBJECTS` to get individual animal records by study

3. **Species/Treatment Join:** Joins with `MNDB.RPTS_TRT_GROUPS` to attach:
   - Species information
   - Sex
   - Other treatment group attributes

4. **Selection Criteria Join:** Joins with `MNDB.RPTS_SUBJECT_SELECTION` to filter for:
   - `selection_type = 'NTP'` (selects only NTP-classified animals)

5. **FASTQ Data Match:** Left outer join with `BMD_5DAY_FASTQ` external table to attach:
   - FASTQ file names
   - Tissue information
   - Matches on: `animal_id`, `test_agent` (chemical name), and `species`

6. **Data Transformations** within the FASTQ CTE:
   - **Animal Number:** Coalesces `ANML_REF` or `ANML_NUM` (handles missing reference IDs)
   - **Dose:** Converts to text; maps `'0'` to `'Vehicle Control'`
   - **Subject Death Status:** Converts to readable format (`'scheduled'` → `'Yes'`, others → `'No'`)
   - **Tissue:** Handles nulls; converts missing values to `'None'`, otherwise shows tissue type
   - **FASTQ File Name:** Handles nulls; converts missing values to `'NA'`

7. **Sorting (within CTE):** Orders by depositor study number, dose (numeric), animal number prefix (numeric), suffix type, and tissue

### Step 2: HEADER CTE
The `HEADER` CTE retrieves study-level metadata:

1. **Study Information:** Queries `RPTS_STUDY` filtered by:
   - `depositor_study_number` matching user input
   - `is_deleted = 'F'`

2. **Chemical Lookup:** Joins `RPTS_PVT_C_NUMBER` to retrieve:
   - Chemical name
   - CAS number (CASNO)
   - DTTID (Accession number)

3. **External Database Link:** Joins with `DDD@datacube_go_link` (appears to be an external database link to DataCube) to retrieve:
   - DTXSID (chemical identifier)

4. **Treatment Metadata:** Joins with `RPTS_TRT_GROUPS` to capture:
   - Species
   - Strain
   - Study type

### Step 3: Final Join and Output
The main query combines results:

1. **Left Outer Join:** FASTQ data left joined to HEADER data on `depositor_study_number` to attach chemical, regulatory, and study-level attributes

2. **Timestamp Addition:** Appends system date and time at report generation in human-readable format:
   - `FORMATTED_DATE` (e.g., "Date: 28 Sep 2026")
   - `FORMATTED_TIME` (e.g., "Time: 14:30:45 PM")

3. **Final Sort:** Orders by:
   - Depositor study number
   - Dose (numeric)
   - Animal number numeric prefix
   - Animal number suffix type (pure numeric first, then alphanumeric)
   - Tissue type

## Important Views, CTEs, and Transformations

### CTEs
- **FASTQ:** Core animal-level data extraction with treatment and FASTQ metadata
- **HEADER:** Study-level chemical and regulatory metadata

### Key Transformations

| Column | Input | Transformation | Purpose |
|--------|-------|-----------------|---------|
| Animal Number | ANML_REF, ANML_NUM | `NVL()` coalesce | Prioritizes reference ID, falls back to animal number |
| Dose | Raw dose value | Case statement on `'0'` | Converts vehicle control dose code to readable label |
| Survived to Study Termination | SUBJECT_DEATH_STATUS | Case on `'scheduled'` | Interprets scheduled death as survival to termination |
| TISSUE_BMD | BMD.Tissue | `CASE` on null | Replaces missing tissue data with `'None'` |
| FASTQ File Name | BMD.fastq_file_name | `CASE` on null | Replaces missing file names with `'NA'` |

### Sorting Logic
Animal numbers are sorted using regular expressions to handle mixed numeric and alphabetic components:
- Extracts numeric prefix: `REGEXP_SUBSTR("Animal Number", '^\d+')`
- Identifies format type: `REGEXP_LIKE("Animal Number", '^\d+')` returns 0 for pure numeric, 1 for alphanumeric
- Extracts alphabetic suffix: `REGEXP_SUBSTR("Animal Number", '[A-Z]+$')`

This ensures animals sort naturally (e.g., 1, 2, 10, A1, A2 rather than 1, 10, 2, A1, A2).

## Dependencies and Assumptions

### Database Dependencies
- **MNDB Database:** Study, subject, treatment group, and subject selection data must be available and current
- **External FASTQ Table:** `BMD_5DAY_FASTQ` table must exist with columns: `animal_id`, `test_agent`, `species`, `tissue`, `fastq_file_name`
- **External Database Link:** `DDD@datacube_go_link` must be configured for DataCube access (for DTXSID lookup)

### Data Assumptions
1. **Study Deletion Status:** Active studies marked with `is_deleted = 'F'`
2. **Selection Type Filter:** Only animals with `selection_type = 'NTP'` are included
3. **CAS Number Availability:** Chemical CAS numbers exist in `RPTS_PVT_C_NUMBER` and link to DataCube
4. **FASTQ Matching:** FASTQ records are matched by exact match on animal ID, chemical name (test agent), and species
5. **Dose Format:** Dose value `'0'` indicates vehicle control; all other values are treated as actual dose levels
6. **Animal Number Format:** Animal identifiers may be numeric-only or contain alphabetic suffixes
7. **Database Link Stability:** External DataCube link remains available during query execution

### Access Control
- View created with read permissions for `CEBS_READER` role only (write/modify restricted to creator)

## Expected Workflow and Usage

### Execution Steps
1. User runs the SQL script in the database environment (typically Oracle, given syntax and functions used)
2. Script prompts user to enter depositor study numbers (format: `'STUDY123'` or `'STUDY123','STUDY124'` for multiple)
3. Script creates or replaces view `V_BMD_5DAY_FASTQ` with filtered results
4. User queries the view: `SELECT * FROM V_BMD_5DAY_FASTQ;`

### Expected Result Set
Each row represents a unique animal with columns:
- **Animal Metadata:** Species, sex, animal number, dose, selection name, survival status
- **FASTQ Details:** Tissue type, FASTQ file name
- **Study Metadata:** Depositor study number, chemical name, CAS number, DTTID, DTXSID, study type, strain
- **Report Metadata:** Formatted date and time of report generation

### How to Understand and Use This SQL

**For Report Users:**
1. Execute the script with your desired study IDs
2. Query the resulting view for a complete dataset combining animal metadata and FASTQ file information
3. Use the FASTQ File Name column to locate sequencing data files
4. Filter by tissue type, dose, or species as needed for downstream analysis

**For Developers/Maintainers:**
1. Review the FASTQ CTE to understand what animal and treatment data is extracted
2. Review the HEADER CTE to trace where chemical and regulatory metadata originates
3. Check join conditions: species and animal ID match is critical for FASTQ linkage
4. Note that the left outer join in the final query means some animals may have null FASTQ data (shown as 'NA' or 'None')
5. Verify user input parameter syntax matches the expected format before debugging filter issues
6. Test with known study IDs to validate output structure and row counts

**For Troubleshooting:**
- If no results appear: Verify `depositor_study_number` values exist and match expected format
- If FASTQ columns are null: Check `BMD_5DAY_FASTQ` table for matching records on animal ID, chemical name, and species
- If external link fails: Contact DBA to verify `DDD@datacube_go_link` availability
- If permissions are denied: Confirm user has select access to all underlying tables and the database link

## Notes for Future Enhancement

- **Needs Clarification:** The relationship between `ANML_REF` and `ANML_NUM` in the coalesce logic is unclear; consider documenting which field is authoritative
- **Needs Clarification:** The exact purpose and content of `BMD_5D` versus `MNDB` schemas should be documented
- **Needs Clarification:** Whether the `SELECTION_TYPE = 'NTP'` filter is project-wide standard or specific to this report
- **Possible Enhancement:** Consider parameterizing the selection type if other filter criteria are needed
- **Possible Enhancement:** The external DataCube link could fail silently; consider adding error handling or validity checks
