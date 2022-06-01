const betterSqlite3 = require('better-sqlite3');

let pool = 'USDC/WETH/3000';
let ringSize = 144;
let windowSize = 1800;

// Around the crash
let blockFrom = 14735000; // May-08-2022 08:27:41 AM +UTC
let blockTo = 14775000; // May-14-2022 05:49:46 PM +UTC

// "Normal" period
//let blockFrom = 14595000;
//let blockTo = 14635000;

//let blockFrom = 14760000; // May-12-2022 08:16:38 AM +UTC
//let blockTo = 14765000; // May-13-2022 03:24:18 AM +UTC

let priceInvert = true;
let decimalScaler = 1e12; // USDC
//let decimalScaler = 1e0; // normal
let minTimeStep = 60*15;


task("sim")
    .setAction(async ({ args, }) => {

    await hre.run("compile");

    const db = new betterSqlite3('./sim/crawl-uniswap/results.db');

    db.pragma('encoding = "UTF-8"');
    db.pragma('foreign_keys = ON');
    db.pragma('defer_foreign_keys = ON');

    let blocks = db.prepare(`SELECT s.tick, s.blockNumber, s.sqrtPriceX96, b.timestamp
                             FROM Swap s, Block b
                             WHERE s.pairName = ?
                             AND s.blockNumber = b.blockNumber
                             AND s.blockNumber>? AND s.blockNumber<?
                             ORDER BY s.blockNumber ASC, s.logIndex ASC`)
                   .all(pool, blockFrom, blockTo);

    console.log("ORIG BLOCKS = ", blocks.length);

    // Populate empty spans of time with data so moving averages look smooth, medians update, etc

    if (minTimeStep) {
        let newBlocks = [];
        newBlocks.push(blocks[0]);

        for (let i = 1; i < blocks.length; i++) {
            while (blocks[i].timestamp - newBlocks[newBlocks.length - 1].timestamp > minTimeStep) {
                newBlocks.push({
                    tick: newBlocks[newBlocks.length - 1].tick,
                    sqrtPriceX96: newBlocks[newBlocks.length - 1].sqrtPriceX96,
                    timestamp: newBlocks[newBlocks.length - 1].timestamp + minTimeStep,
                    virtualBlock: true,
                });
            }

            newBlocks.push(blocks[i]);
        }

        blocks = newBlocks;
    }

    // Only apply last in block, since we are increasing timestamp by 1 every time

    {
        let newBlocks = [];

        for (let i = 1; i < blocks.length - 1; i++) {
            if (blocks[i].blockNumber === blocks[i+1].blockNumber) continue;
            newBlocks.push(blocks[i]);
        }

        blocks = newBlocks;
    }

    console.log("POST-PROC BLOCKS = ", blocks.length);

    let oracle;

    let mode = process.env.MODE || 'median';

    if (mode === "uniswap") {
        const factory = await ethers.getContractFactory("StubUniswapV3Pool");
        oracle = await factory.deploy(ringSize);
        await oracle.deployed();
    } else if (mode === 'median') {
        const factory = await ethers.getContractFactory("MedianOracle");
        oracle = await factory.deploy(ringSize);
        await oracle.deployed();
    } else {
        throw("unrecognized mode: ", mode);
    }

    await (await oracle.updateOracle(blocks[0].tick)).wait();

    let ts = (await ethers.provider.getBlock()).timestamp + 86400;
    await ethers.provider.send("evm_setNextBlockTimestamp", [ts]);
    await ethers.provider.send("evm_mine");

    let gases = [];

    for (let i = 1; i < blocks.length; i++) {
        if ((i % 100) === 1) console.error(`${i}/${blocks.length} (${100*i/blocks.length}%)`);

        let delay = blocks[i].timestamp - blocks[i-1].timestamp;
        ts += delay;
        if (delay > 0) await ethers.provider.send("evm_setNextBlockTimestamp", [ts]);

        console.log(`DELAY ${delay} / PRICE ${blocks[i].tick}`);
        if (blocks[i].tick) {
            await (await oracle.updateOracle(blocks[i].tick)).wait();
        } else {
            await ethers.provider.send("evm_mine");
        }

        let res;
        let gas;

        try {
            gas = (await oracle.estimateGas.readOracle(windowSize)).toNumber() - 21_000;
            console.log(`${i} GAS`,gas);
            gases.push(gas);

            res = await oracle.readOracle(windowSize);
            console.log(`${i} RES`,res);
        } catch(e) {
            console.log(`SKIPPING ERR: ${e}`);
            continue;
        }

        let tickToPrice = (p) => {
            let o = Math.pow(1.0001, p) / decimalScaler;
            if (priceInvert) o = 1/o;
            return o;
        };

        let sqrtPriceX96ToPrice = (p) => {
            p = parseInt(p);
            let o = p*p/(2**(96*2)) / decimalScaler;
            if (priceInvert) o = 1/o;
            return o;
        };

        let requantisedTick = tickToPrice(Math.floor(blocks[i].tick / 30) * 30 + 15);

        console.log(`csv,${blocks[i].timestamp},${res[1]},${tickToPrice(blocks[i].tick)},${tickToPrice(res[1])},${tickToPrice(res[2])},${sqrtPriceX96ToPrice(blocks[i].sqrtPriceX96)},${requantisedTick},${gas}`);
    }

    console.error(`MIN GAS: ${Math.min.apply(null, gases)}`);
    console.error(`MAX GAS: ${Math.max.apply(null, gases)}`);
    console.error(`AVG GAS: ${avg(gases)}`);
});

function avg(arr) {
    let sum = 0;
    for (let n of arr) sum += n;
    return sum / arr.length;
}
