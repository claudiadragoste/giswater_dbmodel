/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 1204

CREATE OR REPLACE FUNCTION "SCHEMA_NAME".gw_trg_edit_connec()  RETURNS trigger AS $BODY$
DECLARE 

v_link integer;
v_sql varchar;
v_code_autofill_bool boolean;
v_promixity_buffer double precision;
v_link_path varchar;
v_record_link record;
v_count integer;
v_addfields record;
v_new_value_param text;
v_old_value_param text;
v_customfeature text;
v_featurecat text;
v_psector_vdefault integer;
v_arc_id text;
v_streetaxis text;
v_streetaxis2 text;
v_matfromcat boolean = false;
v_force_delete boolean;
v_autoupdate_fluid boolean;
v_doublegeometry boolean;
v_doublegeom_buffer double precision;
v_arc record;
v_link_geom public.geometry;
v_connect2network boolean;
v_auto_streetvalues_status boolean;
v_auto_streetvalues_buffer integer;
v_auto_streetvalues_field text;
v_trace_featuregeom boolean;
v_seq_name text;
v_seq_code text;
v_code_prefix text;

BEGIN

	EXECUTE 'SET search_path TO '||quote_literal(TG_TABLE_SCHEMA)||', public';

	--set custom feature custom view inserts
	v_customfeature = TG_ARGV[0];

	IF v_customfeature='parent' THEN
		v_customfeature:=NULL;
	END IF;

	--get system and user variables
	v_promixity_buffer = (SELECT "value" FROM config_param_system WHERE "parameter"='edit_feature_buffer_on_mapzone');
	SELECT value::boolean INTO v_autoupdate_fluid FROM config_param_system WHERE parameter='edit_connect_autoupdate_fluid';
	SELECT value::boolean INTO v_connect2network FROM config_param_user WHERE parameter='edit_connec_automatic_link' AND cur_user=current_user;
	v_auto_streetvalues_status := (SELECT (value::json->>'status')::boolean FROM config_param_system WHERE parameter = 'edit_auto_streetvalues');
	v_auto_streetvalues_buffer := (SELECT (value::json->>'buffer')::integer FROM config_param_system WHERE parameter = 'edit_auto_streetvalues');
	v_auto_streetvalues_field := (SELECT (value::json->>'field')::text FROM config_param_system WHERE parameter = 'edit_auto_streetvalues');

	IF v_promixity_buffer IS NULL THEN v_promixity_buffer=0.5; END IF;

	v_psector_vdefault = (SELECT config_param_user.value::integer AS value FROM config_param_user WHERE config_param_user.parameter::text
	    = 'plan_psector_vdefault'::text AND config_param_user.cur_user::name = "current_user"() LIMIT 1);
	
	
	IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
		-- check if streetname exists
		IF NEW.streetname IS NOT NULL AND ((NEW.streetname NOT IN (SELECT DISTINCT descript FROM v_ext_streetaxis)) OR (NEW.streetname2 NOT IN (SELECT DISTINCT descript FROM v_ext_streetaxis))) THEN
			EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
			"data":{"message":"3246", "function":"1204","debug_msg":null}}$$);';
		END IF;
        
        -- transforming streetaxis name into id
		v_streetaxis = (SELECT id FROM v_ext_streetaxis WHERE (muni_id = NEW.muni_id OR muni_id IS NULL) AND descript = NEW.streetname LIMIT 1);
		v_streetaxis2 = (SELECT id FROM v_ext_streetaxis WHERE (muni_id = NEW.muni_id OR muni_id IS NULL) AND descript = NEW.streetname2 LIMIT 1);
		
		-- managing matcat
		IF (SELECT matcat_id FROM cat_connec WHERE id = NEW.connecat_id) IS NOT NULL THEN
			v_matfromcat = true;
		END IF;

		IF NEW.arc_id IS NOT NULL AND NEW.expl_id IS NOT NULL THEN
			IF (SELECT expl_id FROM arc WHERE arc_id = NEW.arc_id) != NEW.expl_id THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"3144", "function":"1204","debug_msg":"'||NEW.arc_id::text||'"}}$$);';
			END IF;
		END IF;
	END IF;
        
	-- Control insertions ID
	IF TG_OP = 'INSERT' THEN

		-- setting psector vdefault as visible
		IF NEW.state = 2 THEN
			INSERT INTO selector_psector (psector_id, cur_user) VALUES (v_psector_vdefault, current_user) 
			ON CONFLICT DO NOTHING;
		END IF;

		-- connec ID
		IF NEW.connec_id != (SELECT last_value::text FROM urn_id_seq) OR NEW.connec_id IS NULL THEN
			NEW.connec_id = (SELECT nextval('urn_id_seq'));
		END IF;

		-- connec type
		IF (NEW.connec_type IS NULL) AND v_customfeature IS NOT NULL THEN
		    	NEW.connec_type:= v_customfeature;
		ELSIF (NEW.connec_type IS NULL) THEN
			  NEW.connec_type:= (SELECT "value" FROM config_param_user WHERE "parameter"='edit_connectype_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			IF (NEW.connec_type IS NULL) THEN
				NEW.connec_type:=(SELECT id FROM cat_feature_connec JOIN cat_feature USING (id) WHERE active IS TRUE LIMIT 1);
			END IF;
		END IF;
        
		-- connec Catalog ID
		IF (NEW.connecat_id IS NULL) THEN
			IF ((SELECT COUNT(*) FROM cat_connec WHERE active IS TRUE) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"1022", "function":"1204","debug_msg":null}}$$);';
			END IF;
			NEW.connecat_id:= (SELECT "value" FROM config_param_user WHERE "parameter"='edit_connecat_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		-- Exploitation
		IF (NEW.expl_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM exploitation WHERE active IS TRUE) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"1110", "function":"1204","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.expl_id IS NULL) THEN
				NEW.expl_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_exploitation_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.expl_id IS NULL) THEN
				SELECT count(*) INTO v_count FROM exploitation WHERE ST_DWithin(NEW.the_geom, exploitation.the_geom,0.001) AND active IS TRUE;
				IF v_count = 1 THEN
					NEW.expl_id = (SELECT expl_id FROM exploitation WHERE ST_DWithin(NEW.the_geom, exploitation.the_geom,0.001) AND active IS TRUE LIMIT 1);
				ELSE
					NEW.expl_id =(SELECT expl_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.expl_id IS NULL) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"2012", "function":"1204","debug_msg":"'||NEW.connec_id::text||'"}}$$);';
			END IF;            
		END IF;
		
		
		-- Sector ID
		IF (NEW.sector_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM sector WHERE active IS TRUE ) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"1008", "function":"1204","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.sector_id IS NULL) THEN
				NEW.sector_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_sector_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.sector_id IS NULL) THEN
				SELECT count(*) INTO v_count FROM sector WHERE ST_DWithin(NEW.the_geom, sector.the_geom,0.001) AND active IS TRUE ;
				IF v_count = 1 THEN
					NEW.sector_id = (SELECT sector_id FROM sector WHERE ST_DWithin(NEW.the_geom, sector.the_geom,0.001) AND active IS TRUE  LIMIT 1);
				ELSE
					NEW.sector_id =(SELECT sector_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.sector_id IS NULL) THEN
				NEW.sector_id = 0;
			END IF;            
		END IF;
		
		
		-- Dma ID
		IF (NEW.dma_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM dma WHERE active IS TRUE ) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"1012", "function":"1204","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.dma_id IS NULL) THEN
				NEW.dma_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_dma_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.dma_id IS NULL) THEN
				SELECT count(*) INTO v_count FROM dma WHERE ST_DWithin(NEW.the_geom, dma.the_geom,0.001) AND active IS TRUE ;
				IF v_count = 1 THEN
					NEW.dma_id = (SELECT dma_id FROM dma WHERE ST_DWithin(NEW.the_geom, dma.the_geom,0.001) AND active IS TRUE LIMIT 1);
				ELSE
					NEW.dma_id =(SELECT dma_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.dma_id IS NULL) THEN
				NEW.dma_id = 0;
			END IF;            
		END IF;
		
		
		-- Municipality 
		IF (NEW.muni_id IS NULL) THEN
			
			-- getting value default
			IF (NEW.muni_id IS NULL) THEN
				NEW.muni_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_municipality_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.muni_id IS NULL) THEN
				SELECT count(*) INTO v_count FROM ext_municipality WHERE ST_DWithin(NEW.the_geom, ext_municipality.the_geom,0.001) AND active IS TRUE ;
				IF v_count = 1 THEN
					NEW.muni_id = (SELECT muni_id FROM ext_municipality WHERE ST_DWithin(NEW.the_geom, ext_municipality.the_geom,0.001) 
					AND active IS TRUE  LIMIT 1);
				ELSE
					NEW.muni_id =(SELECT muni_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;        
		END IF;
        
		-- District 
		IF (NEW.district_id IS NULL) THEN
			
			-- getting value from geometry of mapzone
			IF (NEW.district_id IS NULL) THEN
				SELECT count(*) INTO v_count FROM ext_district WHERE ST_DWithin(NEW.the_geom, ext_district.the_geom,0.001);
				IF v_count = 1 THEN
					NEW.district_id = (SELECT district_id FROM ext_district WHERE ST_DWithin(NEW.the_geom, ext_district.the_geom,0.001) LIMIT 1);
				ELSIF v_count > 1 THEN
					NEW.district_id =(SELECT district_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;	        
		END IF;
		
		
		-- Verified
		IF (NEW.verified IS NULL) THEN
			NEW.verified := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_verified_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;

		-- State
		IF (NEW.state IS NULL) THEN
			NEW.state := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_state_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		-- State_type
		IF (NEW.state=0) THEN
			IF (NEW.state_type IS NULL) THEN
				NEW.state_type := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_statetype_0_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
		ELSIF (NEW.state=1) THEN
			IF (NEW.state_type IS NULL) THEN
				NEW.state_type := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_statetype_1_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
		ELSIF (NEW.state=2) THEN
			IF (NEW.state_type IS NULL) THEN
				NEW.state_type := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_statetype_2_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
		END IF;

		--check relation state - state_type
		IF NEW.state_type NOT IN (SELECT id FROM value_state_type WHERE state = NEW.state) THEN
			IF NEW.state IS NOT NULL THEN
				v_sql = NEW.state;
			ELSE
				v_sql = 'null';
			END IF;
			EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
			"data":{"message":"3036", "function":"1204","debug_msg":"'||v_sql::text||'"}}$$);'; 
		END IF;		

		-- Workcat_id
		IF (NEW.workcat_id IS NULL) THEN
			NEW.workcat_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_workcat_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		--Workcat_id_plan
		IF (NEW.workcat_id_plan IS NULL AND NEW.state = 2) THEN
			NEW.workcat_id_plan := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_workcat_id_plan' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		-- Ownercat_id
		IF (NEW.ownercat_id IS NULL) THEN
			NEW.ownercat_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_ownercat_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		-- Soilcat_id
		IF (NEW.soilcat_id IS NULL) THEN
			NEW.soilcat_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_soilcat_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		
		--Builtdate
		IF (NEW.builtdate IS NULL) THEN
			NEW.builtdate :=(SELECT "value" FROM config_param_user WHERE "parameter"='edit_builtdate_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			IF (NEW.builtdate IS NULL) AND (SELECT value::boolean FROM config_param_system WHERE parameter='edit_feature_auto_builtdate') IS TRUE THEN
				NEW.builtdate :=date(now());
			END IF;
		END IF;
		
		--Address
		IF (v_streetaxis IS NULL) THEN 
			IF (v_auto_streetvalues_status is true) THEN				
				v_streetaxis := (select v_ext_streetaxis.id from v_ext_streetaxis
								join node on ST_DWithin(NEW.the_geom, v_ext_streetaxis.the_geom, v_auto_streetvalues_buffer)
								order by ST_Distance(NEW.the_geom, v_ext_streetaxis.the_geom) LIMIT 1);
			END IF;
		END IF;

		--Postnumber/postcomplement
		IF (v_auto_streetvalues_status) IS TRUE THEN 
			IF (v_auto_streetvalues_field = 'postcomplement') THEN
				IF (NEW.postcomplement IS NULL) THEN
					NEW.postcomplement = (select ext_address.postnumber from ext_address
						join node on ST_DWithin(NEW.the_geom, ext_address.the_geom, v_auto_streetvalues_buffer)
						order by ST_Distance(NEW.the_geom, ext_address.the_geom) LIMIT 1);
				END IF;
			ELSIF (v_auto_streetvalues_field = 'postnumber') THEN
				IF (NEW.postnumber IS NULL) THEN
					NEW.postnumber= (select ext_address.postnumber from ext_address
						join node on ST_DWithin(NEW.the_geom, ext_address.the_geom, v_auto_streetvalues_buffer)
						order by ST_Distance(NEW.the_geom, ext_address.the_geom) LIMIT 1);
				END IF;
			END IF;
		END IF;

		-- Code
		SELECT code_autofill, cat_feature.id, addparam::json->>'code_prefix' INTO v_code_autofill_bool, v_featurecat, v_code_prefix
		FROM cat_feature WHERE id=NEW.connec_type;
	
		-- use specific sequence for code when its name matches featurecat_code_seq
		EXECUTE 'SELECT concat('||quote_literal(lower(v_featurecat))||',''_code_seq'');' INTO v_seq_name;
		EXECUTE 'SELECT relname FROM pg_catalog.pg_class WHERE relname='||quote_literal(v_seq_name)||';' INTO v_sql;
		
		IF v_sql IS NOT NULL AND NEW.code IS NULL THEN
			EXECUTE 'SELECT nextval('||quote_literal(v_seq_name)||');' INTO v_seq_code;
				NEW.code=concat(v_code_prefix,v_seq_code);
		END IF;

		--Copy id to code field
		IF (v_code_autofill_bool IS TRUE) AND NEW.code IS NULL THEN 
			NEW.code=NEW.connec_id;
		END IF;

		--Inventory
		IF NEW.inventory IS NULL THEN
			NEW.inventory := (SELECT "value" FROM config_param_system WHERE "parameter"='edit_inventory_sysvdefault');
		END IF;
		
		--Publish
		IF NEW.publish IS NULL THEN
			NEW.publish := (SELECT "value" FROM config_param_system WHERE "parameter"='edit_publish_sysvdefault');
		END IF; 
	
		--Uncertain
		IF NEW.uncertain IS NULL THEN
			NEW.uncertain := (SELECT "value" FROM config_param_system WHERE "parameter"='edit_uncertain_sysvdefault');
		END IF;
		
		-- LINK
		--google maps style
		IF (SELECT (value::json->>'google_maps')::boolean FROM config_param_system WHERE parameter='edit_custom_link') IS TRUE THEN
			NEW.link=CONCAT ('https://www.google.com/maps/place/',(ST_Y(ST_transform(NEW.the_geom,4326))),'N+',(ST_X(ST_transform(NEW.the_geom,4326))),'E');
		--fid style
		ELSIF (SELECT (value::json->>'fid')::boolean FROM config_param_system WHERE parameter='edit_custom_link') IS TRUE THEN
			NEW.link=NEW.connec_id;
		END IF;
		
		-- Customer code  
		IF NEW.customer_code IS NULL AND (SELECT (value::json->>'status')::boolean FROM config_param_system WHERE parameter = 'edit_connec_autofill_ccode') IS TRUE
		AND (SELECT (value::json->>'field')::text FROM config_param_system WHERE parameter = 'edit_connec_autofill_ccode')='code'  THEN
		
			NEW.customer_code = NEW.code;
			
		ELSIF NEW.customer_code IS NULL AND (SELECT (value::json->>'status')::boolean FROM config_param_system WHERE parameter = 'edit_connec_autofill_ccode') IS TRUE
		AND (SELECT (value::json->>'field')::text FROM config_param_system WHERE parameter = 'edit_connec_autofill_ccode')='connec_id'  THEN

			NEW.customer_code = NEW.connec_id;

		END IF;

		v_featurecat = NEW.connec_type;

		--Location type
		IF NEW.location_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_location_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.location_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_featureval_location_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.location_type IS NULL THEN
			NEW.location_type = (SELECT value FROM config_param_user WHERE parameter = 'connec_location_vdefault' AND cur_user = current_user);
		END IF;

		--Fluid type
		IF v_autoupdate_fluid IS TRUE AND  NEW.arc_id IS NOT NULL THEN
			NEW.fluid_type = (SELECT fluid_type FROM arc WHERE arc_id = NEW.arc_id);
		END IF;

		IF NEW.fluid_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_fluid_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.fluid_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_featureval_fluid_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.fluid_type IS NULL THEN
			NEW.fluid_type = (SELECT value FROM config_param_user WHERE parameter = 'connec_fluid_vdefault' AND cur_user = current_user);
		END IF;

		--Category type
		IF NEW.category_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_category_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.category_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_featureval_category_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.category_type IS NULL THEN
			NEW.category_type = (SELECT value FROM config_param_user WHERE parameter = 'connec_category_vdefault' AND cur_user = current_user);
		END IF;	

		--Function type
		IF NEW.function_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_function_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.function_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_featureval_function_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.function_type IS NULL THEN
			NEW.function_type = (SELECT value FROM config_param_user WHERE parameter = 'connec_function_vdefault' AND cur_user = current_user);
		END IF;

		--elevation from raster
		IF (SELECT json_extract_path_text(value::json,'activated')::boolean FROM config_param_system WHERE parameter='admin_raster_dem') IS TRUE 
		AND (NEW.top_elev IS NULL) AND
		(SELECT upper(value)  FROM config_param_user WHERE parameter = 'edit_insert_elevation_from_dem' and cur_user = current_user) = 'TRUE' THEN
			NEW.top_elev = (SELECT ST_Value(rast,1,NEW.the_geom,true) FROM v_ext_raster_dem WHERE id =
				(SELECT id FROM v_ext_raster_dem WHERE st_dwithin (envelope, NEW.the_geom, 1) LIMIT 1));
		END IF; 

		-- plot_code from plot layer
		IF (SELECT value::boolean FROM config_param_system WHERE parameter = 'edit_connec_autofill_plotcode') = TRUE THEN
			NEW.plot_code = (SELECT plot_code FROM v_ext_plot WHERE st_dwithin(the_geom, NEW.the_geom, 0) LIMIT 1);
		END IF;
		
		-- FEATURE INSERT
		IF v_matfromcat THEN
			INSERT INTO connec (connec_id, code, customer_code, top_elev, y1, y2,connecat_id, connec_type, sector_id, demand, "state",  state_type, connec_depth, connec_length, arc_id, annotation, 
			"observ","comment",  dma_id, soilcat_id, function_type, category_type, fluid_type, location_type, workcat_id, workcat_id_end, workcat_id_plan, buildercat_id, 
			builtdate, enddate, ownercat_id, muni_id, postcode, district_id,
			streetaxis2_id, streetaxis_id, postnumber, postnumber2, postcomplement, postcomplement2, descript, rotation, link, verified, the_geom,  undelete,  label_x, label_y, 
			label_rotation, accessibility,diagonal, expl_id, publish, inventory, uncertain, num_value, private_connecat_id,
			lastupdate, lastupdate_user, asset_id, drainzone_id, expl_id2, adate, adescript, plot_code)
			VALUES (NEW.connec_id, NEW.code, NEW.customer_code, NEW.top_elev, NEW.y1, NEW.y2, NEW.connecat_id, NEW.connec_type, NEW.sector_id, NEW.demand,NEW."state", NEW.state_type, NEW.connec_depth, 
			NEW.connec_length, NEW.arc_id, NEW.annotation, NEW."observ", NEW."comment", NEW.dma_id, NEW.soilcat_id, NEW.function_type, NEW.category_type, NEW.fluid_type, NEW.location_type, 
			NEW.workcat_id, NEW.workcat_id_end, NEW.workcat_id_plan, NEW.buildercat_id, NEW.builtdate, NEW.enddate, NEW.ownercat_id, NEW.muni_id, NEW.postcode, NEW.district_id, 
			v_streetaxis2, v_streetaxis, NEW.postnumber, NEW.postnumber2, NEW.postcomplement, NEW.postcomplement2,
			NEW.descript, NEW.rotation, NEW.link, NEW.verified, NEW.the_geom, NEW.undelete, NEW.label_x, NEW.label_y, NEW.label_rotation,
			NEW.accessibility, NEW.diagonal, NEW.expl_id, NEW.publish, NEW.inventory, NEW.uncertain, NEW.num_value, NEW.private_connecat_id,
			NEW.lastupdate, NEW.lastupdate_user, NEW.asset_id, NEW.drainzone_id, NEW.expl_id2, NEW.adate, NEW.adescript, NEW.plot_code);	
		ELSE
			INSERT INTO connec (connec_id, code, customer_code, top_elev, y1, y2,connecat_id, connec_type, sector_id, demand, "state",  state_type, connec_depth, connec_length, arc_id, annotation, 
			"observ","comment",  dma_id, soilcat_id, function_type, category_type, fluid_type, location_type, workcat_id, workcat_id_end, workcat_id_plan, buildercat_id, 
			builtdate, enddate, ownercat_id, muni_id,postcode,district_id,
			streetaxis2_id, streetaxis_id, postnumber, postnumber2, postcomplement, postcomplement2, descript, rotation, link, verified, the_geom,  undelete, label_x, label_y, 
			label_rotation, accessibility,diagonal, expl_id, publish, inventory, uncertain, num_value, private_connecat_id, matcat_id,
			lastupdate, lastupdate_user, asset_id, drainzone_id, expl_id2, adate, adescript, plot_code)
			VALUES (NEW.connec_id, NEW.code, NEW.customer_code, NEW.top_elev, NEW.y1, NEW.y2, NEW.connecat_id, NEW.connec_type, NEW.sector_id, NEW.demand,NEW."state", NEW.state_type, NEW.connec_depth, 
			NEW.connec_length, NEW.arc_id, NEW.annotation, NEW."observ", NEW."comment", NEW.dma_id, NEW.soilcat_id, NEW.function_type, NEW.category_type, NEW.fluid_type, NEW.location_type, 
			NEW.workcat_id, NEW.workcat_id_end, NEW.workcat_id_plan, NEW.buildercat_id, NEW.builtdate, NEW.enddate, NEW.ownercat_id, NEW.muni_id, NEW.postcode, NEW.district_id,
			v_streetaxis2, v_streetaxis, NEW.postnumber, NEW.postnumber2, NEW.postcomplement, NEW.postcomplement2,
			NEW.descript, NEW.rotation, NEW.link, NEW.verified, NEW.the_geom, NEW.undelete, NEW.label_x, NEW.label_y, NEW.label_rotation,
			NEW.accessibility, NEW.diagonal, NEW.expl_id, NEW.publish, NEW.inventory, NEW.uncertain, NEW.num_value, NEW.private_connecat_id, NEW.matcat_id,
			NEW.lastupdate, NEW.lastupdate_user, NEW.asset_id, NEW.drainzone_id, NEW.expl_id2, NEW.adate, NEW.adescript, NEW.plot_code);
		END IF;
		
		--check if feature is double geom
		EXECUTE 'SELECT json_extract_path_text(double_geom,''activated'')::boolean, json_extract_path_text(double_geom,''value'')  
		FROM cat_feature_connec WHERE id='||quote_literal(NEW.connec_type)||''
		INTO v_doublegeometry, v_doublegeom_buffer;
		
		-- set and get id for polygon
		IF (v_doublegeometry IS TRUE) THEN
			INSERT INTO polygon(sys_type, the_geom, featurecat_id,feature_id ) 
			VALUES ('CONNEC', (SELECT ST_Multi(ST_Envelope(ST_Buffer(connec.the_geom,v_doublegeom_buffer))) 
			from connec where connec_id=NEW.connec_id), NEW.connec_type, NEW.connec_id);
		END IF;

		-- insertint on psector table
		IF NEW.state=2 THEN
			INSERT INTO plan_psector_x_connec (connec_id, psector_id, state, doable, arc_id)
			VALUES (NEW.connec_id, v_psector_vdefault, 1, true, NEW.arc_id);
		END IF;

		-- manage connect2network
		IF v_connect2network THEN
		
			IF NEW.arc_id IS NOT NULL THEN
				EXECUTE 'SELECT gw_fct_linktonetwork($${"client":{"device":4, "infoType":1, "lang":"ES"},
				"feature":{"id":'|| array_to_json(array_agg(NEW.connec_id))||'},"data":{"feature_type":"CONNEC", "forcedArcs":["'||NEW.arc_id||'"]}}$$)';
			ELSE
				EXECUTE 'SELECT gw_fct_linktonetwork($${"client":{"device":4, "infoType":1, "lang":"ES"},
				"feature":{"id":'|| array_to_json(array_agg(NEW.connec_id))||'},"data":{"feature_type":"CONNEC"}}$$)';
			END IF;

			-- recover values in order to do not disturb this workflow
			SELECT * INTO v_arc FROM arc WHERE arc_id = NEW.arc_id;
			NEW.pjoint_id = v_arc.arc_id; NEW.pjoint_type = 'ARC'; NEW.sector_id = v_arc.sector_id; NEW.dma_id = v_arc.dma_id;
		END IF;
		
		-- childtable insert
		IF v_customfeature IS NOT NULL THEN
			FOR v_addfields IN SELECT * FROM sys_addfields
			WHERE (cat_feature_id = v_customfeature OR cat_feature_id is null) AND active IS TRUE AND iseditable IS TRUE
			LOOP
				EXECUTE 'SELECT $1."' ||v_addfields.param_name||'"'
					USING NEW
					INTO v_new_value_param;

				IF v_new_value_param IS NOT NULL THEN
					EXECUTE 'INSERT INTO man_connec_'||lower(v_customfeature)||' (connec_id, '||v_addfields.param_name||') VALUES ($1, $2::'||v_addfields.datatype_id||')'
						USING NEW.connec_id, v_new_value_param;
				END IF;
			END LOOP;
		END IF;

		RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN

		-- UPDATE geom
		IF st_equals( NEW.the_geom, OLD.the_geom) IS FALSE THEN
			UPDATE connec SET the_geom=NEW.the_geom WHERE connec_id = OLD.connec_id;	

			--update elevation from raster
			IF (SELECT json_extract_path_text(value::json,'activated')::boolean FROM config_param_system WHERE parameter='admin_raster_dem') IS TRUE 
			AND (NEW.top_elev = OLD.top_elev) AND
			(SELECT upper(value)  FROM config_param_user WHERE parameter = 'edit_update_elevation_from_dem' and cur_user = current_user) = 'TRUE' THEN
				NEW.top_elev = (SELECT ST_Value(rast,1,NEW.the_geom,true) FROM v_ext_raster_dem WHERE id =
							(SELECT id FROM v_ext_raster_dem WHERE st_dwithin (envelope, NEW.the_geom, 1) LIMIT 1));
			END IF;	
			
			--update associated geometry of element (if exists) and trace_featuregeom is true
			v_trace_featuregeom:= (SELECT trace_featuregeom FROM element JOIN element_x_connec using (element_id) 
			WHERE connec_id=NEW.connec_id AND the_geom IS NOT NULL LIMIT 1);
			
			-- if trace_featuregeom is false, do nothing
			IF v_trace_featuregeom IS TRUE THEN
				UPDATE v_edit_element SET the_geom = NEW.the_geom WHERE St_dwithin(OLD.the_geom, the_geom, 0.001) 
				AND element_id IN (SELECT element_id FROM element_x_connec WHERE connec_id=NEW.connec_id);
			END IF;

			-- plot_code from plot layer
			IF (SELECT value::boolean FROM config_param_system WHERE parameter = 'edit_connec_autofill_plotcode') = TRUE THEN
				NEW.plot_code = (SELECT plot_code FROM v_ext_plot WHERE st_dwithin(the_geom, NEW.the_geom, 0) LIMIT 1);
			END IF;
			
		END IF;

		-- Reconnect arc_id
		IF (coalesce (NEW.arc_id,'') != coalesce(OLD.arc_id,'')) THEN

			-- when connec_id comes from psector_table
			IF NEW.state = 1 AND (SELECT connec_id FROM plan_psector_x_connec JOIN selector_psector USING (psector_id)
				WHERE connec_id=NEW.connec_id AND psector_id = v_psector_vdefault AND cur_user = current_user AND state = 1) IS NOT NULL THEN
			
				EXECUTE 'SELECT gw_fct_linktonetwork($${"client":{"device":4, "infoType":1, "lang":"ES"},
				"feature":{"id":'|| array_to_json(array_agg(NEW.connec_id))||'},"data":{"feature_type":"CONNEC", "forceEndPoint":"true", "forcedArcs":["'||NEW.arc_id||'"]}}$$)';				
				
			ELSIF NEW.state = 2 THEN

				IF NEW.arc_id IS NOT NULL THEN

					IF (SELECT connec_id FROM plan_psector_x_connec JOIN selector_psector USING (psector_id)
						WHERE connec_id=NEW.connec_id AND psector_id = v_psector_vdefault AND cur_user = current_user AND state = 1) IS NOT NULL THEN

						EXECUTE 'SELECT gw_fct_linktonetwork($${"client":{"device":4, "infoType":1, "lang":"ES"},
						"feature":{"id":'|| array_to_json(array_agg(NEW.connec_id))||'},"data":{"feature_type":"CONNEC", "forceEndPoint":"true", "forcedArcs":["'||NEW.arc_id||'"]}}$$)';
					END IF;
				ELSE
					IF (SELECT link_id FROM plan_psector_x_connec JOIN selector_psector USING (psector_id)
						WHERE connec_id=NEW.connec_id AND psector_id = v_psector_vdefault AND cur_user = current_user AND state = 1) IS NOT NULL THEN
						EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
						"data":{"message":"3204", "function":"1204","debug_msg":""}}$$);';
					ELSE
						UPDATE plan_psector_x_connec SET arc_id = null, link_id = null WHERE connec_id=NEW.connec_id AND psector_id = v_psector_vdefault AND state = 1;
					END IF;

					-- setting values					
					NEW.sector_id = 0; NEW.dma_id = 0; NEW.pjoint_id = null; NEW.pjoint_type = null;
				END IF;
			ELSE
				-- when arc_id comes from connec table
				UPDATE connec SET arc_id=NEW.arc_id where connec_id=NEW.connec_id;

				IF NEW.arc_id IS NOT NULL THEN

					-- when link exists
					IF (SELECT link_id FROM link WHERE state = 1 and feature_id =  NEW.connec_id) IS NOT NULL THEN
						EXECUTE 'SELECT gw_fct_linktonetwork($${"client":{"device":4, "infoType":1, "lang":"ES"},
						"feature":{"id":'|| array_to_json(array_agg(NEW.connec_id))||'},"data":{"feature_type":"CONNEC", "forceEndPoint":"true",  "forcedArcs":["'||NEW.arc_id||'"]}}$$)';	
					END IF;
									
					-- recover values in order to do not disturb this workflow
					SELECT * INTO v_arc FROM arc WHERE arc_id = NEW.arc_id;
					NEW.pjoint_id = v_arc.arc_id; NEW.pjoint_type = 'ARC'; NEW.sector_id = v_arc.sector_id; NEW.dma_id = v_arc.dma_id; 		
				ELSE
				
					IF (SELECT count(*)FROM link WHERE feature_id = NEW.connec_id AND state = 1) > 0 THEN
						EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
						"data":{"message":"3204", "function":"1204","debug_msg":""}}$$);';
					ELSE
						NEW.sector_id = 0; NEW.dma_id = 0; NEW.pjoint_id = null; NEW.pjoint_type = null;
					END IF;

				END IF;
			END IF;
		END IF;
		
		-- State_type
		IF NEW.state=0 AND OLD.state=1 THEN
			IF (SELECT state FROM value_state_type WHERE id=NEW.state_type) != NEW.state THEN
			NEW.state_type=(SELECT "value" FROM config_param_user WHERE parameter='statetype_end_vdefault' AND "cur_user"="current_user"() LIMIT 1);
				IF NEW.state_type IS NULL THEN
				NEW.state_type=(SELECT id from value_state_type WHERE state=0 LIMIT 1);
					IF NEW.state_type IS NULL THEN
					EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
					"data":{"message":"2110", "function":"1204","debug_msg":null}}$$);'; 
					END IF;
				END IF;
			END IF;
			-- Automatic downgrade of associated link
			UPDATE link SET state=0 WHERE feature_id=OLD.connec_id;
			
			--check if there is any active hydrometer related to connec
			IF (SELECT count(id) FROM rtc_hydrometer_x_connec rhc JOIN ext_rtc_hydrometer hc ON hc.id=hydrometer_id
			WHERE (rhc.connec_id=NEW.connec_id OR hc.connec_id=NEW.connec_id) AND state_id = 1) > 0 THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"3184", "function":"1318","debug_msg":null}}$$);';
			END IF;
			
		END IF;

		-- Looking for state control and insert planified connecs to default psector
		IF (NEW.state != OLD.state) THEN   
		
			PERFORM gw_fct_state_control('CONNEC', NEW.connec_id, NEW.state, TG_OP);
			
			IF NEW.state = 2 AND OLD.state=1 THEN
			
				v_link = (SELECT link_id FROM link WHERE feature_id = NEW.connec_id AND state = 1 LIMIT 1);
			
				INSERT INTO plan_psector_x_connec (connec_id, psector_id, state, doable, link_id, arc_id)
				VALUES (NEW.connec_id, v_psector_vdefault, 1, true,
				v_link, NEW.arc_id);
				
				UPDATE link SET state = 2 WHERE link_id  = v_link;
			END IF;
			
			IF NEW.state = 1 AND OLD.state=2 THEN
			
				v_link = (SELECT link_id FROM link WHERE feature_id = NEW.connec_id AND state = 2 LIMIT 1);
			
				-- force delete
				UPDATE config_param_user SET value = 'true' WHERE parameter = 'plan_psector_downgrade_feature' AND cur_user= current_user;
				DELETE FROM plan_psector_x_connec WHERE connec_id=NEW.connec_id;
				-- recover values
				UPDATE config_param_user SET value = 'false' WHERE parameter = 'plan_psector_downgrade_feature' AND cur_user= current_user;

				UPDATE link SET state = 1 WHERE link_id  = v_link;					
			END IF;
			
			UPDATE connec SET state=NEW.state WHERE connec_id = OLD.connec_id;
		END IF;

		IF (NEW.connecat_id != OLD.connecat_id) AND NEW.state > 0 THEN   
			UPDATE link SET connecat_id=NEW.connecat_id WHERE feature_id = NEW.connec_id AND state>0;
		END IF;		
		
		--check relation state - state_type
		IF (NEW.state_type != OLD.state_type) THEN
		
			IF NEW.state_type NOT IN (SELECT id FROM value_state_type WHERE state = NEW.state) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"3036", "function":"1204","debug_msg":"'||NEW.state::text||'"}}$$);'; 
			ELSE
				UPDATE connec SET state_type=NEW.state_type WHERE connec_id = OLD.connec_id;
			END IF;
		END IF;		

		-- rotation
		IF NEW.rotation != OLD.rotation THEN
			UPDATE connec SET rotation=NEW.rotation WHERE connec_id = OLD.connec_id;
		END IF;

		-- customer_code
		IF (NEW.customer_code != OLD.customer_code) OR (OLD.customer_code IS NULL AND NEW.customer_code IS NOT NULL) THEN
			UPDATE connec SET customer_code=NEW.customer_code WHERE connec_id = OLD.connec_id;
		END IF;
		
		--link_path
		SELECT link_path INTO v_link_path FROM cat_feature WHERE id=NEW.connec_type;
		IF v_link_path IS NOT NULL THEN
			NEW.link = replace(NEW.link, v_link_path,'');
		END IF;
		
		--fluid_type
		IF v_autoupdate_fluid IS TRUE AND NEW.arc_id IS NOT NULL THEN
			NEW.fluid_type = (SELECT fluid_type FROM arc WHERE arc_id = NEW.arc_id);
		END IF;

		IF v_matfromcat THEN
			UPDATE connec 
			SET  code=NEW.code, top_elev=NEW.top_elev, y1=NEW.y1, y2=NEW.y2, connecat_id=NEW.connecat_id, connec_type=NEW.connec_type, sector_id=NEW.sector_id, demand=NEW.demand,
			connec_depth=NEW.connec_depth, connec_length=NEW.connec_length, annotation=NEW.annotation, "observ"=NEW."observ",
			"comment"=NEW."comment", dma_id=NEW.dma_id, soilcat_id=NEW.soilcat_id, function_type=NEW.function_type, category_type=NEW.category_type, fluid_type=NEW.fluid_type, 
			location_type=NEW.location_type, workcat_id=NEW.workcat_id, workcat_id_end=NEW.workcat_id_end, workcat_id_plan=NEW.workcat_id_plan, buildercat_id=NEW.buildercat_id, builtdate=NEW.builtdate, enddate=NEW.enddate,
			ownercat_id=NEW.ownercat_id, muni_id=NEW.muni_id, postcode=NEW.postcode, district_id =NEW.district_id, streetaxis2_id=v_streetaxis2, streetaxis_id=v_streetaxis, postnumber=NEW.postnumber, postnumber2=NEW.postnumber2, postcomplement=NEW.postcomplement, postcomplement2=NEW.postcomplement2, descript=NEW.descript, 
			rotation=NEW.rotation, link=NEW.link, verified=NEW.verified, undelete=NEW.undelete, 
			label_x=NEW.label_x, label_y=NEW.label_y, label_rotation=NEW.label_rotation, accessibility=NEW.accessibility, diagonal=NEW.diagonal, publish=NEW.publish, pjoint_id=NEW.pjoint_id, pjoint_type = NEW.pjoint_type,
			inventory=NEW.inventory, uncertain=NEW.uncertain, expl_id=NEW.expl_id,num_value=NEW.num_value, private_connecat_id=NEW.private_connecat_id, lastupdate=now(), lastupdate_user=current_user, asset_id=NEW.asset_id, drainzone_id=NEW.drainzone_id, expl_id2=NEW.expl_id2, adate=NEW.adate, adescript=NEW.adescript,
			plot_code=NEW.plot_code
			WHERE connec_id = OLD.connec_id;
		ELSE
			UPDATE connec 
			SET  code=NEW.code, top_elev=NEW.top_elev, y1=NEW.y1, y2=NEW.y2, connecat_id=NEW.connecat_id, connec_type=NEW.connec_type, sector_id=NEW.sector_id, demand=NEW.demand,
			connec_depth=NEW.connec_depth, connec_length=NEW.connec_length, annotation=NEW.annotation, "observ"=NEW."observ",
			"comment"=NEW."comment", dma_id=NEW.dma_id, soilcat_id=NEW.soilcat_id, function_type=NEW.function_type, category_type=NEW.category_type, fluid_type=NEW.fluid_type, 
			location_type=NEW.location_type, workcat_id=NEW.workcat_id, workcat_id_end=NEW.workcat_id_end, workcat_id_plan=NEW.workcat_id_plan, buildercat_id=NEW.buildercat_id, builtdate=NEW.builtdate, enddate=NEW.enddate,
			ownercat_id=NEW.ownercat_id, muni_id=NEW.muni_id, postcode=NEW.postcode, district_id=NEW.district_id, streetaxis2_id=v_streetaxis2, streetaxis_id=v_streetaxis, postnumber=NEW.postnumber, postnumber2=NEW.postnumber2, postcomplement=NEW.postcomplement, postcomplement2=NEW.postcomplement2, descript=NEW.descript, 
			rotation=NEW.rotation, link=NEW.link, verified=NEW.verified, undelete=NEW.undelete,
			label_x=NEW.label_x, label_y=NEW.label_y, label_rotation=NEW.label_rotation, accessibility=NEW.accessibility, diagonal=NEW.diagonal, publish=NEW.publish, pjoint_id=NEW.pjoint_id, pjoint_type = NEW.pjoint_type,
			inventory=NEW.inventory, uncertain=NEW.uncertain, expl_id=NEW.expl_id,num_value=NEW.num_value, private_connecat_id=NEW.private_connecat_id, lastupdate=now(), 
			lastupdate_user=current_user, matcat_id = NEW.matcat_id, asset_id=NEW.asset_id, drainzone_id=NEW.drainzone_id, expl_id2=NEW.expl_id2, adate=NEW.adate, adescript=NEW.adescript,
			plot_code=NEW.plot_code
			WHERE connec_id = OLD.connec_id;		
		END IF;

		-- childtable update
		IF v_customfeature IS NOT NULL THEN
			FOR v_addfields IN SELECT * FROM sys_addfields
			WHERE (cat_feature_id = v_customfeature OR cat_feature_id is null) AND active IS TRUE AND iseditable IS TRUE
			LOOP
				EXECUTE 'SELECT $1."' || v_addfields.param_name ||'"'
					USING NEW
					INTO v_new_value_param;

				EXECUTE 'SELECT $1."' || v_addfields.param_name ||'"'
					USING OLD
					INTO v_old_value_param;

				IF (v_new_value_param IS NOT NULL AND v_old_value_param!=v_new_value_param) OR (v_new_value_param IS NOT NULL AND v_old_value_param IS NULL) THEN
					EXECUTE 'INSERT INTO man_connec_'||lower(v_customfeature)||' (connec_id, '||v_addfields.param_name||') VALUES ($1, $2::'||v_addfields.datatype_id||')
					    ON CONFLICT (connec_id)
					    DO UPDATE SET '||v_addfields.param_name||'=$2::'||v_addfields.datatype_id||' WHERE man_connec_'||lower(v_customfeature)||'.connec_id=$1'
						USING NEW.connec_id, v_new_value_param;

				ELSIF v_new_value_param IS NULL AND v_old_value_param IS NOT NULL THEN
					EXECUTE 'UPDATE man_connec_'||lower(v_customfeature)||' SET '||v_addfields.param_name||' = null WHERE man_connec_'||lower(v_customfeature)||'.connec_id=$1'
					    USING NEW.connec_id;
				END IF;
			END LOOP;
		END IF;

        RETURN NEW;


    ELSIF TG_OP = 'DELETE' THEN
	
		EXECUTE 'SELECT gw_fct_getcheckdelete($${"client":{"device":4, "infoType":1, "lang":"ES"},
		"feature":{"id":"'||OLD.connec_id||'","featureType":"CONNEC"}, "data":{}}$$)';

		-- delete from polygon table (before the deletion of node)
		DELETE FROM polygon WHERE feature_id=OLD.connec_id;

		-- force plan_psector_force_delete
		SELECT value INTO v_force_delete FROM config_param_user WHERE parameter = 'plan_psector_force_delete' and cur_user = current_user;
		UPDATE config_param_user SET value = 'true' WHERE parameter = 'plan_psector_force_delete' and cur_user = current_user;
 
		DELETE FROM connec WHERE connec_id = OLD.connec_id;
 
		-- restore plan_psector_force_delete
		UPDATE config_param_user SET value = v_force_delete WHERE parameter = 'plan_psector_force_delete' and cur_user = current_user;

		-- Delete childtable addfields (after or before deletion of connec, doesn't matter)
        FOR v_addfields IN SELECT * FROM sys_addfields
        WHERE (cat_feature_id = v_customfeature OR cat_feature_id is null) AND active IS TRUE AND iseditable IS TRUE
        LOOP
		    EXECUTE 'DELETE FROM man_connec_'||lower(v_addfields.cat_feature_id)||' WHERE connec_id = OLD.connec_id';
        END LOOP;

		-- delete links
		FOR v_record_link IN SELECT * FROM link WHERE feature_type='CONNEC' AND feature_id=OLD.connec_id
		LOOP
			-- delete link
			DELETE FROM link WHERE link_id=v_record_link.link_id;

		END LOOP;

		RETURN NULL;  
    END IF;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;    