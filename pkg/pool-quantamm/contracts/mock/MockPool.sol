// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;
import "../UpdateWeightRunner.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IUpdateRule.sol";
import "../rules/UpdateRule.sol";

contract MockPool {
    uint16 public  immutable updateInterval;

    int256 public lambda;

    int256 public epsilonMax;

    int256 public absoluteWeightGuardRail;

    uint256 private invariantValue;

    uint private numberOfAssets;

    uint immutable oracleStalenessThreshold;

    address  immutable updateWeightRunner;

    uint256 poolLpTokenValue;

    uint256 public afterTokenTransferID;

    constructor(uint16 _updateInterval, int256 _lambda, address _updateWeightRunner) {
        updateInterval = _updateInterval;
        lambda = _lambda;
        epsilonMax = 1 * 1e18; // PRBMathSD69x18 1
        absoluteWeightGuardRail = 1 * 1e18; // PRBMathSD69x18 1
        oracleStalenessThreshold = 4 hours;
        updateWeightRunner = _updateWeightRunner;
    }

    function numAssets() external view returns (uint) {
        return numberOfAssets;
    }

    function getBaseAssets() external view returns (IERC20[] memory) {}

    function getAssets() external view returns (address[] memory) {}

    function getEpsilonMax() external view returns (int256) {
        return epsilonMax;
    }

    function getAbsoluteGuardRails() external view returns (int256) {
        return absoluteWeightGuardRail;
    }

    function setRuleForPool(
        IUpdateRule _rule,
        address[][] calldata _poolOracles,
        uint64[] calldata _lambda,
        int256[][] calldata _ruleParameters,
        uint64 _epsilonMax,
        uint64 _absoluteWeightGuardRail,
        uint40 _updateInterval,
        address _poolManager
    ) external {
        IQuantAMMWeightedPool.PoolSettings memory _poolSettings;
        _poolSettings.rule = _rule;
        _poolSettings.oracles = _poolOracles;
        _poolSettings.updateInterval = uint16(_updateInterval);
        _poolSettings.lambda = _lambda;
        _poolSettings.epsilonMax = _epsilonMax;
        _poolSettings.absoluteWeightGuardRail = _absoluteWeightGuardRail;
        _poolSettings.ruleParameters = _ruleParameters;
        _poolSettings.poolManager = _poolManager;

        UpdateWeightRunner(updateWeightRunner).setRuleForPool(_poolSettings);
    }

    function setNumberOfAssets(uint _numberOfAssets) external {
        numberOfAssets = _numberOfAssets;
    }

    function performRuleUpdate() external {}

    function callSetRuleForPool(
        UpdateWeightRunner _updateWeightRunner,
        IUpdateRule _rule,
        address[][] calldata _poolOracles,
        uint64[] calldata _lambda,
        int256[][] calldata _ruleParameters,
        uint64 _epsilonMax,
        uint64 _absoluteWeightGuardRail
    ) public {
        IQuantAMMWeightedPool.PoolSettings memory _poolSettings;

        _poolSettings.rule = _rule;
        _poolSettings.oracles = _poolOracles;
        _poolSettings.updateInterval = updateInterval;
        _poolSettings.lambda = _lambda;
        _poolSettings.epsilonMax = _epsilonMax;
        _poolSettings.absoluteWeightGuardRail = _absoluteWeightGuardRail;
        _poolSettings.ruleParameters = _ruleParameters;

        _updateWeightRunner.setRuleForPool(_poolSettings);
        _updateWeightRunner.performUpdate(address(this));
    }

    function setLambda(int256 _lambda) public {
        lambda = _lambda;
    }

    function setEpsilonMax(int256 _epsilonMax) public {
        epsilonMax = _epsilonMax;
    }

    function setAbsoluteWeightGuardRail(int256 _absoluteWeightGuardRail) public {
        absoluteWeightGuardRail = _absoluteWeightGuardRail;
    }

    function setInvariant(uint256 _invariant) public {
        invariantValue = _invariant;
    }

    function getTokenAddress() public pure returns (address tokenAddress) {
        return address(0);
    }

    function getOracleStalenessThreshold() external view returns (uint) {
        return oracleStalenessThreshold;
    }

    function setPoolLPTokenValue(uint256 _poolLPTokenValue) public {
        poolLpTokenValue = _poolLPTokenValue;
    }

    function getPoolLPTokenValue(int256[] memory /*_prices*/) public view returns (uint256) {
        return poolLpTokenValue;
    }

    function afterTokenTransfer(address /*from*/, address /*to*/, uint256 firstTokenId) public {
        afterTokenTransferID = firstTokenId;
    }
}
