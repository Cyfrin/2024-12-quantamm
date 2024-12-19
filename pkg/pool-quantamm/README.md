# What is QuantAMM?

QuantAMM is a novel DEX that runs a variant of Constant Function Market Making (CFMM)–Temporal Function Market Making (TFMM). Within any given block QuantAMMWeightedPools pools are generic Balancer-style AMM pools run on Balancer v3 infrastructure, but the vector of weights of the pool (the allocation of value between pool constituents) change between blocks in accordance with a specified “update rule”. Arbitrageurs act, just as in vanilla DEX pools, trading so as to bring each pool's holdings into alignment with its vector of weights. The rules for changing weights act as strategies, and good strategies can lead to performance that more than makes up for the rebalancing cost paid to arbitrageurs. (To be clear, capital is at risk.) Oracles are called to provide the information (commonly, market prices) needed for an update rule to operate.
What is novel in QuantAMM?


1. Novel gradient, variance, and covariance estimators: Update rules often reuse various mathematical primitives, which are provided as useful Lego bricks. These are designed for both gas efficiency and for performance in giving signals for update rules to make use of. One example is a statistically motivated gradient estimator–knowing how a price has changed is very important information, but naive on-chain approaches have poor performance. The provided estimators require little storage and can be configured with a temporal “memory” of a desired length.

2. Viable with arbitrageurs only: As the protocol is designed for pools that give capital gain uplift to LPs, rather than relying on swap fee revenue, QuantAMM pools can work off toxic flow only. This allows core features that are institution-friendly, such as compliance hooks, that are unpalatable to vanilla DEXs that are always trying to increase retail trading volume.

3. Continuous Temporal Function Market Making: Not having a fixed target weight has certain benefits. For trend-following strategies, the worst thing to do is to go ‘the wrong way', and the second-worst thing to do is to stop. As a failsafe, Temporal Function Market Making allows for continuous weight changes, so instead of stopping when a preset target weight is reached the weight changes continue in the calculated direction until some form of 'guardrail' is reached (see “Is there MEV protection?” below).

# How are the weights at a given block determined?

An Update Rule is called at a chosen frequency, say every day. It queries oracles and performs calculations to give a weight change at that time-scale, which is then scaled to become a ‘per block’ change in weights.

The simplest thing to go then is to linearly interpolate up to that value over a given period of time, so the weight at any given block is: 

‘Previous fixed weight’ + [('current block timestamp' – ‘block timestamp at which that previous weight was fixed')*'weight multiplier per block unit']

# Is there MEV protection?

Weight changes are, in theory, front-runnable, though this is intrinsically a multi-block attack. (Within a given block QuantAMM pools look like vanilla geometric mean market maker pools.) In analogy with how trades have to be above a certain threshold to be front-runnable on some platforms, here the weight changes have to be 'big enough'. Three types of guard rails provide MEV protection:

1. Absolute weight guardrail. No asset's weight can go below a set minimum guard rail value or above a related maximum value. 

2. Dynamic weight change guardrail. Weights between blocks can only change up to a ‘speed limit’ amount even if the update rule is telling it to change faster. 

3. Proportional trade size per pool. A pool cannot change its reserves beyond a configured % per operation (trade, block trade, single asset deposit/withdrawal)

Each of these guardrails depends on a numerical value that must be chosen by the pool creator.
The combination of these guardrails can provide multi-block MEV protection.

# What is the general protocol design?

QuantAMM is built on Balancer v3 architecture, inheriting the base weighted pool design but with a custom invariant that takes into account interblock changes. 

Two part protocol

The protocol design is split into two core contracts:

1. Update Weight Runner – Responsible for the inter-block weight update rule process. This has one entry point of “Perform Update” whose output is to save new “previous fixed weight” and “weight multiplier per block unit” to the QuantAMM Base Pool

1. QuantAMMWeightedPool – responsible for all reserves and trading. Any deposit/withdraw functionality is inherited from balancer v3 here. 

There are auxiliary contracts that are used, these can be grouped by:

- QuantAMM Based Estimators – these are the generic building blocks containing the novel estimators and the intermediate state per pool required for those calculations

- Rules – Inheriting a base class that maintains moving averages, these rules are responsible for the use of the “QuantAMMBased[]” estimators into applicable strategies

- QuantAMM Storage – storage functions encapsulated to pack and unpack variables into more efficient SSTOREs. 

- Oracles – There are standard oracle wrappers, however there are two kinds of bespoke oracles: 

    - LPOracles – get the underlying value of the base pool, this is an example of a composite pool oracle. In theory, other composite pool oracles based on other factors such as risk variables can be created

    - Multi-hop oracles – it might be that there isn’t a desired oracle that takes you from A->B, multihop oracles abstract the multihop logic away from the update weight runner into a wrapped oracle. 

- Routers – There are two pool types

    - Creator pools – these have specific, per-deposit, charged-on-uplift-only withdrawal fees, so LP tokens are NFTs.

    - Index pools – more standard pools that have simpler fee structures and so have ERC20 LP tokens.

# Oracle use in QuantAMM

Oracles are used in the core of QuantAMM. Traditionally, the use of oracles in DEXs has been vulnerable to oracle manipulation attacks, each QuantAMMuse of oracles provides some protection against this. There are multiple areas of use of oracles:

1. Update weight runner, update rule functionality – oracles are used as the input values for rules to run. As the provided estimators smooth oracle values over time, you would need to have a sustained oracle attack for hours or days for a significant effect. Also, these smoothed moving averages can also be used instead of current prices in the rules, allowing a second layer of smoothing. Long memories (high lambda parameters) combined with moving-average smoothing have proven to be the most alpha generating in standard QuantAMM strategies. 

1. Uplift based fees – given specified DAO controlled oracles to USD on deposit the pool records the USD value of an LP token. On withdrawal, for creator pools, the pool records the new USD value of the LP token and a withdrawal-based fee is taken based on how long you have LP’d (the longer you LP the smaller proportion of fee is taken) and the uplift generated. If the pool has not made any uplift then only the withdrawal amount needed for protection against using deposit/withdraw to perform trades is taken.

# Storing weights and their multipliers

For calculations an 18dp maths library is used. Does storing weights and multipliers at 18dp have benefits for running a pool? Int128 gives the necessary 18dp required, allowing for one constituent to be stored in one slot.

Simulations show no difference with storing at 9dp during a market bull/bear run cycle.

This means the protocol can pack weight at a 9dp resolution with little to no impact on pool performance. This means 8 units now pack in 1 int256 slot, which means 4 constituents and their multipliers fit in one slot. 

Packing like this has one small drawback. Retrieval is more efficient as an all-or-nothing thing. Getting individual weights is not basic but, given the use cases, 90% of the time all the weights are needed anyway. 

# Update weight runner

The update weight runner really performs the coordination of weight updates while only performing DR and final setting functions. It is intended to be a singleton deployment that is recorded in the DAO to allow certain functionality to only be called by the QuantAMM Base Pool and vice versa. 


![](./update_rule_trigger_workflow.jpeg)

## Setting rules

Called during the creation of a pool setRuleForPool sets up all the cache values to run a particular pool and a particular strategy. This could allow the running of a pool without trading being enabled for a pool, allowing for provisional assessment and parallel running of a pool in production. 

## Calling updates

Checks are performed on whether or not the update interval has been reached. This then triggers an update: 

- Get the oracle data required from either normal oracles, multihop oracles or LPOracles

- Pass that data to the updaterule.CalculateNewWeights(…) function

## Getting oracle data

There are two caches of oracles: optimised and non-optimised. Optimised is solely storing happy-path first-choice oracles for a rule/pool combo. The reason why this is split from the backups is efficiency. Accessing this single array reduced the large number of SLOADs from multidimensional array access.

A basic oracle wrapper is provided and others can come along and make derived oracle wrapper classes. Use of those oracles is gated by a registration process so that some rogue oracle is not introduced. 

## Rule structure and calling

The base class for update rules provides an updaterule.CalculateNewWeights(…) function that keeps the core requirements of guards and moving averages in a centralized place while allowing individual rules to override the getweights function. 

The QuantAMMBased classes storing the intermediates allows for an inheritance structure that preserves key areas of code in centralised places. 

The int256s used are converted to 18dp using the PRBMath lib.

## Guard Rail process

See multi-block MEV discussion above. The guard rails are in the base update rule class and functions are always called to provide consistency. 

## Determining multipliers and getting weights

A linear multiplier will always be stored from the update weight runner and the QuantAMM Base Pool. Later there is the possibility in the QuantAMM Base Pool to provide a more advanced feature where the linear multiplier is shifted according to more sophisticated randomization or geometric interpolation. 

While the logic to determine the multiplier is simple given the block interval and change in weight, specific logic is needed to find the block.timestamp which the first constituent will hit a guard rail. Continuing along the linear interpolation path is fine given the guard rails. However, once a guard rail is hit more complex logic would be needed so the pool freezes at that weight. 

## Economic reason to keep interpolating

Why is this desirable? To be clear there are multiple levels of redundancy that should make this a non-issue for triggering the update rule, however in the case that an update is not called and there is a strong signal to rebalance, the worst thing you can do is shift weights against that signal – at least according to the rule – and the second worst thing to do is to stop. So carrying on should reduce impermanent loss or actually continue generating alpha. 

What would it take for this to not be the case? The signal would need to reverse. Given the effective memory lengths of strategies commonly found in testing are of the order of days and weeks, as well as the update intervals currently being every hour or day, it would take a considerable sustained signal change for this to be the case. Even if this were the case, given the update intervals it would probably take even longer for it to be reflected in the normal running of pools. 

Hopefully, by that time, an update would be triggered or another update interval reached.

## Pool Creation

Pools are created via their respective factory methods that ensure parameter requirements are met. SetRuleForPool is called during the construction of a pool, however registration into the UpdateWeightRunner is protocol-controlled. 

## Index pools hooks

Indices are great and simple. They usually want to track a given signal and their exposure should closely match it. Often protocols have attempted to create index trackers by trading themselves. This means the protocol can take a much larger chunk of the swap fees and the product will still serve its purpose. The LP tokens should also be ERC20 compliant, producing all the right events etc. The balance of the ERC20 LP is the central vault reserves given override functions in the token contract.

Fixed fees are needed as, strictly speaking, if there is variation in fees between deposits the ERC20 tokens will not be worth the same value and will not be fungible. This creates a potential downside of this model as fixed fees on total withdrawal could be large or proportionally larger compared to uplift-only fees. 

## Creator pools hooks

Creator pools provide a fee structure that mainly comprises an uplift-only model. Each deposit tracks its LP token value in a base currency. On withdrawal, any uplift since deposit will be the subject of the fee. This should be attractive to LPs as, if the pool has not had any uplift, only the minimum required fee to prevent withdrawal / deposit attacks is changed. 

The uplift is calculated as: base + (x / ”time since deposit” ^ y). If the uplift comes within a small % of the base the fee reverts to the base for simplicity.

If you have multiple deposits into a pool how is a big or partial withdrawal handled? A FIFO mechanism is applied draining earlier deposits of balance. Again this should be attractive as the stickier the LP, the less is taken as fees. If a deposit is fully drained then it can be deleted leading to a small gas benefit during the withdrawal. 

