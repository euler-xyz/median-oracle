## Configuration

* Uniswap pairs to crawl: `sim/crawl-uniswap/crawl-uniswap.js`
* Simulation parameters: `tasks/sim.js`
* Plot parameters: `sim/plot.gnu`

## Crawl Uniswap logs data

In `sim/crawl-uniswap/` directory:

    sqlite3 results.db < schema.sql
    RPC_URL=https://REPLACE_ME node crawl-uniswap.js

## Import BigQuery logs

On google BigQuery, run the following query to get block timestamps, and export results as CSV:

    SELECT number,timestamp FROM `bigquery-public-data.crypto_ethereum.blocks` WHERE number >= 12369621

Import block timestamps into DB:

    perl import-bigquery.pl < bq-results-20220526-103739-1653561636441.csv

## Run simulation

In top-level directory:

    npx hardhat sim | grep ^csv | > median.csv
    MODE=uniswap npx hardhat sim | grep ^csv | > uniswap.csv

## Plot results

    gnuplot sim/plot.gnu
