const { ether, expectRevert, expectEvent, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256, ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");

const TUP = artifacts.require("TUP");
const TUP_ADMIN = artifacts.require("ProxyAdmin");
const VestingContract = artifacts.require("VestingFlex");
const ERC20 = artifacts.require("ERC20Mock");
const { assert } = require('chai');

const initialize = {
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

contract("VestingFlexible", ([alice, proxyOwner, vestingOwner]) => {
    const byVestingOwner = { from: vestingOwner };
    const byProxyAdmin = { from: proxyOwner };
    const byAlice = { from: alice }; 

    const vestParams = async (totalAmount, startIn, duration, cliffInPercent, cliffDelay, exp, revokable) => { 
      const timestamp = +(await time.latest()).toString();
      let start = timestamp + startIn;
      assert(typeof revokable == "boolean");
      assert(typeof start == "number");
      return [ether(totalAmount.toString()), 0, start, duration, cliffInPercent * 10000000, cliffDelay, exp, revokable] 
    }

    before(async () => {

        this.TOK = await ERC20.new("$VEST", "$VEST", 18, byVestingOwner);
        this.IMP = await VestingContract.new();
        this.ADM = await TUP_ADMIN.new(byProxyAdmin);

        const initData = web3.eth.abi.encodeFunctionCall(
            initialize,
            [this.TOK.address, vestingOwner]
        );
        this.PROX = await TUP.new(this.IMP.address, this.ADM.address, initData);
        this.VEST = await VestingContract.at(this.PROX.address);

        await this.TOK.approve(this.VEST.address, MAX_UINT256, byVestingOwner);
        assert.equal((await this.TOK.balanceOf(vestingOwner)).toString(), ether(''+(10**9)).toString());

        console.log("setup complete");
    })
    describe("validating setup", async () => {
      it("proxy setup correctly", async () => {
        assert.equal(await this.ADM.getProxyImplementation(this.PROX.address), this.IMP.address);
        assert.equal(await this.ADM.getProxyAdmin(this.PROX.address), this.ADM.address);
        assert.equal(await this.ADM.owner(), proxyOwner);

        await expectRevert(this.ADM.upgrade(this.PROX.address, alice), "Ownable: caller is not the owner");
        await expectRevert(this.ADM.upgrade(this.PROX.address, alice, byProxyAdmin), "ERC1967: new implementation is not a contract");
      })
      it("state variables initialized", async () => {
        assert.isTrue(await this.VEST.adminCanRevokeGlobal());
        assert.equal(await this.VEST.token(), this.TOK.address);
        assert.equal(await this.VEST.getNumberOfVestings(alice), "0");
        assert.equal(await this.VEST.balanceOf(alice), "0");
        await expectRevert(this.VEST.getVesting(alice, 0), "vesting doesnt exist");
      })
    })

    describe("creating vestings", async () => {
      it("cannot use nonsense params", async () => {
        const params = await vestParams(100, -101, 100, 101, 0, 1, false);
        await expectRevert(this.VEST.createVestings(vestingOwner, [alice], [params], byVestingOwner), "cliff <= MAX_CLIFF");
        await expectRevert(this.VEST.createVestings(vestingOwner, [ZERO_ADDRESS], [params], byVestingOwner), "param is zero");
        
        const params2 = await vestParams(100, -101, 100, 0, 0, 1, false);
        await expectRevert(this.VEST.createVestings(vestingOwner, [alice], [params2], byVestingOwner), "end must be in future"); 
      })
      it("only owner can create vestings", async () => {
        const params = await vestParams(100, -101, 100, 101, 0, 1, false);
        await expectRevert(this.VEST.createVestings(vestingOwner, [alice], [params], byProxyAdmin), "Ownable: caller is not the owner");
      })
      it("can create multiple vestings for addresses at once", async () => {        
        assert.equal(await this.TOK.balanceOf(this.VEST.address), "0");

        this.timestamp = +(await time.latest()).toString();
        const params = [await vestParams(100, 0, 10000, 0, 0, 1, true), await vestParams(100, 1000, 10000, 50, 500, 2, true)]
        const createTx = await this.VEST.createVestings(vestingOwner, [alice, alice], params, byVestingOwner);

        const [
          vestedTotal0,
          claimedTotal0,
          start0,
          duration0,
          cliff0,
          cliffDelay0,
          exp0,
          revokable0
        ] = await this.VEST.getVesting(alice, 0);
        const [ 
          vestedTotal1,
          claimedTotal1,
          start1,
          duration1,
          cliff1,
          cliffDelay1,
          exp1,
          revokable1,
        ] = await this.VEST.getVesting(alice, 1);
        
        await expectEvent(createTx, "VestingCreated", { who: alice, which: "0" })
        await expectEvent(createTx, "VestingCreated", { who: alice, which: "1" })

        assert.equal(await this.VEST.getNumberOfVestings(alice), "2");
        assert.equal(start0.toString(), this.timestamp);
        assert.equal(+start0.toString() + 1000, start1.toString());

        assert.equal((await this.VEST.getReleasedAt(alice, 0, +this.timestamp + 5000)).toString(), ether("50").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 0, +this.timestamp + 6000)).toString(), ether("60").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 0, +this.timestamp + 9000)).toString(), ether("90").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 0, +this.timestamp + 10000)).toString(), ether("100").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 0, +this.timestamp + 20000)).toString(), ether("100").toString());

        assert.equal((await this.VEST.getReleasedAt(alice, 1, +this.timestamp + 500)).toString(), ether("50").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 1, +this.timestamp + 900)).toString(), ether("50").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 1, +this.timestamp + 6000)).toString(), ether("75").toString());
        assert.isAbove(+(await this.VEST.getReleasedAt(alice, 1, +this.timestamp + 8000)).toString(), +ether("98").toString());
        assert.isBelow(+(await this.VEST.getReleasedAt(alice, 1, +this.timestamp + 8000)).toString(), +ether("100").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 1, +this.timestamp + 8100)).toString(), ether("100").toString());
        assert.equal((await this.VEST.getReleasedAt(alice, 1, +this.timestamp + 20000)).toString(), ether("100").toString());

        assert.equal(vestedTotal0.toString(), ether("100"));
        assert.equal(claimedTotal0, "0");
        assert.equal(duration0, "10000");
        assert.equal(cliff0, "0");
        assert.equal(cliffDelay0, "0");
        assert.equal(exp0, "1");
        assert.isTrue(revokable0);

        assert.equal(vestedTotal1.toString(), ether("100"));
        assert.equal(claimedTotal1, "0");
        assert.equal(duration1, "10000");
        assert.equal(cliff1, (5 * 10 ** 8).toString());
        assert.equal(cliffDelay1, "500");
        assert.equal(exp1, "2");
        assert.isTrue(revokable1);

        assert.isTrue(await this.VEST.canAdminRevoke(alice, 0));  
        assert.isTrue(await this.VEST.canAdminRevoke(alice, 1));

        assert.equal(await this.TOK.balanceOf(this.VEST.address), ''+ether("200"));
      })
    })
    describe("retrieving tokens", async () => {
      it("claim cliff", async () => {
        assert.equal(await this.TOK.balanceOf(alice), "0");
        await time.increaseTo(this.timestamp + 450);

        const cliffRelease = ''+ether("50");
        await expectRevert(this.VEST.ownerRetrieveFor(alice, 1, byVestingOwner), "nothing to retrieve");

        await time.increaseTo(this.timestamp + 500);
        const retrieveTx = await this.VEST.ownerRetrieveFor(alice, 1, byVestingOwner);

        assert.equal(await this.TOK.balanceOf(alice), ''+ether("50"));
        await expectEvent(retrieveTx, "Retrieved", { who: alice, amount: cliffRelease })
      })
      it("ongoing", async () => {

        // schedule 0
        await time.increaseTo(1015 + this.timestamp);
        const retrieveTx0 = await this.VEST.retrieve(0, byAlice);
        const elapsed0 = +(await time.latest()) - this.timestamp;
        const released0 = (+ether("100") * elapsed0 / 10000).toString();
        await expectEvent(retrieveTx0, "Retrieved", { who: alice, amount: released0 } )
        await expectEvent.inTransaction(retrieveTx0.tx, this.TOK, "Transfer", { from: this.VEST.address, to: alice, value: released0 });

        // schedule 1
        await time.increaseTo(4000 + this.timestamp);
        const retrieveTx1 = await this.VEST.retrieve(1, byAlice);
        const elapsed1 = +(await time.latest()).toString() - this.timestamp - 1000;
        const released1 = (+ether("100") * (elapsed1 / 10000)**2).toString();
        await expectEvent(retrieveTx1, "Retrieved", { who: alice, amount: released1 } )
        await expectEvent.inTransaction(retrieveTx1.tx, this.TOK, "Transfer", { from: this.VEST.address, to: alice, value: released1 });

        assert.equal(await this.TOK.balanceOf(alice), ((+released0) + (+released1) + (+ether("50"))).toString() )
      })
      it("finished", async () => {
        await time.increaseTo(this.timestamp + 10000);

        await this.VEST.retrieve(0, byAlice);
        await this.VEST.retrieve(1, byAlice);

        assert.equal(await this.TOK.balanceOf(alice), ''+ether("200"));
        assert.equal(await this.VEST.getClaimableNow(alice, 0), "0");
        assert.equal(await this.VEST.getClaimableNow(alice, 1), "0");
        assert.equal(await this.VEST.getClaimed(alice, 0), ''+ether("100"));
        assert.equal(await this.VEST.getClaimed(alice, 1), ''+ether("100"));

        await expectRevert(this.VEST.ownerRetrieveFor(alice, 0, byVestingOwner), "nothing to retrieve");
        await expectRevert(this.VEST.ownerRetrieveFor(alice, 1, byVestingOwner), "nothing to retrieve");

        let retrieveTx0 = await this.VEST.retrieve(0, byAlice);
        let retrieveTx1 = await this.VEST.retrieve(1, byAlice);

        await expectEvent(retrieveTx0, "Retrieved", { who: alice, amount: "0" } );
        await expectEvent(retrieveTx1, "Retrieved", { who: alice, amount: "0" } );
        
        assert.equal(await this.TOK.balanceOf(alice), ''+ether("200"));
      })
    })
    describe("revoking vestings", async () => {
      it("only owner can revoke", async () => {
        await this.VEST.createVestings(
          vestingOwner, 
          [alice, alice], 
          [await vestParams(10**7, 1000, 1000, 10, 1000, 1, true), await vestParams(10**7, 1000, 1000, 10, 1000, 1, true)],
          byVestingOwner
        );

        this.timestamp = +(await time.latest());
        
        await expectRevert(this.VEST.reduceVesting(alice, 2, 0, true, vestingOwner), "Ownable: caller is not the owner");
      })
      it("only owner can revoke vestings partially", async () => {
        assert.equal(await this.VEST.getClaimableNow(alice, 2), ''+ether(''+10**6));
        await expectRevert(
          this.VEST.reduceVesting(alice, 2, ether(''+(10**6 - 1)), false, vestingOwner, byVestingOwner), 
          "cannot reduce, already claimed"
        );

        let revokeTx = await this.VEST.reduceVesting(alice, 2, ether(''+(10**7/2)), false, vestingOwner, byVestingOwner);
        
        await expectEvent(revokeTx, "Retrieved", { who: alice, amount: ''+ether(''+(10**6)) });
        await expectEvent(revokeTx, "VestingReduced", { 
          who: alice, 
          which: "2", 
          amountBefore: ''+ether(''+(10**7)), 
          amountAfter: ''+ether(''+(10**7/2))
        })

        assert.equal(await this.VEST.getClaimableAtTimestamp(alice, 2, this.timestamp + 2000), ''+ether(''+(10**7/2 - 10**6)))
        assert.equal(await this.VEST.getReleasedAt(alice, 2, this.timestamp + 2000), ''+ether(''+(10**7/2)))
      })
      it("only owner can revoke vestings completely", async () => {
        await time.increaseTo(this.timestamp + 1500);

        let revokeTx = await this.VEST.reduceVesting(alice, 3, 0, true, vestingOwner, byVestingOwner);

        await expectRevert(this.VEST.retrieve(3, byAlice), "already claimed");
        await expectEvent(revokeTx, "Retrieved", { who: alice, amount: ''+ether(''+(10**6 + 10**7/2)) });

      })
      it("owner can disable revokability", async () => {
        await expectRevert(this.VEST.disableOwnerRevoke(alice, 3, byAlice), "Ownable: caller is not the owner");
        await expectRevert(this.VEST.disableOwnerRevokeGlobally(byAlice), "Ownable: caller is not the owner");

        let disableTx = await this.VEST.disableOwnerRevoke(alice, 2, byVestingOwner);

        await expectEvent(disableTx, "OwnerRevokeDisabled", { who: alice, which: "2" });
        
        assert.isFalse(await this.VEST.canAdminRevoke(alice, 2));
        assert.isTrue(await this.VEST.canAdminRevoke(alice, 1));

        await expectRevert(this.VEST.reduceVesting(alice, 2, 0, true, vestingOwner, byVestingOwner), "vesting non-revokable");

        let disableGlobalTx = await this.VEST.disableOwnerRevokeGlobally(byVestingOwner);

        await expectEvent(disableGlobalTx, "OwnerRevokeDisabledGlobally");

        assert.isFalse(await this.VEST.canAdminRevoke(alice, 0))
        assert.isFalse(await this.VEST.canAdminRevoke(alice, 1))
        assert.isFalse(await this.VEST.canAdminRevoke(alice, 2))
        assert.isFalse(await this.VEST.canAdminRevoke(alice, 3))
        assert.isFalse(await this.VEST.adminCanRevokeGlobal());

        await expectRevert(
          this.VEST.reduceVesting(alice, 2, 0, true, vestingOwner, byVestingOwner), 
          "admin not allowed to revoke anymore"
        );
      })
    })
})