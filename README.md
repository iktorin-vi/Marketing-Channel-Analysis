# Marketing Channel Analysis — SQL Report
 
> Marketing Analytics · BigQuery SQL  
> Google · Meta · TikTok — повний аналіз воронки та ефективності каналів
 
## Загальна інформація
 
| Параметр | Значення |
|---|---|
| Інструмент | BigQuery (GoogleSQL) |
| Метод дедублікації | ROW_NUMBER() |
| Метрики | CPM, CTR, CAC, LTV/CAC |
| CTE-кроки | 3 + фінальний SELECT |
| Перевірок якості | 3 (Nulls, Enum, Dates) |
| Джерела даних | Google, Meta, TikTok |
| Період | 2024-01-02 — 2024-07-14 (195 днів) |
 
---
 
## 00. Перевірка якості даних
 
### Enum-поля / Канали
 
| Канал | Кількість рядків |
|---|---|
| google | 2 616 |
| meta | 3 544 |
| tiktok | 2 654 |
| **Всього** | **8 814** |
 
✅ Сторонніх джерел немає.
 
### Nulls & Дублікати
 
| Поле | Nulls |
|---|---|
| null_sources | 0 |
| null_dates | 0 |
| null_ads | 0 |
| null_spends | 0 |
 
✅ Дані повні, без пропусків.
 
### Часовий діапазон
 
- **Початок:** 2024-01-02  
- **Кінець:** 2024-07-14  
- **Унікальних дат:** 195 (~6.5 місяців без розривів)
✅ 
 
### SQL-запити перевірки якості
 
**check_1_sources.sql**
```sql
-- Enum-поля: Які унікальні значення є?
SELECT
    source,
    COUNT(*) as row_count
FROM marketing_data.marketing_ads_raw
GROUP BY source;
```
 
**check_2_nulls.sql**
```sql
-- Nulls & дублі: Чи можна довіряти даним?
SELECT
    COUNTIF(source IS NULL) as null_sources,
    COUNTIF(date   IS NULL) as null_dates,
    COUNTIF(ad_id  IS NULL) as null_ads,
    COUNTIF(spend  IS NULL) as null_spends
FROM marketing_data.marketing_ads_raw;
```
 
**check_3_date_range.sql**
```sql
-- Часовий діапазон: За який період дані?
SELECT
    MIN(date) as start_date,
    MAX(date) as end_date,
    COUNT(DISTINCT date) as total_days
FROM marketing_data.marketing_ads_raw;
```
 
---
 
## 01. Результати запиту
 
| Канал | Total Spend ($) | CPM ($) | CTR (%) | CR Click→Install (%) | CR Install→Reg (%) | CAC ($) | LTV ($) | LTV/CAC |
|---|---|---|---|---|---|---|---|---|
| Google | 1 519 991.83 | 40.00 | 0.80 | 36.94 | 95.94 | 14.12 | 12.40 | 0.88 ⚠️ |
| Meta | 6 198 916.86 | 17.38 | 1.20 | 39.99 | 93.98 | 3.86 ★ | 6.20 | 1.61 ★ |
| TikTok | 1 441 769.34 | 22.00 | 1.50 | 30.96 | 87.96 | 5.39 | 8.50 | 1.58 |
 
---
 
## 02. Ключові інсайти
 
| Метрика | Значення | Коментар |
|---|---|---|
| Найнижчий CAC | **$3.86** (Meta) | Meta залучає одного зареєстрованого користувача у 3.6× дешевше за Google. При бюджеті ~$62K — масштабування працює. |
| Google LTV/CAC | **0.88** ⚠️ | Витрачаємо $14.12 на залучення, а користувач приносить $12.40. Кожен новий юзер через Google = мінус $1.72. |
| Втрати у воронці | **~65%** (Клік→Інстал) | Від кліку до встановлення доходить лише ~35% користувачів. Етап Install→Reg, навпаки, конвертує 88–96%. |
| Найкращий LTV/CAC | **1.61** (Meta) | Meta та TikTok — прибуткові канали. На кожен вкладений $1 Meta повертає $1.61 LTV. TikTok зовсім поруч. |
 
---
 
## 03. Де найбільші втрати у воронці?
 
### CR Click → Install (% від кліків, що стали інсталами)
 
| Канал | CR Click→Install |
|---|---|
| Meta | 39.99% |
| Google | 36.94% |
| TikTok | 30.96% |
 
### CR Install → Registration (% інсталів, що стали реєстраціями)
 
| Канал | CR Install→Reg |
|---|---|
| Google | 95.94% |
| Meta | 93.98% |
| TikTok | 87.96% |
 
> 💡 **Висновок:** Проблема не в реєстрації — хто встановив, той і реєструється (88–96%). Головна втрата — на кроці Клік → Інстал. Оптимізуйте App Store / Play Store сторінку.
 
---
 
## 04. SQL-запит (BigQuery)
 
```sql
-- ══════════════════════════════════════════════
-- КРОК 1: Дедублікація
-- Знаходимо останній snapshot для кожного ad_id та date
-- ══════════════════════════════════════════════
WITH deduped_ads AS (
    SELECT
        source, campaign_id, ad_id, date,
        spend, impressions, clicks, installs, registrations,
        ROW_NUMBER() OVER (
            PARTITION BY ad_id, date
            ORDER BY timestamp DESC
        ) as rn
    FROM marketing_data.marketing_ads_raw
),
 
-- ══════════════════════════════════════════════
-- КРОК 2: Фільтруємо останні зрізи
-- Агрегуємо по каналах та датах
-- ══════════════════════════════════════════════
daily_metrics AS (
    SELECT
        source, date,
        SUM(spend)         as daily_spend,
        SUM(impressions)   as daily_impressions,
        SUM(clicks)        as daily_clicks,
        SUM(installs)      as daily_installs,
        SUM(registrations) as daily_registrations
    FROM deduped_ads
    WHERE rn = 1
    GROUP BY source, date
),
 
-- ══════════════════════════════════════════════
-- КРОК 3: Загальні метрики по каналах + LTV
-- ══════════════════════════════════════════════
channel_totals AS (
    SELECT
        source,
        SUM(daily_spend)         as total_spend,
        SUM(daily_impressions)   as total_impressions,
        SUM(daily_clicks)        as total_clicks,
        SUM(daily_installs)      as total_installs,
        SUM(daily_registrations) as total_registrations,
        CASE
            WHEN source = 'google' THEN 12.40
            WHEN source = 'meta'   THEN 6.20
            WHEN source = 'tiktok' THEN 8.50
            ELSE 0
        END as ltv_value
    FROM daily_metrics
    GROUP BY source
)
 
-- ══════════════════════════════════════════════
-- ФІНАЛЬНИЙ SELECT: Розрахунок всіх метрик
-- CPM · CTR · CR Click→Install · CR Install→Reg · CAC · LTV/CAC
-- ══════════════════════════════════════════════
SELECT
    source,
    ROUND(total_spend, 2)                                                     as total_spend,
 
    -- CPM = (Spend / Impressions) * 1000
    CASE WHEN total_impressions > 0
        THEN ROUND((total_spend / total_impressions) * 1000, 2) ELSE 0 END  as cpm,
 
    -- CTR % = (Clicks / Impressions) * 100
    CASE WHEN total_impressions > 0
        THEN ROUND((total_clicks / total_impressions) * 100, 2) ELSE 0 END  as ctr_pct,
 
    -- CR Click→Install % = (Installs / Clicks) * 100
    CASE WHEN total_clicks > 0
        THEN ROUND((total_installs / total_clicks) * 100, 2) ELSE 0 END  as cr_click_install_pct,
 
    -- CR Install→Reg % = (Registrations / Installs) * 100
    CASE WHEN total_installs > 0
        THEN ROUND((total_registrations / total_installs) * 100, 2) ELSE 0 END as cr_install_reg_pct,
 
    -- CAC = Spend / Registrations
    CASE WHEN total_registrations > 0
        THEN ROUND(total_spend / total_registrations, 2) ELSE 0 END          as cac,
 
    ltv_value                                                                  as ltv,
 
    -- LTV / CAC
    CASE WHEN total_registrations > 0
        THEN ROUND(ltv_value / (total_spend / total_registrations), 2) ELSE 0 END as ltv_cac
 
FROM channel_totals
ORDER BY source;
```
 
---
 
## 05. Висновки та рекомендації
 
- 🏆 Meta — найефективніший канал. Найнижчий CAC ($3.86) і найвищий LTV/CAC (1.61) попри найбільший бюджет (~$62K). Це класичний приклад успішного масштабування: більше грошей → ще нижча вартість залучення. Рекомендація: збільшувати бюджет Meta.
- ⚠️ Google — працює в мінус (LTV/CAC = 0.88). Кожен залучений через Google користувач коштує $14.12, а приносить $12.40. Збиток $1.72 з користувача. Рекомендація: або оптимізувати таргетинг / креативи, або перерозподілити бюджет Google на Meta/TikTok.
- 🎯 Головна проблема воронки — Клік → Інстал. Менше 40% кліків конвертуються в інстали. Це означає, що реклама приваблює людей, але сторінка в App Store / Google Play їх не конвертує. Пріоритет для продуктової команди: оптимізація ASO (скріншоти, опис, рейтинг).
- 📈 TikTok — перспективний канал. LTV/CAC 1.58 (майже як Meta), при цьому менший бюджет та найвищий CTR (1.5%). Є потенціал для масштабування — варто тестувати збільшення бюджету TikTok.
---
 
## 06. CAC по місяцях
 
### SQL
 
```sql
monthly_channel_totals AS (
    -- Крок 3 (модифікований): Групуємо по місяцю та каналу
    SELECT
        DATE_TRUNC(date, MONTH) as report_month,
        source,
        SUM(daily_spend)         as total_spend,
        SUM(daily_registrations) as total_registrations
    FROM daily_metrics
    GROUP BY report_month, source
)
 
SELECT
    report_month,
    source,
    ROUND(total_spend, 2)   as total_spend,
    total_registrations,
    CASE WHEN total_registrations > 0
        THEN ROUND(total_spend / total_registrations, 2)
        ELSE 0
    END as cac
FROM monthly_channel_totals
ORDER BY report_month ASC, source ASC;
```
 
### Таблиця CAC по місяцях
 
| Місяць | Google CAC ($) | Meta CAC ($) | TikTok CAC ($) |
|---|---|---|---|
| 2024-01 | 14.32 | -0.10 ⚠️ | 5.43 |
| 2024-02 | 14.17 | 15.34 ⚠️ | 5.40 |
| 2024-03 | 14.13 | 3.11 | 5.39 |
| 2024-04 | 14.12 | 3.10 | 5.39 |
| 2024-05 | 14.11 | 3.10 | 5.39 |
| 2024-06 | 14.11 | 3.10 | 5.39 |
| 2024-07 | 14.10 | 3.10 | 5.38 |
 
> ⚠️ Meta Jan = -$0.10 (кредит), Feb = $15.34 (старт без оптимізації)
 
### Аномалія
 
> ⚠️ Аномалія: Meta 2024-01 та 2024-02 У січні total_spend = -$4 245.93 → ймовірно кредит або повернення від платформи Meta. У лютому CAC злетів до $15.34 — початок кампанії з ще не оптимізованим таргетингом. З березня Meta стабілізувалась на рівні ~$3.10, що є найкращим показником серед усіх каналів.
 
### Динаміка
 
📊 Висновок по динаміці: Google — CAC стабільний (~$14.1) протягом всього періоду, без покращень. Канал не оптимізується сам по собі. Meta — після аномального старту стабілізувалась на ~$3.10 з березня. Ефективність зростала разом з масштабом. TikTok — найстабільніший канал: CAC тримається на рівні $5.38–$5.43 без суттєвих коливань.
 
---
 
*Marketing Channel Analysis Report · BigQuery SQL · 3 CTEs + Bonus · Data: Google, Meta, TikTok · Jan–Jul 2024* 
