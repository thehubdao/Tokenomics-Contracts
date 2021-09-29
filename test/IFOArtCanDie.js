const { expectRevert, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256 } = require('@openzeppelin/test-helpers/src/constants');
const assert = require('assert');
const _IFO = artifacts.require('IFOACD');
const _ERC20 = artifacts.require('mockERC20');
const _ERC206 = artifacts.require('mockERC209');

contract('IFOACD', ([alice, bob, admin]) => {
	beforeEach(async () => {
		this.DIE = await _ERC20.new('ArtCanDie', 'DIE', 1000000, { from: admin });
		this.USD = await _ERC206.new('USDCoin', 'USD', 1000000, { from: admin });
		this.USD.transfer(alice, 500000, { from: admin });
		this.USD.transfer(bob, 500000, { from: admin });
		this.IFO = await _IFO.new(await this.USD.address, await this.DIE.address, 1000000, 2000, 20, 50, admin, { from: admin });
		await this.DIE.transfer(await this.IFO.address, 1000000, { from: admin });

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
		await this.IFO.depositPool(100000, 0, { from: bob });
		await this.IFO.depositPool(400000, 1, { from: bob });
		await this.IFO.depositPool(500000, 1, { from: alice });

		await expectRevert(
			this.IFO.harvestPool(1, { from: bob }),
			"Too early",
		);
		
		assert.equal((await (await this.IFO.viewUserAmount(bob, [0, 1])).toString()), [100000, 400000].toString());
		assert.equal(await this.USD.balanceOf(admin), 0);

		await time.advanceBlockTo(end + 1);
		await this.IFO.harvestPool(1, { from: bob });
		await this.IFO.harvestPool(0, { from: bob });
		await this.IFO.harvestPool(1, { from: alice });

		assert.equal((await (await this.IFO.viewUserAmount(bob, [0, 1])).toString()), [0,0].toString());
		assert.equal(await this.DIE.balanceOf(bob), 422222);
		assert.equal(await this.DIE.balanceOf(alice), 277777);

		await expectRevert(
			this.IFO.finalWithdraw(100, 100, 100, { from: admin }),
			"admin must wait",
		);

		await time.advanceBlockTo(end + 21);

		await expectRevert(
			this.IFO.finalWithdraw(100, 100, 100, { from: bob }),
			"Ownable: caller is not the owner",
		);

		await this.IFO.finalWithdraw(1000000, 1, 0, { from: admin });
		await this.IFO.finalWithdraw(0, 1, 0, { from: admin });

		assert.equal((await this.USD.balanceOf(admin)).toString(), '1000000');
		assert.equal((await this.DIE.balanceOf(admin)).toString(), '1');
	});
});