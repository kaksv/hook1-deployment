// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

contract GasPriceFeesHook is BaseHook {
    using LPFeeLibrary for uint24;
    using CurrencyLibrary for Currency;

    // Octant Spark ETH Vault
    address public constant OCTANT_VAULT = 0xfE6eb3b609a7C8352A241f7F3A21CEA4e9209B8f;

    uint128 public movingAverageGasPrice;
    uint104 public movingAverageGasPriceCount;
    uint24 public constant BASE_FEE = 5000; // 0.5%

    error MustUseDynamicFee();
    error OnlyOwner();

    // Add owner for safe fee collection
    address public owner;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        owner = msg.sender;
        updateMovingAverage();
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // --- Hook permissions & logic (unchanged) ---
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal pure override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 fee = getFee();
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        return (
            this.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feeWithFlag
        );
    }

    function _afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        updateMovingAverage();
        return (this.afterSwap.selector, 0);
    }

    function getFee() internal view returns (uint24) {
        uint128 gasPrice = uint128(tx.gasprice);
        if (gasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }
        if (gasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }
        return BASE_FEE;
    }

    function updateMovingAverage() internal {
        uint128 gasPrice = uint128(tx.gasprice);
        movingAverageGasPrice =
            ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) /
            (movingAverageGasPriceCount + 1);
        movingAverageGasPriceCount++;
    }

    // --- NEW: Fee collection & forwarding ---
    struct CollectParams {
        PoolKey poolKey;
        address recipient;
        uint256 amount0;
        uint256 amount1;
    }

    /// @notice Collect LP fees from the pool and forward ETH portion to Octant vault
    /// @dev Only owner can call. Assumes pool uses ETH (or WETH) as one token.
    ///      You MUST ensure the vault can receive ETH (it's an EOA or payable contract).
    function collectAndForwardFees(
        PoolKey calldata poolKey,
        uint1256 amount0Max,
        uint1256 amount1Max
    ) external onlyOwner {
        // Take fees from pool (in both tokens)
        (uint256 amount0, uint256 amount1) = poolManager.take(
            abi.encode(Currency.unwrap(poolKey.currency0), Currency.unwrap(poolKey.currency1)),
            address(this),
            amount0Max,
            amount1Max
        );

        // Identify which token is ETH (or WETH)
        Currency token0 = poolKey.currency0;
        Currency token1 = poolKey.currency1;

        // Forward ETH (if native ETH is token0 or token1)
        if (token0 == Currency.wrap(address(0))) {
            payable(OCTANT_VAULT).transfer(amount0);
        } else if (token1 == Currency.wrap(address(0))) {
            payable(OCTANT_VAULT).transfer(amount1);
        }

        // Optional: emit event or handle non-ETH token (e.g., donate back or hold)
        // For now, non-ETH fees remain in the hook contract (can be withdrawn later)
    }

    // Optional: fallback to receive ETH (e.g., from refunds)
    receive() external payable {}
}