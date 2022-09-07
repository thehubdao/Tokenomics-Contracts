const { expectEvent, expectRevert, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256, ZERO_ADDRESS } = require('@openzeppelin/test-helpers/src/constants');
const { inTransaction } = require('@openzeppelin/test-helpers/src/expectEvent');
const { assertion } = require('@openzeppelin/test-helpers/src/expectRevert');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');
const DAYS = 24*60*60;

const INITIALIZER = {
  "inputs": [
    {
      "components": [
        {
          "internalType": "uint8",
          "name": "roleId",
          "type": "uint8"
        },
        {
          "internalType": "bool",
          "name": "isPurchaseable",
          "type": "bool"
        },
        {
          "internalType": "uint40",
          "name": "intervalLength",
          "type": "uint40"
        },
        {
          "internalType": "uint40",
          "name": "callsPerInterval",
          "type": "uint40"
        },
        {
          "internalType": "uint16",
          "name": "maxIntervalsAtOnce",
          "type": "uint16"
        },
        {
          "internalType": "uint8",
          "name": "maxRebate",
          "type": "uint8"
        },
        {
          "internalType": "uint8",
          "name": "rebatePerInterval",
          "type": "uint8"
        },
        {
          "internalType": "uint16",
          "name": "referralBonusInUSD",
          "type": "uint16"
        }
      ],
      "internalType": "struct IAccessControlNFT.RoleSetup",
      "name": "rolesSetupData",
      "type": "tuple"
    },
    {
      "internalType": "enum IAccessControlNFT.Tier[]",
      "name": "enabledTiers",
      "type": "uint8[]"
    },
    {
      "internalType": "uint256[]",
      "name": "feeByTier",
      "type": "uint256[]"
    },
    {
      "internalType": "address[]",
      "name": "currencies",
      "type": "address[]"
    },
    {
      "internalType": "address",
      "name": "revenueSplitter",
      "type": "address"
    },
    {
      "internalType": "address",
      "name": "mghWMaticPair",
      "type": "address"
    },
    {
      "internalType": "uint256",
      "name": "mghRebate",
      "type": "uint256"
    }
  ],
  "name": "initialize",
  "outputs": [],
  "stateMutability": "nonpayable",
  "type": "function"
};

const initialRole = [
    initialRoleSetupData = [id=1, isActive=true, length=30*DAYS, calls=10**6, maxIntervals=6, maxRebate=25, rebatePerInterval=5, referralBonus=10],
    tiersOfInitialRole =   [5, 7],
    feeByTierInUSD =       [100, 200]
]

const Proxy = artifacts.require("SimpleProxy")
const ACNFT = artifacts.require('AccessControlNFT');
const Oracle = artifacts.require('AggregatorV3Mock');
const ERC20 = artifacts.require('ERC20Mock');
const RSP = artifacts.require("RevenueSplitterWithPolygonToken");
const UNIv2 = artifacts.require("UniswapV2PoolMock");


contract('AC-NFT', ([alice, referrer, upgrader, owner]) => {
    const byOwner = { from: owner };
    const byAlice = { from: alice };
    const mghRebatePercentage = 10;
    // setup
    before(async () => {
        this.IMP  = await ACNFT.new(byOwner);
        this.RSP  = await RSP.new();
        this.POOL = await UNIv2.new(matic_reserve=10**6, mgh_reserve=10**4);
        this.MGH  = await ERC20.new("MGH", "MGH", 18, byOwner);
        this.USDC = await ERC20.new("USDC", "USDC", 6, byOwner);
        const Oracle_USDC  = await Oracle.new(100);
        const Oracle_MATIC = await Oracle.new(200);

        const CurrencyArray = [
            this.USDC.address, Oracle_USDC.address,
            ZERO_ADDRESS, Oracle_MATIC.address,
            this.MGH.address, this.POOL.address
        ]
        const initData = web3.eth.abi.encodeFunctionCall(
            INITIALIZER,
            [...initialRole, CurrencyArray, this.RSP.address, this.POOL.address, mghRebatePercentage]
        );
        this.ACL = await ACNFT.at(
          (await Proxy.new(this.IMP.address, upgrader, initData)).address
        )
    })
    it("purchase price calc", async () => {
      assert.equal(
        await this.ACL.purchaseRole.call([alice, 1, 5, 1], ZERO_ADDRESS, "0x", {value: 60*10**18}),
        60*10**18
      )
      assert.equal(
        await this.ACL.purchaseRole.call([alice, 1, 7, 1], ZERO_ADDRESS, "0x", {value: 110*10**18}),
        110*10**18
      )
      assert.equal(
        await this.ACL.purchaseRole.call([alice, 1, 5, 2], ZERO_ADDRESS, "0x", {value: 100*10**18}),
        100*10**18
      )
      assert.equal(
        await this.ACL.purchaseRole.call([alice, 1, 5, 5], ZERO_ADDRESS, "0x", {value: 197.5*10**18}),
        197.5*10**18
      )
    }) 
});