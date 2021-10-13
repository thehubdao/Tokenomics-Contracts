const { expectEvent, expectRevert, time, BN } = require("@openzeppelin/test-helpers");
const balance = require("@openzeppelin/test-helpers/src/balance");
const { MAX_UINT256, ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const ether = require("@openzeppelin/test-helpers/src/ether");
const assert = require("assert");

const sale = artifacts.require("DACPublicOffering");
const ERC20 = artifacts.require("mockERC20");
const ERC206 = artifacts.require("mockERC206");
const AGG3 = artifacts.require("mockAggregatorV3")


    contract("PublicOffering", ([alice, owner]) => {
        beforeEach(async () => {
            this.sale = await sale.new();
            this.MGH = await ERC20.new("MetaGameHub", "MGH", 1000000, { from: owner });
            this.USD = await ERC206.new("USD", "USD", 2000000, { from: owner });
            this.AGG = await AGG3.new();
            this.MGH.transfer(await this.sale.address, ether("1000000"), { from: owner });
            this.USD.transfer(alice, 1000000000000, { from: owner });
            this.USD.approve(await this.sale.address, MAX_UINT256, { from: owner });
            this.USD.approve(await this.sale.address, MAX_UINT256, { from: alice });
        })
        it("initializes and correclty calculates ETH amount", async () => {
            const now = await time.latestBlock();
            const start = await now.add(new BN(12));
            const end = await now.add(new BN(25));
            const harvestBlock = await now.add(new BN(30));
            await this.sale.initialize(
                await this.USD.address,
                await this.MGH.address,
                await this.AGG.address,
                alice,
                100000,
                10**7,
                start,
                end,
                harvestBlock
            );
            await expectRevert(
                this.sale.transferOwnership(owner, { from: owner }),
                "Ownable: caller is not the owner",
            );
            await this.sale.transferOwnership(owner, { from: alice });
            assert.equal(await this.sale.owner(), owner);

            await expectRevert(
                this.sale.deposit(0, { value: 1, from: owner }),
                "Not sale time",
            );
            await expectRevert(
                this.sale.deposit(1, { value: 0, from: owner }),
                "Not sale time",
            );
            await expectRevert(
                this.sale.finalWithdraw(0, 1, 2, { from: owner }),
                "too early to withdraw offering token",
            );

            await time.advanceBlockTo(new BN(start).add(new BN(1)));

            await expectRevert(
                this.sale.deposit(1, { value: ether("2"), from: owner }),
                "not enough tokens left",
            );
            await expectRevert(
                this.sale.deposit(10000000001, { from: owner }),
                "not enough tokens left",
            );

            await this.sale.deposit(0, { from: owner, value: ether("1")});
            assert.equal(await this.sale.viewUserAmount(owner), 5000000000);

            await this.sale.deposit(3000000000, { from: alice });
            assert.equal(await this.sale.viewUserAmount(alice), 3000000000);

            await this.sale.deposit(1000000000, { from: alice, value: ether("0.1")});
            assert.equal(await this.sale.viewUserAmount(alice), 4500000000);

            await expectRevert(
                this.sale.deposit(1, { from: owner, value: ether("0.1")}),
                "not enough tokens left",
            );
            await this.sale.deposit(0, { from: alice, value: ether("0.1")});

            await expectRevert(
                this.sale.deposit(0, { from: owner, value: 2*10**8 }),
                "not enough tokens left",
            );

            const {0: offeringAmount , 1: price, 2: totalAmount} = await this.sale.viewPoolInformation();
            assert.equal(offeringAmount.toString(), "100000000000000000000000");
            assert.equal(price.toString(), "10000000000000");
            assert.equal(totalAmount.toString(), "10000000000");

            await expectRevert(
                this.sale.harvest({ from: owner }),
                "Too early to harvest",
            );

            await time.advanceBlockTo(end.add(new BN(1)));

            await expectRevert(
                this.sale.deposit(0, { from: alice }),
                "Not sale time",
            );
            await expectRevert(
                this.sale.finalWithdraw(0, 1, 2, { from: owner }),
                "too early to withdraw offering token",
            );
            await this.sale.finalWithdraw(4000000000, 0, ether("1.2"), { from: owner });
            assert.equal(await balance.current(await this.sale.address), 0);
            assert.equal(await this.USD.balanceOf(await this.sale.address), 0);

            await time.advanceBlockTo(harvestBlock);

            let tx = await this.sale.harvest({ from: owner });
            await expectEvent(
                tx, "Harvest", eventArgs = {user: owner, offeringAmount: ether("50000").toString()}
            );
            await this.sale.harvest({ from: alice });
            await expectRevert(
                this.sale.harvest({ from: alice }),
                "already harvested",
            );
            await expectRevert(
                this.sale.harvest({ from: owner }),
                "already harvested",
            );

            assert.equal((await this.MGH.balanceOf(await this.sale.address)).toString(), (ether("900000")).toString());
            assert.equal((await this.MGH.balanceOf(alice)).toString(), ether("50000").toString());
            assert.equal((await this.MGH.balanceOf(owner)).toString(), ether("50000").toString());
        })
    })