-- =============================================================================
-- SaaS Churn Diagnostic Dashboard - SQL Queries
-- =============================================================================
-- Author: Nikhil Data Analytics
-- Date: January 2026
-- Purpose: Extract churn metrics, segment analysis, and retention signals
-- =============================================================================

-- QUERY 1: Overall Churn Metrics
-- Calculates company-wide churn rate, MRR lost, and lifetime values
-- =============================================================================

WITH account_lifetime AS (
  SELECT 
    a.account_id,
    a.industry,
    a.signup_date,
    a.plan_tier,
    ce.churn_date,
    
    -- Churned if ce.churn_date is NOT NULL
    CASE 
      WHEN ce.churn_date IS NOT NULL 
        THEN DATEDIFF(ce.churn_date, a.signup_date)
      ELSE 
        DATEDIFF(CURDATE(), a.signup_date) 
    END AS lifetime_days,
    
    -- Flag: Is this account churned?
    CASE 
      WHEN ce.churn_date IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_churned,
    
    COALESCE(SUM(s.mrr_amount), 0) AS total_mrr
    
  FROM saas_accounts a
  LEFT JOIN churn_events ce 
    ON a.account_id = ce.account_id
  LEFT JOIN saas_subscriptions s
    ON a.account_id = s.account_id
  
  GROUP BY a.account_id, a.signup_date, ce.churn_date, a.industry, a.plan_tier
)

SELECT 
  'Overall' AS segment,
  COUNT(*) AS total_accounts,
  SUM(CASE WHEN is_churned = TRUE THEN 1 ELSE 0 END) AS churned_accounts,
  ROUND(
    100.0 * SUM(CASE WHEN is_churned = TRUE THEN 1 ELSE 0 END) 
    / COUNT(*), 
    2
  ) as churn_rate_pct,
  ROUND(AVG(CASE WHEN is_churned = TRUE THEN lifetime_days END), 0) 
    as avg_lifetime_days_churned,
  ROUND(AVG(CASE WHEN is_churned = FALSE THEN lifetime_days END), 0) 
    as avg_lifetime_days_active,
  ROUND(SUM(CASE WHEN is_churned = TRUE THEN total_mrr END), 2) 
    as total_mrr_lost
FROM account_lifetime
GROUP BY segment;


-- =============================================================================
-- QUERY 2: Churn by Segment (Industry & Plan Tier)
-- Identifies which segments have highest churn rates
-- =============================================================================

WITH account_lifetime AS (
  SELECT 
    a.account_id,
    a.industry,
    a.plan_tier,
    a.signup_date,
    ce.churn_date,
    
    CASE 
      WHEN ce.churn_date IS NOT NULL 
        THEN DATEDIFF(ce.churn_date, a.signup_date)
      ELSE 
        DATEDIFF(CURDATE(), a.signup_date) 
    END AS lifetime_days,
    
    CASE 
      WHEN ce.churn_date IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_churned,
    
    COALESCE(SUM(s.mrr_amount), 0) AS total_mrr
    
  FROM saas_accounts a
  LEFT JOIN churn_events ce 
    ON a.account_id = ce.account_id
  LEFT JOIN saas_subscriptions s
    ON a.account_id = s.account_id
  
  GROUP BY a.account_id, a.signup_date, ce.churn_date, a.industry, a.plan_tier
)

SELECT 
  a.industry,
  a.plan_tier,
  COUNT(*) AS total_accounts,
  SUM(CASE WHEN is_churned = TRUE THEN 1 ELSE 0 END) AS churned_accounts,
  ROUND(
    100.0 * SUM(CASE WHEN is_churned = TRUE THEN 1 ELSE 0 END) 
    / COUNT(*), 
    2
  ) as churn_rate_pct,
  ROUND(AVG(CASE WHEN is_churned = TRUE THEN lifetime_days END), 0) 
    as avg_lifetime_days_churned,
  ROUND(AVG(CASE WHEN is_churned = FALSE THEN lifetime_days END), 0) 
    as avg_lifetime_days_active,
  ROUND(SUM(CASE WHEN is_churned = TRUE THEN total_mrr END), 2) 
    as total_mrr_lost

FROM account_lifetime a
GROUP BY a.industry, a.plan_tier
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 3: Churn Reasons Analysis
-- Identifies top reasons customers churn and associated costs
-- =============================================================================

SELECT 
  ce.reason_code,
  COUNT(*) as churn_count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM churn_events), 2) as pct_of_total_churn,
  ROUND(AVG(ce.refund_amount_usd), 2) as avg_refund,
  COUNT(DISTINCT ce.account_id) as unique_accounts
FROM churn_events ce
GROUP BY ce.reason_code
ORDER BY churn_count DESC;


-- =============================================================================
-- QUERY 4: Feature Adoption vs Churn
-- Shows if low feature adoption predicts churn
-- Churned customers use fewer features = engagement is early warning signal
-- =============================================================================

WITH user_features AS (
  SELECT 
    s.account_id,
    CASE 
      WHEN ce.churn_date IS NOT NULL THEN 'Churned'
      ELSE 'Active'
    END as customer_status,
    COUNT(DISTINCT fu.feature_name) as unique_features_used,
    SUM(fu.usage_count) as total_usage_count,
    AVG(fu.usage_count) as avg_usage_per_feature
  FROM saas_subscriptions s
  LEFT JOIN churn_events ce ON s.account_id = ce.account_id
  LEFT JOIN feature_usage fu ON s.subscription_id = fu.subscription_id
  GROUP BY s.account_id, customer_status
)

SELECT 
  customer_status,
  COUNT(*) as num_customers,
  ROUND(AVG(unique_features_used), 2) as avg_features_used,
  ROUND(AVG(total_usage_count), 0) as avg_total_usage,
  ROUND(AVG(avg_usage_per_feature), 2) as avg_usage_per_feature
FROM user_features
GROUP BY customer_status;


-- =============================================================================
-- BONUS QUERY: Early Engagement Predictors
-- Identifies customers at risk of churning based on first 30 days activity
-- =============================================================================

WITH first_month_activity AS (
  SELECT 
    a.account_id,
    a.industry,
    a.signup_date,
    ce.churn_date,
    COUNT(DISTINCT CAST(fu.usage_date AS DATE)) as days_active_first_month,
    COUNT(DISTINCT fu.feature_name) as unique_features_first_month,
    SUM(fu.usage_count) as total_usage_first_month,
    COUNT(DISTINCT st.ticket_id) as support_tickets_first_month,
    
    CASE 
      WHEN ce.churn_date IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_churned
    
  FROM saas_accounts a
  LEFT JOIN feature_usage fu 
    ON a.account_id = fu.account_id
    AND DATEDIFF(fu.usage_date, a.signup_date) <= 30
  LEFT JOIN support_tickets st 
    ON a.account_id = st.account_id
    AND DATEDIFF(st.created_date, a.signup_date) <= 30
  LEFT JOIN churn_events ce 
    ON a.account_id = ce.account_id
    
  GROUP BY a.account_id, a.industry, a.signup_date, ce.churn_date
)

SELECT 
  industry,
  is_churned,
  COUNT(*) as customer_count,
  ROUND(AVG(days_active_first_month), 1) as avg_days_active,
  ROUND(AVG(unique_features_first_month), 1) as avg_features_used,
  ROUND(AVG(total_usage_first_month), 0) as avg_total_usage,
  ROUND(AVG(support_tickets_first_month), 1) as avg_support_tickets
FROM first_month_activity
GROUP BY industry, is_churned
ORDER BY industry, is_churned DESC;




