// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MedianOracle {
    int constant TICK_TRUNCATION = 30;
    uint[8192] ringBuffer;

    int16 public currTick;
    uint16 public ringCurr;
    uint16 public ringSize;
    uint64 public lastUpdate;

    constructor(uint16 _ringSize) {
        ringCurr = 0;
        ringSize = _ringSize;
        lastUpdate = uint64(block.timestamp);
    }

    function updateOracle(int newTick) external {
        require(newTick >= -887272 && newTick <= 887272, "newTick out of range");

        unchecked {
            int _currTick = currTick;
            uint _ringCurr = ringCurr;
            uint _ringSize = ringSize;
            uint _lastUpdate = lastUpdate;

            newTick = quantiseTick(newTick);

            if (newTick == _currTick) return;

            uint elapsed = block.timestamp - _lastUpdate;

            if (elapsed != 0) {
                _ringCurr = (_ringCurr + 1) % _ringSize;
                writeRing(_ringCurr, _currTick, clampTime(elapsed));
            }

            currTick = int16(newTick);
            ringCurr = uint16(_ringCurr);
            ringSize = uint16(_ringSize);
            lastUpdate = uint64(block.timestamp);
        }
    }

    function readOracle(uint desiredAge) external view returns (uint16, int24, int24) { // returns (actualAge, median, average)
        require(desiredAge <= type(uint16).max, "desiredAge out of range");

        unchecked {
            int _currTick = currTick;
            uint _ringCurr = ringCurr;
            uint _ringSize = ringSize;
            uint cache = lastUpdate; // stores lastUpdate for first part of function, but then overwritten and used for something else

            uint[] memory arr;
            uint actualAge = 0;

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
                    uint duration = clampTime(block.timestamp - cache);

                    if (duration != 0) {
                        if (duration > desiredAge) duration = desiredAge;
                        actualAge += duration;

                        uint packed = memoryPackTick(_currTick, duration);

                        assembly {
                            mstore(freeMemoryPointer, packed)
                            freeMemoryPointer := add(freeMemoryPointer, 0x20)
                        }
                        arrSize++;
                    }

                    _currTick = unQuantiseTick(_currTick) * int(duration); // _currTick now becomes the average accumulator
                }

                // Continue populating elements until we have satisfied desiredAge

                {
                    uint i = _ringCurr;
                    cache = type(uint).max; // overwrite lastUpdate, use to cache storage reads

                    while (actualAge != desiredAge) {
                        int tick;
                        uint duration;

                        {
                            if (cache == type(uint).max) cache = ringBuffer[i / 8];
                            uint entry = cache >> (32 * (i % 8));
                            tick = int(int16(uint16((entry >> 16) & 0xFFFF)));
                            duration = entry & 0xFFFF;
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

                        _currTick += unQuantiseTick(tick) * int(duration);

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
                uint16(actualAge),
                int24(unQuantiseTick(unMemoryPackTick(weightedMedian(arr, actualAge / 2)))),
                int24(_currTick / int(actualAge))
            );
        }
    }

    // QuickSelect, modified to account for item weights

    function weightedMedian(uint[] memory arr, uint targetWeight) private pure returns (uint) {
        unchecked {
            uint weightAccum = 0;
            uint left = 0;
            uint right = arr.length - 1;
            uint arrp;

            assembly {
                arrp := add(arr, 32)
            }

            while (true) {
                if (left == right) return memload(arrp, left);

                uint pivot = memload(arrp, (left + right) >> 1);
                uint i = left - 1;
                uint j = right + 1;

                while (true) {
                    do ++i; while (memload(arrp, i) < pivot);
                    do --j; while (memload(arrp, j) > pivot);

                    if (i >= j) break;

                    memswap(arrp, i, j);
                }

                uint leftWeight = 0;

                for (uint n = left; n <= j; ++n) {
                    leftWeight += memload(arrp, n) & 0xFFFF;
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

    function memload(uint arrp, uint i) private pure returns (uint ret) {
        assembly {
            ret := mload(add(arrp, mul(i, 32)))
        }
    }

    // Swap two items in array without bounds checking

    function memswap(uint arrp, uint i, uint j) private pure {
        assembly {
            let iOffset := add(arrp, mul(i, 32))
            let jOffset := add(arrp, mul(j, 32))
            let tp := mload(iOffset)
            mstore(iOffset, mload(jOffset))
            mstore(jOffset, tp)
        }
    }

    function writeRing(uint index, int tick, uint duration) private {
        unchecked {
            uint packed = (uint(uint16(int16(tick))) << 16) | duration;

            uint shift = 32 * (index % 8);
            ringBuffer[index / 8] = (ringBuffer[index / 8] & ~(0xFFFFFFFF << shift))
                                    | (packed << shift);
        }
    }

    function clampTime(uint t) private pure returns (uint) {
        unchecked {
            return t > type(uint16).max ? uint(type(uint16).max) : t;
        }
    }

    function quantiseTick(int tick) private pure returns (int) {
        unchecked {
            return (tick + (tick < 0 ? -(TICK_TRUNCATION-1) : int(0))) / TICK_TRUNCATION;
        }
    }

    function unQuantiseTick(int tick) private pure returns (int) {
        unchecked {
            return tick * TICK_TRUNCATION + (TICK_TRUNCATION/2);
        }
    }

    function memoryPackTick(int tick, uint duration) private pure returns (uint) {
        unchecked {
            return (uint(tick + 32768) << 16) | duration;
        }
    }

    function unMemoryPackTick(uint rec) private pure returns (int) {
        unchecked {
            return int(rec >> 16) - 32768;
        }
    }
}
