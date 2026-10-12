-- ==============================================================================
-- SISTEMA DE ADMINISTRACIÓN DE TIERRAS FISCALES - INRA BOLIVIA
-- 06_funciones_estadisticas_y_mejoras.sql
-- Optimización de consultas masivas para el Dashboard por Estado Global
-- ==============================================================================

-- Función RPC para obtener todas las estadísticas del Dashboard en 1 solo llamado rápido
CREATE OR REPLACE FUNCTION public.fn_dashboard_estadisticas()
RETURNS JSON AS $$
DECLARE
  v_total_tf BIGINT;
  v_sup_total NUMERIC;
  v_sup_disp NUMERIC;

  v_reportadas_count BIGINT;
  v_reportadas_sup NUMERIC;

  v_vigentes_count BIGINT;
  v_vigentes_sup NUMERIC;

  v_compensadas_count BIGINT;
  v_compensadas_sup NUMERIC;

  v_anuladas_count BIGINT;
  v_anuladas_sup NUMERIC;

  v_no_reportadas_count BIGINT;
  v_no_reportadas_sup NUMERIC;

  v_remitidos BIGINT;
  v_deptos JSON;
BEGIN
  -- 1. Métricas segregadas por Estado Global (conforme a las reglas institucionales)
  SELECT 
    COUNT(*),
    COALESCE(SUM(superficie_predio), 0),
    COALESCE(SUM(sup_disp), 0),

    -- Anuladas (5)
    COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%ANULADA%'),
    COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%ANULADA%'), 0),

    -- Compensadas a TCO (4)
    COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%COMPENSADA%'),
    COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%COMPENSADA%'), 0),

    -- No Reportadas / En Catastro (2 / 6)
    COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%CATASTRO%' OR UPPER(COALESCE(estado_global, '')) LIKE '%NO REPORTAD%'),
    COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%CATASTRO%' OR UPPER(COALESCE(estado_global, '')) LIKE '%NO REPORTAD%'), 0),

    -- Vigentes (3)
    COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) NOT LIKE '%ANULADA%' 
                       AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%COMPENSADA%' 
                       AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%CATASTRO%'
                       AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%NO REPORTAD%'),
    COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) NOT LIKE '%ANULADA%' 
                                              AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%COMPENSADA%' 
                                              AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%CATASTRO%'
                                              AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%NO REPORTAD%'), 0)
  INTO 
    v_total_tf,
    v_sup_total,
    v_sup_disp,
    v_anuladas_count,
    v_anuladas_sup,
    v_compensadas_count,
    v_compensadas_sup,
    v_no_reportadas_count,
    v_no_reportadas_sup,
    v_vigentes_count,
    v_vigentes_sup
  FROM public.tierras_fiscales;

  -- 2. Total Reportada: Total Identificada menos TF en Catastro (No Reportada)
  v_reportadas_count := GREATEST(0, v_total_tf - v_no_reportadas_count);
  v_reportadas_sup := GREATEST(0, v_sup_total - v_no_reportadas_sup);

  -- 3. Conteo de expedientes actualmente en estado SALIDA (fuera de custodia)
  WITH ultimos_movimientos AS (
    SELECT DISTINCT ON (codpred) codpred, tipo_movimiento
    FROM public.remision_expedientes
    ORDER BY codpred, created_at DESC
  )
  SELECT COUNT(*)
  INTO v_remitidos
  FROM ultimos_movimientos
  WHERE tipo_movimiento = 'SALIDA';

  -- 4. Distribución por departamentos
  SELECT json_agg(d)
  INTO v_deptos
  FROM (
    SELECT 
      COALESCE(NULLIF(TRIM(departamento), ''), 'SIN DEFINIR') AS departamento,
      COUNT(*) AS total,
      COALESCE(SUM(superficie_predio), 0) AS total_sup,
      COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) NOT LIKE '%ANULADA%' 
                         AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%COMPENSADA%' 
                         AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%CATASTRO%'
                         AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%NO REPORTAD%') AS vigentes,
      COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) NOT LIKE '%ANULADA%' 
                                                AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%COMPENSADA%' 
                                                AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%CATASTRO%'
                                                AND UPPER(COALESCE(estado_global, '')) NOT LIKE '%NO REPORTAD%'), 0) AS vigentes_sup,
      COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%COMPENSADA%') AS compensadas,
      COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%COMPENSADA%'), 0) AS compensadas_sup,
      COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%ANULADA%') AS anuladas,
      COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%ANULADA%'), 0) AS anuladas_sup,
      COUNT(*) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%CATASTRO%' OR UPPER(COALESCE(estado_global, '')) LIKE '%NO REPORTAD%') AS no_reportadas,
      COALESCE(SUM(superficie_predio) FILTER (WHERE UPPER(COALESCE(estado_global, '')) LIKE '%CATASTRO%' OR UPPER(COALESCE(estado_global, '')) LIKE '%NO REPORTAD%'), 0) AS no_reportadas_sup
    FROM public.tierras_fiscales
    GROUP BY COALESCE(NULLIF(TRIM(departamento), ''), 'SIN DEFINIR')
    ORDER BY total DESC
  ) d;

  RETURN json_build_object(
    'total_tf', v_total_tf,
    'superficie_total', v_sup_total,
    'superficie_disponible', v_sup_disp,
    'reportadas_count', v_reportadas_count,
    'reportadas_sup', v_reportadas_sup,
    'vigentes_count', v_vigentes_count,
    'vigentes_sup', v_vigentes_sup,
    'compensadas_count', v_compensadas_count,
    'compensadas_sup', v_compensadas_sup,
    'anuladas_count', v_anuladas_count,
    'anuladas_sup', v_anuladas_sup,
    'no_reportadas_count', v_no_reportadas_count,
    'no_reportadas_sup', v_no_reportadas_sup,
    'expedientes_remitidos', v_remitidos,
    'distribucion_departamentos', COALESCE(v_deptos, '[]'::json)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dar permisos de ejecución a usuarios autenticados y anónimos
GRANT EXECUTE ON FUNCTION public.fn_dashboard_estadisticas() TO authenticated, anon;

