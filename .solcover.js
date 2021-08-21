const shell = require("shelljs");
const { mnemonic } = require("./config");

module.exports = {
    istanbulReporter: ["html"],
    onCompileComplete: async function (_config) {
        await run("typechain");
    },
    onIstanbulComplete: async function (_config) {
        // We need to do this because solcover generates bespoke artifacts.
        shell.rm("-rf", "./artifacts");
        shell.rm("-rf", "./typechain");
    },
    providerOptions: {
        mnemonic,
    },
    skipFiles: ["mocks", "test"],
};
