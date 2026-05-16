# Marketing Channel Analysis — SQL Report
 
**Інструмент:** BigQuery (GoogleSQL)  
**Метод дедублікації:** ROW_NUMBER() по ad_id + date  
**Метрики:** CPM, CTR, CAC, LTV/CAC  
**Структура запиту:** 3 CTE + фінальний SELECT  
**Перевірок якості даних:** 3 (Nulls, Enum, Dates)
 
---
 
## 00. Перевірка якості даних
 
Перед аналізом було проведено 3 перевірки якості даних.
 
### Enum-поля — які унікальні значення є?
 
```sql
SELECT
    source,
    COUNT(*) as row_count
FROM marketing_data.marketing_ads_raw
GROUP BY source;
```
 
| source | row_count |
|--------|-----------|
| google | 2 616 |
| meta | 3 544 |
| tiktok | 2 654 |
 
**Всього:** 8 814 рядків. Сторонніх джерел немає. ✅
 
---
 
### Nulls — чи можна довіряти даним?
 
```sql
SELECT
    COUNTIF(source IS NULL) as null_sources,
    COUNTIF(date   IS NULL) as null_dates,
    COUNTIF(ad_id  IS NULL) as null_ads,
    COUNTIF(spend  IS NULL) as null_spends
FROM marketing_data.marketing_ads_raw;
```
 
| null_sources | null_dates | null_ads | null_spends |
|-------------|------------|----------|-------------|
| 0 | 0 | 0 | 0 |
 
Дані повні, без пропусків. ✅
 
---
 
### Часовий діапазон — за який період дані?
 
```sql
SELECT
    MIN(date) as start_date,
    MAX(date) as end_date,
    COUNT(DISTINCT date) as total_days
FROM marketing_data.marketing_ads_raw;
```
 
| start_date | end_date | total_days |
|------------|----------|------------|
| 2024-01-02 | 2024-07-14 | 195 |
 
~6.5 місяців без розривів. ✅
 
**Висновок:** Дані чисті — нульових значень немає, всі три канали присутні, 195 унікальних дат підтверджують цілісність часового ряду. Аналізу можна довіряти.
 
---
 
## 01. SQL-запит
 
```sql
WITH deduped_ads AS (
    -- Крок 1: Дедублікація
    -- Знаходимо останній snapshot для кожного ad_id та date
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
    -- Крок 2: Фільтруємо лише останні зрізи
    -- Агрегуємо за каналами та днями
    SELECT
        source,
        date,
        SUM(spend)         as daily_spend,
        SUM(impressions)   as daily_impressions,
        SUM(clicks)        as daily_clicks,
        SUM(installs)      as daily_installs,
        SUM(registrations) as daily_registrations
    FROM deduped_ads
    WHERE rn = 1
    GROUP BY source, date
),
 
channel_totals AS (
    -- Крок 3: Агрегуємо по каналах за весь період + фіксований LTV
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
 
-- Фінальний розрахунок усіх метрик
SELECT
    source,
    ROUND(total_spend, 2) as total_spend,
 
    -- CPM = (Spend / Impressions) * 1000
    CASE WHEN total_impressions > 0
        THEN ROUND((total_spend / total_impressions) * 1000, 2) ELSE 0 END as cpm,
 
    -- CTR % = (Clicks / Impressions) * 100
    CASE WHEN total_impressions > 0
        THEN ROUND((total_clicks / total_impressions) * 100, 2) ELSE 0 END as ctr_pct,
 
    -- CR Click → Install % = (Installs / Clicks) * 100
    CASE WHEN total_clicks > 0
        THEN ROUND((total_installs / total_clicks) * 100, 2) ELSE 0 END as cr_click_install_pct,
 
    -- CR Install → Reg % = (Registrations / Installs) * 100
    CASE WHEN total_installs > 0
        THEN ROUND((total_registrations / total_installs) * 100, 2) ELSE 0 END as cr_install_reg_pct,
 
    -- CAC = Spend / Registrations
    CASE WHEN total_registrations > 0
        THEN ROUND(total_spend / total_registrations, 2) ELSE 0 END as cac,
 
    ltv_value as ltv,
 
    -- LTV / CAC
    CASE WHEN total_registrations > 0
        THEN ROUND(ltv_value / (total_spend / total_registrations), 2) ELSE 0 END as ltv_cac
 
FROM channel_totals
ORDER BY source;
```
 
---
 
## 02. Результати запиту
 
| source | total_spend | cpm | ctr_pct | cr_click_install_pct | cr_install_reg_pct | cac | ltv | ltv_cac |
|--------|-------------|-----|---------|----------------------|--------------------|-----|-----|---------|
| google | 1 519 991.83 | 40.00 | 0.80 | 36.94 | 95.94 | 14.12 | 12.40 | 0.88 |
| meta | 6 198 916.86 | 17.38 | 1.20 | 39.99 | 93.98 | 3.86 | 6.20 | 1.61 |
| tiktok | 1 441 769.34 | 22.00 | 1.50 | 30.96 | 87.96 | 5.39 | 8.50 | 1.58 |
 
---
 
## 03. Аналіз
 
### 1. Який канал має найнижчий CAC?
 
Найнижчий CAC має **Meta ($3.86)**. Це означає, що залучення одного зареєстрованого користувача через Meta обходиться найдешевше. Для порівняння: TikTok — $5.39, Google — $14.12.
 
### 2. Де найбільші втрати у воронці?
 
- **Клік → Інстал:** конверсія 30–40%. Тобто більше 60% людей, що клікнули, не встановлюють додаток — це головна точка втрат.
- **Інстал → Реєстрація:** конверсія 88–96%. Хто завантажив — майже стовідсотково реєструється.
  
**Висновок:** Проблема на першому кроці воронки. Варто оптимізувати сторінку в App Store / Google Play (скріншоти, опис, рейтинг, розмір додатка).
 
### 3. Meta витрачає в ~3.3× більше за TikTok і Google. Чи виправдано це?
 
**Так.** Meta при бюджеті ~$62K утримує найнижчу вартість залучення ($3.86) — класичний приклад успішного масштабування каналу.
 
### 4. LTV/CAC — який канал найприбутковіший?
 
| Канал | LTV/CAC | Статус |
|-------|---------|--------|
| Meta | 1.61 | ✅ Прибутковий |
| TikTok | 1.58 | ✅ Прибутковий |
| Google | 0.88 | ⚠️ Збитковий |
 
**Найприбутковіший канал — Meta (1.61)**, хоча TikTok зовсім поруч (1.58).
 
> ⚠️ **Google працює в мінус:** витрачаємо на залучення $14.12, а користувач приносить $12.40. Збиток $1.72 з кожного юзера. Цей канал потрібно оптимізувати або перерозподілити його бюджет на Meta/TikTok.
 
---
 
## 04. Висновки та рекомендації
 
1. **Meta — масштабувати.** Найнижчий CAC і найвищий LTV/CAC. Збільшення бюджету Meta — пріоритет.
2. **Google — оптимізувати або скорочувати.** LTV/CAC < 1 означає збитки на кожному залученому користувачі. Варто або переглянути таргетинг/креативи, або перерозподілити бюджет.
3. **TikTok — тестувати масштабування.** Найвищий CTR (1.5%) і LTV/CAC майже на рівні Meta. Є потенціал.
4. **Фокус продуктової команди — App Store/Google Play.** Конверсія Клік→Інстал 30–40% — це головна проблема воронки. Оптимізація ASO може дати більший ефект, ніж зміни в рекламі. 
