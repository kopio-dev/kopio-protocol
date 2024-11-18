import type { SolcUserConfig } from 'hardhat/types'

export const compilers: { compilers: SolcUserConfig[] } = {
  compilers: [
    {
      version: '^0.8.26;',
      settings: {
        evmVersion: 'paris',
        viaIR: false,
        optimizer: {
          enabled: true,
          runs: 1000,
        },
        outputSelection: {
          '*': {
            '*': [
              'metadata',
              'abi',
              'storageLayout',
              'evm.methodIdentifiers',
              'devdoc',
              'userdoc',
              'evm.gasEstimates',
              'evm.byteCode',
            ],
          },
        },
      },
    },
  ],
}
