/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION NUMBER: 2478




CREATE OR REPLACE FUNCTION "SCHEMA_NAME".gw_trg_edit_review_gully()  RETURNS trigger AS
$BODY$

DECLARE
	v_rev_gully_top_elev_tol double precision;
	v_rev_gully_ymax_tol double precision;
	v_rev_gully_sandbox_tol double precision;
	v_rev_gully_units_tol double precision;
	v_tol_filter_bool boolean;
	v_review_status smallint;

	rec_gully record;

BEGIN

	EXECUTE 'SET search_path TO '||quote_literal(TG_TABLE_SCHEMA)||', public';

	-- getting tolerance parameters
	v_rev_gully_top_elev_tol :=(SELECT value::json->'topelev' FROM config_param_system WHERE "parameter"='edit_review_gully_tolerance');
	v_rev_gully_ymax_tol :=(SELECT value::json->'ymax' FROM config_param_system WHERE "parameter"='edit_review_gully_tolerance');		
	v_rev_gully_sandbox_tol :=(SELECT value::json->'sandbox' FROM config_param_system WHERE "parameter"='edit_review_gully_tolerance');	
	v_rev_gully_units_tol :=(SELECT value::json->'units' FROM config_param_system WHERE "parameter"='edit_review_gully_tolerance');	

--get value from edit_review_auto_field_checked
	IF (SELECT value::boolean FROM config_param_system WHERE parameter = 'edit_review_auto_field_checked') IS TRUE THEN
		NEW.field_checked=TRUE;
	END IF;
	
	--getting original values
	SELECT gully_id, top_elev, ymax, sandbox, gully.matcat_id, gully.gully_type, gratecat_id, units, groove, siphon,
		connec_arccat_id, annotation, observ, expl_id, the_geom INTO rec_gully 
	FROM gully JOIN cat_grate ON cat_grate.id=gully.gratecat_id
	WHERE gully_id=NEW.gully_id;
	
	IF (NEW.field_checked is TRUE) THEN
		--looking for insert/update/delete values on audit table
		IF abs(rec_gully.top_elev-NEW.top_elev)>v_rev_gully_top_elev_tol OR  (rec_gully.top_elev IS NULL AND NEW.top_elev IS NOT NULL) OR
			abs(rec_gully.ymax-NEW.ymax)>v_rev_gully_ymax_tol OR  (rec_gully.ymax IS NULL AND NEW.ymax IS NOT NULL) OR
			abs(rec_gully.sandbox-NEW.sandbox)>v_rev_gully_sandbox_tol OR  (rec_gully.sandbox IS NULL AND NEW.sandbox IS NOT NULL) OR
			abs(rec_gully.units-NEW.units)>v_rev_gully_units_tol OR  (rec_gully.units IS NULL AND NEW.units IS NOT NULL) OR
			rec_gully.matcat_id!= NEW.matcat_id OR  (rec_gully.matcat_id IS NULL AND NEW.matcat_id IS NOT NULL) OR
			rec_gully.annotation != NEW.annotation OR  (rec_gully.annotation IS NULL AND NEW.annotation IS NOT NULL) OR
			rec_gully.observ != NEW.observ	OR  (rec_gully.observ IS NULL AND NEW.observ IS NOT NULL) OR
			rec_gully.gratecat_id != NEW.gratecat_id	OR  (rec_gully.gratecat_id IS NULL AND NEW.gratecat_id IS NOT NULL) OR
			rec_gully.groove != NEW.groove	OR  (rec_gully.groove IS NULL AND NEW.groove IS NOT NULL) OR
			rec_gully.siphon != NEW.siphon	OR  (rec_gully.siphon IS NULL AND NEW.siphon IS NOT NULL) OR
			rec_gully.the_geom::text<>NEW.the_geom::text THEN
			v_tol_filter_bool=TRUE;
		ELSE
			v_tol_filter_bool=FALSE;
		END IF;

		-- updating review_status parameter value
			-- new element, re-updated after its insert
			IF (SELECT count(gully_id) FROM gully WHERE gully_id=NEW.gully_id)=0 THEN
				v_review_status=1;
			-- only data changes
			ELSIF (v_tol_filter_bool is TRUE) AND ST_OrderingEquals(NEW.the_geom::text, rec_gully.the_geom::text) is TRUE THEN
				v_review_status=3;
			-- geometry changes	
			ELSIF (v_tol_filter_bool is TRUE) AND ST_OrderingEquals(NEW.the_geom::text, rec_gully.the_geom::text) is FALSE THEN
				v_review_status=2;
			--only review comment
			ELSIF (v_tol_filter_bool is FALSE) AND NEW.review_obs IS NOT NULL THEN
				v_review_status=4;	
			-- changes under tolerance
			ELSIF (v_tol_filter_bool is FALSE) THEN
				v_review_status=0;	
			END IF;
			
			IF NEW.field_date IS NULL THEN 
					NEW.field_date = now();
			END IF;

	END IF;

	-- starting process
	IF TG_OP = 'INSERT' THEN
		
		-- gully_id
		IF NEW.gully_id IS NULL THEN
			NEW.gully_id := (SELECT nextval('urn_id_seq'));
		END IF;
		
		-- Exploitation
		IF (NEW.expl_id IS NULL) THEN
			NEW.expl_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_exploitation_vdefault' AND "cur_user"="current_user"());
			IF (NEW.expl_id IS NULL) THEN
				NEW.expl_id := (SELECT expl_id FROM exploitation WHERE active IS TRUE AND ST_DWithin(NEW.the_geom, exploitation.the_geom,0.001) LIMIT 1);
				IF (NEW.expl_id IS NULL) THEN
					EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
					"data":{"message":"2012", "function":"2478","debug_msg":"'||NEW.gully_id::text||'"}}$$);'; 
				END IF;		
			END IF;
		END IF;
		
				
		-- insert values on review table
		INSERT INTO review_gully (gully_id, top_elev, ymax, sandbox, matcat_id, gully_type, gratecat_id, units, groove, siphon, connec_arccat_id,
				annotation, observ, review_obs, expl_id, the_geom, field_checked, field_date)
		VALUES (NEW.gully_id, NEW.top_elev, NEW.ymax, NEW.sandbox, NEW.matcat_id, NEW.gully_type, NEW.gratecat_id, NEW.units, NEW.groove, NEW.siphon, 
				NEW.connec_arccat_id,NEW.annotation, NEW.observ, NEW.review_obs, NEW.expl_id, NEW.the_geom, NEW.field_checked, NEW.field_date);
		
		
		--looking for insert values on audit table
	  	IF NEW.field_checked=TRUE THEN						

				INSERT INTO review_audit_gully (gully_id, new_top_elev, new_ymax, new_sandbox, new_matcat_id, new_gully_type, new_gratecat_id, new_units, 
				new_groove, new_siphon,new_connec_arccat_id,new_annotation, new_observ, review_obs, expl_id, the_geom, review_status_id, field_date, field_user)
				VALUES (NEW.gully_id, NEW.top_elev, NEW.ymax, NEW.sandbox, NEW.matcat_id, NEW.gully_type, NEW.gratecat_id, NEW.units, NEW.groove, NEW.siphon,
				NEW.connec_arccat_id, NEW.annotation, NEW.observ, NEW.review_obs, NEW.expl_id, NEW.the_geom, 1, NEW.field_date, current_user);
		
		END IF;
			
		RETURN NEW;
	
    ELSIF TG_OP = 'UPDATE' THEN
	
		-- update values on review table
		UPDATE review_gully SET top_elev=NEW.top_elev, ymax=NEW.ymax, sandbox=NEW.sandbox, matcat_id=NEW.matcat_id,gully_type=NEW.gully_type, 
				gratecat_id=NEW.gratecat_id,units=NEW.units, groove=NEW.groove, siphon=NEW.siphon, connec_arccat_id=NEW.connec_arccat_id,
				annotation=NEW.annotation, observ=NEW.observ, review_obs=NEW.review_obs, expl_id=NEW.expl_id, the_geom=NEW.the_geom, field_checked=NEW.field_checked
		WHERE gully_id=NEW.gully_id;
		
		-- if user finish review visit
		IF (NEW.field_checked is TRUE) THEN
			

			-- upserting values on review_audit_gully gully table	
			IF EXISTS (SELECT gully_id FROM review_audit_gully WHERE gully_id=NEW.gully_id) THEN					
				UPDATE review_audit_gully SET old_top_elev=rec_gully.top_elev, new_top_elev=NEW.top_elev, old_ymax=rec_gully.ymax, 
				new_ymax=NEW.ymax, old_sandbox=rec_gully.sandbox, new_sandbox=NEW.sandbox, old_matcat_id=rec_gully.matcat_id, 
				new_matcat_id=NEW.matcat_id, old_gully_type=rec_gully.gully_type, new_gully_type=NEW.gully_type, old_gratecat_id=rec_gully.gratecat_id,	
				new_gratecat_id=NEW.gratecat_id, old_units=rec_gully.units, new_units=NEW.units, old_groove=rec_gully.groove,
				new_groove=NEW.groove, old_siphon=rec_gully.siphon, new_siphon=NEW.siphon,new_connec_arccat_id=NEW.connec_arccat_id, old_connec_arccat_id=rec_gully.connec_arccat_id, 
				old_annotation=rec_gully.annotation,new_annotation=NEW.annotation, old_observ=rec_gully.observ, new_observ=NEW.observ, review_obs=NEW.review_obs, expl_id=NEW.expl_id, 
				the_geom=NEW.the_geom, review_status_id=v_review_status, field_date=NEW.field_date, field_user=current_user
       			WHERE gully_id=NEW.gully_id;

			ELSE
			
				INSERT INTO review_audit_gully
				(gully_id, old_top_elev, new_top_elev, old_ymax, new_ymax, old_sandbox, new_sandbox, old_matcat_id, 
				new_matcat_id, new_gully_type, old_gully_type, old_gratecat_id,new_gratecat_id,old_units, new_units, old_groove, new_groove, old_siphon, 
				new_siphon, old_connec_arccat_id, new_connec_arccat_id, old_annotation, new_annotation, old_observ, new_observ, review_obs, expl_id, the_geom, review_status_id, field_date, field_user)
				VALUES (NEW.gully_id, rec_gully.top_elev, NEW.top_elev, rec_gully.ymax, NEW.ymax, rec_gully.sandbox, NEW.sandbox,
				rec_gully.matcat_id,NEW.matcat_id, rec_gully.gully_type, NEW.gully_type, rec_gully.gratecat_id, NEW.gratecat_id, rec_gully.units, 
				NEW.units, rec_gully.groove, NEW.groove, rec_gully.siphon, NEW.siphon, rec_gully.connec_arccat_id, NEW.connec_arccat_id,
				rec_gully.annotation, NEW.annotation, rec_gully.observ, NEW.observ, NEW.review_obs, NEW.expl_id, NEW.the_geom, v_review_status,NEW.field_date, current_user);

			END IF;
				
		END IF;
	ELSIF TG_OP = 'DELETE' THEN 
	  	DELETE FROM review_gully WHERE gully_id=OLD.gully_id;
    END IF;

    RETURN NEW;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;