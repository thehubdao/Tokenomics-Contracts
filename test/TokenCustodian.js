const { calculateAddress } = require("../scripts/calculateAddress");
const { time, ether } = require("@openzeppelin/test-helpers");
const { MAX_UINT256 } = require("@openzeppelin/test-helpers/src/constants")

const TUP_ADMIN = artifacts.require("ProxyAdmin");
const TUP = artifacts.require("TUP");
const ERC20 = artifacts.require("ERC20Mock");

const VestingContract = artifacts.require("VestingFlex");
const TokenCustodian = artifacts.require("TokenCustodian");

const initializeVesting = {
    "inputs": [
      {
        "internalType": "address",
        "name": "_token",
        "type": "address"
      },
      {
        "internalType": "address",
        "name": "_owner",
        "type": "address"
      }
    ],
    "name": "initialize",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}
const initializeCustodian = {
    "inputs": [
      {
        "internalType": "address",
        "name": "admin",
        "type": "address"
      },
      {
        "internalType": "string[3]",
        "name": "branches",
        "type": "string[3]"
      }
    ],
    "name": "initialize",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}

contract("TokenCustodian", ([admin, branch0, branch1, branch2, beneficiary, proxyAdmin, vestingOwner, alice]) => {
    const byAlice = { from: alice };
    const allocations = ["STRATEGIC_SALE", "WORKING_GROUPS", "ECOSYSTEM_GRANTS"];
    const initDataCustodian = web3.eth.abi.encodeFunctionCall(
        initializeCustodian,
        [admin, allocations]
    );

    before(async () => {

        this.ADM = await TUP_ADMIN.new({ from: proxyAdmin });

        this.TOK = await ERC20.new("$VEST", "$VEST", 18, { from: vestingOwner });

        VestingContract.new().then((imp) => {
            TUP.new(
                imp.address, 
                this.ADM.address, 
                web3.eth.abi.encodeFunctionCall(initializeVesting, [this.TOK.address, vestingOwner])
            ).then((proxy) => {
                VestingContract.at(
                    proxy.address
                ).then(async (vest) => {
                    this.VEST = vest;

                    this.CUST_IMP = await TokenCustodian.new(vest.address);
                    
                    // before deploying the Token custodian we already have to create the vestings: 
                    const proxyAdress = calculateAddress(alice, await web3.eth.getTransactionCount(alice));
                    console.log({vest,proxyAdress,MAX_UINT256})
                    await this.TOK.approve(vest.address, MAX_UINT256, { from: vestingOwner });
                    await vest.createVestings(vestingOwner,
                        [proxyAdress,proxyAdress,proxyAdress],
                        [
                            [ether("10000000"), 0, +await time.latest() + 120, time.duration.years(1), 100_000_000, 0, 1, true],
                            [ether("20000000"), 0, +await time.latest() + 120, time.duration.years(2), 200_000_000, 0, 1, true],
                            [ether("30000000"), 0, +await time.latest() + 120, time.duration.years(3), 300_000_000, 0, 1, true]
                        ],
                        { from: vestingOwner }
                    )
                    this.CUST_PROX = await TUP.new(this.CUST_IMP.address, this.ADM.address, initDataCustodian, byAlice);
                    this.CUST = await TokenCustodian.at(this.CUST_PROX.address);
                });
            })
        });
    })
    it("check", async () => {
        console.log("test test LOL");
        console.log(this.CUST.address, this.VEST.address);
    })
})