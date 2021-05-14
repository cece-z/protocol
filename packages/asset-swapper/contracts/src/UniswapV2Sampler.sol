// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2020 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.6;
pragma experimental ABIEncoderV2;

import "./interfaces/IUniswapV2Router01.sol";
import "@0x/contracts-zero-ex/contracts/src/transformers/bridges/mixins/MixinUniswapV2.sol";


contract UniswapV2Sampler is MixinUniswapV2
{
    /// @dev Gas limit for UniswapV2 calls.
    uint256 constant private UNISWAPV2_CALL_GAS = 150e3; // 150k

    function sampleSwapFromUniswapV2(
        address router,
        address[] memory path,
        uint256 takerTokenAmount
    )
        public
    {
        uint256 amountOut = _tradeUniswapV2(
            IERC20TokenV06(path[path.length-1]),
            takerTokenAmount,
            abi.encode(router, path)
        );

        // Revert it so there is no state change
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountOut)
            revert(ptr, 32)
        }
    }

    function sampleSwapsFromUniswapV2(
        address router,
        address[] memory path,
        uint256[] memory takerTokenAmounts
    )
        public
        returns (uint256[] memory gasUsed, uint256[] memory makerTokenAmounts)
    {
        uint256 numSamples = takerTokenAmounts.length;
        makerTokenAmounts = new uint256[](numSamples);
        gasUsed  = new uint256[](numSamples);
        for (uint256 i = 0; i < numSamples; i++) {
            uint256 gasBefore = gasleft();
            try
                this.sampleSwapFromUniswapV2(router, path, takerTokenAmounts[i])
            {
                // this should have reverted
                require(false, "UniswapV2 should have reverted");
            } catch (bytes memory reason) {
                gasUsed[i] = gasBefore - gasleft();
                makerTokenAmounts[i] = _parseRevertReason(reason);
                if (makerTokenAmounts[i] == 0) {
                    break;
                }
            }
        }
    }

    function _parseRevertReason(
        bytes memory reason
    )
        private
        pure
        returns (uint256)
    {
        if (reason.length != 32) {
            // if (reason.length < 68) revert('Unexpected error');
            // assembly {
            //     reason := add(reason, 0x04)
            // }
            // revert(abi.decode(reason, (string)));
            return 0;
        }
        return abi.decode(reason, (uint256));
    }

    /// @dev Sample sell quotes from UniswapV2.
    /// @param router Router to look up tokens and amounts
    /// @param path Token route. Should be takerToken -> makerToken
    /// @param takerTokenAmounts Taker token sell amount for each sample.
    /// @return makerTokenAmounts Maker amounts bought at each taker token
    ///         amount.
    function sampleSellsFromUniswapV2(
        address router,
        address[] memory path,
        uint256[] memory takerTokenAmounts
    )
        public
        view
        returns (uint256[] memory makerTokenAmounts)
    {
        uint256 numSamples = takerTokenAmounts.length;
        makerTokenAmounts = new uint256[](numSamples);
        for (uint256 i = 0; i < numSamples; i++) {
            try
                IUniswapV2Router01(router).getAmountsOut
                    {gas: UNISWAPV2_CALL_GAS}
                    (takerTokenAmounts[i], path)
                returns (uint256[] memory amounts)
            {
                makerTokenAmounts[i] = amounts[path.length - 1];
                // Break early if there are 0 amounts
                if (makerTokenAmounts[i] == 0) {
                    break;
                }
            } catch (bytes memory) {
                // Swallow failures, leaving all results as zero.
                break;
            }
        }
    }

    /// @dev Sample buy quotes from UniswapV2.
    /// @param router Router to look up tokens and amounts
    /// @param path Token route. Should be takerToken -> makerToken.
    /// @param makerTokenAmounts Maker token buy amount for each sample.
    /// @return takerTokenAmounts Taker amounts sold at each maker token
    ///         amount.
    function sampleBuysFromUniswapV2(
        address router,
        address[] memory path,
        uint256[] memory makerTokenAmounts
    )
        public
        view
        returns (uint256[] memory takerTokenAmounts)
    {
        uint256 numSamples = makerTokenAmounts.length;
        takerTokenAmounts = new uint256[](numSamples);
        for (uint256 i = 0; i < numSamples; i++) {
            try
                IUniswapV2Router01(router).getAmountsIn
                    {gas: UNISWAPV2_CALL_GAS}
                    (makerTokenAmounts[i], path)
                returns (uint256[] memory amounts)
            {
                takerTokenAmounts[i] = amounts[0];
                // Break early if there are 0 amounts
                if (takerTokenAmounts[i] == 0) {
                    break;
                }
            } catch (bytes memory) {
                // Swallow failures, leaving all results as zero.
                break;
            }
        }
    }
}
