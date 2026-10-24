//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Index
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const indexAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: '_name', internalType: 'string', type: 'string' },
      { name: '_symbol', internalType: 'string', type: 'string' },
      { name: '_indexManager', internalType: 'address', type: 'address' },
      { name: '_router', internalType: 'address', type: 'address' },
      { name: '_usdcAddress', internalType: 'address', type: 'address' },
      { name: '_priceFeedManager', internalType: 'address', type: 'address' },
      { name: '_swapManager', internalType: 'address', type: 'address' },
      {
        name: '_uniswapUniversalRouter',
        internalType: 'address',
        type: 'address',
      },
      {
        name: '_asset0',
        internalType: 'struct IndexAsset',
        type: 'tuple',
        components: [
          { name: 'asset', internalType: 'address', type: 'address' },
          {
            name: 'weightPercentage',
            internalType: 'uint128',
            type: 'uint128',
          },
        ],
      },
      {
        name: '_asset1',
        internalType: 'struct IndexAsset',
        type: 'tuple',
        components: [
          { name: 'asset', internalType: 'address', type: 'address' },
          {
            name: 'weightPercentage',
            internalType: 'uint128',
            type: 'uint128',
          },
        ],
      },
      { name: '_feePercentage', internalType: 'uint32', type: 'uint32' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'DOMAIN_SEPARATOR',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'owner', internalType: 'address', type: 'address' },
      { name: 'spender', internalType: 'address', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'spender', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'cancelWeightUpdate',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '_collector', internalType: 'address', type: 'address' }],
    name: 'collectFees',
    outputs: [
      { name: 'feesCollected', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'decimals',
    outputs: [{ name: '', internalType: 'uint8', type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'eip712Domain',
    outputs: [
      { name: 'fields', internalType: 'bytes1', type: 'bytes1' },
      { name: 'name', internalType: 'string', type: 'string' },
      { name: 'version', internalType: 'string', type: 'string' },
      { name: 'chainId', internalType: 'uint256', type: 'uint256' },
      { name: 'verifyingContract', internalType: 'address', type: 'address' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
      { name: 'extensions', internalType: 'uint256[]', type: 'uint256[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'executeWeightUpdate',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAsset0',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAsset1',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAssetsAndUsdcDecimals',
    outputs: [
      { name: 'asset0Decimals', internalType: 'uint8', type: 'uint8' },
      { name: 'asset1Decimals', internalType: 'uint8', type: 'uint8' },
      { name: 'usdcDecimals', internalType: 'uint8', type: 'uint8' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAssetsEffectiveWeights',
    outputs: [
      { name: 'effectiveWeight0', internalType: 'uint128', type: 'uint128' },
      { name: 'effectiveWeight1', internalType: 'uint128', type: 'uint128' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAssetsPendingWeights',
    outputs: [
      { name: '', internalType: 'uint128', type: 'uint128' },
      { name: '', internalType: 'uint128', type: 'uint128' },
      { name: '', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAssetsReserves',
    outputs: [
      { name: '', internalType: 'uint128', type: 'uint128' },
      { name: '', internalType: 'uint128', type: 'uint128' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAssetsReservesStdDecimals',
    outputs: [
      { name: '', internalType: 'uint256', type: 'uint256' },
      { name: '', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAssetsUsdValue',
    outputs: [
      { name: 'asset0TotalUsdValue', internalType: 'uint256', type: 'uint256' },
      { name: 'asset1TotalUsdValue', internalType: 'uint256', type: 'uint256' },
      { name: 'totalUsdValue', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getAssetsWeights',
    outputs: [
      { name: '', internalType: 'uint128', type: 'uint128' },
      { name: '', internalType: 'uint128', type: 'uint128' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getFeesInfo',
    outputs: [
      { name: 'feePercentage', internalType: 'uint32', type: 'uint32' },
      { name: 'totalFees', internalType: 'uint128', type: 'uint128' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getIndexManager',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getInitializationStatus',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getRouter',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getUsdc',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_depositor', internalType: 'address', type: 'address' },
      { name: '_underlyingAmount0', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'initialize',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_usdcAmountIn', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'minMintPreview',
    outputs: [
      { name: 'minSharesToMint', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_sharesAmountIn', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'minRedeemPreview',
    outputs: [
      { name: 'minUsdcToReceive', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_to', internalType: 'address', type: 'address' },
      { name: '_usdcAmountIn', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'mintShares',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'name',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_owner', internalType: 'address', type: 'address' }],
    name: 'nonces',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'owner', internalType: 'address', type: 'address' },
      { name: 'spender', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
      { name: 'deadline', internalType: 'uint256', type: 'uint256' },
      { name: 'v', internalType: 'uint8', type: 'uint8' },
      { name: 'r', internalType: 'bytes32', type: 'bytes32' },
      { name: 's', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'permit',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_newWeightAsset0', internalType: 'uint128', type: 'uint128' },
    ],
    name: 'proposeUpdateWeights',
    outputs: [
      {
        name: 'implementationTimestamp',
        internalType: 'uint256',
        type: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'rebalanceIndex',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_from', internalType: 'address', type: 'address' },
      { name: '_sharesAmount', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'redeem',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'symbol',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'to', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'from', internalType: 'address', type: 'address' },
      { name: 'to', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'transferFrom',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'owner',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'spender',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'value',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'Approval',
  },
  { type: 'event', anonymous: false, inputs: [], name: 'EIP712DomainChanged' },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'feeCollector',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'feeAmount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'FeesCollected',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'depositor',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'asset0Amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset1Amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset0UsdValue',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset1UsdValue',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'sharesMinted',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'IndexInitialized',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'asset0ReserveBefore',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset1ReserveBefore',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset0ReserveAfter',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset1ReserveAfter',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'IndexRebalanced',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'user', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'sharesBurned',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset0Amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset1Amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'usdcAmountOut',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'feeAmount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'SharesBurned',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'user', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'sharesMinted',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset0Amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'asset1Amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'usdcAmountIn',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'feeAmount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'SharesMinted',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'from', internalType: 'address', type: 'address', indexed: true },
      { name: 'to', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'value',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'Transfer',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'cancelledAsset0Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'cancelledAsset1Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
    ],
    name: 'WeightsUpdateCancelled',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'oldAsset0Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'oldAsset1Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'newAsset0Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'newAsset1Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'executableAt',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'WeightsUpdateProposed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'reasonData',
        internalType: 'bytes',
        type: 'bytes',
        indexed: false,
      },
    ],
    name: 'WeightsUpdateRebalanceFailed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [],
    name: 'WeightsUpdateRebalanceSkipped',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'asset0Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'asset1Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
    ],
    name: 'WeightsUpdated',
  },
  { type: 'error', inputs: [], name: 'ECDSAInvalidSignature' },
  {
    type: 'error',
    inputs: [{ name: 'length', internalType: 'uint256', type: 'uint256' }],
    name: 'ECDSAInvalidSignatureLength',
  },
  {
    type: 'error',
    inputs: [{ name: 's', internalType: 'bytes32', type: 'bytes32' }],
    name: 'ECDSAInvalidSignatureS',
  },
  {
    type: 'error',
    inputs: [
      { name: 'spender', internalType: 'address', type: 'address' },
      { name: 'allowance', internalType: 'uint256', type: 'uint256' },
      { name: 'needed', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'ERC20InsufficientAllowance',
  },
  {
    type: 'error',
    inputs: [
      { name: 'sender', internalType: 'address', type: 'address' },
      { name: 'balance', internalType: 'uint256', type: 'uint256' },
      { name: 'needed', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'ERC20InsufficientBalance',
  },
  {
    type: 'error',
    inputs: [{ name: 'approver', internalType: 'address', type: 'address' }],
    name: 'ERC20InvalidApprover',
  },
  {
    type: 'error',
    inputs: [{ name: 'receiver', internalType: 'address', type: 'address' }],
    name: 'ERC20InvalidReceiver',
  },
  {
    type: 'error',
    inputs: [{ name: 'sender', internalType: 'address', type: 'address' }],
    name: 'ERC20InvalidSender',
  },
  {
    type: 'error',
    inputs: [{ name: 'spender', internalType: 'address', type: 'address' }],
    name: 'ERC20InvalidSpender',
  },
  {
    type: 'error',
    inputs: [{ name: 'deadline', internalType: 'uint256', type: 'uint256' }],
    name: 'ERC2612ExpiredSignature',
  },
  {
    type: 'error',
    inputs: [
      { name: 'signer', internalType: 'address', type: 'address' },
      { name: 'owner', internalType: 'address', type: 'address' },
    ],
    name: 'ERC2612InvalidSigner',
  },
  { type: 'error', inputs: [], name: 'Index__AlreadyInitialized' },
  { type: 'error', inputs: [], name: 'Index__CallerNotIndexManager' },
  { type: 'error', inputs: [], name: 'Index__CallerNotRouter' },
  {
    type: 'error',
    inputs: [],
    name: 'Index__DecimalsStandardLowerThanCurrent',
  },
  { type: 'error', inputs: [], name: 'Index__InvalidUnderlyingAmount' },
  { type: 'error', inputs: [], name: 'Index__InvalidWeight' },
  { type: 'error', inputs: [], name: 'Index__NoFeesToCollect' },
  { type: 'error', inputs: [], name: 'Index__NotInitialized' },
  { type: 'error', inputs: [], name: 'Index__NotPendingWeightUpdate' },
  { type: 'error', inputs: [], name: 'Index__PendingWeightUpdate' },
  { type: 'error', inputs: [], name: 'Index__RebalanceNotNeeded' },
  { type: 'error', inputs: [], name: 'Index__RebalanceSlippageTooHigh' },
  { type: 'error', inputs: [], name: 'Index__ToleranceExceeded' },
  { type: 'error', inputs: [], name: 'Index__WeightUpdateExpired' },
  { type: 'error', inputs: [], name: 'Index__ZeroAddress' },
  {
    type: 'error',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'currentNonce', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'InvalidAccountNonce',
  },
  { type: 'error', inputs: [], name: 'InvalidShortString' },
  {
    type: 'error',
    inputs: [
      { name: 'bits', internalType: 'uint8', type: 'uint8' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'SafeCastOverflowedUintDowncast',
  },
  {
    type: 'error',
    inputs: [{ name: 'token', internalType: 'address', type: 'address' }],
    name: 'SafeERC20FailedOperation',
  },
  {
    type: 'error',
    inputs: [{ name: 'str', internalType: 'string', type: 'string' }],
    name: 'StringTooLong',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IndexFactory
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const indexFactoryAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: '_indexCreationCode', internalType: 'bytes', type: 'bytes' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      {
        name: '_params',
        internalType: 'struct IndexDeployParams',
        type: 'tuple',
        components: [
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'router', internalType: 'address', type: 'address' },
          { name: 'usdc', internalType: 'address', type: 'address' },
          {
            name: 'priceFeedManager',
            internalType: 'address',
            type: 'address',
          },
          { name: 'swapManager', internalType: 'address', type: 'address' },
          { name: 'universalRouter', internalType: 'address', type: 'address' },
          {
            name: 'asset0',
            internalType: 'struct IndexAsset',
            type: 'tuple',
            components: [
              { name: 'asset', internalType: 'address', type: 'address' },
              {
                name: 'weightPercentage',
                internalType: 'uint128',
                type: 'uint128',
              },
            ],
          },
          {
            name: 'asset1',
            internalType: 'struct IndexAsset',
            type: 'tuple',
            components: [
              { name: 'asset', internalType: 'address', type: 'address' },
              {
                name: 'weightPercentage',
                internalType: 'uint128',
                type: 'uint128',
              },
            ],
          },
          { name: 'feePercentage', internalType: 'uint32', type: 'uint32' },
        ],
      },
      { name: '_salt', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'deployIndex',
    outputs: [{ name: 'index', internalType: 'address', type: 'address' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getCodePointers',
    outputs: [
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getIndexCreationCode',
    outputs: [{ name: '', internalType: 'bytes', type: 'bytes' }],
    stateMutability: 'view',
  },
  { type: 'error', inputs: [], name: 'IndexFactory__EmptyCreationCode' },
  { type: 'error', inputs: [], name: 'IndexFactory__IndexDeployFailed' },
  {
    type: 'error',
    inputs: [{ name: 'runtimeSize', internalType: 'uint256', type: 'uint256' }],
    name: 'SplitCode__DataTooLarge',
  },
  { type: 'error', inputs: [], name: 'SplitCode__DeployFailed' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IndexManager
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const indexManagerAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: '_usdcAddress', internalType: 'address', type: 'address' },
      {
        name: '_uniswapUniversalRouter',
        internalType: 'address',
        type: 'address',
      },
      {
        name: '_swapManagerImplementation',
        internalType: 'address',
        type: 'address',
      },
      {
        name: '_priceFeedManagerImplementation',
        internalType: 'address',
        type: 'address',
      },
      {
        name: '_routerImplementation',
        internalType: 'address',
        type: 'address',
      },
      { name: '_upgrader', internalType: 'address', type: 'address' },
      { name: '_indexFactory', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'ASSET_MANAGER_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'DEFAULT_ADMIN_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'FEE_COLLECTOR_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'MAX_FEES_PERCENTAGE',
    outputs: [{ name: '', internalType: 'uint32', type: 'uint32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'MIN_FEES_PERCENTAGE',
    outputs: [{ name: '', internalType: 'uint32', type: 'uint32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'REBALANCER_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'cancelWeightUpdate',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'checkIsIndexInitialized',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddresses', internalType: 'address[]', type: 'address[]' },
    ],
    name: 'collectFeesFromMultipleIndexes',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'collectFeesFromSingleIndex',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_feePercentage', internalType: 'uint32', type: 'uint32' },
      {
        name: '_assetA',
        internalType: 'struct IndexAsset',
        type: 'tuple',
        components: [
          { name: 'asset', internalType: 'address', type: 'address' },
          {
            name: 'weightPercentage',
            internalType: 'uint128',
            type: 'uint128',
          },
        ],
      },
      {
        name: '_assetB',
        internalType: 'struct IndexAsset',
        type: 'tuple',
        components: [
          { name: 'asset', internalType: 'address', type: 'address' },
          {
            name: 'weightPercentage',
            internalType: 'uint128',
            type: 'uint128',
          },
        ],
      },
    ],
    name: 'createIndex',
    outputs: [
      { name: 'index', internalType: 'address', type: 'address' },
      { name: 'token0', internalType: 'address', type: 'address' },
      { name: 'token1', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'executeSingleWeightUpdate',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddresses', internalType: 'address[]', type: 'address[]' },
    ],
    name: 'executeWeightUpdateForMultipleIndexes',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getDeployedIndexes',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'getIndexAssets',
    outputs: [
      { name: 'asset0', internalType: 'address', type: 'address' },
      { name: 'asset1', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_assetAddressA', internalType: 'address', type: 'address' },
      { name: '_assetAddressB', internalType: 'address', type: 'address' },
    ],
    name: 'getIndexByAssetsAddresses',
    outputs: [{ name: 'index', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getIndexFactory',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getInitializedIndexes',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getPriceFeedManagerAddress',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'role', internalType: 'bytes32', type: 'bytes32' }],
    name: 'getRoleAdmin',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getRouterAddress',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getSwapManagerAddress',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getTotalFeesCollected',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getUniswapUniversalRouter',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'grantRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'hasRole',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_depositor', internalType: 'address', type: 'address' },
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_underlyingAmount0', internalType: 'uint256', type: 'uint256' },
      {
        name: '_routeAsset0Usdc',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
      {
        name: '_routeAsset1Usdc',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
      {
        name: '_routeAsset0Asset1',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'initializeIndex',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'isIndexAddress',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_newWeightAsset0', internalType: 'uint128', type: 'uint128' },
    ],
    name: 'proposeNewWeights',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddresses', internalType: 'address[]', type: 'address[]' },
    ],
    name: 'rebalanceMultipleIndexes',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'rebalanceSingleIndex',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'callerConfirmation', internalType: 'address', type: 'address' },
    ],
    name: 'renounceRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'revokeRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'interfaceId', internalType: 'bytes4', type: 'bytes4' }],
    name: 'supportsInterface',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'indexAddress',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'caller',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'action',
        internalType: 'enum IndexAction',
        type: 'uint8',
        indexed: true,
      },
      {
        name: 'reasonData',
        internalType: 'bytes',
        type: 'bytes',
        indexed: false,
      },
    ],
    name: 'IndexActionFailed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'indexAddress',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'caller',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'action',
        internalType: 'enum IndexAction',
        type: 'uint8',
        indexed: true,
      },
    ],
    name: 'IndexActionTriggered',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'indexAddress',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'asset0',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'asset1',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'asset0Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'asset1Weight',
        internalType: 'uint128',
        type: 'uint128',
        indexed: false,
      },
      {
        name: 'feePercentage',
        internalType: 'uint32',
        type: 'uint32',
        indexed: false,
      },
      {
        name: 'assetManager',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'IndexCreated',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'previousAdminRole',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: true,
      },
      {
        name: 'newAdminRole',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: true,
      },
    ],
    name: 'RoleAdminChanged',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'account',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'sender',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'RoleGranted',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'account',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'sender',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'RoleRevoked',
  },
  { type: 'error', inputs: [], name: 'AccessControlBadConfirmation' },
  {
    type: 'error',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'neededRole', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'AccessControlUnauthorizedAccount',
  },
  {
    type: 'error',
    inputs: [{ name: 'index', internalType: 'address', type: 'address' }],
    name: 'IndexManager__IndexAlreadyExists',
  },
  { type: 'error', inputs: [], name: 'IndexManager__IndexAlreadyInitialized' },
  { type: 'error', inputs: [], name: 'IndexManager__InvalidFeePercentage' },
  {
    type: 'error',
    inputs: [
      { name: 'implementation', internalType: 'address', type: 'address' },
    ],
    name: 'IndexManager__InvalidImplementation',
  },
  {
    type: 'error',
    inputs: [],
    name: 'IndexManager__InvalidIndexAssetsAddress',
  },
  { type: 'error', inputs: [], name: 'IndexManager__InvalidIndexAssetsAmount' },
  {
    type: 'error',
    inputs: [],
    name: 'IndexManager__InvalidIndexAssetsPercentages',
  },
  {
    type: 'error',
    inputs: [
      { name: 'indexFactory', internalType: 'address', type: 'address' },
    ],
    name: 'IndexManager__InvalidIndexFactory',
  },
  { type: 'error', inputs: [], name: 'IndexManager__IsNotIndex' },
  {
    type: 'error',
    inputs: [{ name: 'index', internalType: 'address', type: 'address' }],
    name: 'IndexManager__NotIndexInitialized',
  },
  {
    type: 'error',
    inputs: [{ name: 'asset', internalType: 'address', type: 'address' }],
    name: 'IndexManager__PriceFeedNotRegistered',
  },
  { type: 'error', inputs: [], name: 'IndexManager__UsdcCannotBeIndexAsset' },
  { type: 'error', inputs: [], name: 'IndexManager__ZeroAddress' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MultiSigWallet
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const multiSigWalletAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: '_owners', internalType: 'address[]', type: 'address[]' },
      { name: '_required', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'nonpayable',
  },
  { type: 'receive', stateMutability: 'payable' },
  {
    type: 'function',
    inputs: [{ name: '_txId', internalType: 'uint256', type: 'uint256' }],
    name: 'confirmTransaction',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_txId', internalType: 'uint256', type: 'uint256' },
      { name: '_signer', internalType: 'address', type: 'address' },
      { name: '_signature', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'confirmTransactionWithSig',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'eip712Domain',
    outputs: [
      { name: 'fields', internalType: 'bytes1', type: 'bytes1' },
      { name: 'name', internalType: 'string', type: 'string' },
      { name: 'version', internalType: 'string', type: 'string' },
      { name: 'chainId', internalType: 'uint256', type: 'uint256' },
      { name: 'verifyingContract', internalType: 'address', type: 'address' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
      { name: 'extensions', internalType: 'uint256[]', type: 'uint256[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_txId', internalType: 'uint256', type: 'uint256' }],
    name: 'executeTransaction',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_txId', internalType: 'uint256', type: 'uint256' },
      { name: '_signer', internalType: 'address', type: 'address' },
    ],
    name: 'getConfirmDigest',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_txId', internalType: 'uint256', type: 'uint256' },
      { name: '_owner', internalType: 'address', type: 'address' },
    ],
    name: 'getConfirmNonce',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_index', internalType: 'uint256', type: 'uint256' }],
    name: 'getOwnerAt',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getOwners',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getRequiredConfirmations',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_txId', internalType: 'uint256', type: 'uint256' }],
    name: 'getTransaction',
    outputs: [
      { name: 'target', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
      { name: 'executed', internalType: 'bool', type: 'bool' },
      { name: 'confirmations', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getTransactionCount',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_addr', internalType: 'address', type: 'address' }],
    name: 'isOwner',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_txId', internalType: 'uint256', type: 'uint256' },
      { name: '_owner', internalType: 'address', type: 'address' },
    ],
    name: 'isTransactionConfirmed',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_txId', internalType: 'uint256', type: 'uint256' }],
    name: 'revokeConfirmation',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_target', internalType: 'address', type: 'address' },
      { name: '_value', internalType: 'uint256', type: 'uint256' },
      { name: '_data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'submitTransaction',
    outputs: [{ name: 'txId', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'txId', internalType: 'uint256', type: 'uint256', indexed: true },
      {
        name: 'owner',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'ConfirmationRevoked',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'sender',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'value',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'Deposit',
  },
  { type: 'event', anonymous: false, inputs: [], name: 'EIP712DomainChanged' },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'owners',
        internalType: 'address[]',
        type: 'address[]',
        indexed: false,
      },
      {
        name: 'requiredConfirmations',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'MultiSigInitialized',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'txId', internalType: 'uint256', type: 'uint256', indexed: true },
      {
        name: 'owner',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'TransactionConfirmed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'txId', internalType: 'uint256', type: 'uint256', indexed: true },
      {
        name: 'executor',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'TransactionExecuted',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'txId', internalType: 'uint256', type: 'uint256', indexed: true },
      {
        name: 'proposer',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'target',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'value',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'TransactionSubmitted',
  },
  { type: 'error', inputs: [], name: 'ECDSAInvalidSignature' },
  {
    type: 'error',
    inputs: [{ name: 'length', internalType: 'uint256', type: 'uint256' }],
    name: 'ECDSAInvalidSignatureLength',
  },
  {
    type: 'error',
    inputs: [{ name: 's', internalType: 'bytes32', type: 'bytes32' }],
    name: 'ECDSAInvalidSignatureS',
  },
  { type: 'error', inputs: [], name: 'InvalidShortString' },
  { type: 'error', inputs: [], name: 'MultiSig__ConfirmationsNotMet' },
  { type: 'error', inputs: [], name: 'MultiSig__InvalidRequirement' },
  { type: 'error', inputs: [], name: 'MultiSig__InvalidSignature' },
  { type: 'error', inputs: [], name: 'MultiSig__NotOwner' },
  { type: 'error', inputs: [], name: 'MultiSig__OwnerNotUnique' },
  { type: 'error', inputs: [], name: 'MultiSig__TxAlreadyConfirmed' },
  { type: 'error', inputs: [], name: 'MultiSig__TxAlreadyExecuted' },
  { type: 'error', inputs: [], name: 'MultiSig__TxDoesNotExist' },
  { type: 'error', inputs: [], name: 'MultiSig__TxFailed' },
  { type: 'error', inputs: [], name: 'MultiSig__TxNotConfirmed' },
  { type: 'error', inputs: [], name: 'MultiSig__ZeroAddress' },
  {
    type: 'error',
    inputs: [{ name: 'str', internalType: 'string', type: 'string' }],
    name: 'StringTooLong',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PriceFeedManager
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const priceFeedManagerAbi = [
  { type: 'constructor', inputs: [], stateMutability: 'nonpayable' },
  {
    type: 'function',
    inputs: [],
    name: 'ASSET_MANAGER_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'UPGRADE_INTERFACE_VERSION',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_asset', internalType: 'address', type: 'address' }],
    name: 'cancelPriceFeedUpdate',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '_asset', internalType: 'address', type: 'address' }],
    name: 'executePriceFeedUpdate',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getImplementation',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_asset', internalType: 'address', type: 'address' }],
    name: 'getPendingPriceFeedUpdate',
    outputs: [
      {
        name: '',
        internalType: 'struct PendingFeed',
        type: 'tuple',
        components: [
          { name: 'feed', internalType: 'address', type: 'address' },
          { name: 'maxDelay', internalType: 'uint32', type: 'uint32' },
          { name: 'executableAt', internalType: 'uint64', type: 'uint64' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_asset', internalType: 'address', type: 'address' }],
    name: 'getPrice',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_asset', internalType: 'address', type: 'address' }],
    name: 'getPriceFeedConfig',
    outputs: [
      {
        name: '',
        internalType: 'struct FeedConfig',
        type: 'tuple',
        components: [
          { name: 'feed', internalType: 'address', type: 'address' },
          { name: 'maxDelay', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getUpgrader',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '_asset', internalType: 'address', type: 'address' }],
    name: 'hasPriceFeed',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexManager', internalType: 'address', type: 'address' },
      { name: '_upgrader', internalType: 'address', type: 'address' },
    ],
    name: 'initialize',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_asset', internalType: 'address', type: 'address' },
      { name: '_feed', internalType: 'address', type: 'address' },
      { name: '_maxDelay', internalType: 'uint32', type: 'uint32' },
    ],
    name: 'proposePriceFeedUpdate',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'proxiableUUID',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_asset', internalType: 'address', type: 'address' },
      { name: '_feed', internalType: 'address', type: 'address' },
      { name: '_maxDelay', internalType: 'uint32', type: 'uint32' },
    ],
    name: 'registerPriceFeed',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'renounceOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', internalType: 'address', type: 'address' }],
    name: 'transferOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'newImplementation', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'upgradeToAndCall',
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'version',
        internalType: 'uint64',
        type: 'uint64',
        indexed: false,
      },
    ],
    name: 'Initialized',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'previousOwner',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'newOwner',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'OwnershipTransferred',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'asset',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      { name: 'feed', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'maxDelay',
        internalType: 'uint32',
        type: 'uint32',
        indexed: false,
      },
    ],
    name: 'PriceFeedRegistered',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'asset',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'cancelledFeed',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'cancelledMaxDelay',
        internalType: 'uint32',
        type: 'uint32',
        indexed: false,
      },
    ],
    name: 'PriceFeedUpdateCancelled',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'asset',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      { name: 'feed', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'maxDelay',
        internalType: 'uint32',
        type: 'uint32',
        indexed: false,
      },
      {
        name: 'executableAt',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'PriceFeedUpdateProposed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'asset',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'oldFeed',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'newFeed',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'maxDelay',
        internalType: 'uint32',
        type: 'uint32',
        indexed: false,
      },
    ],
    name: 'PriceFeedUpdated',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'implementation',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'Upgraded',
  },
  {
    type: 'error',
    inputs: [{ name: 'target', internalType: 'address', type: 'address' }],
    name: 'AddressEmptyCode',
  },
  {
    type: 'error',
    inputs: [
      { name: 'implementation', internalType: 'address', type: 'address' },
    ],
    name: 'ERC1967InvalidImplementation',
  },
  { type: 'error', inputs: [], name: 'ERC1967NonPayable' },
  { type: 'error', inputs: [], name: 'FailedCall' },
  { type: 'error', inputs: [], name: 'InvalidInitialization' },
  { type: 'error', inputs: [], name: 'NotInitializing' },
  {
    type: 'error',
    inputs: [{ name: 'owner', internalType: 'address', type: 'address' }],
    name: 'OwnableInvalidOwner',
  },
  {
    type: 'error',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'OwnableUnauthorizedAccount',
  },
  {
    type: 'error',
    inputs: [],
    name: 'PriceFeedManager__CallerNotAssetManager',
  },
  { type: 'error', inputs: [], name: 'PriceFeedManager__InvalidAsset' },
  {
    type: 'error',
    inputs: [{ name: 'asset', internalType: 'address', type: 'address' }],
    name: 'PriceFeedManager__InvalidAssetDecimals',
  },
  { type: 'error', inputs: [], name: 'PriceFeedManager__InvalidMaxDelay' },
  {
    type: 'error',
    inputs: [{ name: 'feed', internalType: 'address', type: 'address' }],
    name: 'PriceFeedManager__InvalidPriceFeed',
  },
  {
    type: 'error',
    inputs: [],
    name: 'PriceFeedManager__NoPendingPriceFeedUpdate',
  },
  {
    type: 'error',
    inputs: [{ name: 'asset', internalType: 'address', type: 'address' }],
    name: 'PriceFeedManager__PriceFeedAlreadySet',
  },
  {
    type: 'error',
    inputs: [],
    name: 'PriceFeedManager__PriceFeedNotAvailable',
  },
  {
    type: 'error',
    inputs: [{ name: 'asset', internalType: 'address', type: 'address' }],
    name: 'PriceFeedManager__PriceFeedNotSet',
  },
  { type: 'error', inputs: [], name: 'PriceFeedManager__PriceFeedRoundStale' },
  {
    type: 'error',
    inputs: [],
    name: 'PriceFeedManager__PriceFeedUpdateExpired',
  },
  {
    type: 'error',
    inputs: [],
    name: 'PriceFeedManager__PriceFeedUpdatePending',
  },
  { type: 'error', inputs: [], name: 'PriceFeedManager__PriceIsStale' },
  { type: 'error', inputs: [], name: 'PriceFeedManager__SamePriceFeedConfig' },
  { type: 'error', inputs: [], name: 'UUPSUnauthorizedCallContext' },
  {
    type: 'error',
    inputs: [{ name: 'slot', internalType: 'bytes32', type: 'bytes32' }],
    name: 'UUPSUnsupportedProxiableUUID',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'UpgraderAuth__Unauthorized',
  },
  { type: 'error', inputs: [], name: 'UpgraderAuth__ZeroAddress' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Router
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const routerAbi = [
  { type: 'constructor', inputs: [], stateMutability: 'nonpayable' },
  {
    type: 'function',
    inputs: [],
    name: 'UPGRADE_INTERFACE_VERSION',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_usdcAmount', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'buyExactUsdcAmountOfShares',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_usdcAmount', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
      { name: '_deadline', internalType: 'uint256', type: 'uint256' },
      { name: '_v', internalType: 'uint8', type: 'uint8' },
      { name: '_r', internalType: 'bytes32', type: 'bytes32' },
      { name: '_s', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'buyExactUsdcAmountOfSharesWithPermit',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getImplementation',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getIndexManager',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getMaxTolerance',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_usdcAmount', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getMinMintPreview',
    outputs: [
      { name: 'minSharesAmount', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_sharesAmount', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getMinRedeemPreview',
    outputs: [
      { name: 'minUsdcAmount', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getUpgrader',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getUsdc',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexManager', internalType: 'address', type: 'address' },
      { name: '_usdc', internalType: 'address', type: 'address' },
      { name: '_upgrader', internalType: 'address', type: 'address' },
    ],
    name: 'initialize',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'proxiableUUID',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_sharesAmount', internalType: 'uint256', type: 'uint256' },
      { name: '_maxTolerance', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'sellExactAmountOfSharesForUsdc',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'newImplementation', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'upgradeToAndCall',
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'version',
        internalType: 'uint64',
        type: 'uint64',
        indexed: false,
      },
    ],
    name: 'Initialized',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'implementation',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'Upgraded',
  },
  {
    type: 'error',
    inputs: [{ name: 'target', internalType: 'address', type: 'address' }],
    name: 'AddressEmptyCode',
  },
  {
    type: 'error',
    inputs: [
      { name: 'implementation', internalType: 'address', type: 'address' },
    ],
    name: 'ERC1967InvalidImplementation',
  },
  { type: 'error', inputs: [], name: 'ERC1967NonPayable' },
  { type: 'error', inputs: [], name: 'FailedCall' },
  { type: 'error', inputs: [], name: 'InvalidInitialization' },
  { type: 'error', inputs: [], name: 'NotInitializing' },
  { type: 'error', inputs: [], name: 'ReentrancyGuardReentrantCall' },
  {
    type: 'error',
    inputs: [
      { name: 'userBalance', internalType: 'uint256', type: 'uint256' },
      { name: 'requiredAmount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'Router__InsufficientSharesBalance',
  },
  {
    type: 'error',
    inputs: [
      { name: 'userBalance', internalType: 'uint256', type: 'uint256' },
      { name: 'requiredAmount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'Router__InsufficientUsdcBalance',
  },
  { type: 'error', inputs: [], name: 'Router__InvalidAmounts' },
  { type: 'error', inputs: [], name: 'Router__InvalidIndexAddress' },
  { type: 'error', inputs: [], name: 'Router__InvalidTolerance' },
  { type: 'error', inputs: [], name: 'Router__ZeroAddress' },
  { type: 'error', inputs: [], name: 'UUPSUnauthorizedCallContext' },
  {
    type: 'error',
    inputs: [{ name: 'slot', internalType: 'bytes32', type: 'bytes32' }],
    name: 'UUPSUnsupportedProxiableUUID',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'UpgraderAuth__Unauthorized',
  },
  { type: 'error', inputs: [], name: 'UpgraderAuth__ZeroAddress' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// SwapManager
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const swapManagerAbi = [
  { type: 'constructor', inputs: [], stateMutability: 'nonpayable' },
  {
    type: 'function',
    inputs: [],
    name: 'UPGRADE_INTERFACE_VERSION',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_swapType0', internalType: 'enum SwapType', type: 'uint8' },
      { name: '_swapType1', internalType: 'enum SwapType', type: 'uint8' },
      { name: '_tokenIn0', internalType: 'address', type: 'address' },
      { name: '_tokenIn1', internalType: 'address', type: 'address' },
      { name: '_amountIn0', internalType: 'uint128', type: 'uint128' },
      { name: '_amountIn1', internalType: 'uint128', type: 'uint128' },
      { name: '_amountOutMinimum0', internalType: 'uint128', type: 'uint128' },
      { name: '_amountOutMinimum1', internalType: 'uint128', type: 'uint128' },
    ],
    name: 'buildDoubleSwapParams',
    outputs: [
      { name: 'commands', internalType: 'bytes', type: 'bytes' },
      { name: 'inputs', internalType: 'bytes[]', type: 'bytes[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_swapType', internalType: 'enum SwapType', type: 'uint8' },
      { name: '_tokenIn', internalType: 'address', type: 'address' },
      { name: '_amountIn', internalType: 'uint128', type: 'uint128' },
      { name: '_amountOutMinimum', internalType: 'uint128', type: 'uint128' },
    ],
    name: 'buildSingleSwapParams',
    outputs: [
      { name: 'commands', internalType: 'bytes', type: 'bytes' },
      { name: 'inputs', internalType: 'bytes[]', type: 'bytes[]' },
      { name: 'tokenIn', internalType: 'address', type: 'address' },
      { name: 'tokenOut', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getImplementation',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_swapType', internalType: 'enum SwapType', type: 'uint8' },
    ],
    name: 'getRoute',
    outputs: [
      {
        name: '',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getUpgrader',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexManager', internalType: 'address', type: 'address' },
      { name: '_upgrader', internalType: 'address', type: 'address' },
    ],
    name: 'initialize',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'proxiableUUID',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      {
        name: '_routeAsset0Usdc',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
      {
        name: '_routeAsset1Usdc',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
      {
        name: '_routeAsset0Asset1',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'registerIndex',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'renounceOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', internalType: 'address', type: 'address' }],
    name: 'transferOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '_indexAddress', internalType: 'address', type: 'address' },
      { name: '_swapType', internalType: 'enum SwapType', type: 'uint8' },
      {
        name: '_newRoute',
        internalType: 'struct SwapRoute',
        type: 'tuple',
        components: [
          { name: 'version', internalType: 'enum PoolVersion', type: 'uint8' },
          {
            name: 'poolKey',
            internalType: 'struct PoolKey',
            type: 'tuple',
            components: [
              { name: 'currency0', internalType: 'Currency', type: 'address' },
              { name: 'currency1', internalType: 'Currency', type: 'address' },
              { name: 'fee', internalType: 'uint24', type: 'uint24' },
              { name: 'tickSpacing', internalType: 'int24', type: 'int24' },
              {
                name: 'hooks',
                internalType: 'contract IHooks',
                type: 'address',
              },
            ],
          },
          { name: 'v3Path', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'updateRoute',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'newImplementation', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'upgradeToAndCall',
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'version',
        internalType: 'uint64',
        type: 'uint64',
        indexed: false,
      },
    ],
    name: 'Initialized',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'previousOwner',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'newOwner',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'OwnershipTransferred',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'implementation',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'Upgraded',
  },
  {
    type: 'error',
    inputs: [{ name: 'target', internalType: 'address', type: 'address' }],
    name: 'AddressEmptyCode',
  },
  {
    type: 'error',
    inputs: [
      { name: 'implementation', internalType: 'address', type: 'address' },
    ],
    name: 'ERC1967InvalidImplementation',
  },
  { type: 'error', inputs: [], name: 'ERC1967NonPayable' },
  { type: 'error', inputs: [], name: 'FailedCall' },
  { type: 'error', inputs: [], name: 'InvalidInitialization' },
  { type: 'error', inputs: [], name: 'NotInitializing' },
  {
    type: 'error',
    inputs: [{ name: 'owner', internalType: 'address', type: 'address' }],
    name: 'OwnableInvalidOwner',
  },
  {
    type: 'error',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'OwnableUnauthorizedAccount',
  },
  { type: 'error', inputs: [], name: 'SwapManager__IndexNotRegistered' },
  { type: 'error', inputs: [], name: 'SwapManager__InvalidV3Path' },
  { type: 'error', inputs: [], name: 'SwapManager__InvalidV4PoolKey' },
  {
    type: 'error',
    inputs: [
      { name: 'indexAddress', internalType: 'address', type: 'address' },
    ],
    name: 'SwapManager__NotAnIndex',
  },
  { type: 'error', inputs: [], name: 'SwapManager__RouteNotRegistered' },
  {
    type: 'error',
    inputs: [
      { name: 'expectedTokenA', internalType: 'address', type: 'address' },
      { name: 'expectedTokenB', internalType: 'address', type: 'address' },
    ],
    name: 'SwapManager__RouteTokensMismatch',
  },
  { type: 'error', inputs: [], name: 'UUPSUnauthorizedCallContext' },
  {
    type: 'error',
    inputs: [{ name: 'slot', internalType: 'bytes32', type: 'bytes32' }],
    name: 'UUPSUnsupportedProxiableUUID',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'UpgraderAuth__Unauthorized',
  },
  { type: 'error', inputs: [], name: 'UpgraderAuth__ZeroAddress' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TimelockController
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const timelockControllerAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: 'minDelay', internalType: 'uint256', type: 'uint256' },
      { name: 'proposers', internalType: 'address[]', type: 'address[]' },
      { name: 'executors', internalType: 'address[]', type: 'address[]' },
      { name: 'admin', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  { type: 'receive', stateMutability: 'payable' },
  {
    type: 'function',
    inputs: [],
    name: 'CANCELLER_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'DEFAULT_ADMIN_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'EXECUTOR_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'PROPOSER_ROLE',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'bytes32', type: 'bytes32' }],
    name: 'cancel',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'target', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
      { name: 'payload', internalType: 'bytes', type: 'bytes' },
      { name: 'predecessor', internalType: 'bytes32', type: 'bytes32' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'execute',
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'targets', internalType: 'address[]', type: 'address[]' },
      { name: 'values', internalType: 'uint256[]', type: 'uint256[]' },
      { name: 'payloads', internalType: 'bytes[]', type: 'bytes[]' },
      { name: 'predecessor', internalType: 'bytes32', type: 'bytes32' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'executeBatch',
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getMinDelay',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'bytes32', type: 'bytes32' }],
    name: 'getOperationState',
    outputs: [
      {
        name: '',
        internalType: 'enum TimelockController.OperationState',
        type: 'uint8',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'role', internalType: 'bytes32', type: 'bytes32' }],
    name: 'getRoleAdmin',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'bytes32', type: 'bytes32' }],
    name: 'getTimestamp',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'grantRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'hasRole',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'target', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
      { name: 'predecessor', internalType: 'bytes32', type: 'bytes32' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'hashOperation',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [
      { name: 'targets', internalType: 'address[]', type: 'address[]' },
      { name: 'values', internalType: 'uint256[]', type: 'uint256[]' },
      { name: 'payloads', internalType: 'bytes[]', type: 'bytes[]' },
      { name: 'predecessor', internalType: 'bytes32', type: 'bytes32' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'hashOperationBatch',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'bytes32', type: 'bytes32' }],
    name: 'isOperation',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'bytes32', type: 'bytes32' }],
    name: 'isOperationDone',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'bytes32', type: 'bytes32' }],
    name: 'isOperationPending',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'bytes32', type: 'bytes32' }],
    name: 'isOperationReady',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'uint256[]', type: 'uint256[]' },
      { name: '', internalType: 'uint256[]', type: 'uint256[]' },
      { name: '', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'onERC1155BatchReceived',
    outputs: [{ name: '', internalType: 'bytes4', type: 'bytes4' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'uint256', type: 'uint256' },
      { name: '', internalType: 'uint256', type: 'uint256' },
      { name: '', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'onERC1155Received',
    outputs: [{ name: '', internalType: 'bytes4', type: 'bytes4' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'uint256', type: 'uint256' },
      { name: '', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'onERC721Received',
    outputs: [{ name: '', internalType: 'bytes4', type: 'bytes4' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'callerConfirmation', internalType: 'address', type: 'address' },
    ],
    name: 'renounceRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'revokeRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'target', internalType: 'address', type: 'address' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
      { name: 'predecessor', internalType: 'bytes32', type: 'bytes32' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
      { name: 'delay', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'schedule',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'targets', internalType: 'address[]', type: 'address[]' },
      { name: 'values', internalType: 'uint256[]', type: 'uint256[]' },
      { name: 'payloads', internalType: 'bytes[]', type: 'bytes[]' },
      { name: 'predecessor', internalType: 'bytes32', type: 'bytes32' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
      { name: 'delay', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'scheduleBatch',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'interfaceId', internalType: 'bytes4', type: 'bytes4' }],
    name: 'supportsInterface',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'newDelay', internalType: 'uint256', type: 'uint256' }],
    name: 'updateDelay',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'id', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'index',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'target',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      {
        name: 'value',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'CallExecuted',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'id', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'salt',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: false,
      },
    ],
    name: 'CallSalt',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'id', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'index',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'target',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      {
        name: 'value',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
      {
        name: 'predecessor',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: false,
      },
      {
        name: 'delay',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'CallScheduled',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'id', internalType: 'bytes32', type: 'bytes32', indexed: true },
    ],
    name: 'Cancelled',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'oldDuration',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'newDuration',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'MinDelayChange',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'previousAdminRole',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: true,
      },
      {
        name: 'newAdminRole',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: true,
      },
    ],
    name: 'RoleAdminChanged',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'account',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'sender',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'RoleGranted',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'account',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'sender',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'RoleRevoked',
  },
  { type: 'error', inputs: [], name: 'AccessControlBadConfirmation' },
  {
    type: 'error',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'neededRole', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'AccessControlUnauthorizedAccount',
  },
  { type: 'error', inputs: [], name: 'FailedCall' },
  {
    type: 'error',
    inputs: [
      { name: 'delay', internalType: 'uint256', type: 'uint256' },
      { name: 'minDelay', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'TimelockInsufficientDelay',
  },
  {
    type: 'error',
    inputs: [
      { name: 'targets', internalType: 'uint256', type: 'uint256' },
      { name: 'payloads', internalType: 'uint256', type: 'uint256' },
      { name: 'values', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'TimelockInvalidOperationLength',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'TimelockUnauthorizedCaller',
  },
  {
    type: 'error',
    inputs: [
      { name: 'predecessorId', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'TimelockUnexecutedPredecessor',
  },
  {
    type: 'error',
    inputs: [
      { name: 'operationId', internalType: 'bytes32', type: 'bytes32' },
      { name: 'expectedStates', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'TimelockUnexpectedOperationState',
  },
] as const
