# QuantAMM

### Prize Pool

- Total Pool: 49,600 OP
    
- H/M: 44,640 OP
    
- Low: 4,960 OP
    
- Starts:  December 20, 2024 Noon UTC
    
- Ends: January 15, 2025 Noon UTC 
    
- nSLOC:  3359

[//]: # (contest-details-open)

## About the Project

## Summary

QuantAMM is a next generation DeFi protocol launching Blockchain Traded Funds (BTFs).

LPs are no longer only chasing swap fees: the weights of the pool change to take advantage of current underlying price movements and therefore can overcome MEV and Impermanent Loss. QuantAMM does this in a continuous, responsive way with advanced, fully on-chain TradFi-style strategies. It avoids unresponsive, low-reward index products, and side-steps vault-like products where LPs have to trust off-chain managers with murky strategies & exposures. QuantAMM also allows community members with strategy ideas to use protocol-provided highly efficient strategy building blocks to build their own automated strategy pool.

The market making variant where weights change continuously over time is called Temporal Function Market Making (TFMM) 

[Auditor Documentation Quickstart Package](https://docsend.com/view/s/8bx7x3vvjj6y44rh)

### Short Form protocol explainers

Introductory business case for QuantAMM: [https://x.com/QuantAMMDeFi/status/1798725534865870964](https://x.com/QuantAMMDeFi/status/1798725534865870964)

Visual example of weight changes over time:  
[https://x.com/QuantAMMDeFi/status/1773724449411395691](https://x.com/QuantAMMDeFi/status/1773724449411395691)

Initial FAQ  
[https://x.com/QuantAMMDeFi/status/1778433255143842270](https://x.com/QuantAMMDeFi/status/1778433255143842270)  

#Articles

TFMM approach

https://medium.com/@QuantAMM/temporal-function-market-making-tfmm-the-use-of-amms-outside-of-core-liquidity-providing-bc403e76b97

General litepaper for TFMM infrastructure  
[https://www.quantamm.fi/research](https://www.quantamm.fi/research)

QuantAMM Approach

https://medium.com/@QuantAMM/the-state-of-asset-management-in-defi-and-the-btf-revolution-5622abf9920a

General QuantAMM Strategy litepaper  
[https://www.quantamm.fi/research](https://www.quantamm.fi/research)

Balancer V3 Partnership  

[https://medium.com/@QuantAMM/quantamm-x-balancer-v3-046af77ddc81](https://medium.com/@QuantAMM/quantamm-x-balancer-v3-046af77ddc81)

QuantAMM create a novel balancer pool type that has a custom TFMM invariant function instead of the standard G3M invariant function provided in a standard Balancer Weighted pool.   
While the TFMM invariant changes every block, at any given block QuantAMM pools are G3M pools, which means that they are identical for single block actions to weighted pools. Get normalized weights is the primary source of difference between the two implementations. 

There are interesting multiblock implications as stated in: [https://arxiv.org/abs/2404.15489](https://arxiv.org/abs/2404.15489)   

This means that Vault actions, Swap actions, deposit/withdraw actions are all provided by the underlying balancer infrastructure. While QuantAMM have implemented regression tests base underlying functionality provided in balancer contracts are out of scope. 

##Initial Protocol Technical Description


1. Update Weight Runner – Responsible for the inter-block weight update rule process. This has one entry point of “Perform Update” whose output is to save new “previous fixed weight” and “weight multiplier per block unit” to the QuantAMM Base Pool

1. QuantAMMWeightedPool – responsible for all reserves and trading. Any deposit/withdraw functionality is inherited from balancer v3 here. 

There are auxiliary contracts that are used, these can be grouped by:

- QuantAMM Based Estimators – these are the generic building blocks containing the novel estimators and the intermediate state per pool required for those calculations

- Rules – Inheriting a base class that maintains moving averages, these rules are responsible for the use of the “QuantAMMBased[]” estimators into applicable strategies

- QuantAMM Storage – storage functions encapsulated to pack and unpack variables into more efficient SSTOREs. 

- Oracles – There are standard oracle wrappers, however there are two kinds of bespoke oracles: 

    - LPOracles – get the underlying value of the base pool, this is an example of a composite pool oracle. In theory, other composite pool oracles based on other factors such as risk variables can be created

    - Multi-hop oracles – it might be that there isn’t a desired oracle that takes you from A->B, multihop oracles abstract the multihop logic away from the update weight runner into a wrapped oracle. 


### Storing weights and their multipliers

For calculations an 18dp maths library is used. Does storing weights and multipliers at 18dp have benefits for running a pool? Int128 gives the necessary 18dp required, allowing for one constituent to be stored in one slot.

Simulations show no difference with storing at 9dp during a market bull/bear run cycle.

This means the protocol can pack weight at a 9dp resolution with little to no impact on pool performance. This means 8 units now pack in 1 int256 slot, which means 4 constituents and their multipliers fit in one slot. 

Packing like this has one small drawback. Retrieval is more efficient as an all-or-nothing thing. Getting individual weights is not basic but, given the use cases, 90% of the time all the weights are needed anyway. 

### Update weight runner

The update weight runner really performs the coordination of weight updates while only performing DR and final setting functions. It is intended to be a singleton deployment that is recorded to allow certain functionality to only be called by the QuantAMM Base Pool and vice versa. 

### Setting rules

Called during the creation of a pool setRuleForPool sets up all the cache values to run a particular pool and a particular strategy. This could allow the running of a pool without trading being enabled for a pool, allowing for provisional assessment and parallel running of a pool in production. 

### Calling updates

Checks are performed on whether or not the update interval has been reached. This then triggers an update: 

- Get the oracle data required from either normal oracles, multihop oracles or LPOracles

- Pass that data to the updaterule.CalculateNewWeights(…) function

### Getting oracle data

There are two caches of oracles: optimised and non-optimised. Optimised is solely storing happy-path first-choice oracles for a rule/pool combo. The reason why this is split from the backups is efficiency. Accessing this single array reduced the large number of SLOADs from multidimensional array access.

A basic oracle wrapper is provided and others can come along and make derived oracle wrapper classes. Use of those oracles is gated by a registration process so that some rogue oracle is not introduced. 

### Rule structure and calling

The base class for update rules provides an updaterule.CalculateNewWeights(…) function that keeps the core requirements of guards and moving averages in a centralized place while allowing individual rules to override the getweights function. 

The QuantAMMBased classes storing the intermediates allows for an inheritance structure that preserves key areas of code in centralised places. 

The int256s used are converted to 18dp using the PRBMath lib.

### Guard Rail process

See multi-block MEV discussion above. The guard rails are in the base update rule class and functions are always called to provide consistency. 

### Determining multipliers and getting weights

A linear multiplier will always be stored from the update weight runner and the QuantAMM Base Pool. Later there is the possibility in the QuantAMM Base Pool to provide a more advanced feature where the linear multiplier is shifted according to more sophisticated randomization or geometric interpolation. 

While the logic to determine the multiplier is simple given the block interval and change in weight, specific logic is needed to find the block.timestamp which the first constituent will hit a guard rail. Continuing along the linear interpolation path is fine given the guard rails. However, once a guard rail is hit more complex logic would be needed so the pool freezes at that weight. 

### Economic reason to keep interpolating

Why is this desirable? To be clear there are multiple levels of redundancy that should make this a non-issue for triggering the update rule, however in the case that an update is not called and there is a strong signal to rebalance, the worst thing you can do is shift weights against that signal – at least according to the rule – and the second worst thing to do is to stop. So carrying on should reduce impermanent loss or actually continue generating alpha. 

What would it take for this to not be the case? The signal would need to reverse. Given the effective memory lengths of strategies commonly found in testing are of the order of days and weeks, as well as the update intervals currently being every hour or day, it would take a considerable sustained signal change for this to be the case. Even if this were the case, given the update intervals it would probably take even longer for it to be reflected in the normal running of pools. 

Hopefully, by that time, an update would be triggered or another update interval reached.

### Actors

**QuantAMM Admin (trusted)** \- a timelock that will be referenced by most contracts for potential admin override functions. 

**Pool Owner** \- Creates and owns the pool, on creation it could be configured that the pool owner has certain admin rights or could be completely locked out. 

**LP** \- a depositor into a pool, the LP will receive BPTs 

**Trader** \- an actor intending to use swap functions to swap one constituent for another based on the TFMM trading function prices. A variant of trader could be an arbitrageur looking to make a risk free profit by trading between a QuantAMM pool and another pool, this could be another QuantAMM pool or external venue. 

**QuantAMM pool runner** \- periodically the pool is eligible to have the weight trajectory and strategy updated. This is performed given a single entry point in the “update weight runner”. While this can be technically done by anyone, a chainlink automation job will trigger on a standard periodic basis to automatically update all pool strategies. 

[//]: # (contest-details-close)

[//]: # (scope-open)

## Scope (contracts)

The repository is a snapshot of the balancer v3 monorepo. [https://github.com/balancer/balancer-v3-monorepo/](https://github.com/balancer/balancer-v3-monorepo/) 

```
pkg/pool-quantamm/contracts
├── ChainlinkOracle.sol
├── MultiHopOracle.sol
├── QuantAMMStorage.sol
├── QuantAMMWeightedPoolFactory.sol
├── QuantAMMWeightedPool.sol
├── rules
│   ├── AntimomentumUpdateRule.sol
│   ├── base
│   │   ├── QuantammBasedRuleHelpers.sol
│   │   ├── QuantammCovarianceBasedRule.sol
│   │   ├── QuantammGradientBasedRule.sol
│   │   ├── QuantammMathGuard.sol
│   │   ├── QuantammMathMovingAverage.sol
│   │   └── QuantammVarianceBasedRule.sol
│   ├── ChannelFollowingUpdateRule.sol
│   ├── DifferenceMomentumUpdateRule.sol
│   ├── MinimumVarianceUpdateRule.sol
│   ├── MomentumUpdateRule.sol
│   ├── PowerChannelUpdateRule.sol
│   └── UpdateRule.sol
└── UpdateWeightRunner.sol

pkg/pool-hooks/contracts/hooks-quantamm
├── LPNFT.sol
└── UpliftOnlyExample.sol

pkg/interfaces/contracts/pool-quantamm
├── IQuantAMMWeightedPool.sol
├── IUpdateRule.sol
├── IUpdateWeightRunner.sol
├── OracleWrapper.sol
```

## Compatibilities

  Blockchains:

     OP Mainnet
     Arbitrum 
     Ethereum Mainnet
     Base
     
  Tokens:
     ERC20 tokens. 
     
     All non standard ERC20 tokens including but not limited to rebasing, allowlist, double, entrypoint etc. are out of scope.

Any tokens specified to be compatible with Balancer-V3 deployment by Balancer.   
Details can be found both in Balancer V3 documentation and Balancer V3 audits. 

[//]: # (scope-close)

[//]: # (getting-started-open)

## Setup

From the root command:

```
yarn install
```

From any of the following:

- /pkg/pool-quantamm/  
- /pkg/pool-hooks  
- /pkg/interaces/

commands: 

```
forge compile  
forge test
```

[//]: # (getting-started-close)

## Known Issues

- Any acknowledged issue in the included root audit folder audit reports. These may include both issues with fixes implemented or solely acknowledged. This does not include potential issues with the fixes which are in scope for audit.

- Any acknowledged issue in the included pool-quantamm audit folder audit reports. These may include both issues with fixes implemented or solely acknowledged. This does not include potential issues with the fixes which are in scope for audit.
  
- QuantAMM rule equations have theoretical limitations that are unguarded \- for instance divide by potentially 0 or a combination of parameters and prices causes a revert based on a caught overflow/underflow, these are expected to revert and fail the entire perform update call if the condition is met. Either a repeated later call of perform update in the update weight runner or a manual admin intervention is the desired functionality for such an edge case. We do not exclude issues that find silent overflows, unintended sign changes based on the whitepaper equations, weight vectors that mean calculated values are not in accordance with whitepaper equations or ultimate breach of guard rails in a given block inside the weighted pool itself. 

- A known scenario is that in certain extreme edge cases the guard rails will provide a last possible interpolation block that is before the update interval block. Unless a guard rail is broken in the process this expected functionality.

- QuantAMM uses oracles periodically for update rule updates, it also uses a given oracle for uplift calculations for fees. Oracle manipulation is a known risk however Chainlink oracles are going to be used to begin with and any new oracle wrapper and oracle choice has to be approved by the QuantAMM protocol team for security. Manipulation risk of influencing the update rules weight trajectories or influencing the price to make a call fail is out of scope for the audit and a known issue as is potential manipulation of fee quantity given oracle manipulation. 

- Issues found where data from a standard, non manipulated Chainlink Oracle that is providing data that is in spec (i.e. not a bad or badly formatted price) for an in scope token means that the update weight runner does not run the algos as expected is in scope. For example if the Chainlink wrapper given such an oracle does not do decimal conversion properly. 

- The mathematics of the update rules works of periodic updates and if random update intervals are applied this effects the outcome of the strategy. Failures and restarts of the updates for any reason are out of scope. Admin functions are implemented to override key intermediate state variables to be able to restart appropriate update rule values. Underlying pause functionality provided by Balancer is also intended for use during manual intervention. This includes any issue with unpausing the pool after a period of pausing or a jump in weight values based on a manual intervention period. The effects of random interval time updates are out of scope, if there is any issue that means that a pool cannot reset values that is in scope. 

- Potential manipulation/attack risk of any sort on pools with 0 fees is out of scope. This includes withdrawal fees, whose minimum allowed fee is the single swap fee.

- Highlighted in the Cyfrin report and by the QuantAMM team in previous documentation, there is an attack surface for multi-block MEV if appropriate guard rails are not applied. Issues when a pool is configured to have inappropriate guard rails is out of scope and a known issue. 

- Single asset deposits can cause issues at extreme values of weights and/or deposit sums. This will usually cause a deposit to fail or experience extreme slippage. These issues for single asset deposits are out of scope. If a single asset deposit can be used to attack the pool itself that does not have additional out of scope properties (e.g. inappropriate guard rails) then that is in scope.

- Pools require an approval from the quantamm team to be included in the update weight runner process. If they are not approved they are essentially fixed weight pools. Issues where creation process results in "fixed" CFMM weight pools (i.e. if they are not approved by the QuantAMM team for the update weight runner) are in scope, however dynamic functionality / weight issues found must be found on QuantAMM approved pools. 

- The quantammAdmin address is intended to be an OpenZepplin timelock that is configured properly and for the purposes of the audit will be considered secure and working correctly. 

- Potential issues with the use of block.timestamp are known and out of scope.

- Parameter selections that cause overall negative performance for LPs in certain periods of time are out of scope unless they cause other issues than negative performance. 

- Weight changes provide arbitrage opportunities. This is fundamental to the mechanism of QuantAMM pools (it is how they rebalance) and is expected behaviour. The resulting rebalancing causes immediate economic impact to the pool. However, pool creators aim to make TFMM pools where the overall performance of the pool over time will provide and therefore any such impact is out of scope.

- Issues that arise when the quantammAdmin is maliciously taken over are out of scope and known. 

- Balancer V3 batch swap routing is in scope however any issues not related to a combination of the batch swap router and QuantAMMWeightedPools that are found in Balancer audit reports are known issues and out of scope. 

- UpliftOnlyExample router/hook is expected to have a available and valid oracle to get prices in update weight runner. It does not have to be a QuantAMMWeightedPool and standard Balancer WeightedPool is in scope.

- UpliftOnlyExample router/hook ordering of donations and fee taking is known to have the same donation caveats related to Balancer base audit. 

- Inability to deposit after the stated number of deposits is expected and the depositor/withdrawer is expected to have enough to pay for the gas of any of the operations including transfers that are more expensive.

- A pool creator can be approved for admin functionality, this gives wide control over reset strategy features and override weight features. This is not intended to be the case for anything other than pools with regulatory considerations or gated depositor pools. Normal pool creators will not be granted this privilege. There are various known potential malicious issues with approving pool creators to perform admin functions. If there is a pool where the pool creator has not been approved administrative function, manipulation of any aspect of the pool by the untrusted creator is in scope.

[//]: # (known-issues-close)




