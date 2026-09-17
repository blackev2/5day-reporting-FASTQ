/*
Author: Elizabeth Black
Title: \5DAY-BMD_FASTQ.sql
Variables: user_input_fastq (user will add the depositor_study_number at the prompt in single quotes and if multiple studies are included, separated by a comma)
Input: MNDB/BMD_5D
Output: SQL results are output to a view: V_BMD_5DAY_FASTQ (select permissions granted to CEBS_READER).
Purpose: SQL Script to extract data for all animals for all studies specified in 5 Day - BMD Animal Fastq Reports:
*/

UNDEFINE user_input_fastq
ACCEPT user_input_fastq PROMPT 'Enter value:'
CREATE OR REPLACE VIEW V_BMD_5DAY_FASTQ AS

WITH FASTQ AS (select distinct g.species, ns.sex, s.depositor_study_number,nvl (ANML_REF, ANML_NUM) as "Animal Number", selection_name as "Selection", case when dose in '0' then 'Vehicle Control' else s.CHEMICAL_NAME end as "Group", dose as "Dose (ppm)", 
Case when  SUBJECT_DEATH_STATUS in 'scheduled' then 'Yes' else 'No' end as "Survived to Study Termination",-- bmd.tissue,
Case when bmd.Tissue is null then 'None' else bmd.Tissue end as "TISSUE_BMD", 
Case when bmd.fastq_file_name is null then 'NA' else bmd.fastq_file_name end as "FASTQ File Name",
--bmd.fastq_file_name
ANML_NUM
from MNDB.RPTS_STUDY s
join MNDB.RPTS_subjects ns
on s.study_ID = ns.study_ID
and s.is_deleted in 'F'
and s.depositor_study_number  in (&&user_input_fastq)
join mndb.rpts_trt_groups g
on g.studysubjectgroup_ID = ns.studysubjectgroup_ID
join mndb.rpts_subject_selection sel
on sel.studysubject_ID = ns.studysubject_ID
and selection_type in 'NTP'
left join BMD_5DAY_FASTQ bmd on 
bmd.animal_id = anml_num
and bmd.test_agent = s.CHEMICAL_NAME
and bmd.species = g.species
order by s.depositor_study_number, to_number (dose),
TO_NUMBER(REGEXP_SUBSTR("Animal Number", '^\d+')), 
CASE
    WHEN REGEXP_LIKE("Animal Number", '^\d+') THEN 0
    ELSE 1
END,
REGEXP_SUBSTR("Animal Number", '[A-Z]+$') ,
Case when bmd.Tissue is null then 'None' else bmd.Tissue end),

HEADER AS (select distinct study.study_id, study.depositor_study_number, study.chemical_name, pvt.casno, pvt.accession_number AS DTTID, db1.dtxsid, pvt.study_type, rtg.species, rtg.strain
from rpts_study study, rpts_trt_groups rtg, rpts_pvt_c_number pvt, DDD@datacube_go_link db1
where study.depositor_study_number in (&&user_input_fastq)
  and is_deleted = 'F'
  and study.study_id = rtg.study_id
  and study.depositor_study_number = pvt.depositor_study_number
  and pvt.casno = db1.ntp_casrn)
  
select FASTQ.*, HEADER.CHEMICAL_NAME, HEADER.CASNO, HEADER.DTTID, HEADER.DTXSID, HEADER.STUDY_TYPE, HEADER.STRAIN, TO_CHAR(SYSDATE, '"Date: "DD Mon YYYY') AS FORMATTED_DATE,
TO_CHAR(SYSDATE, '"Time: "HH:MM:SS AM') AS FORMATTED_TIME
from FASTQ left join HEADER on FASTQ.depositor_study_number = HEADER.depositor_study_number
order by FASTQ.depositor_study_number, TO_NUMBER(FASTQ."Dose (ppm)"), 
TO_NUMBER(REGEXP_SUBSTR("Animal Number", '^\d+')), 
CASE
    WHEN REGEXP_LIKE("Animal Number", '^\d+') THEN 0
    ELSE 1
END,
REGEXP_SUBSTR("Animal Number", '[A-Z]+$'), FASTQ.TISSUE_BMD
