// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import {
    TokenConfig,
    LiquidityManagement,
    HookFlags,
    AddLiquidityKind,
    RemoveLiquidityKind,
    AddLiquidityParams,
    AfterSwapParams,
    SwapKind,
    PoolData
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { IUpdateWeightRunner } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IUpdateWeightRunner.sol";

import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { MinimalRouter } from "../MinimalRouter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";

import { LPNFT } from "./LPNFT.sol";

struct PoolCreationSettings {
    string name;
    string symbol;
    int256[] initialWeights;
    int256[] initialMovingAverages;
    int256[] initialIntermediateValues;
    uint oracleStalenessThreshold;
}

/**
 * @title UpliftOnlyExample
 * @notice Deposits are recorded in USD notional and at withdrawal, the user is charged a fee based on the uplift since deposit.
 * This is done in a FILO manner given the user can have multiple deposits.
 * Transfers are possible however are expensive given a reordering of the storage array is required.
 * Alternatives include depositing under different addresses or withdrawing and transferring.
 *
 * Fixed swap fees are also divided between the owner and the quantAMM admin.
 *
 * The user is restricted to 100 deposits to avoid Ddos issues.
 *
 */
/// @notice Change Withdrawal fees on USD uplift since deposit, and charge swap fees on every swap operation.
contract UpliftOnlyExample is MinimalRouter, BaseHooks, Ownable {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

    /// @notice The withdrawal fee in basis points (1/10000) that will be charged if no uplift was provided.
    uint64 public immutable minWithdrawalFeeBps;

    /// @notice The uplift fee in basis points (1/10000) for the pool
    uint64 public upliftFeeBps;

    /// @notice The hook swap fee percentage, charged on every swap operation.
    uint64 public hookSwapFeePercentage;

    /// @notice The fee data for a given owner and deposit
    struct FeeData {
        uint256 tokenID;
        uint256 amount;
        uint256 lpTokenDepositValue;
        uint40 blockTimestampDeposit;
        uint64 upliftFeeBps;
    }

    /// @notice The LP NFT contract for the pool
    LPNFT public lpNFT;

    /// @notice pool => owner => FeeData[]
    mapping(address => mapping(address => FeeData[])) public poolsFeeData;

    /// @notice The pool associated with the NFT Token ID
    mapping(uint256 => address) public nftPool;

    // NFT unique identifier.
    uint256 private _nextTokenId;

    address private immutable _updateWeightRunner;

    uint64 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint64 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    /**
     * @notice A new `UpliftOnlyExampleRegistered` contract has been registered successfully for a given pool.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param hooksContract This contract
     * @param pool The pool on which the hook was registered
     */
    event UpliftOnlyExampleRegistered(address indexed hooksContract, address indexed pool);

    /**
     * @notice The hooks contract has charged a fee on a withdrawal.
     * @param nftHolder The NFT holder who withdrew liquidity
     * @param pool The pool from which the NFT holder withdrew liquidity
     * @param feeToken The address of the token in which the fee was charged
     * @param feeAmount The amount of the fee, in native token decimals
     */
    event ExitFeeCharged(address indexed nftHolder, address indexed pool, IERC20 indexed feeToken, uint256 feeAmount);

    /**
     * @notice The hooks contract has charged a swap fee.
     * @param hooksContract The contract that collected the fee
     * @param token The token in which the fee was charged
     * @param feeAmount The amount of the fee
     */
    event SwapHookFeeCharged(address indexed hooksContract, IERC20 indexed token, uint256 feeAmount);

    /**
     * @notice The swap hook fee percentage has been changed.
     * @dev Note that the initial fee will be zero, and no event is emitted on deployment.
     * @param hooksContract The hooks contract charging the fee
     * @param hookFeePercentage The new hook swap fee percentage
     */
    event HookSwapFeePercentageChanged(address indexed hooksContract, uint256 hookFeePercentage);

    /**
     * @notice The uplift withdrawal fee percentage has been changed.
     * @dev Note that the initial fee will be zero, and no event is emitted on deployment.
     * @param hooksContract The hooks contract charging the fee
     * @param hookFeePercentage The new hook swap fee percentage
     */
    event HookUpliftWithdrawalFeePercentageChanged(address indexed hooksContract, uint256 hookFeePercentage);

    /**
     * @notice Hooks functions called from an external router.
     * @dev This contract inherits both `MinimalRouter` and `BaseHooks`, and functions as is its own router.
     * @param router The address of the Router
     */
    error CannotUseExternalRouter(address router);

    /**
     * @notice The pool does not support adding liquidity through donation.
     * @dev There is an existing similar error (IVaultErrors.DoesNotSupportDonation), but hooks should not throw
     * "Vault" errors.
     */
    error PoolDoesNotSupportDonation();

    /**
     * @notice The pool supports adding unbalanced liquidity.
     * @dev There is an existing similar error (IVaultErrors.DoesNotSupportUnbalancedLiquidity), but hooks should not
     * throw "Vault" errors.
     */
    error PoolSupportsUnbalancedLiquidity();

    /**
     * @notice To avoid Ddos issues, a single depositor can only deposit 100 times
     * @param pool The pool the depositor is attempting to deposit to
     * @param depositor The address of the depositor
     */
    error TooManyDeposits(address pool, address depositor);

    /**
     * @notice Attempted withdrawal of an NFT-associated position by an address that is not the owner.
     * @param withdrawer The address attempting to withdraw
     * @param pool The attempted target pool
     * @param bptAmountIn The amount of BPT requested
     */
    error WithdrawalByNonOwner(address withdrawer, address pool, uint256 bptAmountIn);

    /**
     * @notice Attempted transfer of an NFT-associated position by an address that is not the nft.
     * @param from The address the NFT is being transferred from
     * @param to The address the NFT is being transferred to
     * @param caller The address that called the transfer function
     * @param tokenId The token ID being transferred
     */
    error TransferUpdateNonNft(address from, address to, address caller, uint256 tokenId);

    /**
     * @notice Attempted transfer of an NFT-associated position with an incorrect nft id.
     * @param from The address the NFT is being transferred from
     * @param to The address the NFT is being transferred to
     * @param tokenId The token ID being transferred
     */
    error TransferUpdateTokenIDInvaid(address from, address to, uint256 tokenId);

    modifier onlySelfRouter(address router) {
        _ensureSelfRouter(router);
        _;
    }

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        uint64 _upliftFeeBps,
        uint64 _minWithdrawalFeeBps,
        address _updateWeightRunnerParam,
        string memory version,
        string memory name,
        string memory symbol
    ) MinimalRouter(vault, weth, permit2, version) Ownable(msg.sender) {
        require(bytes(name).length > 0 && bytes(symbol).length > 0, "NAMEREQ"); //Must provide a name / symbol

        lpNFT = new LPNFT(name, symbol, address(this));

        upliftFeeBps = _upliftFeeBps;
        minWithdrawalFeeBps = _minWithdrawalFeeBps;
        _updateWeightRunner = _updateWeightRunnerParam;
    }

    /***************************************************************************
                                  Router Functions
    ***************************************************************************/

    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsIn) {
        if (poolsFeeData[pool][msg.sender].length > 100) {
            revert TooManyDeposits(pool, msg.sender);
        }
        // Do addLiquidity operation - BPT is minted to this contract.
        amountsIn = _addLiquidityProportional(
            pool,
            msg.sender,
            address(this),
            maxAmountsIn,
            exactBptAmountOut,
            wethIsEth,
            userData
        );

        uint256 tokenID = lpNFT.mint(msg.sender);

        //this requires the pool to be registered with the QuantAMM update weight runner
        //as well as approved with oracles that provide the prices
        uint256 depositValue = getPoolLPTokenValue(
            IUpdateWeightRunner(_updateWeightRunner).getData(pool),
            pool,
            MULDIRECTION.MULDOWN
        );

        poolsFeeData[pool][msg.sender].push(
            FeeData({
                tokenID: tokenID,
                amount: exactBptAmountOut,
                //this rounding favours the LP
                lpTokenDepositValue: depositValue,
                //known use of timestamp, caveats are known.
                blockTimestampDeposit: uint40(block.timestamp),
                upliftFeeBps: upliftFeeBps
            })
        );

        nftPool[tokenID] = pool;
    }

    function removeLiquidityProportional(
        uint256 bptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        address pool
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsOut) {
        uint depositLength = poolsFeeData[pool][msg.sender].length;

        if (depositLength == 0) {
            revert WithdrawalByNonOwner(msg.sender, pool, bptAmountIn);
        }
        // Do removeLiquidity operation - tokens sent to msg.sender.
        amountsOut = _removeLiquidityProportional(
            pool,
            address(this),
            msg.sender,
            bptAmountIn,
            minAmountsOut,
            wethIsEth,
            abi.encodePacked(msg.sender)
        );
    }

    /***************************************************************************
                                  Hook Functions
    ***************************************************************************/

    /// @inheritdoc BaseHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    ) public override onlyVault returns (bool success, uint256 hookAdjustedAmountCalculatedRaw) {
        hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;
        if (hookSwapFeePercentage > 0) {
            uint256 hookFee = params.amountCalculatedRaw.mulUp(hookSwapFeePercentage);

            if (hookFee > 0) {
                IERC20 feeToken;

                // Note that we can only alter the calculated amount in this function. This means that the fee will be
                // charged in different tokens depending on whether the swap is exact in / out, potentially breaking
                // the equivalence (i.e., one direction might "cost" less than the other).

                if (params.kind == SwapKind.EXACT_IN) {
                    // For EXACT_IN swaps, the `amountCalculated` is the amount of `tokenOut`. The fee must be taken
                    // from `amountCalculated`, so we decrease the amount of tokens the Vault will send to the caller.
                    //
                    // The preceding swap operation has already credited the original `amountCalculated`. Since we're
                    // returning `amountCalculated - hookFee` here, it will only register debt for that reduced amount
                    // on settlement. This call to `sendTo` pulls `hookFee` tokens of `tokenOut` from the Vault to this
                    // contract, and registers the additional debt, so that the total debits match the credits and
                    // settlement succeeds.
                    feeToken = params.tokenOut;
                    hookAdjustedAmountCalculatedRaw -= hookFee;
                } else {
                    // For EXACT_OUT swaps, the `amountCalculated` is the amount of `tokenIn`. The fee must be taken
                    // from `amountCalculated`, so we increase the amount of tokens the Vault will ask from the user.
                    //
                    // The preceding swap operation has already registered debt for the original `amountCalculated`.
                    // Since we're returning `amountCalculated + hookFee` here, it will supply credit for that increased
                    // amount on settlement. This call to `sendTo` pulls `hookFee` tokens of `tokenIn` from the Vault to
                    // this contract, and registers the additional debt, so that the total debits match the credits and
                    // settlement succeeds.
                    feeToken = params.tokenIn;
                    hookAdjustedAmountCalculatedRaw += hookFee;
                }

                uint256 quantAMMFeeTake = IUpdateWeightRunner(_updateWeightRunner).getQuantAMMUpliftFeeTake();
                uint256 ownerFee = hookFee;

                if (quantAMMFeeTake > 0) {
                    uint256 adminFee = hookFee / (1e18 / quantAMMFeeTake);
                    ownerFee = hookFee - adminFee;
                    address quantAMMAdmin = IUpdateWeightRunner(_updateWeightRunner).getQuantAMMAdmin();
                    _vault.sendTo(feeToken, quantAMMAdmin, adminFee);
                    emit SwapHookFeeCharged(quantAMMAdmin, feeToken, adminFee);
                }

                if (ownerFee > 0) {
                    _vault.sendTo(feeToken, address(this), ownerFee);

                    emit SwapHookFeeCharged(address(this), feeToken, ownerFee);
                }
            }
        }
        return (true, hookAdjustedAmountCalculatedRaw);
    }

    /// @inheritdoc BaseHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata liquidityManagement
    ) public override onlyVault returns (bool) {
        // This hook requires donation support to work (see above).
        if (liquidityManagement.enableDonation == false) {
            revert PoolDoesNotSupportDonation();
        }
        if (liquidityManagement.disableUnbalancedLiquidity == false) {
            revert PoolSupportsUnbalancedLiquidity();
        }

        emit UpliftOnlyExampleRegistered(address(this), pool);

        return true;
    }

    /// @inheritdoc BaseHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // `enableHookAdjustedAmounts` must be true for all contracts that modify the `amountCalculated`
        // in after hooks. Otherwise, the Vault will ignore any "hookAdjusted" amounts, and the transaction
        // might not settle. (It should be false if the after hooks do something else.)
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        hookFlags.shouldCallAfterSwap = true;

        return hookFlags;
    }

    /// @inheritdoc BaseHooks
    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override onlySelfRouter(router) returns (bool) {
        // We only allow addLiquidity via the Router/Hook itself (as it must custody BPT).
        return true;
    }

    struct TakeFeeLocalData {
        address nftHolder;
        address pool;
        uint256[] amountsOutRaw;
        uint256 currentFee;
        IERC20[] tokens;
        uint256[] accruedFees;
    }

    //needed to avoid stack too deep error
    struct AfterRemoveLiquidityData {
        address pool;
        uint256 bptAmountIn;
        uint256[] amountsOutRaw;
        uint256[] minAmountsOut;
        uint256[] accruedFees;
        uint256[] accruedQuantAMMFees;
        uint256 currentFee;
        uint256 feeAmount;
        int256[] prices;
        uint256 lpTokenDepositValueNow;
        int256 lpTokenDepositValueChange;
        uint256 lpTokenDepositValue;
        IERC20[] tokens;
        uint256 feeDataArrayLength;
        uint256 amountLeft;
        uint256 feePercentage;
        uint256 adminFeePercent;
    }

    /// @inheritdoc BaseHooks
    function onAfterRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind,
        uint256 bptAmountIn,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory userData
    ) public override onlySelfRouter(router) returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        address userAddress = address(bytes20(userData));

        AfterRemoveLiquidityData memory localData = AfterRemoveLiquidityData({
            pool: pool,
            bptAmountIn: bptAmountIn,
            amountsOutRaw: amountsOutRaw,
            minAmountsOut: new uint256[](amountsOutRaw.length),
            accruedFees: new uint256[](amountsOutRaw.length),
            accruedQuantAMMFees: new uint256[](amountsOutRaw.length),
            currentFee: minWithdrawalFeeBps,
            feeAmount: 0,
            prices: IUpdateWeightRunner(_updateWeightRunner).getData(pool),
            lpTokenDepositValueNow: 0,
            lpTokenDepositValueChange: 0,
            lpTokenDepositValue: 0,
            tokens: new IERC20[](amountsOutRaw.length),
            feeDataArrayLength: 0,
            amountLeft: 0,
            feePercentage: 0,
            adminFeePercent: 0
        });
        // We only allow removeLiquidity via the Router/Hook itself so that fee is applied correctly.
        hookAdjustedAmountsOutRaw = amountsOutRaw;

        //this rounding faxvours the LP
        localData.lpTokenDepositValueNow = getPoolLPTokenValue(localData.prices, pool, MULDIRECTION.MULDOWN);

        FeeData[] storage feeDataArray = poolsFeeData[pool][userAddress];
        localData.feeDataArrayLength = feeDataArray.length;
        localData.amountLeft = bptAmountIn;
        for (uint256 i = localData.feeDataArrayLength - 1; i >= 0; --i) {
            localData.lpTokenDepositValue = feeDataArray[i].lpTokenDepositValue;

            localData.lpTokenDepositValueChange =
                (int256(localData.lpTokenDepositValueNow) - int256(localData.lpTokenDepositValue)) /
                int256(localData.lpTokenDepositValue);

            uint256 feePerLP;
            // if the pool has increased in value since the deposit, the fee is calculated based on the deposit value
            if (localData.lpTokenDepositValueChange > 0) {
                feePerLP =
                    (uint256(localData.lpTokenDepositValueChange) * (uint256(feeDataArray[i].upliftFeeBps) * 1e18)) /
                    10000;
            }
            // if the pool has decreased in value since the deposit, the fee is calculated based on the base value - see wp
            else {
                //in most cases this should be a normal swap fee amount.
                //there always myst be at least the swap fee amount to avoid deposit/withdraw attack surgace.
                feePerLP = (uint256(minWithdrawalFeeBps) * 1e18) / 10000;
            }

            // if the deposit is less than the amount left to burn, burn the whole deposit and move on to the next
            if (feeDataArray[i].amount <= localData.amountLeft) {
                uint256 depositAmount = feeDataArray[i].amount;
                localData.feeAmount += (depositAmount * feePerLP);

                localData.amountLeft -= feeDataArray[i].amount;

                lpNFT.burn(feeDataArray[i].tokenID);

                delete feeDataArray[i];
                feeDataArray.pop();

                if (localData.amountLeft == 0) {
                    break;
                }
            } else {
                feeDataArray[i].amount -= localData.amountLeft;
                localData.feeAmount += (feePerLP * localData.amountLeft);
                break;
            }
        }

        localData.feePercentage = (localData.feeAmount) / bptAmountIn;

        hookAdjustedAmountsOutRaw = localData.amountsOutRaw;
        localData.tokens = _vault.getPoolTokens(localData.pool);

        localData.adminFeePercent = IUpdateWeightRunner(_updateWeightRunner).getQuantAMMUpliftFeeTake();

        // Charge fees proportional to the `amountOut` of each token.
        for (uint256 i = 0; i < localData.amountsOutRaw.length; i++) {
            uint256 exitFee = localData.amountsOutRaw[i].mulDown(localData.feePercentage);

            if (localData.adminFeePercent > 0) {
                localData.accruedQuantAMMFees[i] = exitFee.mulDown(localData.adminFeePercent);
            }

            localData.accruedFees[i] = exitFee - localData.accruedQuantAMMFees[i];
            hookAdjustedAmountsOutRaw[i] -= exitFee;
            // Fees don't need to be transferred to the hook, because donation will redeposit them in the Vault.
            // In effect, we will transfer a reduced amount of tokensOut to the caller, and leave the remainder
            // in the pool balance.
        }

        if (localData.adminFeePercent > 0) {
            _vault.addLiquidity(
                AddLiquidityParams({
                    pool: localData.pool,
                    to: IUpdateWeightRunner(_updateWeightRunner).getQuantAMMAdmin(),
                    maxAmountsIn: localData.accruedQuantAMMFees,
                    minBptAmountOut: localData.feeAmount.mulDown(localData.adminFeePercent) / 1e18,
                    kind: AddLiquidityKind.PROPORTIONAL,
                    userData: bytes("")
                })
            );
            emit ExitFeeCharged(
                userAddress,
                localData.pool,
                IERC20(localData.pool),
                localData.feeAmount.mulDown(localData.adminFeePercent) / 1e18
            );
        }

        if (localData.adminFeePercent != 1e18) {
            // Donates accrued fees back to LPs.
            _vault.addLiquidity(
                AddLiquidityParams({
                    pool: localData.pool,
                    to: msg.sender, // It would mint BPTs to router, but it's a donation so no BPT is minted
                    maxAmountsIn: localData.accruedFees, // Donate all accrued fees back to the pool (i.e. to the LPs)
                    minBptAmountOut: 0, // Donation does not return BPTs, any number above 0 will revert
                    kind: AddLiquidityKind.DONATION,
                    userData: bytes("") // User data is not used by donation, so we can set it to an empty string
                })
            );
        }

        return (true, hookAdjustedAmountsOutRaw);
    }

    /// @param _from the owner to transfer from
    /// @param _to the owner to transfer to
    /// @param _tokenID the token ID to transfer
    /// @notice aftertokenafterUpdate called after overridden _update function in LPNFT for transfers only
    function afterUpdate(address _from, address _to, uint256 _tokenID) public {
        if (msg.sender != address(lpNFT)) {
            revert TransferUpdateNonNft(_from, _to, msg.sender, _tokenID);
        }

        address poolAddress = nftPool[_tokenID];

        if (poolAddress == address(0)) {
            revert TransferUpdateTokenIDInvaid(_from, _to, _tokenID);
        }

        int256[] memory prices = IUpdateWeightRunner(_updateWeightRunner).getData(poolAddress);
        uint256 lpTokenDepositValueNow = getPoolLPTokenValue(prices, poolAddress, MULDIRECTION.MULDOWN);

        FeeData[] storage feeDataArray = poolsFeeData[poolAddress][_from];

        uint256 feeDataArrayLength = feeDataArray.length;
        uint256 tokenIdIndex;
        bool tokenIdIndexFound = false;

        //find the tokenID index in the array
        for (uint256 i; i < feeDataArrayLength; ++i) {
            if (feeDataArray[i].tokenID == _tokenID) {
                tokenIdIndex = i;
                tokenIdIndexFound = true;
                break;
            }
        }

        if (tokenIdIndexFound) {
            if (_to != address(0)) {
                // Update the deposit value to the current value of the pool in base currency (e.g. USD) and the block index to the current block number
                //vault.transferLPTokens(_from, _to, feeDataArray[i].amount);
                feeDataArray[tokenIdIndex].lpTokenDepositValue = lpTokenDepositValueNow;
                feeDataArray[tokenIdIndex].blockTimestampDeposit = uint32(block.number);
                feeDataArray[tokenIdIndex].upliftFeeBps = upliftFeeBps;

                //actual transfer not a afterTokenTransfer caused by a burn
                poolsFeeData[poolAddress][_to].push(feeDataArray[tokenIdIndex]);

                if (tokenIdIndex != feeDataArrayLength - 1) {
                    //Reordering the entire array could be expensive but it is the only way to keep true FILO
                    for (uint i = tokenIdIndex + 1; i < feeDataArrayLength; i++) {
                        delete feeDataArray[i - 1];
                        feeDataArray[i - 1] = feeDataArray[i];
                    }
                }

                delete feeDataArray[feeDataArrayLength - 1];
                feeDataArray.pop();
            }
        }
    }

    /**
     * @notice Sets the hook swap fee percentage, charged on every swap operation.
     * @dev This function must be permissioned.
     * @param hookFeePercentage The new hook fee percentage
     */
    function setHookSwapFeePercentage(uint64 hookFeePercentage) external onlyOwner {
        require(hookFeePercentage >= _MIN_SWAP_FEE_PERCENTAGE, "Below _MIN_SWAP_FEE_PERCENTAGE");
        require(hookFeePercentage <= _MAX_SWAP_FEE_PERCENTAGE, "Above _MAX_SWAP_FEE_PERCENTAGE");

        hookSwapFeePercentage = hookFeePercentage;

        emit HookSwapFeePercentageChanged(address(this), hookFeePercentage);
    }

    function getUserPoolFeeData(address _pool, address _user) public view returns (FeeData[] memory) {
        return poolsFeeData[_pool][_user];
    }

    enum MULDIRECTION {
        MULUP,
        MULDOWN
    }

    // Internal Functions

    /// @notice gets the notional value of the lp token in USD
    /// @param _prices the prices of the assets in the pool
    function getPoolLPTokenValue(
        int256[] memory _prices,
        address pool,
        MULDIRECTION _direction
    ) internal view returns (uint256) {
        uint256 poolValueInUSD;

        PoolData memory poolData = IVaultExplorer(address(_vault)).getPoolData(pool);
        uint256 poolTotalSupply = _vault.totalSupply(pool);

        for (uint i; i < poolData.tokens.length; ) {
            int256 priceScaled18 = _prices[i] * 1e18;
            if (_direction == MULDIRECTION.MULUP) {
                poolValueInUSD += FixedPoint.mulUp(uint256(priceScaled18), poolData.balancesLiveScaled18[i]);
            } else {
                poolValueInUSD += FixedPoint.mulDown(uint256(priceScaled18), poolData.balancesLiveScaled18[i]);
            }

            unchecked {
                ++i;
            }
        }

        return poolValueInUSD / poolTotalSupply;
    }

    function _ensureSelfRouter(address router) private view {
        if (router != address(this)) {
            revert CannotUseExternalRouter(router);
        }
    }
}
