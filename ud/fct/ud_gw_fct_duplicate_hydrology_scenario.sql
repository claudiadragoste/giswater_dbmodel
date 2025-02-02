/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3156

CREATE OR REPLACE FUNCTION "SCHEMA_NAME".gw_fct_duplicate_hydrology_scenario(p_data json)
RETURNS json AS
$BODY$

/*EXAMPLE
SELECT SCHEMA_NAME.gw_fct_duplicate_hydrology_scenario($${"client":{"device":4, "infoType":1, "lang":"ES"}, "data":{"parameters":{"target":"1", "copyFrom":"2", "action":"DELETE-COPY"}}}$$)

SELECT SCHEMA_NAME.gw_fct_duplicate_hydrology_scenario($${"client":{"device":4, "lang":"en_US", "infoType":1, "epsg":25831}, "form":{}, "feature":{}, "data":{"filterFields":{}, "pageInfo":{}, "parameters":{"name":"test", "descript":null, "parent":null, "type":"DEMAND", "active":"true", "expl":"1", "copyFrom": 1}}}$$)

-- fid: 459

*/


DECLARE

object_rec record;

v_version text;
v_result json;
v_result_info json;
v_copyfrom integer;
v_target integer;
v_error_context text;
v_count integer;
v_count2 integer;
v_projecttype text;
v_fid integer = 459;
v_source_name text;
v_target_name text;
v_action text;
v_querytext text;
v_result_id text = null;

v_name text;
v_descript text;
v_parent_id integer;
v_active boolean;
v_expl_id integer;
v_scenarioid integer;
v_aux_params json;
v_infiltration text;
v_text text;
v_inp_hydrology text;


BEGIN

	SET search_path = "SCHEMA_NAME", public;

	-- select version
	SELECT giswater, project_type INTO v_version, v_projecttype FROM sys_version ORDER BY id DESC LIMIT 1;

	-- getting input data
	v_name :=  ((p_data ->>'data')::json->>'parameters')::json->>'name';
	v_infiltration :=  ((p_data ->>'data')::json->>'parameters')::json->>'infiltration';
	v_text :=  ((p_data ->>'data')::json->>'parameters')::json->>'text';
	v_expl_id :=  ((p_data ->>'data')::json->>'parameters')::json->>'expl';
	v_active :=  ((p_data ->>'data')::json->>'parameters')::json->>'active';
	v_aux_params :=  ((p_data ->>'data')::json->>'aux_params')::json;
	v_copyfrom := ((p_data ->>'data')::json->>'parameters')::json->>'copyFrom';
    v_action := 'KEEP-COPY';

	-- Reset values
	DELETE FROM anl_node WHERE cur_user="current_user"() AND fid=v_fid;
	DELETE FROM audit_check_data WHERE cur_user="current_user"() AND fid=v_fid;

	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, concat('DUPLICATE HYDROLOGY SCENARIO'));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, '--------------------------------------------------');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, concat('Name: ',v_name));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, concat('Infiltration: ',v_infiltration));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, concat('Text: ',v_text));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, concat('Expl_id: ',v_expl_id));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, concat('Active: ',v_active));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 4, concat(''));

	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 3, 'ERRORS');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 3, '--------');

	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 2, 'WARNINGS');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 2, '---------');

	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 1, 'INFO');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 1, '---------');

	-- process
	-- Create empty hydrology_scenario
	EXECUTE 'SELECT gw_fct_create_hydrology_scenario_empty($$'||p_data||'$$);';
	SELECT hydrology_id INTO v_scenarioid FROM cat_hydrology where name = v_name;
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
		VALUES (v_fid, null, 1, concat('INFO: Hydrology scenario named "',v_name,'" created with values from hydrology scenario ( ',v_copyfrom,' )'));

	-- Copy values from hydrology scenario to copy from
	EXECUTE 'SELECT gw_fct_manage_hydrology_values($${"client": '||(p_data ->>'client')::json||', "data": {"parameters": {"target": '||v_scenarioid||', "copyFrom": '||v_copyfrom||', "action": '||quote_ident(v_action)||', "sector":-998}}}$$);';
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
		VALUES (v_fid, null, 1, concat('INFO: Copied values from hydrology scenario ( ',v_copyfrom,' ) to new hydrology scenario ( ',v_scenarioid,' )'));

	-- insert spacers
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 3, concat(''));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, null, 2, concat(''));

	-- get results
	-- info
	SELECT array_to_json(array_agg(row_to_json(row))) INTO v_result
	FROM (SELECT id, error_message as message FROM audit_check_data WHERE cur_user="current_user"() AND fid=v_fid order by criticity desc, id asc) row;
	v_result := COALESCE(v_result, '{}');
	v_result_info = concat ('{"geometryType":"", "values":',v_result, '}');

	-- Control nulls
	v_result_info := COALESCE(v_result_info, '{}');

	-- Return
	RETURN gw_fct_json_create_return(('{"status":"Accepted", "message":{"level":1, "text":"Analysis done successfully"}, "version":"'||v_version||'"'||
             ',"body":{"form":{}'||
		     ',"data":{ "info":'||v_result_info||
			'}}'||
	    '}')::json, 3156, null, null, null);

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
