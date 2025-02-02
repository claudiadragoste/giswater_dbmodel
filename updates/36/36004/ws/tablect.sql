/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


SET search_path = SCHEMA_NAME, public, pg_catalog;

ALTER TABLE IF EXISTS rpt_cat_result DROP CONSTRAINT IF EXISTS rpt_cat_result_status_check;

ALTER TABLE IF EXISTS rpt_cat_result
 ADD CONSTRAINT rpt_cat_result_status_check CHECK (status = ANY (ARRAY[0, 1, 2, 3]));
