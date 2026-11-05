/* Linked */
SET NOCOUNT ON;

/* =========================== PARTE 1 =========================== */
DECLARE @sql nvarchar(max) = N'
USE dw_curated;
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @hasta date = CAST(GETDATE() AS date);
DECLARE @desde date = DATEADD(DAY, -150, @hasta);

-- 0. Base filtrada una sola vez (cabecera + detalle, ultimos 60 dias)
SELECT c.Emp_Id, c.idempresa, c.idingresosalidaproceso, c.dw_fecha, c.idsucursal,
       c.idprocesod, c.idsubprocesod,
       d.item, d.idproducto, d.peso, d.pesodrenado
INTO #cd
FROM dw_landing.NISIRA.ingresosalidaproceso c
    INNER JOIN dw_landing.NISIRA.ddingresosalidaproceso d
        ON c.Emp_Id = d.Emp_Id AND c.idempresa = d.idempresa
       AND c.idingresosalidaproceso = d.idingresosalidaproceso
WHERE c.idestado <> ''AN''
  AND c.dw_fecha BETWEEN @desde AND @hasta;

CREATE CLUSTERED INDEX IX_cd ON #cd (Emp_Id, idempresa, idingresosalidaproceso, item);

BEGIN TRY
    BEGIN TRAN;

    -- 1. PLANILLAPRODUCCION_DIGITACION
    DELETE FROM PRODUCCION.PLANILLAPRODUCCION_DIGITACION
    WHERE dw_fecha BETWEEN @desde AND @hasta;

    INSERT INTO PRODUCCION.PLANILLAPRODUCCION_DIGITACION (
        Emp_Id,idempresa,idingresosalidaproceso,dw_fecha,idsucursal,idconsumidor,item,idproducto,iddigitacion,cantidad,peso,sobrepeso,es_muestra,idcultivo,idvariedad,
        idcondicion,idtalla,idenvase,idcolor,idcampana
    )
    SELECT cd.Emp_Id,
        cd.idempresa,
        cd.idingresosalidaproceso,
        cd.dw_fecha,
        cd.idsucursal,
        CASE WHEN ddg.item IS NULL THEN dg.idconsumidor ELSE ddg.idconsumidor END,
        cd.item,
        cd.idproducto,
        dpr.id,
        -- OJO: si dw_cnt_variedades es INT, 1/2 = 0 (division entera)
        CASE WHEN ddg.item IS NULL THEN 1 ELSE 1/pv.dw_cnt_variedades END,
        cd.pesodrenado * CASE WHEN ddg.item IS NULL THEN 1 ELSE 1/pv.dw_cnt_variedades END,
        (cd.peso - cd.pesodrenado) * CASE WHEN ddg.item IS NULL THEN 1 ELSE 1/pv.dw_cnt_variedades END,
        ISNULL(mt.es_muestra,0),
        dg.idcultivo,
        CASE WHEN ddg.item IS NULL THEN dg.idvariedad ELSE ddg.idvariedad END,
        dg.idcategoria,
        dg.idcalibre,
        dg.idenvase,
        dg.idcolor,
        dg.idcampana
    FROM #cd cd
        LEFT JOIN dw_landing.NISIRA.ddingresosalidaproceso_referencias dr ON cd.Emp_Id = dr.Emp_Id AND cd.idempresa = dr.idempresa AND cd.idingresosalidaproceso = dr.idingresosalidaproceso AND cd.item = dr.item
        LEFT JOIN dw_landing.NISIRA.registropaleta p ON dr.Emp_Id = p.Emp_Id AND dr.idempresa = p.idempresa AND dr.idreferencia = p.idregistropaleta
        LEFT JOIN dw_landing.NISIRA.dregistropaleta dp ON dr.Emp_Id = dp.Emp_Id AND dr.idempresa = dp.idempresa AND dr.idreferencia = dp.idregistropaleta AND dr.itemref = dp.item
        LEFT JOIN dw_landing.NISIRA.dregistropaleta_referencia dpr ON dr.Emp_Id = dpr.Emp_Id AND dr.idempresa = dpr.idempresa AND dr.idreferencia = dpr.idregistropaleta AND dr.itemref = dpr.item
        LEFT JOIN dw_landing.NISIRA.digitacion dg ON dpr.Emp_Id = dg.Emp_Id AND dpr.id = dg.id
        LEFT JOIN dw_landing.NISIRA.ddigitacion ddg ON dpr.idempresa = ddg.idempresa AND dpr.Emp_Id = ddg.Emp_Id AND dpr.id = ddg.id
        LEFT JOIN dw_landing.NISIRA.VARIEDADES_CULTIVOS pv ON dg.Emp_Id = pv.Emp_Id AND dg.idempresa = pv.IDEMPRESA AND dg.idcultivo = pv.IDCULTIVO AND dg.idvariedad = pv.IDVARIEDAD
        LEFT JOIN dw_landing.NISIRA.motivopaleta mt ON p.Emp_Id = mt.Emp_Id AND p.idempresa = mt.idempresa AND p.idmotivopaleta = mt.idmotivopaleta
        LEFT JOIN dw_landing.NISIRA.consumidor cn ON dg.Emp_Id = cn.Emp_Id AND dg.idempresa = cn.idempresa AND dg.idconsumidor = cn.idconsumidor          -- no se usa
        LEFT JOIN dw_landing.NISIRA.subprocesos spc ON cd.Emp_Id = spc.Emp_Id AND cd.idempresa = spc.idempresa AND cd.idprocesod = spc.idproceso AND cd.idsubprocesod = spc.idsubproceso  -- no se usa
        LEFT JOIN dw_landing.NISIRA.productos pr ON cd.Emp_Id = pr.Emp_Id AND cd.idempresa = pr.idempresa AND cd.idproducto = pr.idproducto
        LEFT JOIN dw_landing.NISIRA.DREGISTROPALETA_CCOSTO dcc ON dp.IDEMPRESA = dcc.IDEMPRESA AND dp.IDREGISTROPALETA = dcc.IDREGISTROPALETA AND dp.ITEM = dcc.ITEM
    WHERE pr.es_merma = 0 AND pr.es_descarte = 0
      AND ISNULL(mt.detalle_ccosto, 0) = 0
      AND dcc.ITEM IS NULL

    UNION ALL

    SELECT cd.Emp_Id,
        cd.idempresa,
        cd.idingresosalidaproceso,
        cd.dw_fecha,
        cd.idsucursal,
        dpc.idconsumidor,
        dpc.item,
        dp.idproducto,
        COUNT(dpc.ITEM),
        SUM(dp.CANTIDAD) / ISNULL(NULLIF(cc.TotalDistribucion, 0), 1),
        SUM(dp.CANTIDAD * pr.KG_CAJAS) / ISNULL(NULLIF(cc.TotalDistribucion, 0), 1),
        SUM(dp.CANTIDAD * (cd.peso - cd.pesodrenado)) / ISNULL(NULLIF(cc.TotalDistribucion, 0), 1),
        ISNULL(mt.es_muestra,0),
        p.idcultivo,
        pc.idvariedad,
        dp.idcondicion,
        dp.idtalla,
        pr.IDINSUMO,
        dp.idcolor,
        p.serie
    FROM #cd cd
        LEFT JOIN dw_landing.NISIRA.ddingresosalidaproceso_referencias dr ON cd.Emp_Id = dr.Emp_Id AND cd.idempresa = dr.idempresa AND cd.idingresosalidaproceso = dr.idingresosalidaproceso AND cd.item = dr.item
        LEFT JOIN dw_landing.NISIRA.registropaleta p ON dr.Emp_Id = p.Emp_Id AND dr.idempresa = p.idempresa AND dr.idreferencia = p.idregistropaleta
        LEFT JOIN dw_landing.NISIRA.dregistropaleta dp ON dr.Emp_Id = dp.Emp_Id AND dr.idempresa = dp.idempresa AND dr.idreferencia = dp.idregistropaleta AND dr.itemref = dp.item
        LEFT JOIN dw_landing.NISIRA.DREGISTROPALETA_CCOSTO dpc ON dpc.idempresa = dp.idempresa AND dpc.idregistropaleta = dp.idregistropaleta AND dpc.item = dp.item
        LEFT JOIN dw_landing.NISIRA.VARIEDADES_CULTIVOS pv ON p.Emp_Id = pv.Emp_Id AND p.idempresa = pv.IDEMPRESA AND p.idcultivo = pv.IDCULTIVO AND p.idvariedad = pv.IDVARIEDAD   -- no se usa
        LEFT JOIN dw_landing.NISIRA.motivopaleta mt ON p.Emp_Id = mt.Emp_Id AND p.idempresa = mt.idempresa AND p.idmotivopaleta = mt.idmotivopaleta
        LEFT JOIN dw_landing.NISIRA.consumidor cn ON dpc.Emp_Id = cn.Emp_Id AND dpc.idempresa = cn.idempresa AND dpc.IDCONSUMIDOR = cn.IDCONSUMIDOR                                   -- no se usa
        LEFT JOIN dw_landing.NISIRA.subprocesos spc ON cd.Emp_Id = spc.Emp_Id AND cd.idempresa = spc.idempresa AND cd.idprocesod = spc.idproceso AND cd.idsubprocesod = spc.idsubproceso -- no se usa
        LEFT JOIN dw_landing.NISIRA.productos pr ON cd.Emp_Id = pr.Emp_Id AND cd.idempresa = pr.idempresa AND cd.idproducto = pr.idproducto
        LEFT JOIN dw_landing.NISIRA.productos prp ON dp.Emp_Id = prp.Emp_Id AND dp.idempresa = prp.idempresa AND dp.idproducto = prp.idproducto                                        -- no se usa
        LEFT JOIN dw_landing.NISIRA.DCAMPANA_CULTIVO dccu ON dpc.IDEMPRESA = dccu.IDEMPRESA AND dpc.IDCONSUMIDOR = dccu.IDCONSUMIDOR AND dpc.IDSIEMBRA = dccu.IDSIEMBRA AND dpc.IDCAMPANA = dccu.IDCAMPANA AND dpc.Emp_Id = dccu.Emp_Id
        LEFT JOIN dw_landing.NISIRA.productos pc ON dccu.IDEMPRESA = pc.IDEMPRESA AND dccu.IDPRODUCTO = pc.IDPRODUCTO
        LEFT JOIN (
            SELECT IDEMPRESA, IDREGISTROPALETA, ITEM, COUNT(*) AS TotalDistribucion
            FROM dw_landing.NISIRA.DREGISTROPALETA_CCOSTO
            WHERE IDEMPRESA = ''001''
            GROUP BY IDEMPRESA, IDREGISTROPALETA, ITEM
        ) cc ON dp.IDEMPRESA = cc.IDEMPRESA AND dp.IDREGISTROPALETA = cc.IDREGISTROPALETA AND dp.ITEM = cc.ITEM
    WHERE cd.idempresa = ''001''
      AND ISNULL(pc.es_merma,0) = 0 AND ISNULL(pc.es_descarte,0) = 0 AND pc.ES_MATPRIMA = 1
    GROUP BY cd.Emp_Id, cd.idempresa, cd.idingresosalidaproceso, cd.dw_fecha, cd.idsucursal, dpc.idconsumidor, dpc.item, dp.idproducto,
             ISNULL(mt.es_muestra,0), p.idcultivo, pc.idvariedad, dp.idcondicion, dp.idtalla, pr.IDINSUMO, dp.idcolor, p.serie, cc.TotalDistribucion;

    -- 2. PLANILLAPRODUCCION_DIGITACION_RES
    TRUNCATE TABLE PRODUCCION.PLANILLAPRODUCCION_DIGITACION_RES;

    INSERT INTO PRODUCCION.PLANILLAPRODUCCION_DIGITACION_RES (
        idempresa,Emp_Id,idingresosalidaproceso,dw_fecha,idsucursal,idcultivo,idvariedad,idconsumidor,idcondicion,idtalla,idproducto,idenvase,idcolor,
        es_muestra,peso,sobrepeso,cantidad,idcampana
    )
    SELECT pt.idempresa, pt.Emp_Id, pt.idingresosalidaproceso, pt.dw_fecha, pt.idsucursal, pt.idcultivo, pt.idvariedad,
           pt.idconsumidor, pt.idcondicion, pt.idtalla, pt.idproducto, pt.idenvase, pt.idcolor, pt.es_muestra,
           SUM(pt.peso), SUM(pt.sobrepeso), SUM(pt.cantidad), pt.idcampana
    FROM PRODUCCION.PLANILLAPRODUCCION_DIGITACION pt
    GROUP BY pt.idempresa, pt.Emp_Id, pt.idingresosalidaproceso, pt.dw_fecha, pt.idsucursal, pt.idcultivo, pt.idvariedad,
             pt.idconsumidor, pt.idcondicion, pt.idtalla, pt.idproducto, pt.idenvase, pt.idcolor, pt.es_muestra, pt.idcampana;

    -- 3. PLANILLAPRODUCCION_DETALLADO
    TRUNCATE TABLE PRODUCCION.PLANILLAPRODUCCION_DETALLADO;

    INSERT INTO PRODUCCION.PLANILLAPRODUCCION_DETALLADO (
        Emp_Id,idempresa,idcampana,campania,idconsumidor,idsucursal,desc_sucursal,fechacosecha,idproductor,cod_productor,productor,idcultivo,desc_cultivo,idvariedad,
        desc_variedad,idlote,lote,totalkg,fechaproduccion,idcondicion,desc_condicion,idtalla,desc_talla,idproducto,producto,idenvase,desc_envase,idcolor,desc_color,
        idproceso,proceso,idsubproceso,subproceso,es_muestra,peso,sobrepeso,cantidad,descarte,merma
    )
    SELECT mp.Emp_Id,
        mp.idempresa,
        pt.idcampana, ca.Descripcion,
        mp.idconsumidor,
        mp.idsucursal, sc.descripcion,
        mr.dw_fecha,
        cn.idprovlote,
        cn.IdClieProv,
        cn.Productor,
        pmp.idcultivo, cl.descripcion,
        pmp.idvariedad, vr.descripcion,
        mp.idconsumidor, cn.descripcioncorta,
        mp.cantidad,
        mp.dw_fecha,
        pt.idcondicion, cat.NombreCorto,
        pt.idtalla, tll.descorta,
        pt.idproducto, ptr.Producto,
        pt.idenvase, env.NombreCorto,
        pt.idcolor, col.DescripcionColor,
        mp.idprocesod, spp.Proceso,
        mp.idsubprocesod, spp.SubProceso,
        pt.es_muestra,
        SUM(pt.peso),
        SUM(pt.sobrepeso),
        SUM(pt.cantidad),
        dcm.descarte,
        dcm.merma
    FROM PRODUCCION.MATERIAPRIMA_PROCESO_RES mp
        LEFT JOIN PRODUCCION.PLANILLAPRODUCCION_DIGITACION_RES pt ON mp.idempresa = pt.idempresa AND mp.Emp_Id = pt.Emp_Id AND mp.idingresosalidaproceso = pt.idingresosalidaproceso AND mp.idconsumidor = pt.idconsumidor
            AND mp.IDSUCURSAL = pt.IDSUCURSAL AND mp.idcultivo = pt.idcultivo AND mp.IDVARIEDAD = pt.idvariedad
        LEFT JOIN DIMENSION.Sucursales sc ON mp.idempresa = sc.idempresa AND mp.Emp_Id = sc.Emp_Id AND mp.idsucursal = sc.idsucursal
        LEFT JOIN PRODUCCION.MATERIAPRIMA_RECIBIDA mr ON mp.idempresa = mr.idempresa AND mp.Emp_Id = mr.Emp_Id AND mp.idlote_mp = mr.idlote_mp AND mp.idconsumidor = mr.idconsumidor
            AND mp.IDSUCURSAL = mr.IDSUCURSAL AND mp.idcultivo = mr.IDCULTIVO AND mp.IDVARIEDAD = mr.IDVARIEDAD
        LEFT JOIN DIMENSION.consumidor cn ON mp.idempresa = cn.idempresa AND mp.Emp_Id = cn.Emp_Id AND mp.idconsumidor = cn.Codigo
        LEFT JOIN DIMENSION.productos pmp ON mp.idempresa = pmp.idempresa AND mp.Emp_Id = pmp.Emp_Id AND mp.idproducto_mp = pmp.idproducto
        LEFT JOIN DIMENSION.Cultivo cl ON pmp.idempresa = cl.idempresa AND pmp.Emp_Id = cl.Emp_Id AND pmp.idcultivo = cl.IdCultivo
        LEFT JOIN DIMENSION.VariedadesCultivos vr ON pmp.idempresa = vr.idempresa AND pmp.Emp_Id = vr.Emp_Id AND pmp.idcultivo = vr.idcultivo AND pmp.idvariedad = vr.idvariedad
        LEFT JOIN DIMENSION.condicionmp cat ON pt.idempresa = cat.idempresa AND pt.Emp_Id = cat.Emp_Id AND pt.idcondicion = cat.idcondicion
        LEFT JOIN DIMENSION.tallas tll ON pt.idempresa = tll.idempresa AND pt.Emp_Id = tll.Emp_Id AND pt.idtalla = tll.idtalla
        LEFT JOIN DIMENSION.productos ptr ON pt.idempresa = ptr.idempresa AND pt.Emp_Id = ptr.Emp_Id AND pt.idproducto = ptr.idproducto
        LEFT JOIN DIMENSION.TipoInsumos env ON pt.Emp_Id = env.Emp_Id AND pt.idenvase = env.idinsumo
        LEFT JOIN DIMENSION.COLORES col ON pt.Emp_Id = col.Emp_Id AND pt.idcolor = col.idcolor
        LEFT JOIN DIMENSION.Procesos spp ON mp.idempresa = spp.idempresa AND mp.Emp_Id = spp.Emp_Id AND mp.idprocesod = spp.idproceso AND mp.idsubprocesod = spp.idsubproceso
        LEFT JOIN PRODUCCION.PLANILLAPRODUCCION_DESCARTEYMERMA_RES dcm ON mp.idempresa = dcm.idempresa AND mp.Emp_Id = dcm.Emp_Id AND mp.idingresosalidaproceso = dcm.idingresosalidaproceso AND mp.idconsumidor = dcm.idconsumidor
        LEFT JOIN DIMENSION.Campania ca ON pt.Emp_Id = ca.Emp_Id AND pt.idcampana = ca.IdFecha
    WHERE pt.idenvase IS NOT NULL
      AND pt.idcondicion IS NOT NULL
      AND pt.idtalla IS NOT NULL
      AND pt.idcolor IS NOT NULL
    GROUP BY
        mp.Emp_Id, mp.idempresa, pt.idcampana, ca.Descripcion, mp.idsucursal, sc.descripcion, mr.dw_fecha,
        cn.idprovlote, cn.IdClieProv, cn.Productor, pmp.idcultivo, cl.descripcion, pmp.idvariedad, vr.descripcion,
        mp.idconsumidor, cn.descripcioncorta, mp.cantidad, mp.dw_fecha, pt.idcondicion, cat.NombreCorto,
        pt.idtalla, tll.descorta, pt.idproducto, ptr.Producto, pt.idenvase, env.NombreCorto, pt.idcolor, col.DescripcionColor,
        mp.idprocesod, spp.Proceso, mp.idsubprocesod, spp.SubProceso, pt.es_muestra, dcm.descarte, dcm.merma,
        pt.idempresa, pt.idingresosalidaproceso, pt.idconsumidor;

    -- 4. PLANILLAPRODUCCION_SUBRESUMEN
    TRUNCATE TABLE PRODUCCION.PLANILLAPRODUCCION_SUBRESUMEN;

    INSERT INTO PRODUCCION.PLANILLAPRODUCCION_SUBRESUMEN (
        Emp_Id,idempresa,idcampana,campania,idconsumidor,idsucursal,desc_sucursal,fechacosecha,idproductor,cod_productor,productor,idcultivo,desc_cultivo,
        idvariedad,desc_variedad,idlote,lote,exportable,fechaproduccion,idproceso,proceso,idsubproceso,subproceso,cantidad,cantidad_muestra,cantidad_total,
        peso,sobrepeso,exportado,peso_muestra,sobrepeso_muestra,exportado_muestra,peso_total,sobrepeso_total,exportado_total,descarte,merma
    )
    SELECT t.Emp_Id, t.idempresa, t.idcampana, t.campania, t.idconsumidor, t.idsucursal, t.desc_sucursal, t.fechacosecha,
        t.idproductor, t.cod_productor, t.productor, t.idcultivo, t.desc_cultivo, t.idvariedad, t.desc_variedad,
        t.idlote, t.lote, t.totalkg, t.fechaproduccion, t.idproceso, t.proceso, t.idsubproceso, t.subproceso,
        SUM(CASE WHEN t.es_muestra = 0 THEN t.cantidad ELSE 0 END),
        SUM(CASE WHEN t.es_muestra = 1 THEN t.cantidad ELSE 0 END),
        SUM(t.cantidad),
        SUM(CASE WHEN t.es_muestra = 0 THEN t.peso ELSE 0 END),
        SUM(CASE WHEN t.es_muestra = 0 THEN t.sobrepeso ELSE 0 END),
        SUM(CASE WHEN t.es_muestra = 0 THEN t.peso + t.sobrepeso ELSE 0 END),
        SUM(CASE WHEN t.es_muestra = 1 THEN t.peso ELSE 0 END),
        SUM(CASE WHEN t.es_muestra = 1 THEN t.sobrepeso ELSE 0 END),
        SUM(CASE WHEN t.es_muestra = 1 THEN t.peso + t.sobrepeso ELSE 0 END),
        SUM(t.peso),
        SUM(t.sobrepeso),
        SUM(t.peso + t.sobrepeso),
        MAX(t.descarte),
        MAX(t.merma)
    FROM PRODUCCION.PLANILLAPRODUCCION_DETALLADO t
    GROUP BY t.Emp_Id, t.idempresa, t.idcampana, t.campania, t.idconsumidor, t.idsucursal, t.desc_sucursal, t.fechacosecha,
        t.idproductor, t.cod_productor, t.productor, t.idcultivo, t.desc_cultivo, t.idvariedad, t.desc_variedad,
        t.idlote, t.lote, t.totalkg, t.fechaproduccion, t.idproceso, t.proceso, t.idsubproceso, t.subproceso;

    -- 5. PLANILLAPRODUCCION_RESUMEN
    TRUNCATE TABLE PRODUCCION.PLANILLAPRODUCCION_RESUMEN;

    INSERT INTO PRODUCCION.PLANILLAPRODUCCION_RESUMEN (
        Emp_Id,idempresa,idcampana,campania,idconsumidor,idsucursal,desc_sucursal,fechacosecha,idproductor,cod_productor,productor,idcultivo,desc_cultivo,
        idvariedad,desc_variedad,idlote,lote,exportable,fechaproduccion,idproceso,proceso,idsubproceso,subproceso,cantidad,cantidad_muestra,cantidad_total,
        peso,sobrepeso,exportado,peso_muestra,sobrepeso_muestra,exportado_muestra,peso_total,sobrepeso_total,exportado_total,descarte,merma
    )
    SELECT t.Emp_Id, t.idempresa, t.idcampana, t.campania, t.idconsumidor, t.idsucursal, t.desc_sucursal, t.fechacosecha,
        t.idproductor, t.cod_productor, t.productor, t.idcultivo, t.desc_cultivo, t.idvariedad, t.desc_variedad,
        t.idlote, t.lote, SUM(t.exportable), t.fechaproduccion, t.idproceso, t.proceso, t.idsubproceso, t.subproceso,
        SUM(t.cantidad),
        SUM(t.cantidad_muestra),
        SUM(t.cantidad),          -- OJO: deberia ser SUM(t.cantidad_total)? Se dejo como estaba
        SUM(t.peso), SUM(t.sobrepeso), SUM(t.exportado),
        SUM(t.peso_muestra), SUM(t.sobrepeso_muestra), SUM(t.exportado_muestra),
        SUM(t.peso_total), SUM(t.sobrepeso_total), SUM(t.exportado_total),
        SUM(t.descarte), SUM(t.merma)
    FROM PRODUCCION.PLANILLAPRODUCCION_SUBRESUMEN t
    GROUP BY t.Emp_Id, t.idempresa, t.idcampana, t.campania, t.idconsumidor, t.idsucursal, t.desc_sucursal, t.fechacosecha,
        t.idproductor, t.cod_productor, t.productor, t.idcultivo, t.desc_cultivo, t.idvariedad, t.desc_variedad,
        t.idlote, t.lote, t.fechaproduccion, t.idproceso, t.proceso, t.idsubproceso, t.subproceso;

    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH
';

EXEC (@sql) AT LinkedDW;


/* =========================== PARTE 2 =========================== */
IF OBJECT_ID('tempdb..#Planilla') IS NOT NULL DROP TABLE #Planilla;

SELECT *
INTO #Planilla
FROM OPENQUERY(LinkedDW, '
    SELECT T.Emp_Id AS IdEmpresa, ''001'' AS CodEmpresa, T.CodCampana AS CodCampania, T.CodPlanta AS CodSucursal, T.CodCliente AS CodProductor,
           T.CodCultivo, T.CodVariedad, T.CodConsumidor, T.CodProceso, T.CodSubProceso,
           T.FechaCosecha, T.FechaProceso, T.ExportableTotal,
           T.Cantidad, T.Peso, T.SobrePeso, T.Exportado, T.CantidadMuestra, T.PesoMuestra, T.SobrePesoMuestra, T.ExportadoMuestra,
           T.CantidadTotal, T.PesoTotal, T.SobrePesoTotal, T.ExportadoTotal,
           T.Descarte, T.Merma, T.EsNacional
    FROM dw_curated.PRODUCCION.PLANILLAPRODUCCION_HISTORICO T
    WHERE T.CodCampana NOT IN (''UV23'',''PA24'',''AR23'',''PA23'')
    UNION ALL
    SELECT T.Emp_Id, T.idcampana /* OJO: CodEmpresa = idcampana? se dejo como estaba */, T.idcampana, T.idsucursal, T.cod_productor,
           T.idcultivo, T.idvariedad, T.idconsumidor, T.idproceso, T.idsubproceso,
           T.fechacosecha, T.fechaproduccion, T.exportable,
           T.cantidad, T.peso, T.sobrepeso, T.exportado, T.cantidad_muestra, T.peso_muestra, T.sobrepeso_muestra, T.exportado_muestra,
           T.cantidad_total, T.peso_total, T.sobrepeso_total, T.exportado_total,
           T.descarte, T.merma, 0
    FROM dw_curated.PRODUCCION.PLANILLAPRODUCCION_RESUMEN T
    WHERE T.fechaproduccion >= ''20230731'' AND T.idcampana NOT IN (''CT23'')
');

TRUNCATE TABLE DW_ADR.FactPlanta.PlanillaProduccion;

INSERT INTO DW_ADR.FactPlanta.PlanillaProduccion (
    id,IdEmpresa,IdCampania,IdSucursal,IdProductor,IdCultivo,IdVariedadesCultivos,IdConsumidor,IdProcesos,IdTiempo,CodEmpresa,CodCampania,CodSucursal,
    CodProductor,CodCultivo,CodVariedad,CodConsumidor,CodProceso,CodSubProceso,FechaCosecha,FechaProceso,ExportableTotal,Cantidad,Peso,SobrePeso,Exportado,
    CantidadMuestra,PesoMuestra,SobrePesoMuestra,ExportadoMuestra,CantidadTotal,PesoTotal,SobrePesoTotal,ExportadoTotal,Descarte,merma,EsNacional
)
SELECT CAST(CAST(T.IdEmpresa AS varchar(1))
        + RIGHT(CAST(YEAR(T.FechaProceso) AS varchar(4)),2) + CAST(DATEPART(dayofyear,T.FechaProceso) AS varchar(3))
        + RIGHT('000' + CAST(ROW_NUMBER() OVER (PARTITION BY T.IdEmpresa, T.FechaProceso
                                                ORDER BY T.IdEmpresa, T.FechaProceso, T.CodSucursal, T.CodCultivo, T.CodVariedad, T.CodConsumidor) AS varchar(4)),3) AS int),
    T.IdEmpresa,
    ISNULL(CA.Id,0), ISNULL(SU.Id,0), ISNULL(CP.Id,0), ISNULL(CU.Id,0),
    ISNULL(VC.Id,0), ISNULL(CN.Id,0), ISNULL(PS.Id,0), ISNULL(TI.Id,0),
    T.CodEmpresa, T.CodCampania, T.CodSucursal, T.CodProductor, T.CodCultivo, T.CodVariedad, T.CodConsumidor, T.CodProceso, T.CodSubProceso,
    T.FechaCosecha, T.FechaProceso, T.ExportableTotal,
    T.Cantidad, T.Peso, T.SobrePeso, T.Exportado,
    T.CantidadMuestra, T.PesoMuestra, T.SobrePesoMuestra, T.ExportadoMuestra,
    T.CantidadTotal, T.PesoTotal, T.SobrePesoTotal, T.ExportadoTotal,
    ISNULL(T.Descarte,0), ISNULL(T.Merma,0),
    CAST(T.EsNacional AS bit)
FROM #Planilla T
    LEFT JOIN DW_ADR.Dimension.Campania CA ON T.IdEmpresa = CA.IdEmpresa AND T.CodCampania = CA.CodCampania
    LEFT JOIN DW_ADR.Dimension.Sucursal SU ON T.IdEmpresa = SU.IdEmpresa AND T.CodSucursal = SU.CodSucursal
    LEFT JOIN DW_ADR.Dimension.ClienteProveedor CP ON T.IdEmpresa = CP.IdEmpresa AND T.CodProductor = CP.CodClienteProveedor
    LEFT JOIN DW_ADR.Dimension.Cultivo CU ON T.IdEmpresa = CU.IdEmpresa AND T.CodCultivo = CU.CodCultivo
    LEFT JOIN DW_ADR.Dimension.VariedadesCultivos VC ON T.IdEmpresa = VC.IdEmpresa AND T.CodCultivo = VC.CodCultivo AND T.CodVariedad = VC.CodVariedad
    LEFT JOIN DW_ADR.Dimension.Consumidor CN ON T.IdEmpresa = CN.IdEmpresa AND T.CodConsumidor = CN.CodConsumidor
    LEFT JOIN DW_ADR.Dimension.Procesos PS ON T.IdEmpresa = PS.IdEmpresa AND T.CodProceso = PS.CodProceso AND T.CodSubProceso = PS.CodSubProceso
    LEFT JOIN DW_ADR.Dimension.Tiempo TI ON T.FechaProceso = TI.Fecha;

DROP TABLE #Planilla;