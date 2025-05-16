// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title HookTuah
 * @notice A Uniswap V4 hook that enables single-sided liquidity provision with JIT rebalancing
 * @dev This hook allows users to deposit only one token of a pair while the hook
 *      acts as a counterparty by providing the other token. It also includes JIT
 *      rebalancing during swaps to reduce impermanent loss and increase efficiency.
 */
contract HookTuah is BaseHook {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    bytes public constant COPOOL = hex"00";
    
    uint16 public constant MIN_PRICE_IMPACT_BPS = 10; 
    
    Currency private token0;
    Currency private token1;
    address public token0Address;
    address public token1Address;

    int256 public token0NetDelta;
    int256 public token1NetDelta;

    mapping(bytes => int128) public token0DeltaForPosition;
    mapping(bytes => int128) public token1DeltaForPosition;

    mapping(address => uint256) public token0Balance;
    mapping(address => uint256) public token1Balance;
    
    uint160 public lastSqrtPriceX96;
    bool public priceInitialized;
    
    uint128 public totalHookLiquidity;
    int24 public currentTickLower;
    int24 public currentTickUpper;

    // events
    event JITRebalanced(uint160 oldSqrtPriceX96, uint160 newSqrtPriceX96, uint128 liquidityAmount);
    event SingleSidedDeposit(address indexed user, bool isToken0, uint256 amount);
    event LiquidityAdded(address indexed user, bool providedToken0, uint128 liquidity);
    event LiquidityRemoved(address indexed user, bool providedToken0, uint128 liquidity);

    // errors
    error OnlyPoolManager();
    error InvalidTokenSelection();
    error InsufficientLiquidity();
    error InsufficientBalance();
    error PriceSlippageTooHigh();


    /**
     * @notice Constructor initializes the hook with the pool manager and sets token0/token1 addresses
     * @param _manager The Uniswap V4 pool manager
     * @param _token0 The address of token0 (ERC20)
     * @param _token1 The address of token1 (ERC20)
     */
    constructor(IPoolManager _manager, address _token0, address _token1) BaseHook(_manager) {
        token0 = Currency.wrap(_token0);
        token1 = Currency.wrap(_token1);
        token0Address = _token0;
        token1Address = _token1;
    }

    function getToken0() external view returns (address) {
        return token0Address;
    }

    function getToken1() external view returns (address) {
        return token1Address;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,           // Enable afterSwap for JIT rebalancing
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address /*sender*/, PoolKey calldata key, uint160 sqrtPriceX96, int24 /*tick*/) internal override returns (bytes4) {
        token0 = key.currency0;
        token1 = key.currency1;
        lastSqrtPriceX96 = sqrtPriceX96;
        priceInitialized = true;
        int24 tickSpacing = key.tickSpacing;
        int24 currentTick = getCurrentTick(sqrtPriceX96);
        currentTickLower = (currentTick - 3000) - (currentTick - 3000) % tickSpacing;
        currentTickUpper = (currentTick + 3000) - (currentTick + 3000) % tickSpacing + tickSpacing;
        return this.afterInitialize.selector;
    }

    function deposit(uint256 amount, bool isToken0) external {
        address sender = msg.sender;
        
        Currency token = isToken0 ? token0 : token1;
        IERC20Minimal(Currency.unwrap(token)).transferFrom(sender, address(this), amount);
        
        if (isToken0) {
            token0Balance[sender] += amount;
            token0NetDelta -= int256(amount);
        } else {
            token1Balance[sender] += amount;
            token1NetDelta -= int256(amount);
        }
        
        emit SingleSidedDeposit(sender, isToken0, amount);
    }

    function withdraw(uint256 amount, bool isToken0) external {
        address sender = msg.sender;
        int256 amountInt = int256(amount);
        
        if (isToken0) {
            if (token0Balance[sender] < amount) revert InsufficientBalance();
            
            if (amountInt + token0NetDelta > 0) revert InsufficientLiquidity();
            
            token0.transfer(sender, amount);
            token0Balance[sender] -= amount;
            token0NetDelta += amountInt;
        } else {
            if (token1Balance[sender] < amount) revert InsufficientBalance();
            if (amountInt + token1NetDelta > 0) revert InsufficientLiquidity();
            
            token1.transfer(sender, amount);
            token1Balance[sender] -= amount;
            token1NetDelta += amountInt;
        }
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (hookData.length == 0) {
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        (bytes memory identifier, uint8 tokenSelection) = abi.decode(hookData, (bytes, uint8));

        if (identifier.length == COPOOL.length && keccak256(identifier) == keccak256(COPOOL)) {
            if (tokenSelection != 0 && tokenSelection != 1) {
                revert InvalidTokenSelection();
            }

            int128 amount0 = delta.amount0();
            int128 amount1 = delta.amount1();

            bytes memory positionId = abi.encodePacked(sender, params.salt);
            
            BalanceDelta hookDelta;
            
            if (tokenSelection == 0) {
                int128 newDelta1;
                
                if (token1NetDelta <= amount1) {
                    token1NetDelta -= amount1;
                    newDelta1 = amount1;
                } else {
                    newDelta1 = int128(token1NetDelta);
                    token1NetDelta = 0;
                }
                
                token1DeltaForPosition[positionId] += newDelta1;
                
                if (newDelta1 < 0) {
                    _settle(key.currency1, SignedMath.abs(newDelta1));
                }
                
                hookDelta = toBalanceDelta(0, newDelta1);
                
                if (params.liquidityDelta > 0) {
                    totalHookLiquidity += uint128(uint256(params.liquidityDelta));
                    emit LiquidityAdded(sender, true, uint128(uint256(params.liquidityDelta)));
                }

            } else {
                int128 newDelta0;
                
                if (token0NetDelta <= amount0) {
                    token0NetDelta -= amount0;
                    newDelta0 = amount0;
                } else {
                    newDelta0 = int128(token0NetDelta);
                    token0NetDelta = 0;
                }
                
                token0DeltaForPosition[positionId] += newDelta0;
                
                if (newDelta0 < 0) {
                    _settle(key.currency0, SignedMath.abs(newDelta0));
                }
                
                hookDelta = toBalanceDelta(newDelta0, 0);
                
                if (params.liquidityDelta > 0) {
                    totalHookLiquidity += uint128(uint256(params.liquidityDelta));
                    emit LiquidityAdded(sender, false, uint128(uint256(params.liquidityDelta)));
                }

            }
            
            return (this.afterAddLiquidity.selector, hookDelta);
        }

        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _handleToken0LiquidityRemoval(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        int128 amount1,
        bytes memory positionId
    ) internal returns (BalanceDelta) {
        int128 recoverableDelta = recoverCounterpartyToken(amount1, positionId, true);
        
        if (recoverableDelta > 0) {
            _take(key.currency1, SignedMath.abs(recoverableDelta));
        }
        
        if (params.liquidityDelta < 0) {
            uint128 absDelta = uint128(uint256(-params.liquidityDelta));
            if (totalHookLiquidity >= absDelta) {
                totalHookLiquidity -= absDelta;
                emit LiquidityRemoved(sender, true, absDelta);
            }
        }
        
        return toBalanceDelta(0, recoverableDelta);
    }

    function _handleToken1LiquidityRemoval(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        int128 amount0,
        bytes memory positionId
    ) internal returns (BalanceDelta) {
        int128 recoverableDelta = recoverCounterpartyToken(amount0, positionId, false);
        
        if (recoverableDelta > 0) {
            _take(key.currency0, SignedMath.abs(recoverableDelta));
        }
        
        if (params.liquidityDelta < 0) {
            uint128 absDelta = uint128(uint256(-params.liquidityDelta));
            if (totalHookLiquidity >= absDelta) {
                totalHookLiquidity -= absDelta;
                emit LiquidityRemoved(sender, false, absDelta);
            }
        }
        
        return toBalanceDelta(recoverableDelta, 0);
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (hookData.length == 0) {
            return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        (bytes memory identifier, uint8 tokenSelection) = abi.decode(hookData, (bytes, uint8));
        if (identifier.length == COPOOL.length && keccak256(identifier) == keccak256(COPOOL)) {
            if (tokenSelection != 0 && tokenSelection != 1) {
                revert InvalidTokenSelection();
            }

            bytes memory positionId = abi.encodePacked(sender, params.salt);
            
            BalanceDelta hookDelta;
            
            if (tokenSelection == 0) {
                hookDelta = _handleToken0LiquidityRemoval(
                    sender, 
                    key, 
                    params, 
                    delta.amount1(), 
                    positionId
                );
            } else {
                hookDelta = _handleToken1LiquidityRemoval(
                    sender, 
                    key, 
                    params, 
                    delta.amount0(), 
                    positionId
                );
            }
            
            return (this.afterRemoveLiquidity.selector, hookDelta);
        }

        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }
    
    function _afterSwap(
        address /*sender*/,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata /*params*/,
        BalanceDelta /*delta*/,
        bytes calldata /*hookData*/
    ) internal override returns (bytes4, int128) {
        // TODO: Get current price from the pool. poolManager.getSlot0 is not available on IPoolManager interface.
        // (uint160 currentSqrtPriceX96,,,,) = poolManager.getSlot0(key.toId());
        uint160 currentSqrtPriceX96 = 0; // <-- Replace with actual pool price fetch
        
        // Only proceed if price is initialized and price impact is significant
        int128 jitDelta = 0;
        if (priceInitialized && isPriceImpactSignificant(lastSqrtPriceX96, currentSqrtPriceX96)) {
            // Attempt JIT rebalancing
            performJITRebalancing(key, currentSqrtPriceX96);
            // Update last known price
            lastSqrtPriceX96 = currentSqrtPriceX96;
            // TODO: Set jitDelta as needed by your logic
        }
        return (this.afterSwap.selector, jitDelta);
    }
    
    function _afterSwapReturnDelta(
        address /*sender*/,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata /*params*/,
        BalanceDelta /*delta*/,
        bytes calldata /*hookData*/
    ) internal returns (bytes4, BalanceDelta) {
        return (bytes4(0), BalanceDeltaLibrary.ZERO_DELTA);
    }
    
    function isPriceImpactSignificant(uint160 oldSqrtPriceX96, uint160 newSqrtPriceX96) 
        internal pure returns (bool isSignificant) 
    {
        if (oldSqrtPriceX96 == 0 || newSqrtPriceX96 == 0) return false;
        
        // Calculate price change in basis points (1 basis point = 0.01%)
        uint256 priceDiff;
        if (oldSqrtPriceX96 > newSqrtPriceX96) {
            priceDiff = uint256(oldSqrtPriceX96 - newSqrtPriceX96) * 10000 / uint256(oldSqrtPriceX96);
        } else {
            priceDiff = uint256(newSqrtPriceX96 - oldSqrtPriceX96) * 10000 / uint256(oldSqrtPriceX96);
        }
        
        // Is the price impact above our threshold?
        return priceDiff >= MIN_PRICE_IMPACT_BPS;
    }
    
    function performJITRebalancing(PoolKey calldata key, uint160 currentSqrtPriceX96) internal {
        // Only proceed if we actually have hook-managed liquidity
        if (totalHookLiquidity == 0) return;
        
        // Calculate new optimal tick range based on current price
        int24 tickSpacing = key.tickSpacing;
        int24 currentTick = getCurrentTick(currentSqrtPriceX96);
        
        int24 newTickLower = (currentTick - 3000) - (currentTick - 3000) % tickSpacing;
        int24 newTickUpper = (currentTick + 3000) - (currentTick + 3000) % tickSpacing + tickSpacing;
        
        // Only rebalance if the current tick is outside our centered range
        if (currentTick >= currentTickLower && currentTick <= currentTickUpper) return;
        
        // Remove liquidity from old range
        if (totalHookLiquidity > 0) {
            IPoolManager.ModifyLiquidityParams memory removeParams = IPoolManager.ModifyLiquidityParams({
                tickLower: currentTickLower,
                tickUpper: currentTickUpper,
                liquidityDelta: -int256(uint256(totalHookLiquidity)),
                salt: bytes32(0)
            });
            
            poolManager.modifyLiquidity(key, removeParams, new bytes(0));
        }
        
        IPoolManager.ModifyLiquidityParams memory addParams = IPoolManager.ModifyLiquidityParams({
            tickLower: newTickLower,
            tickUpper: newTickUpper,
            liquidityDelta: int256(uint256(totalHookLiquidity)),
            salt: bytes32(0)
        });
        
        poolManager.modifyLiquidity(key, addParams, new bytes(0));
        
        currentTickLower = newTickLower;
        currentTickUpper = newTickUpper;
        
        emit JITRebalanced(lastSqrtPriceX96, currentSqrtPriceX96, totalHookLiquidity);
    }

    function recoverCounterpartyToken(int128 withdrawAmount, bytes memory positionId, bool isForToken1)
        internal
        returns (int128 delta)
    {
        if (isForToken1) {
            // Calculate how much of token1 the hook can recover
            int128 positionDelta = token1DeltaForPosition[positionId];
            int128 difference = withdrawAmount + positionDelta;
            
            if (difference >= 0) {
                // User is withdrawing more than the hook provided
                delta = -positionDelta;
                token1DeltaForPosition[positionId] = 0;
            } else {
                // User is withdrawing less than the hook provided
                delta = withdrawAmount;
                token1DeltaForPosition[positionId] = difference;
            }
            
            token1NetDelta -= delta;
        } else {
            // Calculate how much of token0 the hook can recover
            int128 positionDelta = token0DeltaForPosition[positionId];
            int128 difference = withdrawAmount + positionDelta;
            
            if (difference >= 0) {
                // User is withdrawing more than the hook provided
                delta = -positionDelta;
                token0DeltaForPosition[positionId] = 0;
            } else {
                // User is withdrawing less than the hook provided
                delta = withdrawAmount;
                token0DeltaForPosition[positionId] = difference;
            }
            
            token0NetDelta -= delta;
        }
    }
    
    function getCurrentTick(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        // This is a simplified version - in production you'd want to use TickMath more carefully
        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function _settle(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            // Handle ETH settlement
            poolManager.settle{value: amount}();
        } else {
            // Handle ERC20 settlement
            poolManager.sync(currency);
            IERC20Minimal(Currency.unwrap(currency)).transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }

    function _take(Currency currency, uint256 amount) internal {
        poolManager.take(currency, address(this), amount);
    }
}