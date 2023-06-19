CREATE OR REPLACE PROCEDURE "RP_NC_HISSTORAGE_GENERATE"(p_pi_id NUMBER) IS

    /*create by vetica 20120312
    */

    v_date      VARCHAR2(80);
    v_dateend   NUMBER(8);
    v_yearmonth NUMBER(6);
    v_count     NUMBER(10);

    TYPE t_type1 IS TABLE OF NUMBER(10);
    t_store_id t_type1;
    r_p_store  r_tabid := r_tabid(); --记录已有月结记录店仓ID集合
    r_np_store r_tabid := r_tabid(); --记录无月结店仓ID集合

    --error_msg     VARCHAR2(4000);
    r_store   r_tabid; --记录店仓ID集合
    r_product r_tabid; --记录款号ID集合
    v_sql_0   VARCHAR2(300);
    v_sql     CLOB; --存放SQL语句
    v_userid  NUMBER(10);

BEGIN
    --清除与当前传入参数相同数据行
    -- raise_application_error(-20201, p_pi_id);
    EXECUTE IMMEDIATE ('truncate TABLE RP_NC_HISSTORAGE01');

    v_sql_0 := 'select t.info from ad_pinstance_para t
               where t.name=:name and t.ad_pinstance_id=:pid';
    SELECT t.modifierid
    INTO v_userid
    FROM ad_pinstance t
    WHERE t.id = p_pi_id;
    --依次获取界面查询条件参数
    EXECUTE IMMEDIATE v_sql_0
        INTO v_sql
        USING '日期', p_pi_id;

    v_date := REPLACE(REPLACE(TRIM(v_sql), '(日期=', ''), ')', '');
    IF length(v_date) <> 8 THEN
        raise_application_error(-20201, ' 输入的日期格式不对!');
    END IF;

    v_dateend := to_char(is_date(v_date, 'YYYYMMDD', ''), 'YYYYMMDD');

    v_yearmonth := substr(v_dateend, 1, 6);

    EXECUTE IMMEDIATE v_sql_0
        INTO v_sql
        USING '店仓', p_pi_id;
    r_store := f_fast_table(v_sql);

    EXECUTE IMMEDIATE v_sql_0
        INTO v_sql
        USING '款号', p_pi_id;
    r_product := f_fast_table(v_sql);

    ---------------------------------------------------------------
    --获取从未月结过的店仓集合
    --begin no.1 未月结过，需加入期初值0.1  0.2
    SELECT rs.id BULK COLLECT
    INTO t_store_id
    FROM c_store a
    JOIN TABLE(r_store) rs ON (a.id = rs.id)
    LEFT JOIN c_period b ON (a.c_customer_id = b.c_customer_id AND
                            b.ismonthsum = 'Y' AND b.isendaccount = 'Y' AND
                            b.dateend <= v_dateend)
    WHERE b.c_customer_id IS NULL;

    v_count := t_store_id.COUNT;
    IF v_count > 0 THEN

        FOR i IN 1 .. v_count LOOP
            r_np_store.EXTEND();
            r_np_store(i) := r_id(t_store_id(i));
        END LOOP;

        --未月结过，需加入期初值0.1  0.2
        INSERT INTO rp_nc_hisstorage01
            (id, ad_client_id, ad_org_id, isactive, ownerid, modifierid,
             creationdate, modifieddate, ad_pi_id, c_store_id, m_product_id,
             m_attributesetinstance_id, m_productalias_id, pricelist, total,
             amt_list)
            SELECT 1, t.ad_client_id, t.ad_org_id, 'Y', v_userid, v_userid,
                   SYSDATE, SYSDATE, p_pi_id, t.c_store_id, t.m_product_id,
                   t.m_attributesetinstance_id, c.id AS m_productalias_id,
                   a.pricelist, t.total, a.pricelist * t.total AS amt_list
            FROM (SELECT SUM(t.qtychange) AS total, t.m_product_id,
                          t.m_attributesetinstance_id, t.c_store_id,
                          t.ad_client_id, t.ad_org_id
                   FROM TABLE(r_np_store) rs, fa_storage_ftp t,
                        TABLE(r_product) rp
                   WHERE rs.id = t.c_store_id
                   AND t.m_product_id = rp.id
                   AND t.changedate <= v_dateend
                   GROUP BY t.m_product_id, t.m_attributesetinstance_id,
                            t.c_store_id, t.ad_client_id, t.ad_org_id
                   UNION ALL
                   SELECT SUM(b.qtybegin) AS total, b.m_product_id,
                          b.m_attributesetinstance_id, a.c_store_id,
                          a.ad_client_id, a.ad_org_id
                   FROM TABLE(r_np_store) rs, c_begiinning a, c_begiinningitem b,
                        TABLE(r_product) rp
                   WHERE rs.id = a.c_store_id
                   AND a.id = b.c_begiinning_id
                   AND b.m_product_id = rp.id
                   GROUP BY b.m_product_id, b.m_attributesetinstance_id,
                            a.c_store_id, a.ad_client_id, a.ad_org_id) t,
                 m_product a, m_product_alias c
            WHERE t.m_product_id = a.id
            AND t.m_product_id = c.m_product_id
            AND t.m_attributesetinstance_id = c.m_attributesetinstance_id;

    END IF;
    --end no.1

    --begin no.2 月结过，需加入期初值0.1  0.2
    v_count := t_store_id.COUNT;
    IF v_count > 0 THEN
        FOR i IN 1 .. r_store.COUNT LOOP
            IF r_store(i).id NOT MEMBER OF t_store_id THEN
                r_p_store.EXTEND();
                r_p_store(r_p_store.COUNT) := r_id(r_store(i).id);
            END IF;
        END LOOP;
    ELSE
        r_p_store := r_store;
    END IF;

    --店仓存在月结过, 需加入期初值0.1  0.2
    IF r_p_store.COUNT > 0 THEN

        INSERT INTO rp_nc_hisstorage01
            (id, ad_client_id, ad_org_id, isactive, ownerid, modifierid,
             creationdate, modifieddate, ad_pi_id, c_store_id, m_product_id,
             m_attributesetinstance_id, m_productalias_id, pricelist, total,
             amt_list) WITH period_as AS
            (SELECT /*+materialize*/
              b.id, b.dateend
             FROM (SELECT t.c_customer_id, MAX(t.yearmonth) yearmonth
                    FROM TABLE(r_p_store) rs, c_store s, c_period t
                    WHERE rs.id = s.id
                    AND s.c_customer_id = t.c_customer_id
                    AND t.ismonthsum = 'Y'
                    AND t.isendaccount = 'Y'
                    AND t.dateend <= v_dateend
                    GROUP BY t.c_customer_id) a
             JOIN c_period b ON (a.c_customer_id = b.c_customer_id AND
                                a.yearmonth = b.yearmonth))
            SELECT 1, a.ad_client_id, a.ad_org_id, 'Y', v_userid, v_userid,
                   SYSDATE, SYSDATE, p_pi_id, a.c_store_id, a.m_product_id,
                   a.m_attributesetinstance_id, d.id, c.pricelist, a.qtyend,
                   c.pricelist * a.qtyend AS amt_list
            FROM fa_monthstore a, TABLE(r_p_store) rs, TABLE(r_product) rp,
                 m_product c, m_product_alias d, period_as m
            WHERE rs.id = a.c_store_id
            AND a.c_period_id = m.id
            AND rp.id = c.id
            AND a.m_product_id = rp.id
            AND a.m_product_id = d.m_product_id
            AND a.m_attributesetinstance_id = d.m_attributesetinstance_id;

        MERGE INTO rp_nc_hisstorage01 g
        USING (SELECT h.ad_client_id, h.ad_org_id, h.m_product_id, h.c_store_id,
                      h.m_attributesetinstance_id, h.sumqty, k.pricelist,
                      pa.id AS m_productalias_id
               FROM (SELECT st.ad_client_id, st.ad_org_id, st.c_store_id,
                             st.m_product_id, st.m_attributesetinstance_id,
                             SUM(st.qtychange) AS sumqty
                      FROM TABLE(r_p_store) rs, fa_storage_ftp st,
                           TABLE(r_product) rp, c_store c,
                           (SELECT b.id, b.c_customer_id, b.dateend
                             FROM (SELECT t.c_customer_id, MAX(t.yearmonth) yearmonth
                                    FROM TABLE(r_p_store) rs, c_store s, c_period t
                                    WHERE rs.id = s.id
                                    AND s.c_customer_id = t.c_customer_id
                                    AND t.ismonthsum = 'Y'
                                    AND t.isendaccount = 'Y'
                                    AND t.dateend <= v_dateend
                                    GROUP BY t.c_customer_id) a
                             JOIN c_period b ON (a.c_customer_id = b.c_customer_id AND
                                                a.yearmonth = b.yearmonth)) m
                      WHERE rs.id = st.c_store_id
                      AND st.m_product_id = rp.id
                      AND st.changedate <= v_dateend
                      AND rs.id = c.id
                      AND c.c_customer_id = m.c_customer_id
                      AND st.changedate > m.dateend
                      GROUP BY st.ad_client_id, st.ad_org_id, st.c_store_id,
                               st.m_product_id, st.m_attributesetinstance_id) h,
                    m_product k, m_product_alias pa
               WHERE h.m_product_id = k.id
               AND h.sumqty <> 0
               AND h.m_product_id = pa.m_product_id
               AND h.m_attributesetinstance_id = pa.m_attributesetinstance_id) w
        ON (g.c_store_id = w.c_store_id AND g.m_product_id = w.m_product_id AND g.m_attributesetinstance_id = w.m_attributesetinstance_id AND g.ad_pi_id = p_pi_id)
        WHEN MATCHED THEN
            UPDATE
            SET g.total = g.total + w.sumqty,
                g.amt_list = g.pricelist * (g.total + w.sumqty)
        WHEN NOT MATCHED THEN
            INSERT
                (id, ad_client_id, ad_org_id, isactive, ownerid, modifierid,
                 creationdate, modifieddate, ad_pi_id, c_store_id, m_product_id,
                 m_attributesetinstance_id, m_productalias_id, pricelist, total,
                 amt_list)
            VALUES
                (1, w.ad_client_id, w.ad_org_id, 'Y', v_userid, v_userid,
                 SYSDATE, SYSDATE, p_pi_id, w.c_store_id, w.m_product_id,
                 w.m_attributesetinstance_id, w.m_productalias_id, w.pricelist,
                 w.sumqty, w.pricelist * w.sumqty);
    END IF;

    --end no.2

END rp_nc_hisstorage_generate;


 
