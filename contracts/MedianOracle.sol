// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MedianOracle {
    int24 constant TICK_TRUNCATION = 30;
    uint[8192] ringBuffer;

    int24 public currTick;
    uint16 public ringCurr;
    uint16 public ringSize;
    uint64 public lastUpdate;

    constructor(uint16 _ringSize) {
        ringCurr = 0;
        ringSize = _ringSize;
        lastUpdate = uint64(block.timestamp);
    }

    function updateOracle(int24 newTick) external {
        unchecked {
            int24 _currTick = currTick;
            uint16 _ringCurr = ringCurr;
            uint16 _ringSize = ringSize;
            uint64 _lastUpdate = lastUpdate;

            if (newTick == _currTick) return;

            uint elapsed = block.timestamp - _lastUpdate;

            int16 qCurrTick = quantiseTick(_currTick);

            if (elapsed != 0) {
                (int16 prevTick, uint16 prevDuration) = readRing(_ringCurr);

                if (prevTick == qCurrTick) elapsed += prevDuration;
                else _ringCurr = (_ringCurr + 1) % _ringSize;

                writeRing(_ringCurr, qCurrTick, clampTime(elapsed));
            }

            currTick = newTick;
            ringCurr = _ringCurr;
            ringSize = _ringSize;
            lastUpdate = uint64(block.timestamp);
        }
    }

    function readOracle(uint16 desiredAge) external view returns (int24, uint16) { // returns (tick, actualAge)
        unchecked {
            int24 _currTick = currTick;
            uint16 _ringCurr = ringCurr;
            uint16 _ringSize = ringSize;
            uint cache = lastUpdate; // stores lastUpdate for first part of function, but then overwritten and used for something else

            uint[] memory arr;
            uint16 actualAge = 0;

            // Load ring buffer entries into memory

            {
                uint arrSize = 0;
                uint256 freeMemoryPointer;
                assembly {
                    arr := mload(0x40)
                    freeMemoryPointer := add(arr, 0x20)
                }

                // Populate first element in arr with current tick, if any time has elapsed since current tick was set

                {
                    uint16 duration = clampTime(block.timestamp - cache);

                    if (duration != 0) {
                        if (duration > desiredAge) duration = desiredAge;
                        actualAge += duration;

                        uint packed = memoryPackTick(quantiseTick(_currTick), duration);

                        assembly {
                            mstore(freeMemoryPointer, packed)
                            freeMemoryPointer := add(freeMemoryPointer, 0x20)
                        }
                        arrSize++;
                    }
                }

                // Continue populating elements until we have satisfied desiredAge

                {
                    uint i = _ringCurr;
                    cache = type(uint).max; // overwrite lastUpdate, use to cache storage reads

                    while (actualAge != desiredAge) {
                        int16 tick;
                        uint16 duration;

                        {
                            if (cache == type(uint).max) cache = ringBuffer[i / 8];
                            uint entry = cache >> (32 * (i % 8));
                            tick = int16(uint16((entry >> 16) & 0xFFFF));
                            duration = uint16(entry & 0xFFFF);
                        }

                        if (duration == 0) break; // uninitialised

                        if (actualAge + duration > desiredAge) duration = desiredAge - actualAge;
                        actualAge += duration;

                        uint packed = memoryPackTick(tick, duration);

                        assembly {
                            mstore(freeMemoryPointer, packed)
                            freeMemoryPointer := add(freeMemoryPointer, 0x20)
                        }
                        arrSize++;

                        if (i & 7 == 0) cache = type(uint).max;

                        i = (i + _ringSize - 1) % _ringSize;
                        if (i == _ringCurr) break; // wrapped back around
                    }

                    assembly {
                        mstore(arr, arrSize)
                        mstore(0x40, freeMemoryPointer)
                    }
                }
            }

            return (
                unQuantiseTick(int(weightedMedian(arr, actualAge / 2) >> 16) - 32768),
                actualAge
            );
        }
    }

    // QuickSelect, modified to account for item weights

    function weightedMedian(uint[] memory arr, uint targetWeight) private pure returns (uint) {
        unchecked {
            uint weightAccum = 0;
            uint left = 0;
            uint right = arr.length - 1;

            while (true) {
                if (left == right) return memload(arr, left);

                uint pivot = memload(arr, (left + right) / 2);
                uint i = left - 1;
                uint j = right + 1;

                while (true) {
                    do ++i; while (memload(arr, i) < pivot);
                    do --j; while (memload(arr, j) > pivot);

                    if (i >= j) break;

                    memswap(arr, i, j);
                }

                uint leftWeight = 0;

                for (uint n = left; n <= j; ++n) {
                    leftWeight += memload(arr, n) & 0xFFFF;
                }

                if (weightAccum + leftWeight >= targetWeight) {
                    right = j;
                } else {
                    weightAccum += leftWeight;
                    left = j + 1;
                }
            }
        }

        assert(false);
        return 0;
    }

    // Array access without bounds checking

    function memload(uint[] memory arr, uint i) private pure returns (uint ret) {
        assembly {
            ret := mload(add(add(arr, 32), mul(i, 32)))
        }
    }

    // Swap two items in array without bounds checking

    function memswap(uint[] memory arr, uint i, uint j) private pure {
        assembly {
            let offset := add(arr, 32)
            let tp := mload(add(offset, mul(i, 32)))
            mstore(add(offset, mul(i, 32)), mload(add(offset, mul(j, 32))))
            mstore(add(offset, mul(j, 32)), tp)
        }
    }

    function writeRing(uint index, int16 tick, uint16 duration) private {
        unchecked {
            uint packed = (uint(uint16(tick)) << 16) | duration;

            uint shift = (32 * (index % 8));
            ringBuffer[index / 8] = (ringBuffer[index / 8] & ~(0xFFFFFFFF << shift))
                                    | (packed << shift);
        }
    }

    function readRing(uint index) public view returns (int16, uint16) {
        unchecked {
            uint entry = ringBuffer[index / 8] >> (32 * (index % 8));
            return (int16(uint16((entry >> 16) & 0xFFFF)), uint16(entry & 0xFFFF));
        }
    }

    function clampTime(uint t) private pure returns (uint16) {
        unchecked {
            return uint16(t > type(uint16).max ? type(uint16).max : t);
        }
    }

    function quantiseTick(int24 tick) private pure returns (int16) {
        unchecked {
            return int16((tick + (tick < 0 ? -(TICK_TRUNCATION-1) : int24(0))) / TICK_TRUNCATION);
        }
    }

    function unQuantiseTick(int tick) private pure returns (int24) {
        unchecked {
            return int24(tick) * TICK_TRUNCATION + (TICK_TRUNCATION/2);
        }
    }

    function memoryPackTick(int16 tick, uint16 duration) private pure returns (uint) {
        unchecked {
            return (uint(int(tick) + 32768) << 16) | duration;
        }
    }
}
