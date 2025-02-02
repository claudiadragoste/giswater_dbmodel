/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


SET search_path = SCHEMA_NAME, public, pg_catalog;

CREATE OR REPLACE VIEW v_edit_dma
AS SELECT dma.dma_id,
    dma.name,
    dma.macrodma_id,
    dma.descript,
    dma.the_geom,
    dma.undelete,
    dma.expl_id,
    dma.pattern_id,
    dma.link,
    dma.minc,
    dma.maxc,
    dma.effc,
    dma.active,
    dma.stylesheet,
    dma.expl_id2
   FROM selector_expl,
    dma
  WHERE (dma.expl_id = selector_expl.expl_id OR dma.expl_id2 = selector_expl.expl_id) AND selector_expl.cur_user = "current_user"()::text;

-- 2024/06/29
DROP VIEW IF EXISTS vi_parent_arc;
DELETE FROM sys_table WHERE id = 'vi_parent_arc';

DROP VIEW IF EXISTS v_anl_flow_arc;
DROP VIEW IF EXISTS v_anl_flow_node;
DROP VIEW IF EXISTS v_anl_flow_connec;
DROP VIEW IF EXISTS v_anl_flow_gully;
DELETE FROM sys_table WHERE id IN ('v_anl_flow_arc','v_anl_flow_node','v_anl_flow_connec','v_anl_flow_gully');

