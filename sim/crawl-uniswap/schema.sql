PRAGMA encoding = "UTF-8";
PRAGMA foreign_keys = ON;


CREATE TABLE Pair (
    name TEXT PRIMARY KEY,
    uniswapPoolAddr TEXT
);


CREATE TABLE Block (
    blockNumber INTEGER PRIMARY KEY,
    timestamp INTEGER NOT NULL
);


CREATE TABLE Swap (
    pairName TEXT NOT NULL,
    blockNumber INTEGER NOT NULL,
    logIndex INTEGER NOT NULL,
    tick INTEGER NOT NULL,
    sqrtPriceX96 TEXT NOT NULL,

    PRIMARY KEY (pairName, blockNumber, logIndex),
    FOREIGN KEY (pairName) REFERENCES Pair(name)
);
