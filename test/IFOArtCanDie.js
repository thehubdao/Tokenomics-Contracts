const { expectRevert, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256 } = require('@openzeppelin/test-helpers/src/constants');
const assert = require('assert');
const _IFO = artifacts.require('IFOACD');
const _ERC20 = artifacts.require('mockERC20');
const _ERC206 = artifacts.require('mockERC206')

const cmil = 100000;

contract('IFOACD', ([alice, bob, admin]) => {
	beforeEach(async () => {
		this.DIE = await _ERC20.new('ArtCanDie', 'DIE', 1000000, { from: admin });
		this.USD = await _ERC206.new('USDCoin', 'USD', 1000000, { from: admin });
		this.USD.transfer(alice, 500000, { from: admin });
		this.USD.transfer(bob, 500000, { from: admin });
		this.IFO = await _IFO.new(await this.USD.address, await this.DIE.address, { from: admin });
		await this.DIE.transfer(await this.IFO.address, 1000000, { from: admin });

		await this.IFO.setPool(500000, 2, 0, { from: admin });
		await this.IFO.setPool(500000, 2, 1, { from: admin });

		await this.USD.approve(await this.IFO.address, MAX_UINT256, { from: bob });
		await this.USD.approve(await this.IFO.address, MAX_UINT256, { from: alice });

	});

	it('should deposit and harvest correctly', async () => {
		await this.IFO.updateStartAndEndBlocks(20, 50, { from: admin });
		const end = 50;
		const start = 20;
		await expectRevert(
			this.IFO.depositPool(100000, 0, { from: bob }),
			"Too early",
		);
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
<
		assert.equal((await (await this.IFO.viewUserAmount(bob, [0, 1])).toString()), [0,0].toString());
		assert.equal(await this.DIE.balanceOf(bob), 422222);
		assert.equal(await this.DIE.balanceOf(alice), 277777);

		await expectRevert(
			this.IFO.adminWithdraw({ from: bob }),
			'Ownable: caller is not the owner',
		);

		await this.IFO.adminWithdraw({ from: admin });
		await this.IFO.finalWithdraw(0, 1, 0, { from: admin });

		assert.equal((await this.USD.balanceOf(admin)).toString(), '1000000');
		assert.equal((await this.DIE.balanceOf(admin)).toString(), '1');
	});
});