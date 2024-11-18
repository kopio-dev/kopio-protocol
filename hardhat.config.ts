/* eslint-disable @typescript-eslint/no-var-requires */
/* eslint-disable @typescript-eslint/ban-ts-comment */
import '@nomicfoundation/hardhat-foundry'
import type { HardhatUserConfig } from 'hardhat/config'
import 'tsconfig-paths/register'

/* -------------------------------------------------------------------------- */
/*                                   Plugins                                  */
/* -------------------------------------------------------------------------- */

import '@nomiclabs/hardhat-ethers'
import '@typechain/hardhat'
import '@nomicfoundation/hardhat-chai-matchers'
import 'hardhat-deploy'
import 'hardhat-deploy-ethers'

/* -------------------------------------------------------------------------- */
/*                                   Dotenv                                   */
/* -------------------------------------------------------------------------- */
import { configDotenv } from 'dotenv'
configDotenv()
process.env.HARDHAT = 'true'

const mnemonic = process.env.MNEMONIC_KOPIO || 'test test test test test test test test test test test junk'

/* -------------------------------------------------------------------------- */
/*                                Config helpers                              */
/* -------------------------------------------------------------------------- */

import { compilers, handleForking, networks, users } from '@config/hardhat'

/* -------------------------------------------------------------------------- */
/*                               CONFIGURATION                                */
/* -------------------------------------------------------------------------- */

export default {
  solidity: compilers,
  networks: handleForking(networks(mnemonic)),
  namedAccounts: users,
  mocha: {
    reporter: process.env.CI ? 'spec' : 'mochawesome',
    reporterOptions: process.env.CI
      ? undefined
      : {
          reportDir: 'docs/test-report',
          assetsDir: 'docs/test-report/assets',
          reportTitle: 'Kopio Protocol Hardhat Test Report',
          reportPageTitle: 'Kopio Protocol Hardhat Test Report',
        },
    timeout: process.env.CI ? 45000 : process.env.FORKING ? 300000 : 30000,
  },
  external: {
    contracts: [
      {
        artifacts: 'build/foundry',
      },
    ],
  },
  paths: {
    artifacts: 'build/hardhat/artifacts',
    cache: 'build/hardhat/cache',
    sources: 'src',
    tests: 'src-ts/test',
    deploy: 'src-ts/deploy',
    deployments: 'out/hardhat/deploy',
  },
  typechain: {
    outDir: 'src-ts/types/typechain',
    target: 'ethers-v5',
    alwaysGenerateOverloads: false,
    dontOverrideCompile: false,
    discriminateTypes: true,
    tsNocheck: true,
    externalArtifacts: [],
  },
} satisfies HardhatUserConfig
