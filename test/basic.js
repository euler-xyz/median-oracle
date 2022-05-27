const { expect } = require("chai");
const seedrandom = require("seedrandom");

describe("median oracle tests", function () {
    it("quantisation", async function () {
        const [owner] = await ethers.getSigners();

        let MedianOracleFactory = await ethers.getContractFactory("MedianOracle");

        let oracle = await MedianOracleFactory.deploy(144);

        let ts = (await ethers.provider.getBlock()).timestamp;
        let origTs = ts;

        let TICK_MAX = 887272;
        let TICK_MIN = -887272;

        let checkTick = async (tickIn, tickOut) => {
            let tx = await oracle.updateOracle(tickIn);
            await tx.wait();

            ts += 2000;
            await ethers.provider.send("evm_setNextBlockTimestamp", [ts]);
            await ethers.provider.send("evm_mine");

            let res = await oracle.readOracle(1800);

            expect(res[0]).to.equal(tickOut);
            expect(res[0]).to.be.gte(TICK_MIN);
            expect(res[0]).to.be.lte(TICK_MAX);
        };

        await checkTick(0, 15);
        await checkTick(1, 15);
        await checkTick(15, 15);
        await checkTick(29, 15);
        await checkTick(30, 45);
        await checkTick(59, 45);
        await checkTick(60, 75);

        await checkTick(-1, -15);
        await checkTick(-2, -15);
        await checkTick(-15, -15);
        await checkTick(-29, -15);
        await checkTick(-30, -15);
        await checkTick(-31, -45);
        await checkTick(-60, -45);
        await checkTick(-61, -75);

        await checkTick(TICK_MAX, 887265);
        await checkTick(TICK_MIN, -887265);
    });

    it("fuzz", async function () {
        const [owner] = await ethers.getSigners();

        let MedianOracleFactory = await ethers.getContractFactory("MedianOracle");

        let oracle = await MedianOracleFactory.deploy(144);

        let ts = (await ethers.provider.getBlock()).timestamp;
        let origTs = ts;

        let rng = seedrandom('');

        let updates = [];

        let seen = 0;

        while (seen < 100) {
            let duration = Math.floor(rng() * 30) + 1;
            ts += duration;
            await ethers.provider.send("evm_setNextBlockTimestamp", [ts]);

            if (updates.length > 0) updates[updates.length - 1].duration += duration;

            {
                let price = Math.floor((rng() * 10_000) - 0);

                updates.push({
                    price,
                    duration: 0,
                });

                let tx = await oracle.updateOracle(price);
                await tx.wait();
            }

            const windowLen = 1800;

            let res = await oracle.readOracle(windowLen);

            // Check result

            let arr = [];

            for (let i = updates.length - 1; i >= 0; i--) {
                //if (updates[i].duration) console.log("ZZ",[Math.floor(updates[i].price/30), Math.min(updates[i].duration, windowLen - arr.length)]);
                for (let j = 0; j < updates[i].duration; j++) {
                    arr.push(updates[i].price);
                    if (arr.length === windowLen) break;
                }
                if (arr.length === windowLen) break;
            }

            arr.sort((a,b) => Math.sign(a-b));

            let median = arr[Math.ceil(windowLen/2) - 1];
            median = Math.floor(median / 30) * 30 + 15;

            if (process.env.VERBOSE) {
                console.log("------------");
                console.log("SEEN", seen);
                console.log("RES", res);
                console.log("MEDIAN=",median);
                console.log("AL=",arr.length);
                console.log("RES=",res[0]);
            }

            if (arr.length === windowLen) {
                seen++;

                if (res[0] !== median) {
                    console.log("DIFFERENT",res[0],median);
                    throw("DIFFERENT");
                }
            }
        }
    });
});
