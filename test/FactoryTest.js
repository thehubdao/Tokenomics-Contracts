const { expectEvent, expectRevert, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256, ZERO_ADDRESS } = require('@openzeppelin/test-helpers/src/constants');

const assert = require('assert');
const vest = artifacts.require('DACVesting');
const sale = artifacts.require('DACPublicOffering')
const ERC20 = artifacts.require('mockERC20');
const ERC206 = artifacts.require('mockERC206');
const factory = artifacts.require('DACFactory');

const duration = 10; // in days
const startIn = 1;   // in days
const cliffDelay = 1;
const cliff = 100; // 1%
const exp = 2;


contract('vest', ([alice, owner, AggregatorDummy]) => {
    beforeEach(async () => {
        this.vesting = await vest.new();
        this.sale = await sale.new();
        this.FAC = await factory.new(await this.vesting.address, await this.sale.address);
        this.MGH = await ERC20.new('MetaGameHub', 'MGH', 2100000, { from: owner });
        this.USD = await ERC206.new('USD', 'USD', 1000000, { from: owner });
    });

    it("factory deploys vesting clone correctly, quadratic + cliff", async () => {
        await this.FAC.createVestingClone(
            await this.MGH.address,
            owner,
            startIn,
            duration,
            cliff,
            cliffDelay,
            exp
        );
        const clone = await this.FAC.vestingClones.call(0);
        this.V = await vest.at(clone);
        assert.equal((await this.V.owner()).toString(), owner.toString());
        assert.equal((await this.V.getRetrievablePercentage()).toString(), "1");

        await this.MGH.approve(clone, MAX_UINT256, {from: owner });
        await this.MGH.approve(clone, MAX_UINT256, {from: alice });
        
        await this.V.depositFor(alice, 1000000, { from: owner });
        await this.V.retrieve({ from: alice });
        await expectRevert(
            this.V.retrieve({ from: alice }),
            "nothing to retrieve",
        );
        assert.equal(await this.MGH.balanceOf(alice), 10000);

        await time.increaseTo((await this.V.startTime.call()).add(new BN(duration*86400/2)));

        assert.equal((await this.V.getRetrievablePercentage()).toString(), "26");
        await this.V.retrieve({ from: alice });
        await expectRevert(
            this.V.retrieve({ from: alice }),
            "nothing to retrieve",
        );
        assert.equal(await this.MGH.balanceOf(alice), 260000);

        time.increaseTo((await this.V.startTime.call()).add( new BN(duration*86400)));
        await this.V.retrieveFor([alice], { from: alice });
        assert.equal(await this.MGH.balanceOf(alice), 1000000);

        await expectRevert(
            this.V.depositFor(alice, 1000001, { from: alice }),
            "ERC20: transfer amount exceeds balance",
        );

        await this.V.depositAllFor(alice, { from: alice });
        assert.equal(await this.MGH.balanceOf(alice), 0);
        assert.equal(await this.V.balanceOf(alice), 1000000);

        time.increaseTo((await this.V.startTime.call()).add( new BN((duration+1)*86400)));
        await this.V.retrieveFor([alice], { from: owner });
        assert.equal(await this.MGH.balanceOf(alice), 1000000);
        assert.equal(await this.V.getTotalDeposit(alice), 2000000);
        assert.equal(await this.V.getRetrievableAmount(alice), 0);
    })

    it("deploys FIXPRICE POOL correctly", async () => {
        const currentBlock = await time.latestBlock();
        console.log("now: " + currentBlock.toString());
        await this.FAC.createSaleClone(
            await this.USD.address,
            await this.MGH.address,
            AggregatorDummy,
            owner,
            1,
            10**7,
            currentBlock.add(new BN(10)),
            currentBlock.add(new BN(25)),
            currentBlock.add(new BN(30))
        );
        const clone = await this.FAC.saleClones.call(0);
        this.S = await sale.at(clone);
        await this.MGH.transfer(clone, new BN(1000000000000000000n), { from: owner });

        const start = await this.S.startBlock.call();
        const end = await this.S.endBlock.call();

        console.log("start: " + (await start.toString() + "end: " + (await end.toString()) + "harvestBlock: "));

        await this.USD.approve(clone, MAX_UINT256, {from: owner });
        await this.USD.approve(clone, MAX_UINT256, {from: alice });

        assert.equal(await this.S.lpToken.call(), await this.USD.address);

        await expectRevert(
            this.S.deposit(1, { from: owner }),
            'Not sale time',
        );
        await time.advanceBlockTo(start.add(new BN(1)));

        await this.S.deposit(1, { from: owner });
        await expectRevert(
            this.S.deposit(100000, { from: owner }),
            'not enough tokens left',
        );
        assert.equal((await this.USD.balanceOf(clone)).toString(), "1");

        await this.S.deposit(99999, { from: owner });

        assert.equal(await this.S.viewUserAmount(owner), 100000);

        await time.advanceBlockTo(end.add(new BN(1)));
        await expectRevert(
            this.S.harvest({ from: owner }),
            'Too early to harvest'
        );

        await time.advanceBlockTo(end.add(new BN(6)));
        await this.S.harvest({ from: owner });
        assert.equal((await this.MGH.balanceOf(owner)).toString(), "2100000000000000000000000");
        assert.equal((await this.MGH.balanceOf(clone)).toString(), "0");
    })

    it('linear with no cliff', async () => {
        const now = time.latest();
        await this.FAC.createVestingClone(
            await this.MGH.address,
            owner,
            50,
            1000,
            0,
            0,
            1
        );
        const clone = await this.FAC.vestingClones.call(0);
        this.V = await vest.at(clone);
        const start = await this.V.startTime.call();
        const _duration = await this.V.duration.call();

        assert.equal((await this.V.owner()).toString(), owner.toString());
        assert.equal((await this.V.getRetrievablePercentage()).toString(), "0");

        await this.MGH.approve(clone, MAX_UINT256, {from: owner });
        await this.MGH.approve(clone, MAX_UINT256, {from: alice });
        
        await this.V.depositFor(alice, 1000000, { from: owner });
        await expectRevert(
            this.V.retrieve({ from: alice }),
            "nothing to retrieve",
        );
        assert.equal(await this.MGH.balanceOf(alice), 0);

        await time.increaseTo(start);

        await expectRevert(
            this.V.retrieve({ from: owner }),
            'nothing to retrieve',
        );
        await expectRevert(
            this.V.retrieve({ from: alice }),
            'nothing to retrieve',
        );
        await this.V.retrieveFor([alice, owner], { from: owner });
        assert.equal(await this.MGH.balanceOf(alice), 0);
        assert.equal(await this.MGH.balanceOf(clone), 1000000);

        await time.increaseTo(start.add(new BN(_duration/2)));
        
        console.log("fraction of time passed: " + (await time.latest()).sub((await this.V.startTime.call()))/(new BN(_duration)));

        assert.equal((await this.V.getRetrievablePercentage()).toString(), "50");

        await this.V.retrieve({ from: alice });
        await expectRevert(
            this.V.retrieve({ from: alice }),
            "nothing to retrieve",
        );

        assert.equal(await this.MGH.balanceOf(alice), 500000);

        time.increaseTo(start.add(new BN(_duration)));

        await this.V.retrieveFor([alice, owner], { from: alice });
        assert.equal(await this.MGH.balanceOf(alice), 1000000);
        assert.equal(await this.MGH.balanceOf(clone), 0);
        await expectRevert(
            this.V.depositFor(alice, 1000001, { from: alice }),
            "ERC20: transfer amount exceeds balance",
        );
        await this.V.depositAllFor(alice, { from: owner });
        assert.equal(await this.MGH.balanceOf(clone), 1000000);
        assert.equal(await this.V.balanceOf(alice), 2000000);

        time.increaseTo(start.add(new BN(_duration+86400)));

        await this.V.retrieveFor([alice], { from: owner });
        assert.equal(await this.MGH.balanceOf(alice), 2000000);
        assert.equal(await this.V.getTotalDeposit(alice), 2000000);
        assert.equal(await this.V.getRetrievableAmount(alice), 0);
        assert.equal(await this.V.getRetrievablePercentage(), 100);
    })
})