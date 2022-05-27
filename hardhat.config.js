require("@nomiclabs/hardhat-waffle");
const fs = require("fs");

// Load tasks

const files = fs.readdirSync('./tasks');

for (let file of files) {
    if (!file.endsWith('.js')) continue;
    require(`./tasks/${file}`);
}

// Config

module.exports = {
    networks: {
        hardhat: {
            hardfork: 'berlin',
            blockGasLimit: 100_000_000,
        },
    },

    solidity: {
        compilers: [
            {
                version: "0.8.13",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            {
                version: "0.7.6",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
        ],
    },
};
