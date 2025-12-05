// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { V4DeltaRouter } from "../src/V4DeltaRouter.sol";
import { RatQuoter } from "../src/RatQuoter.sol";

contract DeployBaseMainnet is Script {
    function run() external {
        if (block.chainid != 8453) {
            revert("Unrecognized chain, use base mainnet");
        }

        // Load the private key from the `PRIVATE_KEY` environment variable (in .env)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address weth = 0x4200000000000000000000000000000000000006;
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        // Uniswap v4 pool manager
        address poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        // the newer one is 0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D but eurc pools use the legacy one
        address aerodromeRouter = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;

        V4DeltaRouter router = new V4DeltaRouter(permit2, weth, poolManager, aerodromeRouter);
        console.log("deployed router address: ", address(router));

        address uniswapV4Quoter = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;
        // the newer one is 0x3d4C22254F86f64B7eC90ab8F7aeC1FBFD271c6C but eurc pools use the legacy one
        address aerodromeQuoter = 0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0;

        RatQuoter ratQuoter = new RatQuoter(uniswapV4Quoter, aerodromeQuoter);
        console.log("deployed ratQuoter address: ", address(ratQuoter));
    }
}
