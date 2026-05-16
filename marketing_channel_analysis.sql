WITH deduped_ads AS (
    -- Крок 1: Дедублікація. Знаходимо останній snapshot для кожного ad_id та date
    SELECT 
        source,
        campaign_id,
        ad_id,
        date,
        spend,
        impressions,
        clicks,
        installs,
        registrations,
        ROW_NUMBER() OVER (
            PARTITION BY ad_id, date 
            ORDER BY timestamp DESC
        ) as rn
    FROM marketing_data.marketing_ads_raw
),

daily_metrics AS (
    -- Крок 2: Фільтруємо лише останні зрізи та агрегуємо за каналами та днями
    -- (Це проміжний крок, корисний для бонусного аналізу по місяцях)
    SELECT 
        source,
        date,
        SUM(spend) as daily_spend,
        SUM(impressions) as daily_impressions,
        SUM(clicks) as daily_clicks,
        SUM(installs) as daily_installs,
        SUM(registrations) as daily_registrations
    FROM deduped_ads
    WHERE rn = 1
    GROUP BY source, date
),

channel_totals AS (
    -- Крок 3: Агрегуємо метрики по каналах за весь період та додаємо фіксований LTV
    SELECT 
        source,
        SUM(daily_spend) as total_spend,
        SUM(daily_impressions) as total_impressions,
        SUM(daily_clicks) as total_clicks,
        SUM(daily_installs) as total_installs,
        SUM(daily_registrations) as total_registrations,
        -- Додаємо LTV згідно з умовою бонусного завдання
        CASE 
            WHEN source = 'google' THEN 12.40
            WHEN source = 'meta' THEN 6.20
            WHEN source = 'tiktok' THEN 8.50
            ELSE 0 
        END as ltv_value
    FROM daily_metrics
    GROUP BY source
)

-- Фінальний розрахунок усіх необхідних метрик для таблиці результатів
SELECT 
    source,
    ROUND(total_spend, 2) as total_spend,
    
    -- CPM = (Spend / Impressions) * 1000
    CASE WHEN total_impressions > 0 THEN ROUND((total_spend / total_impressions) * 1000, 2) ELSE 0 END as cpm,
    
    -- CTR % = (Clicks / Impressions) * 100
    CASE WHEN total_impressions > 0 THEN ROUND((total_clicks / total_impressions) * 100, 2) ELSE 0 END as ctr_pct,
    
    -- CR Click -> Install % = (Installs / Clicks) * 100
    CASE WHEN total_clicks > 0 THEN ROUND((total_installs / total_clicks) * 100, 2) ELSE 0 END as cr_click_install_pct,
    
    -- CR Install -> Reg % = (Registrations / Installs) * 100
    CASE WHEN total_installs > 0 THEN ROUND((total_registrations / total_installs) * 100, 2) ELSE 0 END as cr_install_reg_pct,
    
    -- CAC = Spend / Registrations (реєстрація як фінальний етап/підписка)
    CASE WHEN total_registrations > 0 THEN ROUND(total_spend / total_registrations, 2) ELSE 0 END as cac,
    
    -- LTV (з воркшопу)
    ltv_value as ltv,
    
    -- LTV / CAC
    CASE WHEN total_registrations > 0 THEN ROUND(ltv_value / (total_spend / total_registrations), 2) ELSE 0 END as ltv_cac
FROM channel_totals
ORDER BY source;