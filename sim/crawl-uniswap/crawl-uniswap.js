"use strict";
Error.stackTraceLimit = 10000;

const ethers = require('ethers');
const betterSqlite3 = require('better-sqlite3');
const fetch = require('cross-fetch');


// Config

let rpcUrl = process.env.RPC_URL;
let batchSize = 2000;
let crawlDelaySeconds = 1;

let startBlock = 12369621; // Uniswap 3 factory deployed: May-04-2021 07:27:00 PM +UTC
let endBlock = 14843012; // Arbitrary end-point: May-25-2022 04:58:50 PM +UTC

let uniswapFactoryAddr = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
let quoteToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'; // WETH

let toks = {
    WETH: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
    USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
    DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
    UNI: '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984',
    MKR: '0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2',
    WBTC: '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599',
    FRAX: '0x853d955acef822db058eb8505911ed77f175b99e',
};

let pairsToCrawl = [
    "USDC/WETH/3000",
    "DAI/WETH/3000",
    "DAI/USDC/100",
    "UNI/WETH/3000",
    "MKR/WETH/3000",
    "FRAX/USDC/500",
    "WBTC/WETH/3000",
];

// End of config



let factoryIface = new ethers.utils.Interface([
    'function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool)',
]);


let pairIface = new ethers.utils.Interface([
    'event Swap(address indexed sender, address indexed recipient, int256 amount0, int256 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick)',
]);


const db = new betterSqlite3('./results.db');

db.pragma('encoding = "UTF-8"');
db.pragma('foreign_keys = ON');
db.pragma('defer_foreign_keys = ON');


let uniswapPoolAddrToPair = {};



let provider = new ethers.providers.JsonRpcProvider(rpcUrl);



main();

async function main() {
    await populateTokenAddrs();
    await crawl();
}




async function populateTokenAddrs() {
    console.log(`Looking up ${pairsToCrawl.length} pairs`);

    let uniswapFactory = new ethers.Contract(uniswapFactoryAddr, factoryIface, provider);

    let skipped = 0;
    let lookedUp = 0;

    for (let pairName of pairsToCrawl) {
        let row = db.prepare(`SELECT name, uniswapPoolAddr FROM Pair WHERE name = ?`)
                    .get(pairName);

        let pair = unpackPairToCrawl(pairName);

        if (row) {
            uniswapPoolAddrToPair[row.uniswapPoolAddr] = pair;
            console.log(`${pairName} already in DB`);
            skipped++;
            continue;
        }

        lookedUp++;

        let uniswapPoolAddr = await uniswapFactory.getPool(pair.baseAddr, pair.quoteAddr, pair.fee);
        uniswapPoolAddr = uniswapPoolAddr.toLowerCase();
        uniswapPoolAddrToPair[uniswapPoolAddr] = pair;

        console.log(`${pairName}: Uniswap pair=${uniswapPoolAddr}`);

        db.prepare('INSERT OR REPLACE INTO Pair (name, uniswapPoolAddr) VALUES (?,?)')
          .run(pairName, uniswapPoolAddr);
    }


    console.log(`Looked up ${lookedUp}/${skipped+lookedUp} tokens`);
}



async function crawl() {
    {
        let highestBlock = db.prepare(`SELECT MAX(blockNumber) FROM Swap`).pluck().get();
        if (highestBlock && highestBlock > startBlock) {
            startBlock = highestBlock + 1;
        }

        console.log(`startBlock = ${startBlock}`);
    }


    let currBlock = startBlock;

    while (currBlock <= endBlock) {
        let rangeEnd = currBlock + batchSize - 1;
        if (rangeEnd > endBlock) rangeEnd = endBlock;

        console.log(`Fetching blocks: ${currBlock} - ${rangeEnd}`);

        let params = [{
            fromBlock: '0x' + currBlock.toString(16),
            toBlock: '0x' + rangeEnd.toString(16),

            address: Object.keys(uniswapPoolAddrToPair),
            topics: [pairIface.getEventTopic('Swap')],
        }];

        let query = {
            jsonrpc: "2.0",
            id: 1,
            method: "eth_getLogs",
            params,
        };

        let res = await fetch(rpcUrl, {
                            method: 'post',
                            body: JSON.stringify(query),
                            headers: { 'Content-Type': 'application/json' },
                        });

        let resJson = await res.json();
        if (resJson.error) {
            console.error(`ERROR from eth_getLogs. Response:`);
            console.error(resJson);
            console.error(`Request params:`);
            console.error(params);
            process.exit(1);
        }

        // Add Swap records
        //console.log("RES" + JSON.stringify(resJson));

        db.transaction(() => {
            for (let log of resJson.result) {
                let pair = uniswapPoolAddrToPair[log.address.toLowerCase()];

                //console.log(log);
                
                let parsedLog = pairIface.parseLog(log);

                //console.log(parsedLog);

                db.prepare(`INSERT OR REPLACE INTO Swap (pairName, blockNumber, logIndex, tick, sqrtPriceX96)
                            VALUES (?, ?, ?, ?, ?)`)
                  .run(pair.name,
                       parseInt(log.blockNumber, 16),
                       parseInt(log.logIndex, 16),
                       parsedLog.args.tick,
                       parsedLog.args.sqrtPriceX96.toString());
            }
        })();


        currBlock += batchSize;
        await delay(1000 * crawlDelaySeconds);
    }
}



//////

async function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function getCurrTimeMilliseconds() {
    return (new Date()).getTime();
}

function unpackPairToCrawl(pair) {
    let p = pair.split("/");

    let o = {
        name: pair,
        base: p[0],
        quote: p[1],
        baseAddr: toks[p[0]],
        quoteAddr: toks[p[1]],
        fee: parseInt(p[2]),
    };

    if (!o.baseAddr) throw(`Couldn't lookup ${p[0]}`);
    if (!o.quoteAddr) throw(`Couldn't lookup ${p[0]}`);

    return o;
}
