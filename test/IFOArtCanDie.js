const { expectRevert, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256 } = require('@openzeppelin/test-helpers/src/constants');
const assert = require('assert');
const _IFO = artifacts.require('IFOACD');
const _ERC20 = artifacts.require('mockERC20');
const _ERC209 = artifacts.require('mockERC209');

contract('IFOACD', ([alice, bob, admin]) => {
	beforeEach(async () => {
		this.DIE = await _ERC20.new('ArtCanDie', 'DIE', 2000000, { from: admin });
		this.USD = await _ERC209.new('USDCoin', 'USD', 3500, { from: admin });
		this.USD.transfer(alice, 1000, { from: admin });
		this.USD.transfer(bob, 2500, { from: admin });
		console.log((await time.latestBlock()).toString());
		this.IFO = await _IFO.new(await this.USD.address, await this.DIE.address, 1000000, 1000000, 2000, 2000, 20, 50, admin, { from: admin });
		await this.DIE.transfer(await this.IFO.address, 2000000, { from: admin });

		await this.USD.approve(await this.IFO.address, MAX_UINT256, { from: bob });
		await this.USD.approve(await this.IFO.address, MAX_UINT256, { from: alice });

	});

	it('should deposit and harvest correctly', async () => {
		const end = 50;
		const start = 20;
		await expectRevert(
			this.IFO.depositPool(100000, 0, { from: bob }),
			"Too early",
		);
		await expectRevert(
			this.IFO.setPool(100, 1, 1, 0, { from: admin }),
			"admin must wait",
		)
		await time.advanceBlockTo(start);
		await expectRevert(
			this.IFO.depositPool(501, 0, { from: bob }),
			'not enough Offering Tokens left in Pool1',
		);
		await this.IFO.depositPool(500, 0, { from: bob });
		await this.IFO.depositPool(2000, 1, { from: bob });
		await this.IFO.depositPool(1000, 1, { from: alice });

		await expectRevert(
			this.IFO.harvestPool(1, { from: bob }),
			"Too early",
		);
		
		assert.equal((await (await this.IFO.viewUserAmount(bob, [0, 1, 2])).toString()), [500, 2000, 0].toString());
		assert.equal(await this.USD.balanceOf(admin), 0);

		await time.advanceBlockTo(end);
		await this.IFO.harvestPool(1, { from: bob });
		await this.IFO.harvestPool(0, { from: bob });
		await this.IFO.harvestPool(1, { from: alice });

		assert.equal((await (await this.IFO.viewUserAmount(bob, [0, 1, 2])).toString()), [0,0,0].toString());
		assert.equal((await this.DIE.balanceOf(bob)).toString(), "1666666");
		assert.equal((await this.DIE.balanceOf(alice)).toString(), "333333");

		await expectRevert(
			this.IFO.finalWithdraw(100, 100, 100, { from: admin }),
			"admin must wait",
		);

		await time.advanceBlockTo(end + 6);

		await expectRevert(
			this.IFO.finalWithdraw(100, 100, 100, { from: bob }),
			"Ownable: caller is not the owner",
		);

		await this.IFO.finalWithdraw(3500, 1, 0, { from: admin });

		assert.equal((await this.USD.balanceOf(admin)).toString(), '3500');
		assert.equal((await this.DIE.balanceOf(admin)).toString(), '1');
	});
});