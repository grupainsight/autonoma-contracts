# Merchant product performance (sql/005)

Weekly paid (ADS) and free (ORGANIC) traffic per offer, from Merchant Reports API v1
`product_performance_view`. Written by Merchant Agent, read by Ads and SEO agents.

## Tables
- `merchant_performance_periods`: one row per client, Merchant account and week (Monday-Sunday).
  It is the **publication record**: a week exists for readers only when this row exists,
  and it names the load (`fetch_id`) whose offer rows are valid. It holds channel totals
  (query without `offer_id`) and the sums of the offer rows of that load.
- `merchant_product_performance`: one row per offer and channel of one load.
- `merchant_product_performance_published` (view): offer rows of published loads only.
  Readers use the view, never the raw table.

Model and helpers: `autonoma_contracts.merchant_performance`.

## Reading rules
1. **Missing row is not zero.** When the API splits traffic by offer it leaves part of it out
   (Piccolo, Oct 2026: 69-84% of impressions per channel visible per offer). Per-offer
   values are a lower bound. Clicks were 100% visible in the tested weeks; this is
   measured every week (`*_clicks_by_offer` vs `*_clicks`), not assumed.
2. **Channel totals and trends** come from the period row, not from summed offer rows.
3. **ADS and ORGANIC are separate.** Do not add them up or interpret them together.
4. **`current_product_url` / `in_current_catalog` are not historical.** They come from the
   catalog snapshot of the load (`catalog_snapshot_date`). A week loaded later shows the
   URL at load time; an offer removed since then has NULL / false.
5. **Identity.** `client_key` = `client_profile.client_key`, resolved with
   `resolve_client_key('merchant_id', ...)`. No write without a resolved key.

## Writing protocol (Merchant Agent)
1. Fetch the whole week (offer query and totals query, paginated). Any API error: nothing is written.
2. Insert the offer rows under a new `fetch_id` (invisible: not published).
3. Publish: insert the period row, or update it **only if its `fetch_id` is still the one read
   before the load** (compare-and-set). If another load published first, this load deletes
   its own rows and stops.
4. Delete the rows of the replaced load (that exact `fetch_id`).
5. Unpublished rows older than one day (a load that stopped part-way) are deleted by the next run.

A load that fails at any step never changes what readers see.

## Retention and loads
Configurable in the agent: weekly job loads the last complete week plus a revision window
(default 2 weeks); history (default 56 weeks) is a separate backfill command; retention
default 60 weeks.
