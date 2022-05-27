// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './Oracle.sol';

contract StubUniswapV3Pool {
    using Oracle for Oracle.Observation[65535];

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;

    Oracle.Observation[65535] public observations;

    constructor(uint16 _ringSize) {
        int24 tick = 0;

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        slot0 = Slot0({
            sqrtPriceX96: 0,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

        // Grow to 144

        uint16 observationCardinalityNext = _ringSize;

        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext; // for the event
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);
        slot0.observationCardinalityNext = observationCardinalityNextNew;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }

    function updateOracle(int24 newTick) external {
        Slot0 memory slot0Start = slot0;

        (uint16 observationIndex, uint16 observationCardinality) =
            observations.write(
                slot0Start.observationIndex,
                _blockTimestamp(),
                slot0Start.tick,
                0,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
        (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
            0,
            newTick,
            observationIndex,
            observationCardinality
        );
    }

    function readOracle(uint16 desiredAge, uint)
        external
        view
        returns (int24, uint16)
    {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = desiredAge;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) =
            observations.observe(
                _blockTimestamp(),
                secondsAgos,
                slot0.tick,
                slot0.observationIndex,
                0,
                slot0.observationCardinality
            );

        return (
            int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int(desiredAge))),
            desiredAge
        );
    }
}
