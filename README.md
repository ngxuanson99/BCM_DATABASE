# BCM Nexus — Data Pipeline

Turns raw Magento e-commerce data into a clean, reporting-ready star schema for Power BI — no coding experience required.

This repository contains two SQL scripts that, together, take your Magento store's data and turn it into six clean tables ready to connect to Power BI (or any other BI tool).

---

## What this does

| Stage | Script | What happens |
|---|---|---|
| 1 | `01_extraction.sql` | Copies the relevant tables from your live Magento database into an isolated working database — a safe, untouched copy. |
| 2 | `02_pipeline.sql` | Flattens that raw data, cleans it up, and builds the final six reporting tables (a "star schema") ready for Power BI. |

You do not need to understand SQL to use this — just follow the steps below.

---

## Before you start

You will need:

- Access to **phpMyAdmin** (or another MySQL admin tool) for the server hosting your Magento database
- Permission to **create new databases**
- A text editor to open the `.sql` files (e.g. **VS Code**, Notepad++, or even Notepad)

You will be creating **two new, empty databases**:

1. A database to hold the raw copy of your Magento data (referred to below as your **source database**)
2. A database to hold the staging and final reporting tables (referred to below as your **staging database**)

> You can name these anything you like — just remember what you named them, since you'll need to type them in Step 2 below.
> Suggested names: `bcm_nexus_raw` and `bcm_nexus_staging`

---

## Setup — Step by Step

### Step 1 — Create your two databases

In phpMyAdmin, create two new, empty databases (see naming suggestion above).

### Step 2 — Prepare the pipeline script (one-time text replacement)

Open `02_pipeline.sql` in a text editor. Near the top of the file, you'll see two placeholder names used throughout:

- `SOURCE_DB`
- `STAGING_DB`

Using **Find & Replace** (`Ctrl+H` in most editors, including VS Code):
p/s: you can also keep these two name if it's easy to understand for you

1. Replace every `STAGING_DB` with the name of the staging database you created in Step 1
2. Replace every `SOURCE_DB` with the name of the source database you created in Step 1

Save the file once both replacements are done.

> **Tip:** Replace `STAGING_DB` first, then `SOURCE_DB` — this avoids issues if your chosen names happen to overlap with each other.

### Step 3 — Run the extraction script

1. Open `01_extraction.sql`
2. In phpMyAdmin, select your **source database** (the one you created for the raw Magento copy)
3. Go to the **SQL** tab, paste in the entire contents of `01_extraction.sql`, and click **Go**

This copies the relevant Magento tables into your source database. Nothing is changed in your live Magento database — this is a one-way copy.

### Step 4 — Run the pipeline script

1. Open your edited `02_pipeline.sql` (from Step 2 — the one with your database names already filled in)
2. In phpMyAdmin, go to the **SQL** tab (it doesn't matter which database is currently selected, since the script specifies both database names directly)
3. Paste in the entire contents and click **Go**

This builds the staging tables, then the final six reporting tables, inside your staging database.

### Step 5 — Verify it worked

In phpMyAdmin, open your staging database and confirm you can see these six tables:

- `bcm_dim_customers`
- `bcm_dim_products`
- `bcm_dim_categories`
- `bcm_fact_orders`
- `bcm_fact_order_items`
- `bcm_bridge_product_category`

Click into any of them and confirm they contain data.

---

## Connecting to Power BI

1. Open Power BI Desktop → **Get Data** → **MySQL database**
2. **Server:** your MySQL server address (e.g. `localhost`)
3. **Database:** your staging database name
4. Choose **Import** as the connectivity mode
5. In the Navigator window, select only the six tables listed above (do **not** import any table starting with `bcm_stg_` — those are working tables, not meant for reporting)
6. Click **Load**

---

## Re-running the pipeline (refreshing your data)

Whenever your Magento data changes and you want the reporting tables refreshed, simply repeat **Step 3** and **Step 4** above. Both scripts are safe to run again — they automatically clear out old tables before rebuilding them, so there's no risk of duplicate data.

---

## Database Structure

*(Diagrams to be added — see `/docs` folder)*

- **Entity Relationship Diagram (raw Magento tables):** `docs/erd_magento_raw.png`
- **Star Schema Diagram (final reporting tables):** `docs/erd_star_schema.png`

<!--
Add images here once available, for example:
![Magento Raw ERD](docs/erd_magento_raw.png)
![Star Schema ERD](docs/erd_star_schema.png)
-->

---

## Project Structure

```
bcm-nexus-pipeline/
├── README.md                  ← this file
├── 01_extraction.sql          ← raw Magento table copy
├── 02_pipeline.sql            ← staging + star schema build
└── docs/
    ├── erd_magento_raw.png    ← (to be added)
    └── erd_star_schema.png    ← (to be added)
```

---

## Understanding the Output

### Staging tables (`bcm_stg_*`)
Intermediate working tables. Flattened and cleaned, but not yet part of the final reporting model. Not meant to be connected to Power BI directly.

### Dimension tables (`bcm_dim_*`)
Descriptive reference tables — customers, products, categories. Each row has a unique internal ID (a "surrogate key") used to connect it to the fact tables.

### Fact tables (`bcm_fact_*`)
The measurable events — orders and order line items — linked back to the dimension tables via their surrogate keys.

### Bridge table (`bcm_bridge_product_category`)
Links products to categories. Kept separate because a single product can belong to more than one category.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| `Unknown database 'SOURCE_DB'` or `'STAGING_DB'` | You ran the script without completing Step 2 (Find & Replace) | Go back to Step 2 and make sure every placeholder has been replaced |
| `Table already exists` | Rare — normally handled automatically | Re-run the script; it drops old tables before rebuilding them |
| A dimension/fact table looks empty | The extraction step (Step 3) may not have completed successfully | Re-run `01_extraction.sql` and check for error messages, then re-run `02_pipeline.sql` |
| Reserved word / syntax error | A database or column name matches a MySQL reserved word | Check the exact error message — it will name the offending word |

---

## Notes on Data & Privacy

This pipeline deliberately excludes personally identifiable customer information (names, emails, dates of birth) from the reporting tables, in line with the Australian Privacy Principles. Only high-level attributes needed for business reporting (customer group, account type, shipping region/postcode) are retained.

---

## Questions or Issues

If you run into a problem not covered above, open an issue on this repository or contact the maintainer.
