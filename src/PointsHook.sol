// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC1155 {
    event PointsAssigned(address indexed user, uint256 poolId, uint256 points);
    
    constructor(
        IPoolManager _manager
    ) BaseHook(_manager) {}

    // Set up hook permissions to return true
    // for the two hook functions we are using
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return (
            Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        }));

    }

            // Implement the ERC1155 `uri` function
        function uri(uint256) public view virtual override returns(string memory) {
            return "https://example.com/token/";
        }
        // You could use beforeInitialize or afterInitialize to revert if currency0 is not ETH
        
        // Stub implementation of afterswap
        // 1. Make sure the pool is ETH <> Token
        // 2. Make sure the swap is to buy Token in exchange for ETH
        // 3. Mint points equal to 20% of the amount of ETH being swapped
        function _afterSwap(
            address sender,
            PoolKey calldata key,
            SwapParams calldata swapParams,
            BalanceDelta delta,
            bytes calldata hookData
        ) internal override returns(bytes4, int128) {
            // We'll add more code here shortly
            // 1. Make sure the pool is ETH <> Token
            if(!key.currency0.isAddressZero()){
                return (this.afterSwap.selector, 0);
            }
            // 2. Make sure the swap is to buy Token in exchange for ETH
            if(!swapParams.zeroForOne) {
                return (this.afterSwap.selector, 0);
            }
            // 3. Mint points equal to 20% of the amount of ETH being swapped
            // Since It's a zeroForOne swap
            // If amountSpecified is negative (<0):
            // - This is an "exact input for output" swap
            // - amountSpecified is the amount of ETH being swapped
            // If amountSpecified is positive (>0):
            // - This is instead an "exact output for input" swap
            // - The amount of ETH they spent is equal to BalanceDelta.amount0()

            // The balanceDelta will always give us the amount of ETH swapped in
            // Just rely on the balanceDelta value

            uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
            uint256 pointsForSwap = ethSpendAmount / 5; // 20% of the amount of ETH being swapped

            // Mint points to the user
            _assignPoints(key.toId(), hookData, pointsForSwap);

            return(this.afterSwap.selector, 0);
        }

        function _assignPoints(
            PoolId poolId,
            bytes calldata hookData,
            uint256 points
        ) internal {
            // Check that points are allocated
            if(points == 0) return;
            // If no hook data is passed in, then no points will be assigned
            if(hookData.length ==  0) return;

            // Extract the user address from hookData
            address user = abi.decode(hookData, (address));

            // If there is hookdata but not in the format we expect, then exit
            if(user == address(0)) return;
            // Finally we can mint points to the user
            uint256 poolIdUint = uint256(PoolId.unwrap(poolId));
            _mint(user, poolIdUint, points, '');
            emit PointsAssigned(user, poolIdUint, points);

        }
}

